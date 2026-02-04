param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$LocalAdminPassword,
    
    [Parameter(Mandatory=$false)]
    [bool]$IsFirstDC = $false
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
    Write-Log "Is First DC: $IsFirstDC"
    
    # Install required Windows features
    Write-Log "Installing AD DS and DNS roles..."
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -Confirm:$false | Out-Null
    
    if ($IsFirstDC) {
        Write-Log "Creating new Active Directory Forest..."
        
        # Convert domain name to DN format
        $domainComponents = $DomainName.Split(".")
        $dnsDomain = ($domainComponents | ForEach-Object { "dc=$_" }) -join ","
        
        # Create new forest
        $params = @{
            DomainName = $DomainName
            SafeModeAdministratorPassword = (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
            CreateDnsDelegation = $false
            DatabasePath = "C:\Windows\NTDS"
            LogPath = "C:\Windows\NTDS"
            SysvolPath = "C:\Windows\SYSVOL"
            Force = $true
            SkipPreChecks = $false
            NoRebootOnCompletion = $true
            Confirm = $false
        }
        
        Install-ADDSForest @params | Out-Null
        Write-Log "Active Directory Forest created successfully"
    }
    else {
        Write-Log "Adding Domain Controller to existing domain..."
        
        # Wait for first DC to be reachable
        $dcReady = $false
        $retries = 0
        $maxRetries = 30
        
        while (-not $dcReady -and $retries -lt $maxRetries) {
            try {
                $dcTest = Test-NetConnection -ComputerName "10.38.0.4" -Port 389 -InformationLevel Quiet
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
            Credential = New-Object System.Management.Automation.PSCredential ("$DomainName\Administrator", (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force))
            SafeModeAdministratorPassword = (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
            DatabasePath = "C:\Windows\NTDS"
            LogPath = "C:\Windows\NTDS"
            SysvolPath = "C:\Windows\SYSVOL"
            Force = $true
            NoRebootOnCompletion = $true
            Confirm = $false
        }
        
        Install-ADDSDomainController @params | Out-Null
        Write-Log "Domain Controller added to domain successfully"
    }
    
    # Configure DNS forwarders
    Write-Log "Configuring DNS..."
    Add-DnsServerForwarder -IPAddress 8.8.8.8, 8.8.4.4 -PassThru -Confirm:$false | Out-Null
    
    # Configure firewall rules for AD/DNS
    Write-Log "Configuring Windows Firewall..."
    Enable-NetFirewallRule -DisplayName "Active Directory Domain Controller (TCP-In)" -Confirm:$false -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayName "DNS (TCP)" -Confirm:$false -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayName "DNS (UDP)" -Confirm:$false -ErrorAction SilentlyContinue
    
    # Change local admin password
    Write-Log "Updating local admin password..."
    $localAdmin = [ADSI]"WinNT://./Administrator"
    $localAdmin.SetPassword($LocalAdminPassword)
    
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
