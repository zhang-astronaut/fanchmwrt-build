/* dhcp-snooper — passive DHCP hostname learner for bypass gateways.
 *
 * When FanchmWrt runs as a bypass gateway the upstream router serves DHCP,
 * so /tmp/dhcp.leases stays empty and fwxd cannot resolve terminal
 * hostnames (the dashboard shows bare MACs). This daemon binds UDP/67 —
 * free because the local DHCP server is disabled in bypass mode — and
 * listens for DHCP broadcasts on the LAN: every client (re)connect
 * broadcasts its hostname (option 12) alongside its MAC. Learned
 * MAC -> hostname (and IP when visible) mappings are kept in
 * /tmp/dhcp_snoop.leases in dnsmasq lease-file format; fwxd falls back to
 * that file when its own lease file has no entry. If binding fails
 * (e.g. local DHCP was enabled later) the daemon retries periodically and
 * stays harmless.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define LEASE_FILE    "/tmp/dhcp_snoop.leases"
#define LEASE_TTL     86400   /* sliding expiry, refreshed hourly */
#define REFRESH_SECS  3600
#define MAX_ENTRIES   256
#define MAX_HOSTNAME  63
#define DHCP_COOKIE   { 0x63, 0x82, 0x53, 0x63 }

struct entry {
    char mac[18];
    char ip[16];
    char hostname[MAX_HOSTNAME + 1];
    time_t expires;
    struct entry *next;
};

static struct entry *entries = NULL;
static int entry_count = 0;
static volatile sig_atomic_t stop_flag = 0;
static int lease_dirty = 0;

static void on_term(int sig) { (void)sig; stop_flag = 1; }

static struct entry *find_entry(const char *mac) {
    struct entry *e;
    for (e = entries; e; e = e->next)
        if (strcmp(e->mac, mac) == 0)
            return e;
    return NULL;
}

static void sanitize(char *s) {
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c <= 32 || c > 126 || c == '"' || c == '\\')
            *s = '_';
    }
}

static void upsert(const char *mac, const char *ip, const char *hostname) {
    struct entry *e = find_entry(mac);
    time_t now = time(NULL);

    if (!e) {
        if (entry_count >= MAX_ENTRIES) {
            /* drop the oldest expired/least-recent entry */
            struct entry **pp = &entries, *oldest = entries, *prev = NULL, *op = NULL;
            while (*pp) {
                if (!oldest || (*pp)->expires < oldest->expires) { oldest = *pp; op = prev; }
                prev = *pp; pp = &(*pp)->next;
            }
            if (!oldest) return;
            if (op) op->next = oldest->next; else entries = oldest->next;
            free(oldest);
            entry_count--;
        }
        e = calloc(1, sizeof(*e));
        if (!e) return;
        strncpy(e->mac, mac, sizeof(e->mac) - 1);
        e->next = entries;
        entries = e;
        entry_count++;
    }

    if (strcmp(e->hostname, hostname) != 0 || strcmp(e->ip, ip) != 0)
        lease_dirty = 1;
    strncpy(e->hostname, hostname, sizeof(e->hostname) - 1);
    strncpy(e->ip, ip, sizeof(e->ip) - 1);
    e->expires = now + LEASE_TTL;
}

static void write_leases(void) {
    char tmp[] = LEASE_FILE ".tmp";
    FILE *fp = fopen(tmp, "w");
    time_t now = time(NULL);
    struct entry *e;

    if (!fp) return;
    for (e = entries; e; e = e->next) {
        if (e->expires <= now) continue;
        fprintf(fp, "%lld %s %s %s *\n", (long long)e->expires, e->mac,
                e->ip[0] ? e->ip : "*", e->hostname);
    }
    fclose(fp);
    if (rename(tmp, LEASE_FILE) != 0)
        unlink(tmp);
    else
        lease_dirty = 0;
}

static void drop_expired(void) {
    struct entry **pp = &entries;
    time_t now = time(NULL);
    while (*pp) {
        if ((*pp)->expires <= now) {
            struct entry *dead = *pp;
            *pp = dead->next;
            free(dead);
            entry_count--;
            lease_dirty = 1;
        } else {
            pp = &(*pp)->next;
        }
    }
}

static void refresh_expiries(void) {
    time_t now = time(NULL);
    struct entry *e;
    for (e = entries; e; e = e->next)
        e->expires = now + LEASE_TTL;
    lease_dirty = 1;
}

