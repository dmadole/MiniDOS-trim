# MiniDOS-trim

This is a utility to change the length of a Mini/DOS file. The usage is:
```
trim [-s size] file
```
When run with no argument, it will remove any XMODEM block padding from the end of the named file.

If run with the -s argument, it will change the file's size to that specified, truncating the file if less than the current size, or extending it if larger than the current size. Note that extending the size is done with o_seek and any added bytes on the file will be filled with whatever was in the allocated disk blocks, it is not zeroed.

