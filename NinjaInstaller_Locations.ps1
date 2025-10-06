$regPath = "hklm:\SOFTWARE\WOW6432Node\NinjaRMM LLC\NinjaRMMAgent\Server\"
$regName = "DivisionUID"
$expectedValue = "f68396d5-b1fa-4799-83d3-5e107c33d0f2"
$ProgressPreference = 'SilentlyContinue'
$selectedOrg = $null

# Replace Get-ItemPropertyValue with Get-ItemProperty for v2.0 compatibility
if (!(Test-Path $regPath) -or ((Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName) -ne $expectedValue) {
    if (Test-Path $regPath) {
        Write-Output "Ninja previous installation found. Will uninstall."
        # Uninstall
        Write-Output "We are disabling uninstall protection in case there is any."
        $NinjaFolder = Get-ChildItem 'C:\Program Files (x86)\*\ninjarmmagent.exe'
        & "$($NinjaFolder.FullName)" -disableUninstallPrevention

        Write-Output "Stopping service and process to prevent uninstallation hanging."
        $service = Get-Service -Name "ninjarmmagent" -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Stop-Service -Name "ninjarmmagent" -NoWait
            $serviceProcess = Get-WmiObject -Query "SELECT * FROM Win32_Service WHERE Name='ninjarmmagent'"
            if ($serviceProcess) {
                Stop-Process -Id $serviceProcess.ProcessId -Force
            }
        }

        Write-Output "Triggering uninstallation"
        $uninstallEntry = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -match "NinjaRMMAgent" -and $_.UninstallString -match "msiexec" }
        if ($uninstallEntry) {
            $uninstallString = $uninstallEntry.UninstallString -replace "MsiExec.exe ", ""
            Start-Process -NoNewWindow -Wait -FilePath "msiexec.exe" -ArgumentList "$uninstallString /qn"
        }
    } else {
        Write-Output "NINJA not yet installed"
    }

