PROGRAMS =

LD = ld
NASM = nasm
NASMFLAGS = -f elf64


epoll-nasm: epoll-nasm.o
	$(LD) -s -o $@ $<

epoll-nasm.o: epoll.asm
	$(NASM) $(NASMFLAGS) $< -o $@

PROGRAMS += epoll-nasm


all: $(PROGRAMS)

.PHONY: clean
clean:
	rm -rf *.o
	rm $(PROGRAMS)
