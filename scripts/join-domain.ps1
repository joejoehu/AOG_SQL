<#
.SYNOPSIS
    Joins an Azure Windows VM to an Active Directory domain.

.DESCRIPTION
    Standalone script to join any Azure Windows VM to the domain.
    - Waits for Domain Controller connectivity (LDAP port 389)
    - Configures DNS to point to both Domain Controllers
    - Joins the computer to the domain
    - Schedules a reboot to finalize the join

.PARAMETER DomainName
    FQDN of the Active Directory domain. Default: redcross.local

.PARAMETER DomainAdminUser
    Domain admin username used for the join operation. Default: redcross_admin

.PARAMETER DomainAdminPassword
    Plaintext password for the domain admin account. Required.

.PARAMETER PrimaryDCIP
    IP address of the primary Domain Controller. Default: 10.38.0.4

.PARAMETER SecondaryDCIP
    IP address of the secondary Domain Controller. Default: 10.38.0.5

.EXAMPLE
    .\join-domain.ps1 -DomainAdminPassword 'MyP@ssw0rd!'

.EXAMPLE
    .\join-domain.ps1 -DomainName 'contoso.local' -DomainAdminUser 'admin' -DomainAdminPassword 'P@ss' -PrimaryDCIP '10.0.0.4' -SecondaryDCIP '10.0.0.5'
#>

param(
    [string]$DomainName = "redcross.local",
    [string]$DomainAdminUser = "redcross_admin",
    [Parameter(Mandatory = $true)]
    [string]$DomainAdminPassword,
    [string]$PrimaryDCIP = "10.38.0.4",
    [string]$SecondaryDCIP = "10.38.0.5"
)

$ErrorActionPreference = 'Stop'

# ── Logging ──────────────────────────────────────────────────────────────────
$logDir = "C:\Logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "join-domain.log"
Start-Transcript -Path $logFile -Append -Force
Write-Host "=========================================="
Write-Host " Join-Domain Script"
Write-Host " Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host " Target Domain: $DomainName"
Write-Host " Domain Admin:  $DomainAdminUser"
Write-Host " Primary DC:    $PrimaryDCIP"
Write-Host " Secondary DC:  $SecondaryDCIP"
Write-Host "=========================================="

# ── 1. Wait for Domain Controller connectivity ──────────────────────────────
Write-Host "`n[Step 1/4] Waiting for Domain Controller at $PrimaryDCIP (LDAP port 389)..."
$maxAttempts = 30
$sleepSeconds = 10
$connected = $false

for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($PrimaryDCIP, 389)
        $tcp.Close()
        $connected = $true
        Write-Host "  DC is reachable on attempt $i."
        break
    }
    catch {
        Write-Host "  Attempt $i/$maxAttempts - DC not reachable yet. Retrying in ${sleepSeconds}s..."
        Start-Sleep -Seconds $sleepSeconds
    }
}

if (-not $connected) {
    Write-Error "FATAL: Could not reach Domain Controller at ${PrimaryDCIP}:389 after $maxAttempts attempts."
    Stop-Transcript
    exit 1
}

# ── 2. Configure DNS to use Domain Controllers ──────────────────────────────
Write-Host "`n[Step 2/4] Setting DNS servers to $PrimaryDCIP, $SecondaryDCIP..."
try {
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
    if (-not $adapter) {
        Write-Error "FATAL: No active network adapter found."
        Stop-Transcript
        exit 1
    }
    Write-Host "  Using adapter: $($adapter.Name) (ifIndex $($adapter.ifIndex))"
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($PrimaryDCIP, $SecondaryDCIP)
    Write-Host "  DNS servers configured successfully."
    
    # Flush DNS cache to pick up new settings immediately
    Clear-DnsClientCache
    Write-Host "  DNS cache flushed."
}
catch {
    Write-Error "FATAL: Failed to configure DNS - $_"
    Stop-Transcript
    exit 1
}

# ── 3. Join the domain ──────────────────────────────────────────────────────
Write-Host "`n[Step 3/4] Joining computer to domain '$DomainName'..."
try {
    # Check if already joined
    $currentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
    if ($currentDomain -eq $DomainName) {
        Write-Host "  Computer is already joined to '$DomainName'. Skipping join."
    }
    else {
        Write-Host "  Current domain/workgroup: $currentDomain"
        $securePassword = ConvertTo-SecureString $DomainAdminPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential(
            "$DomainName\$DomainAdminUser",
            $securePassword
        )
        Add-Computer -DomainName $DomainName -Credential $credential -Force -Confirm:$false
        Write-Host "  Successfully joined domain '$DomainName'."
    }
}
catch {
    Write-Error "FATAL: Domain join failed - $_"
    Stop-Transcript
    exit 1
}

# ── 4. Schedule reboot ──────────────────────────────────────────────────────
Write-Host "`n[Step 4/4] Scheduling reboot in 30 seconds to finalize domain join..."
Write-Host "  Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Stop-Transcript
shutdown /r /t 30 /c "Rebooting to finalize domain join to $DomainName"


# Always exit 0 so the Custom Script Extension reports success
exit 0