/* returns 1 when a hostname was learned */
static int parse_dhcp(const unsigned char *buf, ssize_t len,
                      char *mac, size_t mac_sz,
                      char *ip, size_t ip_sz,
                      char *hostname, size_t hostname_sz) {
    static const unsigned char cookie[4] = DHCP_COOKIE;
    const unsigned char *opt, *end;
    unsigned int hlen, yiaddr;
    int have_host = 0, have_req = 0, have_yi = 0;
    unsigned int req_ip = 0;
    char host[MAX_HOSTNAME + 1] = {0};
    unsigned int i;

    if (len < 240 || memcmp(buf + 236, cookie, 4) != 0)
        return 0;

    hlen = buf[2];
    if (hlen == 0 || hlen > 16 || 28 + hlen > (unsigned int)len)
        return 0;
    for (i = 0; i < hlen && mac_sz > strlen(mac) + 3; i++)
        snprintf(mac + strlen(mac), mac_sz - strlen(mac), "%s%02x",
                 i ? ":" : "", buf[28 + i]);
    if (strlen(mac) == 0)
        return 0;

    yiaddr = ((unsigned int)buf[16] << 24) | ((unsigned int)buf[17] << 16) |
             ((unsigned int)buf[18] << 8) | (unsigned int)buf[19];
    have_yi = (yiaddr != 0);

    opt = buf + 240;
    end = buf + len;
    while (opt + 2 <= end) {
        unsigned int code = opt[0], olen;
        if (code == 0) { opt++; continue; }
        if (code == 255) break;
        olen = opt[1];
        if (opt + 2 + olen > end) break;
        if (code == 12 && olen > 0) {
            unsigned int n = olen > MAX_HOSTNAME ? MAX_HOSTNAME : olen;
            memcpy(host, opt + 2, n);
            host[n] = '\0';
            sanitize(host);
            if (host[0] != '\0') have_host = 1;
        } else if (code == 50 && olen == 4) {
            req_ip = ((unsigned int)opt[2] << 24) | ((unsigned int)opt[3] << 16) |
                     ((unsigned int)opt[4] << 8) | (unsigned int)opt[5];
            have_req = 1;
        }
        opt += 2 + olen;
    }
    if (!have_host)
        return 0;

    strncpy(hostname, host, hostname_sz - 1);
    if (have_yi)
        snprintf(ip, ip_sz, "%u.%u.%u.%u", (yiaddr >> 24) & 0xff,
                 (yiaddr >> 16) & 0xff, (yiaddr >> 8) & 0xff, yiaddr & 0xff);
    else if (have_req)
        snprintf(ip, ip_sz, "%u.%u.%u.%u", (req_ip >> 24) & 0xff,
                 (req_ip >> 16) & 0xff, (req_ip >> 8) & 0xff, req_ip & 0xff);
    else
        ip[0] = '\0';
    return 1;
}

static int open_dhcp_socket(void) {
    int fd, on = 1;
    struct sockaddr_in addr;

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(67);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int main(void) {
    int fd = -1;
    time_t last_refresh = 0;

    signal(SIGINT, on_term);
    signal(SIGTERM, on_term);

    while (!stop_flag) {
        char buf[2048];
        char mac[18] = {0}, ip[16] = {0}, hostname[MAX_HOSTNAME + 1] = {0};
        struct timeval tv;
        fd_set rfds;
        ssize_t n;

        if (fd < 0) {
            fd = open_dhcp_socket();
            if (fd < 0) {
                if (!stop_flag)
                    fprintf(stderr, "dhcp-snooper: UDP/67 busy (local DHCP on?), retrying in 60s\n");
                sleep(60);
                continue;
            }
            fprintf(stderr, "dhcp-snooper: listening on UDP/67\n");
        }

        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        n = select(fd + 1, &rfds, NULL, NULL, &tv);
        if (stop_flag) break;
        if (n < 0) { if (errno == EINTR) continue; break; }

        if (n > 0) {
            n = recv(fd, buf, sizeof(buf), 0);
            if (n > 0 && parse_dhcp((const unsigned char *)buf, n,
                                    mac, sizeof(mac), ip, sizeof(ip),
                                    hostname, sizeof(hostname))) {
                upsert(mac, ip, hostname);
                if (lease_dirty) write_leases();
            }
        }

        if (time(NULL) - last_refresh >= REFRESH_SECS) {
            drop_expired();
            refresh_expiries();
            write_leases();
            last_refresh = time(NULL);
        }
    }

    if (fd >= 0) close(fd);
    return 0;
}
