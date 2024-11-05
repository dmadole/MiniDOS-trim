
all: trim.bin

lbr: trim.lbr

clean:
	rm -f trim.lst
	rm -f trim.bin
	rm -f trim.lbr

trim.bin: trim.asm include/bios.inc include/kernel.inc
	asm02 -L -b trim.asm
	rm -f trim.build

trim.lbr: trim.bin
	rm -f trim.lbr
	lbradd trim.lbr trim.bin

