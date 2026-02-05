param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$false)]
    [string]$NetBiosName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$LocalAdminPassword,
    
    [Parameter(Mandatory=$false)]
    [bool]$IsFirstDC = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$PrimaryDCAddress = "10.38.0.4",
    
    [Parameter(Mandatory=$false)]
    [string]$DatabasePath = "F:\NTDS",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "F:\NTDS",
    
    [Parameter(Mandatory=$false)]
    [string]$SysvolPath = "F:\SYSVOL"
)

# Suppress progress messages
$ProgressPreference = "SilentlyContinue"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path "C:\dc-setup.log" -Value "[$timestamp] $Message"
    Write-Output "[$timestamp] $Message"
}

try {
    Write-Log "Starting Domain Controller Setup"
    Write-Log "Domain Name: $DomainName"
    Write-Log "NetBios Name: $NetBiosName"
    Write-Log "Is First DC: $IsFirstDC"
    Write-Log "Database Path: $DatabasePath"
    Write-Log "Log Path: $LogPath"
    Write-Log "Sysvol Path: $SysvolPath"
    
    # Install required Windows features
    Write-Log "Installing AD DS and DNS roles..."
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -Confirm:$false | Out-Null
    
    # Configure DNS client to use local DNS server
    Write-Log "Configuring DNS client to use local server..."
    try {
        $InterfaceAlias = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name
        if ($InterfaceAlias) {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "127.0.0.1"
            Write-Log "DNS client configured on interface: $InterfaceAlias"
            
            # Verify DNS configuration
            $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
            Write-Log "DNS Server addresses configured: $($dnsConfig.ServerAddresses -join ', ')"
        }
        else {
            Write-Log "WARNING: No active network adapter found for DNS configuration"
        }
    }
    catch {
        Write-Log "ERROR configuring DNS client: $($_.Exception.Message)"
    }
    
    if ($IsFirstDC) {
        Write-Log "Creating new Active Directory Forest..."

        # Validate and prepare database paths
        $dbPathDrive = if ($DatabasePath -match "^F:") { "F" } else { "C" }
        $pathsReady = $true
        
        if ($dbPathDrive -eq "F") {
            if (-not (Test-Path "F:\")) {
                Write-Log "WARNING: F: drive not found, falling back to C: drive"
                $DatabasePath = "C:\Windows\NTDS"
                $LogPath = "C:\Windows\NTDS"
                $SysvolPath = "C:\Windows\SYSVOL"
            }
        }

        # Create new forest
        $params = @{
            DomainName = $DomainName
            DomainNetbiosName = if ([string]::IsNullOrEmpty($NetBiosName)) { ($DomainName.Split(".")[0]).ToUpper() } else { $NetBiosName }
            SafeModeAdministratorPassword = (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
            DatabasePath = $DatabasePath
            LogPath = $LogPath
            SysvolPath = $SysvolPath
            InstallDns = $true
            CreateDnsDelegation = $false
            Force = $true
            NoRebootOnCompletion = $false
            Confirm = $false
        }
        
        Install-ADDSForest @params | Out-Null
        Write-Log "Active Directory Forest created successfully"
        Write-Log "System will automatically reboot to complete configuration"
    }
    else {
        Write-Log "Adding Domain Controller to existing domain..."
        
        # Wait for first DC to be reachable
        $dcReady = $false
        $retries = 0
        $maxRetries = 30
        
        while (-not $dcReady -and $retries -lt $maxRetries) {
            try {
                $dcTest = Test-NetConnection -ComputerName $PrimaryDCAddress -Port 389 -InformationLevel Quiet
                if ($dcTest) {
                    Write-Log "First DC is reachable"
                    $dcReady = $true
                }
            }
            catch {
                Write-Log "Waiting for first DC... (attempt $($retries + 1)/$maxRetries)"
                Start-Sleep -Seconds 10
                $retries++
            }
        }
        
        if (-not $dcReady) {
            Write-Log "WARNING: First DC not reachable after 5 minutes, proceeding anyway"
        }
        
        # Add as additional DC
        $params = @{
            DomainName = $DomainName
            Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\$DomainAdminUser", (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))
            SafeModeAdministratorPassword = (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
            DatabasePath = $DatabasePath
            LogPath = $LogPath
            SysvolPath = $SysvolPath
            Force = $true
            NoRebootOnCompletion = $false
            Confirm = $false
        }
        
        Install-ADDSDomainController @params | Out-Null
        Write-Log "Domain Controller added to domain successfully"
        Write-Log "System will automatically reboot to complete configuration"
    }
    
    # Configure DNS forwarders after reboot via a one-time scheduled task to ensure AD DS is fully online
    Write-Log "Queuing DNS forwarder configuration after reboot..."
    $forwarderScript = "Start-Sleep -Seconds 60; Add-DnsServerForwarder -IPAddress 8.8.8.8,8.8.4.4 -PassThru -Confirm:\$false; Unregister-ScheduledTask -TaskName 'ConfigureDnsForwarders' -Confirm:\$false"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command \"$forwarderScript\""
    $trigger = New-ScheduledTaskTrigger -AtStartup -Once
    Register-ScheduledTask -TaskName "ConfigureDnsForwarders" -Action $action -Trigger $trigger -RunLevel Highest -Force | Out-Null
    
    # Configure firewall rules for AD/DNS
    Write-Log "Configuring Windows Firewall..."
    Enable-NetFirewallRule -DisplayName "Active Directory Domain Controller (TCP-In)" -Confirm:$false -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayName "DNS (TCP)" -Confirm:$false -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayName "DNS (UDP)" -Confirm:$false -ErrorAction SilentlyContinue
    
    # Change local admin password
    Write-Log "Updating local admin password..."
    try {
        $localAdmin = [ADSI]"WinNT://./Administrator"
        $localAdmin.SetPassword($LocalAdminPassword)
        Write-Log "Local admin password updated"
    }
    catch {
        Write-Log "Failed to update local admin password: $($_.Exception.Message)"
    }
    
    Write-Log "Domain Controller setup completed successfully. System will reboot to complete configuration."
    Write-Log "Setup completed at $(Get-Date)"
    
    # Schedule reboot
    shutdown /r /t 10 /c "Domain Controller setup complete, rebooting..."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "ERROR Stack: $($_.ScriptStackTrace)"
    exit 1
}
