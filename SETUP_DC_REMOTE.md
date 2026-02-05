# Domain Controller Remote Setup Guide

This guide explains how to set up your Domain Controllers remotely using Azure CLI orchestration.

## Overview

The remote DC setup process uses two scripts:

1. **`setup-dc-remote.sh`** - Main Bash orchestration script (runs on your local machine)
   - Orchestrates the entire setup process
   - Uses `az vm run-command invoke` to execute PowerShell commands remotely on Azure VMs
   - No files need to be uploaded - PowerShell code is executed inline
   - Platform: macOS, Linux, Windows (WSL)

2. **`configure-dc1-pre.ps1`** - PowerShell DC setup script (parameterized)
   - Disk initialization and formatting
   - Role installation (AD DS, DNS)
   - DNS client configuration
   - Forest/Domain Controller promotion
   - Can be used locally as a reference or manual execution

## Prerequisites

### Required
- **Azure CLI** - installed and authenticated
  ```bash
  # Install (macOS)
  brew install azure-cli
  
  # Verify installation
  az version
  ```

- **Microsoft Azure Subscription** with:
  - Virtual Network created (10.38.0.0/16 by default)
  - DC subnet created (10.38.0.0/24 by default)
  - Windows Server 2022 VM deployed in DC subnet with:
    - Static IP (e.g., 10.38.0.4)
    - VM admin password configured
    - Data disk attached and visible to the VM (will be formatted as F:)

### Recommended
- **Bash shell** (zsh or bash) - for running the orchestration script
- **PowerShell 7+** (optional) - for testing locally

## Setup Steps

### Step 1: Verify Azure CLI Authentication

```bash
# Login to Azure
az login

# Set default subscription
az account set --subscription <YOUR_SUBSCRIPTION_ID>

# Verify
az account show
```

### Step 2: Configuration

Update the following information:

```bash
SUBSCRIPTION_ID="45befe1a-5a11-4644-8876-273bdf9e6a68"  # From terraform.tfvars
RESOURCE_GROUP="rg-redcross-sql"
VM_NAME="VM-DC-1"                               # First DC
DOMAIN_NAME="redcross.local"                    # From terraform.tfvars
DOMAIN_ADMIN_USER="redcross_admin"              # From terraform.tfvars
DOMAIN_ADMIN_PASSWORD="YourSecurePassword123!"  # Generate via Key Vault
VM_ADMIN_PASSWORD="YourSecurePassword123!"      # Generate via Key Vault
VNET_NAME="vnet-redcross"                       # From terraform.tfvars
```

### Step 3: Run the Setup Script

#### **First Domain Controller (Forest Root)**

```bash
./scripts/setup-dc-remote.sh \
  --subscription-id "45befe1a-5a11-4644-8876-273bdf9e6a68" \
  --resource-group "rg-redcross-sql" \
  --vm-name "VM-DC-1" \
  --domain-name "redcross.local" \
  --domain-admin-user "redcross_admin" \
  --domain-admin-password "P@ssw0rd123!" \
  --vm-admin-password "P@ssw0rd123!" \
  --is-first-dc true \
  --vnet-name "vnet-redcross"
```

**Expected Duration:** 15-20 minutes
- Phase 1 (Disk Init): 2-3 minutes
- Phase 2 (Role Install): 3-5 minutes
- Phase 3 (DNS Config): 1 minute
- Phase 4 (DC Promotion): 5-10 minutes ⚠️ **VM will reboot**
- Phase 5-7 (DNS Forwarders, VNet Update, Verification): 2-3 minutes

#### **Second Domain Controller (Replica)**

Wait 10-15 minutes after first DC finishes and VNet DNS updates complete.

```bash
./scripts/setup-dc-remote.sh \
  --subscription-id "45befe1a-5a11-4644-8876-273bdf9e6a68" \
  --resource-group "rg-redcross-sql" \
  --vm-name "VM-DC-2" \
  --domain-name "redcross.local" \
  --domain-admin-user "redcross_admin" \
  --domain-admin-password "P@ssw0rd123!" \
  --vm-admin-password "P@ssw0rd123!" \
  --is-first-dc false \
  --primary-dc-ip "10.38.0.4" \
  --vnet-name "vnet-redcross"
```

**Expected Duration:** 10-15 minutes (similar phases but shorter)

### Step 4: Verify Setup Completion

After the script completes:

```bash
# Check ADS services on DC
az vm run-command invoke \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --command-id RunPowerShellScript \
  --scripts 'Get-Service -Name NTDS, DNS, Netlogon | Select-Object Name, Status'

# Check domain info
az vm run-command invoke \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --command-id RunPowerShellScript \
  --scripts 'Get-ADDomain | Select-Object Name, DomainMode, Forest'

# Check DNS zones
az vm run-command invoke \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --command-id RunPowerShellScript \
  --scripts 'Get-DnsServerZone | Where-Object ZoneType -eq Primary'
```

