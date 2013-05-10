@echo off
REM PerlShare starter
set CYGWIN=nodosfilewarning
set HOME=%USERPROFILE%
set PATH=%PATH%;%CD%\bin;%CD%\ssh\bin
perl PerlShare.pl >%TEMP%\perlshare.log 2>&1
