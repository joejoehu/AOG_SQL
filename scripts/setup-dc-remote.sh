#!/bin/bash

################################################################################
# Domain Controller Remote Setup via Azure CLI
# 
# This script orchestrates the complete setup of a Domain Controller on Azure
# using `az vm run-command invoke` to execute PowerShell commands remotely.
#
# Usage:
#   ./setup-dc-remote.sh \
#     --subscription-id <subscription-id> \
#     --resource-group <resource-group> \
#     --vm-name <vm-name> \
#     --domain-name <domain.local> \
#     --domain-admin-user <username> \
#     --domain-admin-password <password> \
#     --vm-admin-password <password> \
#     [--is-first-dc true|false] \
#     [--primary-dc-ip <ip-address>] \
#     [--dns-forwarder <8.8.8.8|168.63.129.16>] \
#     [--data-drive F|C]
#
# Example:
#   ./setup-dc-remote.sh \
#     --subscription-id 45befe1a-5a11-4644-8876-273bdf9e6a68 \
#     --resource-group rg-redcross-sql \
#     --vm-name VM-DC-1 \
#     --domain-name redcross.local \
#     --domain-admin-user redcross_admin \
#     --domain-admin-password 'P@ssw0rd123!' \
#     --vm-admin-password 'P@ssw0rd123!' \
#     --is-first-dc true
#
################################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
IS_FIRST_DC="true"
PRIMARY_DC_IP="10.38.0.4"
DNS_FORWARDER="8.8.8.8"
DATA_DRIVE="F"
VNET_NAME="vnet-redcross"
DC_SUBNET_NAME="subnet-dc"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --subscription-id)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --domain-name)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --domain-admin-user)
                DOMAIN_ADMIN_USER="$2"
                shift 2
                ;;
            --domain-admin-password)
                DOMAIN_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --vm-admin-password)
                VM_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --is-first-dc)
                IS_FIRST_DC="$2"
                shift 2
                ;;
            --primary-dc-ip)
                PRIMARY_DC_IP="$2"
                shift 2
                ;;
            --dns-forwarder)
                DNS_FORWARDER="$2"
                shift 2
                ;;
            --data-drive)
                DATA_DRIVE="$2"
                shift 2
                ;;
            --vnet-name)
                VNET_NAME="$2"
                shift 2
                ;;
            --dc-subnet-name)
                DC_SUBNET_NAME="$2"
                shift 2
                ;;
            *)
                error "Unknown parameter: $1"
                ;;
        esac
    done
}

# Validate required parameters
validate_parameters() {
    [[ -z "$SUBSCRIPTION_ID" ]] && error "Missing required parameter: --subscription-id"
    [[ -z "$RESOURCE_GROUP" ]] && error "Missing required parameter: --resource-group"
    [[ -z "$VM_NAME" ]] && error "Missing required parameter: --vm-name"
    [[ -z "$DOMAIN_NAME" ]] && error "Missing required parameter: --domain-name"
    [[ -z "$DOMAIN_ADMIN_USER" ]] && error "Missing required parameter: --domain-admin-user"
    [[ -z "$DOMAIN_ADMIN_PASSWORD" ]] && error "Missing required parameter: --domain-admin-password"
    [[ -z "$VM_ADMIN_PASSWORD" ]] && error "Missing required parameter: --vm-admin-password"
    
    log "Parameters validated successfully"
}

# Check Azure CLI is installed and authenticated
check_azure_cli() {
    log "Checking Azure CLI installation..."
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first: https://learn.microsoft.com/cli/azure/install-azure-cli"
    fi
    
    log "Setting Azure subscription context..."
    az account set --subscription "$SUBSCRIPTION_ID" || error "Failed to set subscription. Verify the subscription ID is correct."
    
    log "Azure CLI check passed"
}

# Validate DNS IP format
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Invalid IP address format: $ip"
    fi
}

# Execute remote command via Azure CLI
execute_remote_command() {
    local command_id=$1
    local script=$2
    local timeout=${3:-3600}  # Default 1 hour timeout
    
    log "Executing remote command: $command_id"
    
    # Escape single quotes in PowerShell script by replacing ' with ''
    local escaped_script="${script//\'/\'\'}"
    
    local result=$(az vm run-command invoke \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --command-id RunPowerShellScript \
        --scripts "$escaped_script" \
        --output json 2>&1)
    
    echo "$result"
}