### Step 5: Configure SQL Server VMs

Once DCs are fully operational (allow 10-15 minutes for replication):

1. Update SQL VM Network Configuration to use DC DNS:
   ```bash
   # Azure Portal or CLI: Set DNS servers to DC IP (e.g., 10.38.0.4)
   az network vnet update \
     --resource-group rg-redcross-sql \
     --name vnet-redcross \
     --dns-servers 10.38.0.4 10.38.0.5
   ```

2. Domain-join SQL Server VMs using `configure-sql.ps1`

3. Configure Always On Availability Group using `setup-ag.ps1`

## Execution Phases Explained

### Phase 1: Disk Initialization
- Detects raw/uninitialized data disk
- Initializes as GPT partition
- Formats with NTFS
- Creates AD database directories (F:\NTDS, F:\AD_LOG, F:\SYSVOL)

### Phase 2: Install AD DS and DNS Roles
- Installs Windows Features for Active Directory Domain Services
- Installs DNS role with management tools
- Verifies installation

### Phase 3: Configure DNS Client
- Points local DNS client to 127.0.0.1 (self)
- Ensures VM resolves internal DNS queries

### Phase 4: Promote Domain Controller
- **First DC:** Creates new Active Directory forest and domain
- **Additional DC:** Joins existing forest as replica DC
- Installs DNS integrated with AD
- Triggers automatic VM reboot

### Phase 5: Configure DNS Forwarders
- Adds forwarders for external DNS resolution
- Default: Google DNS (8.8.8.8) or can use Azure DNS (168.63.129.16)

### Phase 6: Update VNet DNS
- Updates Azure Virtual Network DNS settings
- Points all VMs in VNet to new DC(s)

### Phase 7: Verification
- Checks AD DS services status
- Verifies domain functionality
- Confirms DNS zones exist
- Validates DC role and replication

## Troubleshooting

### Script Won't Run
```bash
# Check permissions
ls -la scripts/setup-dc-remote.sh

# Fix if needed
chmod +x scripts/setup-dc-remote.sh

# Check Bash syntax
bash -n scripts/setup-dc-remote.sh
```

### Azure CLI Errors
```bash
# Verify authentication
az account show

# Re-authenticate if needed
az login

# Check subscription
az account list --output table
```

### Remote Execution Fails
```bash
# Check VM is running
az vm get-instance-view \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --query "instanceView.statuses[1].displayStatus"

# Check VM can receive run commands (must be running)
az vm run-command invoke \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --command-id RunPowerShellScript \
  --scripts 'Write-Output "VM is responding"'
```

### DC Promotion Issues
```bash
# Check log file on VM (wait for reboot to complete first)
az vm run-command invoke \
  --resource-group rg-redcross-sql \
  --name VM-DC-1 \
  --command-id RunPowerShellScript \
  --scripts 'Get-ChildItem C:\dc-setup*.log | Select-Object -First 1 | Get-Content -Tail 50'
```

### Domain Join Fails for Second DC
- Ensure first DC DNS is fully operational (10-15 minutes minimum)
- Verify network connectivity between DCs
- Check firewall rules allow AD/DNS traffic (ports 53, 88, 389, 445, 636, 3268-3269)

## Manual Local Execution (Optional)

If you prefer to execute the PowerShell script locally on the VM:

```powershell
# Run on Windows Server VM as Administrator
.\configure-dc1-pre.ps1 `
  -DomainName "redcross.local" `
  -DomainAdminUser "redcross_admin" `
  -DomainAdminPassword "P@ssw0rd123!" `
  -NetBiosName "REDCROSS" `
  -IsFirstDC $true
```

## Security Considerations

### Passwords
- ⚠️ **Never commit passwords to git**
- Use Azure Key Vault for credential management
- Pass passwords via environment variables or secure parameter entry
- Rotate passwords regularly

### DNS Forwarders
- **Google DNS (8.8.8.8)** - public internet resolution
- **Azure DNS (168.63.129.16)** - Azure internal services only
- Adjust based on your security policy

### Network Segmentation
- DCs should be in isolated subnet (10.38.0.0/24)
- SQL VMs in separate subnets (10.38.1.0/24, 10.38.2.0/24)
- Configure NSGs for least-privilege access

## Next Steps

1. ✅ Validate DC setup with verification commands
2. ✅ Wait 15+ minutes for AD replication to stabilize
3. ➜ Run `configure-sql.ps1` to domain-join SQL VMs
4. ➜ Configure SQL Always On Availability Group with `setup-ag.ps1`
5. ➜ Test failover and availability group replication

## Support

For issues or questions:
1. Check script output for specific error messages
2. Review log files in `C:\dc-setup-*.log` on the VM
3. Verify Azure CLI and subscription authentication
4. Consult [Azure AD Setup Docs](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services)

