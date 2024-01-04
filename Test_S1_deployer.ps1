param (
    $workingDir = "$($env:localappdata)\S1_Deployment",
    $logPath = "$($workingDir)\S1_Script_log.txt",
    $InstallerName = "S1.exe",
    $InstallSource,
    $InstallToken,
    $CentralErrorRepo,
    $centralReportRepo
)


$ProgressPreference = "SilentlyContinue"
$ErrorState = $false



function Write-log {
    Param(
        $data,
        $path = $logPath
    )
    "$(get-date -Format G),$($data)" | Out-File $logPath -Encoding ascii -Append
    if ($centralReportRepo) {"$(get-date -Format G),$($data)" | Out-File "$centralReportRepo\$($env:COMPUTERNAME).txt" -Encoding ascii -Append -ErrorAction:SilentlyContinue}

}

write-log -data "Script running"
write-log -data $PSScriptRoot

#if ($MyInvocation.MyCommand -notmatch "/.ps1") {
    If (-not (Test-Path "$workingDir\S1_deployer.ps1")) {
        [void](New-Item -ItemType Directory -Path $workingDir)
        Invoke-RestMethod -Uri "https://raw.githubusercontent.com/a-m-rose/Installers/master/S1_deployer.ps1" -OutFile $workingDir\S1_deployer.ps1
        Write-log -data "Script ran without being cached locally. Downloaded to local cache."
    }
    
#}


try {
    
    [void]((Get-WmiObject Win32_BIOS).SerialNumber)

} catch {
    $ErrorState = $true
    $ErrorMessage += "Wmi seems to be corrupted"
    write-log -data "Wmi Corrupted"
}


if ((Test-Path 'C:\Program Files\SentinelOne\Sentinel Agent *\SentinelCtl.exe') -and (-not $ErrorState)) {
        
    write-log -data "SentinelCTL found. S1 seems to be installed."

    # Get SetninelOne Status
    $SentinelStatusOutput = & ('C:\Program Files\SentinelOne\Sentinel Agent *\SentinelCtl.exe') status

    $SentinelStatus = [pscustomobject]@{

        "SentinelState" = [bool]($SentinelStatusOutput | where-object { $_ -match "Disable State: Not disabled" })
        "MonitorState"  = [bool]($SentinelStatusOutput | where-object { $_ -match "SentinelMonitor is loaded" })
        "AgentState"    = [bool]($SentinelStatusOutput | where-object { $_ -match "SentinelAgent is running" })
    }

    write-log -data "SentinelCTL status output: $($SentinelStatusOutput)"
    write-log -data "Script parsting of SentinelCTL status: $($SentinelStatus)"


    # If sentinelOne Installed and running try to uninstall SEP if installed.
    if ($SentinelStatus.AgentState -or $SentinelStatus.MonitorState -or $SentinelStatus.SentinelState) {

        write-log -data "S1 seems to be running fine."
        Get-Childitem 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
        ForEach-Object { Get-ItemProperty "Microsoft.PowerShell.Core\Registry::$_" } |
        Where-Object { $_.displayname -eq 'Symantec Endpoint Protection' } |
        ForEach-Object {
        
            & msiexec.exe /x $($_.uninstallstring -replace 'MsiExec.exe /i', '') /qn
            write-log -data "SEP installed found on this machine. Triggering uninstallation."
        }

    } else {
        
        $ErrorState = $true
        $ErrorMessage += "`nS1 is installed but not running on this computer"
        $Errormessage += "`n$($SentinelStatusOutput)"
        $Errormessage += "`n$($SentinelStatus)"
        write-log -data "S1 is installed but NOT in perfect running condition"

    }

}
else {

    if (-not $InstallSource) {
        write-log -data "No install source provided. Falling back to Internet Source"
        $InstallSource = "$workingDir\$InstallerName"
    }
    if (Test-Path $InstallSource) {
        write-log -data "S1_Installer_Accessible. No need to redownload."
    }
    else {

        # If install source path not accessible fall back to internet source. 
        $InstallSource = "$workingDir\$InstallerName"
        write-log -data "S1_Being_Downloaded"
        try {
            Invoke-RestMethod -Method get -uri "https://s3.us-east-1.wasabisys.com/amrose/$InstallerName" -OutFile $InstallSource
        }
        catch {
            write-log -data  "Download_failed"
            $ErrorState = $true
            $ErrorMessage += "S1 Download failed`nIssue:$($_.exception.message)"
        }
    }


    if (-not $ErrorState) {

        # Install Process
        Try {
            write-log -data "S1_Install_Started_Source_$installsource"
            $installProcess = Start-Process -NoNewWindow -PassThru -Wait -FilePath $InstallSource -ArgumentList "-q -t $($InstallToken)"
            $InstallExitCode = $installProcess.ExitCode
            write-log -data "Install_ExitCode_$InstallExitCode"
        }
        Catch {
            write-log -data "Install_Failed_$($_.exception.message)"
            $ErrorState = $true
            $ErrorMessage += "Install failed`nReason: $($_.exception.message)"
        }

    }
    #Exit codes - https://usea1-pax8-03.sentinelone.net/docs/en/installing-windows-agent-22-1--with-the-new-installation-package.html

    If ($InstallExitCode -notmatch "\b0\b|\b12\b") {

        $ErrorState = $true
        $ErrorMessage += "Installer exit code indicates installation not 100% success.`nExit Code:$($installProcess.ExitCode)`nSee link for S1 exit codes values - usea1-pax8-03.sentinelone.net/docs/en/installing-windows-agent-22-1--with-the-new-installation-package.html"
        write-log -data "Installer exit code indicates installation not 100% success.`nExit Code:$($installProcess.ExitCode)`nSee link for S1 exit codes values - usea1-pax8-03.sentinelone.net/docs/en/installing-windows-agent-22-1--with-the-new-installation-package.html"

    }


}


