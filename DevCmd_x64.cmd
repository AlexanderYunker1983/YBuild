@if not defined _echo echo off
if "%~1"=="" goto default
set low=%1
goto continue
:default
set low=15

:continue
set /a high=%low%+1

for /f "tokens=*" %%i in ('%~dp0\bin\vswhere.exe -version [%low%^,%high%^) -latest -property installationPath') do (
  echo %%i
  if exist "%%i\Common7\Tools\vsdevcmd.bat" (
    call "%%i\Common7\Tools\vsdevcmd.bat" -arch=amd64
    exit /b
  )
)

exit /b 2