@echo off
bitsadmin /transfer NINJAInstaller /download /DYNAMIC "https://raw.githubusercontent.com/a-m-rose/Installers/refs/heads/master/NinjaInstaller.ps1" "c:\windows\temp\NinjaInstaller.ps1"
bitsadmin /cancel NINJAInstaller
powershell.exe -executionpolicy bypass -file "c:\windows\temp\NinjaInstaller.ps1"
del "c:\windows\temp\NinjaInstaller.ps1"