# Phase 1: Initialize data disk and format
phase_disk_initialization() {
    log "=========================================="
    log "PHASE 1: Disk Initialization"
    log "=========================================="
    
    local ps_script=$(cat <<'PWSH'
# Check if F: drive exists
$driveExists = Get-Disk | Where-Object DriveLetter -eq 'F' -ErrorAction SilentlyContinue

if (-not $driveExists) {
    Write-Output "[DISK] Initializing raw disk..."
    
    try {
        $rawDisk = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Select-Object -First 1
        
        if ($rawDisk) {
            Write-Output "[DISK] Found raw disk: $($rawDisk.Number)"
            
            $rawDisk | Initialize-Disk -PartitionStyle GPT -PassThru | 
                New-Partition -DriveLetter F -UseMaximumSize | 
                Format-Volume -FileSystem NTFS -NewFileSystemLabel "AD_DATA" -Confirm:$false
            
            Write-Output "[DISK] F: drive initialized and formatted successfully"
            Start-Sleep -Seconds 5
        }
        else {
            Write-Output "[DISK] No raw disk found. Skipping initialization."
        }
    }
    catch {
        Write-Output "[DISK] Error during initialization: $($_.Exception.Message)"
    }
}
else {
    Write-Output "[DISK] F: drive already exists. Skipping initialization."
}

# Create AD data directories
Write-Output "[DISK] Creating AD data directories..."
$paths = @("F:\NTDS", "F:\SYSVOL", "F:\AD_LOG")

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-Output "[DISK] Created: $path"
    }
    else {
        Write-Output "[DISK] Directory exists: $path"
    }
}

Write-Output "[DISK] Disk initialization phase completed"
PWSH
)
    
    execute_remote_command "DiskInitialization" "$ps_script"
    log "Disk initialization phase completed"
}

# Phase 2: Install AD DS and DNS roles
phase_install_roles() {
    log "=========================================="
    log "PHASE 2: Install AD DS and DNS Roles"
    log "=========================================="
    
    local ps_script=$(cat <<'PWSH'
Write-Output "[ROLES] Starting Windows Features installation..."

try {
    # Install AD DS and DNS
    Write-Output "[ROLES] Installing AD-Domain-Services and DNS..."
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -IncludeAllSubFeature -Confirm:$false
    
    Write-Output "[ROLES] Installation completed"
    
    # Verify installation
    Write-Output "[ROLES] Verifying installation..."
    $features = Get-WindowsFeature | Where-Object {$_.Name -like "*AD-Domain*" -or $_.Name -eq "DNS"}
    
    foreach ($feature in $features) {
        if ($feature.Installed) {
            Write-Output "[ROLES] ✓ $($feature.Name) is installed"
        }
        else {
            Write-Output "[ROLES] ✗ $($feature.Name) is NOT installed"
        }
    }
}
catch {
    Write-Output "[ROLES] Error: $($_.Exception.Message)"
    exit 1
}
PWSH
)
    
    execute_remote_command "InstallRoles" "$ps_script"
    log "AD DS and DNS installation phase completed"
}

# Phase 3: Configure DNS client
phase_configure_dns_client() {
    log "=========================================="
    log "PHASE 3: Configure DNS Client"
    log "=========================================="
    
    local ps_script=$(cat <<'PWSH'
Write-Output "[DNS] Configuring local DNS client..."

try {
    $InterfaceAlias = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name | Select-Object -First 1
    
    if ($InterfaceAlias) {
        Write-Output "[DNS] Configuring DNS on interface: $InterfaceAlias"
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses "127.0.0.1"
        
        # Verify configuration
        $dnsConfig = Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
        Write-Output "[DNS] DNS servers configured: $($dnsConfig.ServerAddresses -join ', ')"
    }
    else {
        Write-Output "[DNS] ERROR: No active network adapter found"
        exit 1
    }
}
catch {
    Write-Output "[DNS] Error: $($_.Exception.Message)"
    exit 1
}
PWSH
)
    
    execute_remote_command "ConfigureDnsClient" "$ps_script"
    log "DNS client configuration completed"
}

