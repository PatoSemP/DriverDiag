@echo off
setlocal EnableExtensions

REM ferramenta.bat - Launcher compartilhavel (estilo Chris Titus: executa da rede, sem git clone)
REM Elevacao: DriverDiag.ps1 apos o bootstrap transferir para %%TEMP%%.

set "BOOTSTRAP_URL=https://raw.githubusercontent.com/PatoSemP/DriverDiag/main/bootstrap.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }; ^
   $u = '%BOOTSTRAP_URL%'; ^
   $s = Invoke-RestMethod -Uri $u -UseBasicParsing; ^
   if (-not $s) { Write-Host '[ferramenta] Resposta vazia do bootstrap.' -ForegroundColor Red; exit 1 }; ^
   & ([scriptblock]::Create($s)) @args" %*

set "ERR=%ERRORLEVEL%"
exit /b %ERR%
