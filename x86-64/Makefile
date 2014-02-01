LD = ld
LDFLAGS = -A x86_64

NASM = nasm
NASMFLAGS = -f elf64

GAS = as
GASFLAGS = -msyntax=intel -mmnemonic=intel --64 --gen-debug

PROGRAMS = epoll-nasm epoll-gas

all: $(PROGRAMS)


epoll-nasm: epoll-nasm.o
	$(LD) -s -o $@ $<
epoll-nasm.o: epoll.asm
	$(NASM) $(NASMFLAGS) $< -o $@


ifdef DEBUG
epoll-gas: epoll.S
	gcc -nostartfiles -g -o $@ $<
else
epoll-gas: epoll-gas.o
	$(LD) -s -o $@ $<
epoll-gas.o: epoll.S
	$(GAS) $(GASFLAGS) $< -o $@
endif


.PHONY: clean
clean:
	rm -rf *.o
	rm $(PROGRAMS)
