
;  Copyright 2023, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; Definition files

          #include include/bios.inc
          #include include/kernel.inc


          ; Unpublished kernel vector points

d_ideread:  equ   0447h
d_idewrite: equ   044ah


          ; Executable header block

            org   1ffah
            dw    begin
            dw    end-begin
            dw    begin
 
begin:      br    start

            db    7+80h
            db    29
            dw    2023
            dw    1

            db    'See github/dmadole/Elfos-trim for more information',0


start:      ldi   1                     ; flag to automatically trim
            phi   r8

skplead:    lda   ra                    ; skip any leading spaces
            lbz   dousage
            sdi   ' '
            lbdf  skplead

            adi   '-'-' '               ; if not a dash, no option
            lbnz  notopts

            lda   ra                    ; only valid option is s
            smi   's'
            lbnz  dousage

skppref:    lda   ra                    ; skip any leading spaces
            lbz   dousage
            sdi   ' '
            lbdf  skppref

            ghi   ra                    ; get pointer to input
            phi   rf
            glo   ra
            plo   rf
            dec   rf

            sep   scall                 ; convert input to number
            dw    f_atoi
            lbdf  dousage

            ghi   rd                    ; save result
            phi   rc
            glo   rd
            plo   rc

            ldi   0                     ; clear automatic trim flag
            phi   r8
            plo   r8

            ghi   rf                    ; set pointer after number
            phi   ra
            glo   rf
            plo   ra

skpsuff:    lda   ra                    ; skip any leading spaces
            lbz   dousage
            sdi   ' '
            lbdf  skpsuff

notopts:    ghi   ra                    ; leave rf at start of filename
            phi   rf
            glo   ra
            plo   rf
            dec   rf

skpfile:    lda   ra                    ; skip over filename
            lbz   gotargs
            sdi   ' '
            lbnf  skpfile

            ldi   0                     ; zero-terminate filename
            dec   ra
            str   ra
            inc   ra

skptail:    lda   ra                    ; absorb trailing spaces
            lbz   gotargs
            sdi   ' '
            lbdf  skptail

dousage:    sep   scall                 ; otherwise display usage message
            dw    o_inmsg
            db    'USAGE: trim [-s size] filename',13,10,0
            sep   sret                  ; and return to os


          ; Open the file we are going to trim to read the directory entry
          ; and let us seek on it. We are going to try to do what we need
          ; as much as possible through the API and not muck around with the
          ; disk and internals.

gotargs:    ldi   fildes.1              ; get file descriptor
            phi   rd
            ldi   fildes.0
            plo   rd

            ldi   0                     ; plain open, no flags
            plo   r7

            sep   scall                 ; open file
            dw    o_open
            lbnf  opened

            sep   scall                 ; error if can't be opened
            dw    o_inmsg
            db    'ERROR: kernel file cannot be opened',13,10,0
            sep   sret


          ; If we are not automatically trimming, then get the size to trim
          ; to into the seek register and go right to truncating.

opened:     glo   rc                    ; get size, r8 was already set
            plo   r7
            ghi   rc
            phi   r7

            ghi   r8                    ; if size if fixed, go truncate
            lbz   truncat


          ; Otherwise, we need to find the last non-1Ah byte in the last
          ; 128 bytes of the file. Start by seeing to 128 bytes from the end.

            ldi   -128.0                ; negative 128 bytes seek
            plo   r7
            ldi   -128.1
            phi   r7
            plo   r8
            phi   r8

            ldi   2                     ; relative to end of file
            plo   rc

            sep   scall                 ; perform seek
            dw    o_seek


          ; Next read the last 128 bytes of data in the file to the buffer.

            ldi   buffer.1              ; reset pointer to buffer
            phi   rf
            ldi   buffer.0
            plo   rf

            ldi   128.1                 ; read remainder of file
            phi   rc
            ldi   128.0
            plo   rc

            sep   scall                 ; read the data
            dw    o_read
            lbnf  gotdata

            sep   scall                 ; if the read failed
            dw    o_inmsg
            db    'ERROR: could not read kernel file.',13,10,0

            sep   sret


          ; Search backward from the end of the read data to the last non-
          ; padding (1Ah) byte in the buffer.

gotdata:    ldi   (buffer+127).1        ; get pointer to last byte
            phi   rf
            ldi   (buffer+127).0
            plo   rf

            ldn   rf                    ; if its not padding, nothing to do
            smi   26
            lbnz  return

            glo   r7                    ; advance location offset to end
            adi   128
            plo   r7
            ghi   r7
            adci  0
            phi   r7
            glo   r8
            adci  0
            plo   r8
            ghi   r8
            adci  0
            phi   r8


          ; Now do the actual scanning backwards. Note that the buffer is
          ; prefixed with a static zero so that scanning will not go back
          ; past the beginning of the buffer, without needing a counter.

