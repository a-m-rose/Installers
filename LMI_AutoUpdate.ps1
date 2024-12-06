param($logpath)
$Key = "HKLM:\SOFTWARE\LogMeIn\V5\AutoUpdate"
$Property = "AutoStartUpdate"
$time = (Get-Date).ToString('MM/dd/yyyy hh:mm:ss tt')
$BootTime = Get-CimInstance -ClassName win32_operatingsystem | Select-Object lastbootuptime
$Results = Get-ItemProperty -Path $key -name $property
$FirstRunKey = "HKLM:\SOFTWARE\LogMeIn\V5\AutoUpdate\FirstRun"
$FirstRunValueName = "FirstRunCompleted"

if (-not (Test-Path $FirstRunKey)) {
    New-Item -Path $FirstRunKey -Force | Out-Null
}

$FirstRunCompleted = Get-ItemProperty -Path $FirstRunKey -Name $FirstRunValueName -ErrorAction SilentlyContinue

if (-not $FirstRunCompleted.FirstRunCompleted) {
    Set-ItemProperty -Path $Key -Name $Property -Value 1 -Force
    New-ItemProperty -Path $FirstRunKey -Name $FirstRunValueName -Value 1 -PropertyType DWORD -Force | Out-Null
    exit
}

$Results = Get-ItemProperty -Path $key -name $property 

if ($Results.AutoStartUpdate -eq 0 -and $FirstRunCompleted) { 
    Set-ItemProperty -Path $Key -name $property -Value 1 -Force 
    if ($BootTime.lastbootuptime -le (get-date).AddMinutes(-10)) { 
        "$time :: $($env:computername),0" | out-file $logpath -Append -Encoding ascii 
    } 
}
