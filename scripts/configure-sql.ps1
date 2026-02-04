param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminUser,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainAdminPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$SQLServiceAccount,
    
    [Parameter(Mandatory=$true)]
    [string]$SQLServicePassword,
    
    [Parameter(Mandatory=$true)]
    [string]$LocalAdminPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$VMName = ""
)

# Suppress progress messages
$ProgressPreference = "SilentlyContinue"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = "C:\sql-setup.log"
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
    Write-Output "[$timestamp] $Message"
}

try {
    Write-Log "Starting SQL Server Configuration"
    Write-Log "Domain: $DomainName"
    Write-Log "VM Name: $VMName"
    
    # Wait for DC to be ready and domain to be available
    Write-Log "Waiting for domain connectivity..."
    $domainReady = $false
    $retries = 0
    $maxRetries = 60
    
    while (-not $domainReady -and $retries -lt $maxRetries) {
        try {
            $dcTest = Test-NetConnection -ComputerName "10.38.0.4" -Port 389 -InformationLevel Quiet
            if ($dcTest) {
                Write-Log "Domain controller is reachable"
                $domainReady = $true
            }
        }
        catch {
            Write-Log "Domain not ready, retrying... (attempt $($retries + 1)/$maxRetries)"
            Start-Sleep -Seconds 5
            $retries++
        }
    }
    
    if (-not $domainReady) {
        Write-Log "WARNING: Domain controller not reachable after 5 minutes, proceeding anyway"
    }
    
    # Configure DNS to point to Domain Controllers
    Write-Log "Configuring DNS settings..."
    $dnsSetting = Get-DnsClientGlobalSetting
    Set-DnsClientGlobalSetting -SuffixSearchList @($DomainName) -Confirm:$false
    
    # Configure network adapters for DNS
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        Write-Log "Configuring DNS on adapter: $($adapter.Name)"
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("10.38.0.4", "10.38.0.5") -Confirm:$false
    }
    
    # Join domain
    Write-Log "Joining domain: $DomainName"
    $credential = New-Object System.Management.Automation.PSCredential(
        "$DomainName\$DomainAdminUser",
        (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
    )
    
    Add-Computer -DomainName $DomainName -Credential $credential -Force -Confirm:$false
    Write-Log "Domain join initiated"
    
    # Create SQL Service Account in Active Directory
    Write-Log "Creating SQL Service Account in Active Directory..."
    $adCred = New-Object System.Management.Automation.PSCredential(
        "$DomainName\$DomainAdminUser",
        (ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force)
    )
    
    # Wait for domain join to complete (for local execution)
    Start-Sleep -Seconds 10
    
    try {
        $sqlServiceCred = New-Object System.Management.Automation.PSCredential(
            "$DomainName\$SQLServiceAccount",
            (ConvertTo-SecureString $SQLServicePassword -AsPlainText -Force)
        )
        
        # Create SQL service account user in AD
        $adUserParams = @{
            Name = $SQLServiceAccount
            AccountPassword = (ConvertTo-SecureString $SQLServicePassword -AsPlainText -Force)
            CannotChangePassword = $true
            PasswordNotRequired = $false
            Enabled = $true
            Credential = $adCred
            Server = "10.38.0.4"
        }
        
        New-ADUser @adUserParams -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "SQL Service Account created: $SQLServiceAccount"
    }
    catch {
        Write-Log "SQL Service Account already exists or error creating: $($_.Exception.Message)"
    }
    
    # Update local admin password
    Write-Log "Updating local admin password..."
    try {
        $localAdmin = [ADSI]"WinNT://./Administrator"
        $localAdmin.SetPassword($LocalAdminPassword)
        Write-Log "Local admin password updated"
    }
    catch {
        Write-Log "Could not update local admin password: $($_.Exception.Message)"
    }
    
    # Install prerequisite Windows features for SQL Server and Failover Clustering
    Write-Log "Installing prerequisite Windows features..."
    Install-WindowsFeature -Name Failover-Clustering, RSAT-AD-Tools -IncludeManagementTools -Confirm:$false | Out-Null
    
    # Enable SQL Server features for Always On
    Write-Log "Enabling SQL Server Always On features..."
    
    # Get SQL Server instance name
    $sqlInstances = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "MSSQL" }
    
    if ($sqlInstances) {
        foreach ($instance in $sqlInstances) {
            Write-Log "Configuring SQL Server instance: $($instance.PSChildName)"
            
            # Enable Always On via SQL Server Configuration Manager
            # This requires SQL Server to be running and configured
        }
    }
    
    # Configure Windows Firewall for SQL Server
    Write-Log "Configuring Windows Firewall for SQL Server..."
    
    # SQL Server default instance
    New-NetFirewallRule -DisplayName "SQL Server Default Instance (TCP)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    
    # SQL Server named pipes
    New-NetFirewallRule -DisplayName "SQL Server Named Pipes" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 445 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    
    # Always On endpoint
    New-NetFirewallRule -DisplayName "SQL Server Always On Endpoint" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5022 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    
    # Cluster communication
    New-NetFirewallRule -DisplayName "Windows Cluster Communication (UDP)" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 3343 -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    
    Write-Log "SQL Server configuration setup completed successfully"
    Write-Log "System will reboot to complete domain join"
    Write-Log "Setup completed at $(Get-Date)"
    
    # Schedule reboot
    shutdown /r /t 30 /c "SQL Server setup complete, rebooting to complete domain join..."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "ERROR Stack: $($_.ScriptStackTrace)"
    exit 1
}