Function Get-InteractiveNINJAToken {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # Download the single mappings file
    $request = New-Object System.Net.WebClient
    $mappings = @{}

    try {
        $MappingFile = $request.DownloadString("https://raw.githubusercontent.com/a-m-rose/Installers/refs/heads/master/NINJA_locations.txt")
        if ($MappingFile) {
            $MappingFile -split "`n" | ForEach-Object {
                if ($_ -match "^\s*$") { return } # skip blank lines
                if ($_ -match "^([^|=]+)\|?([^=]*)=(.+)$") {
                    $org = $matches[1].Trim()
                    $loc = $matches[2].Trim()
                    $tok = $matches[3].Trim()
                    if (-not $mappings.ContainsKey($org)) { $mappings[$org] = @{} }
                    if ([string]::IsNullOrWhiteSpace($loc)) { $loc = "Default Location" }
                    $mappings[$org][$loc] = $tok
                }
            }
        }
    } catch {
        Write-Warning "Could not download mapping file."
    }

    # --- Step 1: select organization ---
    $xamlOrg = '
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Select Organization" Height="180" Width="360"
            WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="#F0F0F0">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Label Grid.Row="0" Content="Select Organization:"
                   FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,10"/>
            <ComboBox Grid.Row="1" x:Name="OrgComboBox" FontFamily="Segoe UI" FontSize="12"
                      Height="30" Margin="0,0,0,15"/>
            <Button Grid.Row="2" x:Name="ApplyButton" Content="Next"
                    Width="100" Height="30" HorizontalAlignment="Center"
                    FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                    Background="#0078D7" Foreground="White" BorderThickness="0"/>
        </Grid>
    </Window>
'

    $reader = [System.Xml.XmlNodeReader]::new([xml]$xamlOrg)
    $orgWindow = [Windows.Markup.XamlReader]::Load($reader)
    $orgBox = $orgWindow.FindName("OrgComboBox")
    $applyBtn = $orgWindow.FindName("ApplyButton")

    $mappings.Keys | Sort-Object | ForEach-Object { $orgBox.Items.Add($_) | Out-Null }
    $orgBox.SelectedIndex = 0

    

    $applyBtn.Add_Click({
        $selectedOrg = $orgBox.SelectedItem
        if (!$selectedOrg) {
            [System.Windows.MessageBox]::Show("Please select an organization.")
        } else {
        $env:NINJAOrg = $SelectedOrg
            $orgWindow.Close()
        }
    })

    $orgWindow.ShowDialog() | Out-Null
    if (!$env:NINJAOrg) {
        Write-Output "No organization selected."
        return
    }

    # --- Step 2: select location (if multiple) ---
    $orgLocations = $mappings[$env:NINJAOrg].Keys
    $selectedLoc = $orgLocations | Select-Object -First 1
	$selectedOrrg = $env:NINJAOrg
    if ($orgLocations.Count -gt 1) {
        $xamlLoc = '
        <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                Title="Select Location" Height="180" Width="360"
                WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="#F0F0F0">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

        <Label x:Name="OrgLabel" Grid.Row="0" Content="Select Location:"
                       FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,10"/>
                <ComboBox Grid.Row="1" x:Name="LocComboBox" FontFamily="Segoe UI" FontSize="12"
                          Height="30" Margin="0,0,0,15"/>
                <Button Grid.Row="2" x:Name="ApplyButton" Content="Apply"
                        Width="100" Height="30" HorizontalAlignment="Center"
                        FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                        Background="#0078D7" Foreground="White" BorderThickness="0"/>
            </Grid>
        </Window>
'

        $reader2 = [System.Xml.XmlNodeReader]::new([xml]$xamlLoc)
        $locWindow = [Windows.Markup.XamlReader]::Load($reader2)
# --- set the label content at runtime (safe: escapes special chars) ---
$orgLabel = $locWindow.FindName("OrgLabel")
# Use SecurityElement.Escape to avoid XAML-breaking characters (ampersand, <, >, etc.)
$escapedOrg = [System.Security.SecurityElement]::Escape($selectedOrg)
$orgLabel.Content = "Select Location for ${escapedOrg}:"
        $locBox = $locWindow.FindName("LocComboBox")
        $applyBtn2 = $locWindow.FindName("ApplyButton")

        $orgLocations | Sort-Object | ForEach-Object { $locBox.Items.Add($_) | Out-Null }
        $locBox.SelectedIndex = 0

        $applyBtn2.Add_Click({
            $selectedLoc = $locBox.SelectedItem
            if (-not $selectedLoc) {
                [System.Windows.MessageBox]::Show("Please select a location.")
            } else {
                $env:NINJAloc = $selectedLoc
                $locWindow.Close()
          
		  }
        })

        $locWindow.ShowDialog() | Out-Null
    }

    # --- Use the selected token ---
    $env:NINJAToken = $mappings[$env:NINJAOrg][$env:NINJAloc]
    Write-Output "Selected organization: $env:NINJAOrg"
    Write-Output "Selected location: $env:NINJAloc"
    Write-Output "Got token: $($env:NINJAToken)"
}

    if ([string]::IsNullOrEmpty($env:NINJAToken)) {
        $env:NINJAToken = Get-Content "\\$((Get-WmiObject Win32_ComputerSystem).Domain)\netlogon\NINJATOKEN.txt" -ErrorAction:SilentlyContinue
    }
    if ([string]::IsNullOrEmpty($env:NINJAToken)) {
        Get-InteractiveNINJAToken
    }
    if ($env:NINJAToken) {
        Write-Output "Got the following NINJA token: $($env:NINJAToken)"
        Write-Output "Downloading the installer"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile("https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-x86.msi", "c:\windows\temp\NinjaOneAgent-x86.msi")
        Write-Output "Starting installation"
        Start-Process -NoNewWindow -PassThru -Wait -FilePath "msiexec.exe" -ArgumentList "-i `"c:\windows\temp\NinjaOneAgent-x86.msi`" TOKENID=$($env:NINJAToken)"
    } else {
        write-output "No NINJA installation token."
    }
} else {
    Write-Output "A.M.Rose NINJA installed"
}
