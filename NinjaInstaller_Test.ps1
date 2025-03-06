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
    } else {
        Write-Output "NINJA not yet installed"
    }


    Function Get-InteractiveNINJAToken {
        # Load WPF assemblies
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase

        # Read mappings from file into a hashtable
        $mappings = @{}
        (Invoke-RestMethod "https://raw.githubusercontent.com/a-m-rose/Installers/refs/heads/master/NINJA_mappings.txt") -split "`n"| ForEach-Object {
            if ($_ -match "^([^=]+)=(.+)$") {
                $mappings[$matches[1]] = $matches[2]
            }
        }

        # Define XAML for the WPF window
        $xaml ='
        <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                Title="Select Environment Variable" Height="200" Width="350"
                WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
                Background="#F0F0F0">
            <Grid Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <Label Grid.Row="0" Content="Select an option:"
                    FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,10"/>
                
                <ComboBox Grid.Row="1" x:Name="OptionComboBox"
                        FontFamily="Segoe UI" FontSize="12" Margin="0,0,0,20"
                        VerticalContentAlignment="Center" Height="30"/>
                
                <Button Grid.Row="2" x:Name="ApplyButton" Content="Apply"
                        Width="100" Height="30" HorizontalAlignment="Center"
                        FontFamily="Segoe UI" FontSize="12" FontWeight="Bold"
                        Background="#0078D7" Foreground="White"
                        BorderThickness="0">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Template">
                                <Setter.Value>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}"
                                                BorderThickness="{TemplateBinding BorderThickness}">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#0063B1"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Setter.Value>
                            </Setter>
                        </Style>
                    </Button.Style>
                </Button>
            </Grid>
        </Window>
        '

        # Create the WPF window from XAML
        $reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)

        # Get references to controls
        $comboBox = $window.FindName("OptionComboBox")
        $applyButton = $window.FindName("ApplyButton")

        # Populate the ComboBox
        $mappings.Keys | ForEach-Object { $comboBox.Items.Add($_) | Out-Null }
        $comboBox.SelectedIndex = 0

        # Add click event handler for the Apply button
        $applyButton.Add_Click({
            $selectedOption = $comboBox.SelectedItem
            $envValue = $mappings[$selectedOption]
            
            # Set the environment variable
            $env:NINJAToken = $envValue
            
            Write-Host "Environment variable MY_ENV_VAR set to: $envValue"
            Write-Host "You can verify this by closing and reopening PowerShell and typing: `$env:MY_ENV_VAR"
            
            $window.Close()
        })

        # Show the window
        $window.ShowDialog() | Out-Null
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
        Invoke-WebRequest -Uri "https://app.ninjarmm.com/ws/api/v2/generic-installer/NinjaOneAgent-x86.msi" -OutFile "c:\windows\temp\NinjaOneAgent-x86.msi"
        Write-Output "Starting installation"
        Start-Process -NoNewWindow -PassThru -Wait -FilePath "msiexec.exe" -ArgumentList "-i `"c:\windows\temp\NinjaOneAgent-x86.msi`" TOKENID=$($env:NINJAToken)"
    } else {
        write-output "No NINJA installation token."
    }
} else {
    Write-Output "A.M.Rose NINJA installed"
}
