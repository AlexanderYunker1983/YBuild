@ECHO OFF
for /f "tokens=2*" %%a in ('reg query HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\VS7 /v 15.0') do set "vs15=%%bCommon7\Tools\VsDevCmd.bat"
call "%vs15%" -arch=amd64
