IF "%1"=="NODEBUG" MAKE REL=NODEBUG MAKEFILE
IF NOT "%1"=="NODEBUG" MAKE REL=DEBUG MAKEFILE
IF ERRORLEVEL 1 GOTO EXIT
COPY OBJ\IBMBIO.COM A:
IF "%2"=="" GOTO EXIT
CD ..\DOS
MK %1 %2
:EXIT
