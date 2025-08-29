@echo off
setlocal

set PS1File=%WINDIR%\Temp\NinjaInstaller.ps1
set URL=https://raw.githubusercontent.com/a-m-rose/Installers/refs/heads/master/NinjaInstaller.ps1
set LOGFILE=%WINDIR%\Temp\NinjaInstaller.log

:: Write header to log
echo === Ninja Installer started on %DATE% at %TIME% === > "%LOGFILE%"

:: Try downloading the script (log all output)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%PS1File%' -UseBasicParsing -ErrorAction Stop } catch { Write-Host 'Download failed' ; exit 1 }" >> "%LOGFILE%" 2>&1

if errorlevel 1 (
    echo ERROR: Could not download installer. >> "%LOGFILE%"
    exit /b 1
)

:: Run the installer script (log all output)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1File%" >> "%LOGFILE%" 2>&1

:: Clean up
del "%PS1File%" >> "%LOGFILE%" 2>&1

echo === Ninja Installer finished on %DATE% at %TIME% === >> "%LOGFILE%"

endlocal
exit