# Phase 4: Promote to Domain Controller (First DC or Additional DC)
phase_promote_dc() {
    log "=========================================="
    log "PHASE 4: Domain Controller Promotion"
    log "=========================================="
    
    # Extract NetBios name from domain name (first part before dot)
    NETBIOS_NAME=$(echo "$DOMAIN_NAME" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')
    
    if [[ ${#NETBIOS_NAME} -gt 15 ]]; then
        NETBIOS_NAME="${NETBIOS_NAME:0:15}"
        warning "NetBios name truncated to 15 characters: $NETBIOS_NAME"
    fi
    
    log "Domain: $DOMAIN_NAME"
    log "NetBios: $NETBIOS_NAME"
    log "Database Path: $DATA_DRIVE:\NTDS"
    log "Is First DC: $IS_FIRST_DC"
    
    if [[ "$IS_FIRST_DC" == "true" ]]; then
        phase_promote_first_dc
    else
        phase_promote_additional_dc
    fi
}

# Promote First Domain Controller - Create new forest
phase_promote_first_dc() {
    log "Promoting to FIRST Domain Controller (creating new forest)..."
    
    local ps_script=$(cat <<PWSH
\$DomainName = "$DOMAIN_NAME"
\$NetBiosName = "$NETBIOS_NAME"
\$DSRMPassword = ConvertTo-SecureString "$DOMAIN_ADMIN_PASSWORD" -AsPlainText -Force
\$DatabasePath = "$DATA_DRIVE`:\NTDS"
\$LogPath = "$DATA_DRIVE`:\AD_LOG"
\$SysvolPath = "$DATA_DRIVE`:\SYSVOL"

Write-Output "[DC-PROMOTE] Starting Forest Creation..."
Write-Output "[DC-PROMOTE] Domain: \$DomainName"
Write-Output "[DC-PROMOTE] NetBios: \$NetBiosName"
Write-Output "[DC-PROMOTE] Database Path: \$DatabasePath"
Write-Output "[DC-PROMOTE] Log Path: \$LogPath"
Write-Output "[DC-PROMOTE] Sysvol Path: \$SysvolPath"

try {
    # Verify paths exist
    foreach (\$path in @(\$DatabasePath, \$LogPath, \$SysvolPath)) {
        if (-not (Test-Path \$path)) {
            Write-Output "[DC-PROMOTE] Creating path: \$path"
            New-Item -Path \$path -ItemType Directory -Force | Out-Null
        }
    }
    
    # Create new forest
    Install-ADDSForest \`
        -DomainName \$DomainName \`
        -DomainNetbiosName \$NetBiosName \`
        -SafeModeAdministratorPassword \$DSRMPassword \`
        -DatabasePath \$DatabasePath \`
        -LogPath \$LogPath \`
        -SysvolPath \$SysvolPath \`
        -InstallDns \`
        -CreateDnsDelegation:\$false \`
        -NoRebootOnCompletion:\$false \`
        -Force \`
        -Confirm:\$false
    
    Write-Output "[DC-PROMOTE] Forest creation initiated. Server will reboot automatically."
}
catch {
    Write-Output "[DC-PROMOTE] ERROR: \$(\$_.Exception.Message)"
    exit 1
}
PWSH
)
    
    execute_remote_command "PromoteFirstDC" "$ps_script" 1800
}

# Promote Additional Domain Controller
phase_promote_additional_dc() {
    log "Promoting to ADDITIONAL Domain Controller (joining existing forest)..."
    
    local ps_script=$(cat <<PWSH
\$DomainName = "$DOMAIN_NAME"
\$PrimaryDCIP = "$PRIMARY_DC_IP"
\$DomainAdminUser = "$DOMAIN_ADMIN_USER"
\$DomainAdminPassword = ConvertTo-SecureString "$DOMAIN_ADMIN_PASSWORD" -AsPlainText -Force
\$DomainAdminCred = New-Object System.Management.Automation.PSCredential("\$DomainName\\\$DomainAdminUser", \$DomainAdminPassword)
\$DSRMPassword = ConvertTo-SecureString "$DOMAIN_ADMIN_PASSWORD" -AsPlainText -Force
\$DatabasePath = "$DATA_DRIVE`:\NTDS"
\$LogPath = "$DATA_DRIVE`:\AD_LOG"
\$SysvolPath = "$DATA_DRIVE`:\SYSVOL"

Write-Output "[DC-PROMOTE] Starting Additional DC Promotion..."
Write-Output "[DC-PROMOTE] Domain: \$DomainName"
Write-Output "[DC-PROMOTE] Primary DC IP: \$PrimaryDCIP"
Write-Output "[DC-PROMOTE] Database Path: \$DatabasePath"

try {
    # Set primary DC as DNS server temporarily
    Write-Output "[DC-PROMOTE] Setting DNS to primary DC: \$PrimaryDCIP"
    \$InterfaceAlias = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceAlias \$InterfaceAlias -ServerAddresses \$PrimaryDCIP
    
    Start-Sleep -Seconds 5
    
    # Verify paths exist
    foreach (\$path in @(\$DatabasePath, \$LogPath, \$SysvolPath)) {
        if (-not (Test-Path \$path)) {
            Write-Output "[DC-PROMOTE] Creating path: \$path"
            New-Item -Path \$path -ItemType Directory -Force | Out-Null
        }
    }
    
    # Install as replica DC
    Install-ADDSDomainController \`
        -DomainName \$DomainName \`
        -Credential \$DomainAdminCred \`
        -SafeModeAdministratorPassword \$DSRMPassword \`
        -DatabasePath \$DatabasePath \`
        -LogPath \$LogPath \`
        -SysvolPath \$SysvolPath \`
        -InstallDns \`
        -NoRebootOnCompletion:\$false \`
        -Force \`
        -Confirm:\$false
    
    Write-Output "[DC-PROMOTE] DC promotion initiated. Server will reboot automatically."
}
catch {
    Write-Output "[DC-PROMOTE] ERROR: \$(\$_.Exception.Message)"
    exit 1
}
PWSH
)
    
    execute_remote_command "PromoteAdditionalDC" "$ps_script" 1800
}

# Phase 5: Configure DNS Forwarders (wait for reboot to complete)
phase_configure_dns_forwarders() {
    log "=========================================="
    log "PHASE 5: Configure DNS Forwarders"
    log "=========================================="
    
    log "Waiting for DC promotion and reboot to complete (30 seconds)..."
    sleep 30
    
    log "Configuring DNS forwarders to: $DNS_FORWARDER"
    validate_ip "$DNS_FORWARDER"
    
    local ps_script=$(cat <<PWSH
\$DnsForwarder = "$DNS_FORWARDER"

Write-Output "[DNS-FWD] Configuring DNS forwarders..."

try {
    # Remove existing forwarders if any
    Write-Output "[DNS-FWD] Clearing existing forwarders..."
    Remove-DnsServerForwarder -IPAddress (Get-DnsServerForwarder).IPAddress -Force -ErrorAction SilentlyContinue
    
    # Add new forwarder
    Write-Output "[DNS-FWD] Adding forwarder: \$DnsForwarder"
    Add-DnsServerForwarder -IPAddress \$DnsForwarder -PassThru
    
    # Verify configuration
    Write-Output "[DNS-FWD] Current forwarders:"
    Get-DnsServerForwarder | Select-Object IPAddress
}
catch {
    Write-Output "[DNS-FWD] Error: \$(\$_.Exception.Message)"
    exit 1
}
PWSH
)
    
    execute_remote_command "ConfigureDnsForwarders" "$ps_script"
    log "DNS forwarders configuration completed"
}

# Phase 6: Update VNet DNS settings via Azure CLI
#      --output json | grep -o '"privateIpAddress": "[^"]*"' | cut -d'"' -f4 | head -1)
phase_update_vnet_dns() {
    log "=========================================="
    log "PHASE 6: Update VNet DNS Settings"
    log "=========================================="
    
    # Get DC static IP
    log "Retrieving DC IP address..."
    local dc_ip=$(az vm list-ip-addresses \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --query "[0].virtualMachine.network.privateIpAddresses[0]" \
        --output tsv
    
    if [[ -z "$dc_ip" ]]; then
        error "Failed to retrieve DC IP address"
    fi
    
    log "DC IP Address: $dc_ip"
    log "Updating VNet DNS servers..."
    
    az network vnet update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --dns-servers "$dc_ip" \
        --output none || error "Failed to update VNet DNS settings"
    
    log "VNet DNS settings updated successfully"
}

# Phase 7: Verification
phase_verification() {
    log "=========================================="
    log "PHASE 7: Verification"
    log "=========================================="
    
    local ps_script=$(cat <<'PWSH'
Write-Output "[VERIFY] Starting verification..."

try {
    # Check AD DS services
    Write-Output "[VERIFY] Checking AD DS services..."
    $services = Get-Service -Name NTDS, DNS, Netlogon, ADWS -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "Running"}
    
    foreach ($svc in $services) {
        Write-Output "[VERIFY] ✓ $($svc.Name) is running"
    }
    
    # Check domain
    Write-Output "[VERIFY] Checking domain information..."
    $domain = Get-ADDomain -ErrorAction SilentlyContinue
    if ($domain) {
        Write-Output "[VERIFY] ✓ Domain: $($domain.Name)"
        Write-Output "[VERIFY] ✓ Forest: $($domain.Forest)"
        Write-Output "[VERIFY] ✓ Functional Level: $($domain.DomainMode)"
    }
    
    # Check DC role
    Write-Output "[VERIFY] Checking Domain Controller role..."
    $dc = Get-ADDomainController -ErrorAction SilentlyContinue
    if ($dc) {
        Write-Output "[VERIFY] ✓ DC Name: $($dc.Name)"
        Write-Output "[VERIFY] ✓ IPv4 Address: $($dc.IPv4Address)"
        Write-Output "[VERIFY] ✓ Global Catalog: $($dc.IsGlobalCatalog)"
    }
    
    # Check DNS zones
    Write-Output "[VERIFY] Checking DNS zones..."
    $zones = Get-DnsServerZone | Where-Object {$_.ZoneType -eq "Primary"} | Select-Object -First 3
    foreach ($zone in $zones) {
        Write-Output "[VERIFY] ✓ DNS Zone: $($zone.Name)"
    }
    
    # Check DNS forwarders
    Write-Output "[VERIFY] Checking DNS forwarders..."
    $forwarders = Get-DnsServerForwarder
    Write-Output "[VERIFY] DNS Forwarders: $($forwarders.IPAddress -join ', ')"
    
    Write-Output "[VERIFY] Verification completed successfully"
}
catch {
    Write-Output "[VERIFY] Warning: Some verification checks failed: $($_.Exception.Message)"
}
PWSH
)
    
    execute_remote_command "Verification" "$ps_script"
    log "Verification phase completed"
}

# Main execution
main() {
    log "=========================================="
    log "Domain Controller Remote Setup via Azure CLI"
    log "=========================================="
    log ""
    
    parse_arguments "$@"
    validate_parameters
    check_azure_cli
    
    log "Starting DC setup orchestration..."
    log "Subscription: $SUBSCRIPTION_ID"
    log "Resource Group: $RESOURCE_GROUP"
    log "VM Name: $VM_NAME"
    log "Domain: $DOMAIN_NAME"
    log ""
    
    # Execute phases in order
    phase_disk_initialization
    phase_install_roles
    phase_configure_dns_client
    phase_promote_dc
    phase_configure_dns_forwarders
    phase_update_vnet_dns
    phase_verification
    
    log ""
    log "=========================================="
    log "✓ Domain Controller setup completed!"
    log "=========================================="
    log "Domain Controller: $VM_NAME"
    log "Domain: $DOMAIN_NAME"
    log "Admin User: $DOMAIN_ADMIN_USER"
    log ""
    log "Next steps:"
    log "  1. Verify DNS is resolving: nslookup $DOMAIN_NAME"
    log "  2. Wait 5-10 minutes for replication to stabilize"
    log "  3. Configure SQL Server VMs to join the domain"
    log "  4. Setup SQL Always On Availability Group"
}

# Run main function
main "$@"
