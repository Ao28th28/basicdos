IF "%1"=="FINAL" MAKE REL=FINAL MAKEFILE
IF NOT "%1"=="FINAL" MAKE REL=DEBUG MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
COPY OBJ\MSBASIC.EXE A:
IF "%2"=="" GOTO EXIT
CD ..
:EXIT
