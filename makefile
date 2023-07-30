
trim.bin: trim.asm
	asm02 -L -b trim.asm
	rm -f trim.build

clean:
	rm -f trim.lst
	rm -f trim.bin

