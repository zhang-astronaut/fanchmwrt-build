OBJS:=dhcp_snooper.o
EXEC:=dhcp-snooper
all: $(EXEC)
$(EXEC): $(OBJS)
	$(CC) -o $(EXEC) $(OBJS) $(LDFLAGS)
clean:
	rm -f $(EXEC) *.o