scanpad:    dec   rf                    ; back up a byte

            glo   r7                    ; if r7 is not zero, just decrement
            lbnz  notzero
            ghi   r7
            lbnz  notzero

            dec   r8                    ; else borrow from r8

notzero:    dec   r7                    ; drop location offset by one

            ldn   rf                    ; continue while still padding
            smi   26
            lbz   scanpad


          ; Here is where we actually truncate the file. Start by seeking to
          ; the location to truncate at, which will setup the correct sector
          ; for that location in the file decriptor. This will also append
          ; to the file if the size specified is actually larger than the file.

truncat:    ldi   0                     ; seek from beginning of file
            plo   rc

            sep   scall                 ; seek to truncate location
            dw    o_seek


          ; Next we update the correct EOF offset in the file descriptor,
          ; and set the flag marking the file as being written to. This will
          ; cause the changed EOF to get written back into the file's directory
          ; entry when it is closed. We also check the flags to see if we
          ; are in the last allocation unit of the file, if so, there is not
          ; anything else that we need to do to truncate.

            ldi   (fildes+6).1          ; get pointer to eof field
            phi   r9
            ldi   (fildes+6).0
            plo   r9

            ghi   r7                    ; mask low 16 bits for eof offset
            ani   4095.1                ;  and store into file descriptor
            str   r9
            inc   r9
            glo   r7         
            str   r9
            inc   r9

            ldn   r9                    ; set file has been written flag
            ori   16
            str   r9

            ani   4                     ; if not the last lump, delete aus
            lbz   notlast

            sep   scall                 ; else, just close the file
            dw    o_close

            sep   sret                  ; all done


          ; If we truncated the file to a point prior to the last allocation
          ; unit in the file, then we need mark the current allocation unit
          ; as the last, and also free any that are beyond it. Start by
          ; calculating the current allocation unit number from the sector.

notlast:    ldi   (fildes+15).1         ; pointer to address of loaded sector
            phi   r9
            ldi   (fildes+15).0
            plo   r9

            lda   r9                    ; this will be the drive number
            phi   r8

            lda   r9                    ; get the sector address to rb:ra
            plo   rb
            lda   r9
            phi   ra
            lda   r9
            plo   ra
 
            sep   scall                 ; close file to write changed eof
            dw    o_close


          ; Divide the sector address by 8 to get the AU number.

            ldi   3                     ; number of bits to shift right
            plo   re

divby8:     glo   rb                    ; shift 24 bits one bit right
            shr
            plo   rb
            ghi   ra
            shrc
            phi   ra
            glo   ra
            shrc
            plo   ra

            dec   re                    ; continue for all three shifts
            glo   re
            lbnz  divby8


          ; Lastly, follow the AU chain marking the current one as the last
          ; with the special value of FEFE, and mark any following ones as
          ; free with the special value of 0000.
       
            ldi   0feh                  ; set first one to fefe
            plo   rf
            phi   rf

clrloop:    ghi   ra                    ; save current au number
            phi   rb
            glo   ra
            plo   rb

            sep   scall                 ; lookup next au
            dw    o_rdlump

            ghi   ra                    ; save next au number
            phi   rc
            glo   ra
            plo   rc

            ghi   rb                    ; get back current au
            phi   ra
            glo   rb
            plo   ra

            sep   scall                 ; update au pointer value
            dw    o_wrlump

            ldi   0                     ; any after the first are set to 0
            plo   rf
            phi   rf

            ghi   rc                    ; get back next au
            phi   ra
            glo   rc
            plo   ra

            ghi   ra                    ; if this was not the last one,
            smi   0feh                  ;  continue through the chain
            lbnz  clrloop
            glo   ra
            smi   0feh
            lbnz  clrloop

return:     sep   sret                  ; we are done


          ; Static data area follows. The db and dw items will be included in
          ; the executable with the given values. The following ds areas
          ; will have the labels set to the correct addresses, but no bytes
          ; will actually be generated. We do include them in the executable
          ; size in the header, as the kernel will use this to check that there
          ; is enough memory available when loading the executable.

fildes:     db    0,0,0,0               ; file descriptor for opening
            dw    dta
            db    0,0
            db    0
            db    0,0,0,0
            dw    0,0
            db    0,0,0,0

            db    0                     ; ensure we will stops here
buffer:     ds    128                   ;  when we are scanning buffer

dta:        ds    512                   ; buffer for file descriptor

end:        end   begin

