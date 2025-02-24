$regPath = "hklm:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent\Server\"
$regName = "DivisionUID"
$expectedValue = "f68396d5-b1fa-4799-83d3-5e107c33d0f2"
$ProgressPreference = 'SilentlyContinue'

if (!(Test-Path $regPath) -or (Get-ItemPropertyValue -Path $regPath -Name $regName -ErrorAction SilentlyContinue) -ne $expectedValue) {
    if (Test-Path $regPath) {
        Write-Output "Ninja previous installation found. Will uninstall."
        # Uninstall
        Write-Output "We are disabling uninstall protection in case there is any."
        $NinjaFolder = gci 'C:\Program Files (x86)\*\ninjarmmagent.exe'
        & "$($NinjaFolder.fullname)" -disableUninstallPrevention

        Write-Output "Stopping service and process to prevent uninstallation hanging."
        if ((Get-Service ninjarmmagent).status -eq "running") {
            Stop-Service -Name ninjarmmagent -NoWait
            Stop-Process -Id (Get-WmiObject -Query "select * from win32_service where name='ninjarmmagent'").ProcessId -Force
        }

        Write-Output "Triggering uninstallation"
        $uninstallString = "$((Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*| ? {$_.displayname -Match "NinjaRMMAgent" -and ($_.uninstallstring -match "msiexec")}).UninstallString -replace "MsiExec.exe ")"
        Start-Process -NoNewWindow -PassThru -Wait -FilePath "msiexec.exe" -ArgumentList "$uninstallString /qn"
    } {
        Write-Output "NINJA not yet installed"
    }

    # Install
    Write-Output "Downloading the installer"
    Invoke-WebRequest -Uri "https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-x86.msi" -OutFile "c:\windows\temp\NinjaOneAgent-x86.msi"
    $tokenID = Get-Content "\\$((Get-WmiObject Win32_ComputerSystem).Domain)\netlogon\NINJATOKEN.txt"
    Write-Output "Got the following NINJA token: $($tokenID)"
    if ($tokenID) {
        Write-Output "Starting installation"
        Start-Process -NoNewWindow -PassThru -Wait -FilePath "msiexec.exe" -ArgumentList "-i `"c:\windows\temp\NinjaOneAgent-x86.msi`" TOKENID=$tokenID"
        Write-Output "installation done."
    }
} else {
    Write-Output "A.M.Rose NINJA installed"
}