write-log -data "ErrorState: $ErrorState"

# Open ticket if last ticket is 2 days old.
if ($ErrorState) {
        

    try {$ErrorMessage | Out-File "$CentralErrorRepo\$($env:COMPUTERNAME).txt"} catch {$ErrorMessage += "Unable to write error log to central repo."}


    try { $TicketDate = ((Get-Item "$workingDir\Ticket.json" -ErrorAction:SilentlyContinue).LastWriteTimeUtc).AddDays(2) ; write-log -data "Old Ticket exsists. Date: $TicketDate" } catch { $TicketDate = ((get-date).ToUniversalTime()).AddDays(-2) ; write-log -data "No Old ticket." }
        
    # Don't open a new ticket if previous ticket is less than a day.
    if ($TicketDate -le (Get-Date).ToUniversalTime()) {
            
        write-log -data "Opening Ticket"

        $request = @{
            "request" = @{
                "requester" = @{"email" = "Testing_S1_Deployer@amrose.it"; "name" = "Testing S1 Deployer Script" }
                "subject"   = "Testing S1 script error $($env:COMPUTERNAME)@$($env:USERDOMAIN) - $((Resolve-DnsName -Server resolver1.opendns.com -Name  myip.opendns.com.).ipaddress)"
                "comment"   = @{"body" = "___Testing___`n$($env:COMPUTERNAME)@$($env:USERDOMAIN)`n$ErrorMessage" }
            }
        } | ConvertTo-Json

        # Write-Output $ErrorMessage
        $Ticket = Invoke-RestMethod -Uri "https://amrose.zendesk.com/api/v2/requests" -Method Post -Body $request -ContentType "application/json"
        $Ticket | Out-File "$workingDir\Ticket.json" -Force
        if ($ticket) { write-log -data "Ticket info: $($ticket.request)" } else { write-log -data "Ticket creation failed" }
        
    }

}
else {

    Remove-Item "$CentralErrorRepo\$($env:COMPUTERNAME).txt" -ErrorAction:SilentlyContinue
}