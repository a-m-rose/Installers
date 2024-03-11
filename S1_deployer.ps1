param (
    $workingDir = "$($env:localappdata)\S1_Deployment",
    $logPath = "$workingDir\S1_Script_log.txt",
    $InstallerName = "S1.exe",
    $InstallSource,
    $InstallToken,
    $CentralErrorRepo,
    $centralReportRepo
)

#if ($MyInvocation.MyCommand -notmatch "/.ps1") {
    If (-not (Test-Path "$workingDir\S1_deployer.ps1")) {
        [void](New-Item -ItemType Directory -Path $workingDir)
        # Invoke-RestMethod -Uri "https://raw.githubusercontent.com/a-m-rose/Installers/master/S1_deployer.ps1" -OutFile $workingDir\S1_deployer.ps1
    }
    
#}

$ProgressPreference = "SilentlyContinue"
$ErrorState = $false

# Cleaning up in case of mistakes.
if ($workingDir) {$workingDir = $workingDir.trimend("\")}
if ($CentralErrorRepo) {$CentralErrorRepo = $CentralErrorRepo.trimend("\")}
if ($centralReportRepo) {$centralReportRepo = $centralReportRepo.trimend("\")}  
if ($InstallSource) {
    $InstallSource = $InstallSource.trimend("\")
    if ($InstallSource.Substring($InstallSource.Length -4) -match "\.exe") {
        $InstallerName = Split-Path $InstallSource -Leaf; $Installsource = Split-Path $InstallSource
    } 
}


function Write-log {
    Param(
        $data,
        $path = $logPath,
        [switch]$Errorlog
    )

    $logtype = "verbose"
    if ($Errorlog) {
        $logtype = "Errors"
    }

    $LogData = "$(get-date -Format G),$LogType,$($data)"
    
    # Always write to local log path.
    $LogData | Out-File $path -Encoding ascii -Append

    # Populate a globalally scoped variable with error info to be used when opening a ticket.
    if ($Errorlog) {
        $global:ErrorMessage += "`r`n$($data)"
    }

    if ($centralReportRepo -and (-not $NocentralReportRepo)) {
        try {
            $LogData | Out-File "$centralReportRepo\$($env:COMPUTERNAME).txt" -Encoding ascii -Append
        } catch {
            $global:NocentralReportRepo = $true
            Write-log -ErrorLog -data "Error writing log to central folder. Exception: $($_.exception.message)" -path $path
        }
    }

    # Send Error logs also to a seperate error log folder.
    if ($Errorlog -and (-not $NoCentralErrorRepo)) {
        try {
            $LogData | Out-File "$CentralErrorRepo\$($env:COMPUTERNAME).txt" -Encoding ascii -Append
        } catch {
            $global:NoCentralErrorRepo = $true
            Write-log -Errorlog -data "Error writing error log to central folder. Exception: $($_.exception.message)" -path $path
        }
    }

}

write-log -data "Script running"
write-log -data $PSScriptRoot


try {
    
    [void]((Get-WmiObject Win32_BIOS).SerialNumber)

} catch {
    $ErrorState = $true
    Write-log -ErrorLog -data "Wmi seems to be corrupted"
}


if ((Test-Path 'C:\Program Files\SentinelOne\Sentinel Agent *\SentinelCtl.exe') -and (-not $ErrorState)) {
        
    write-log -data "SentinelCTL found. S1 seems to be installed."

    # Get SetninelOne Status
    $SentinelStatusOutput = & ('C:\Program Files\SentinelOne\Sentinel Agent *\SentinelCtl.exe') status

    $SentinelStatus = [pscustomobject]@{

        "SentinelState" = [bool]($SentinelStatusOutput | where-object { $_ -match "Disable State: Not disabled" })
        "MonitorState"  = [bool]($SentinelStatusOutput | where-object { $_ -match "SentinelMonitor is loaded" })
        "AgentState"    = [bool]($SentinelStatusOutput | where-object { $_ -match "(SentinelAgent is )running|Loaded" })
    }

    write-log -data "SentinelCTL status output: $($SentinelStatusOutput)"
    write-log -data "Script parsting of SentinelCTL status: $($SentinelStatus)"


    # If sentinelOne Installed and running try to uninstall SEP if installed.
    if ($SentinelStatus.AgentState -and $SentinelStatus.MonitorState -and $SentinelStatus.SentinelState) {

        write-log -data "S1 seems to be running fine."
        Get-Childitem 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
        foreach-object { Get-ItemProperty "Microsoft.PowerShell.Core\Registry::$_" } |
        where-object { $_.displayname -eq 'Symantec Endpoint Protection' } |
        foreach-object {
        
            & msiexec.exe /x $($_.uninstallstring -replace 'MsiExec.exe /i', '') /qn /log "$((Get-Item $centralReportRepo\..\..).fullname)\SEP\Uninstall_Logs\$($env:computername).txt"
            write-log -data "SEP installed found on this machine. Triggering uninstallation." 
        }

    } else {
        
        $ErrorState = $true
        Write-log -ErrorLog -data "S1 is installed but not running on this computer"
        Write-log -ErrorLog -data "$($SentinelStatusOutput)"
        Write-log -ErrorLog -data "$($SentinelStatus)"

    }

} else {

    if ((-not $InstallSource)) {
        write-log -data "No install source provided. Falling back to local Source."
        $InstallSource = $workingDir
    }
    if (-not (Test-Path "$InstallSource\$InstallerName")) {
        write-log -data "Installer not accessible at $InstallSource\$InstallerName. Falling back to local source."
        $InstallSource = $workingDir
    }

    if (Test-Path "$InstallSource\$InstallerName") {
        write-log -data "S1_Installer_Accessible at $InstallSource\$InstallerName No need to redownload."
    } else {
        write-log -data "S1_Being_Downloaded"
        try {
            Invoke-RestMethod -Method get -uri "https://s3.us-east-1.wasabisys.com/amrose/$InstallerName" -OutFile "$InstallSource\$InstallerName"
        }
        catch {
            write-log -ErrorLog -data "Veriable_InstallerName_Download_failed"
            $originalerror = $_.exception.message
            Write-log -ErrorLog -data $originalerror
            try {
                Write-log -data "Falling back to hardcoded installer download link."
                Invoke-RestMethod -Method get -uri "https://s3.us-east-1.wasabisys.com/amrose/s1.exe" -OutFile "$InstallSource\S1.exe"
            } catch {
                Write-log -ErrorLog -data "Hardcoded_InstallerName_download_Failed."
                $originalerror = $_.exception.message
                Write-log -ErrorLog -data $_.exception.message
                $ErrorState = $true
            }

        }
    }


    if (-not $ErrorState) {

        # Install Process
        Try {
            write-log -data "S1_Install_Started_Source_$installsource\$installername"
            $installProcess = Start-Process -NoNewWindow -PassThru -Wait -FilePath "$InstallSource\$InstallerName" -ArgumentList "-q -t $($InstallToken)"
            $InstallExitCode = $installProcess.ExitCode
            write-log -data "Install_ExitCode_$InstallExitCode"
        }
        Catch {
            write-log -ErrorLog -data "Install_Failed_$($_.exception.message)"
            $ErrorState = $true
        }
        #Exit codes - https://usea1-pax8-03.sentinelone.net/docs/en/return-codes-after-installing-or-updating-windows-agents.html

        If ($InstallExitCode -notmatch "\b0\b|\b12\b") {

            $ErrorState = $true
            $exitcodemessage = "Installer exit code indicates installation not 100% success.
                                Exit Code:$($installProcess.ExitCode)
                                See link for S1 exit codes values - https://usea1-pax8-03.sentinelone.net/docs/en/return-codes-after-installing-or-updating-windows-agents.html"
            write-log -ErrorLog -data $exitcodemessage

        }
    }

}

write-log -data "ErrorState: $ErrorState"

# Open ticket if last ticket is 2 days old.
if ($ErrorState) {
        
    try {
        $TicketDate = (Get-Item "$workingDir\Ticket.json" -ErrorAction:Stop).LastWriteTimeUtc
        write-log -data "Old Ticket exists. Date: $TicketDate"
    }
    catch {
        $TicketDate = (get-date).ToUniversalTime().AddDays(-2)
        write-log -data "No Old ticket."
    }

    # Don't open a new ticket if previous ticket is less than a day.
    if ($TicketDate -lt (Get-Date).ToUniversalTime().AddDays(-2)) {
            
        write-log -data "Opening Ticket"
        $request = @{
            "request" = @{
                "requester" = @{"email" = "S1_Deployer@amrose.it"; "name" = "S1 Deployer Script" }
                "subject"   = "S1 script error $($env:COMPUTERNAME)@$($env:USERDOMAIN) - $((Resolve-DnsName -Server resolver1.opendns.com -Name myip.opendns.com.).ipaddress)"
                "comment"   = @{"body" = "$($env:COMPUTERNAME)@$($env:USERDOMAIN)`n$ErrorMessage" }
            }
        } | ConvertTo-Json
        try {
            $Ticket = Invoke-RestMethod -Uri "https://amrose.zendesk.com/api/v2/requests" -Method Post -Body $request -ContentType "application/json" -ErrorAction:Stop
            $Ticket.request | Out-File "$workingDir\Ticket.json" -Force
            write-log -data "Ticket info: $($ticket.request)"
        }
        Catch {
            write-log -data "Ticket creation failed"
            Write-log -data $_.exception.message
        }
    } else {
        Write-log -data "Ticket date too new. $TicketDate"

    }

}
else {
    Write-log -data "Computer in good state. If error log exists it's being deleted."
    Remove-Item "$CentralErrorRepo\$($env:COMPUTERNAME).txt" -ErrorAction:SilentlyContinue
}
Write-log -data "Script ended"