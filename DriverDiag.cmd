@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM chama no kit: call "%~dp0DriverDiag\DriverDiag.cmd"

set "PS1=%~dp0DriverDiag.ps1"
if not exist "%PS1%" (
  echo [DriverDiag] Arquivo nao encontrado: %PS1%
  pause
  exit /b 1
)

REM elevacao fica no .ps1 (caminho com acento quebra o RunAs do .cmd)
set "ARGS=%*"
echo.%ARGS% | findstr /I /C:"-Console" /C:"/console" /C:"--console" >nul
if not errorlevel 1 (
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%PS1%" -Console
) else (
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%PS1%"
)

set "ERR=%ERRORLEVEL%"
if not "%ERR%"=="0" (
  echo.
  echo [DriverDiag] Encerrou com codigo %ERR%.
  pause
)
exit /b %ERR%
