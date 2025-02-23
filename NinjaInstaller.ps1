$NINJARegPath = "hklm:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent\Server\"
if (Test-Path $NINJARegPath) {
    if ((Get-ItemPropertyValue $NINJARegPath -name DivisionUID) -ne "f68396d5-b1fa-4799-83d3-5e107c33d0f2") {
        $NinjaFolder = gci 'C:\Program Files (x86)\*\ninjarmmagent.exe'
        & "$($NinjaFolder.fullname)" -disableUninstallPrevention
        & "$($NinjaFolder.Directory)\uninstall.exe" --mode unattended
    }
}
Invoke-WebRequest -Uri "https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-x86.msi" -OutFile "c:\windows\temp\NinjaOneAgent-x86.msi"
$tokenID = Get-Content "\\$((Get-WmiObject Win32_ComputerSystem).Domain)\netlogon\NINJATOKEN.txt"
& msiexec.exe -i "c:\windows\temp\NinjaOneAgent-x86.msi" TOKENID=$tokenID