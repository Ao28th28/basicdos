DEL A:*.COM
MAKE MAKEFILE
IF ERRORLEVEL 1 GOTO END
ECHO CON=SCR,KBD>A:CONFIG.SYS
COPY DEV\*.OBJ A:
COPY DEV\IBMBIO.COM A:
COPY DEV\*.EXE A:
COPY DOS\IBMDOS.COM A:
COPY DEV\*.COM A:
:END
