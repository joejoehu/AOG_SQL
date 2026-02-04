# Quick Start Guide - RedCross SQL Deployment

## 5-Minute Quick Start

### 1. Prerequisites Check

```bash
# Verify required tools
terraform -version          # Should be >= 1.0
az version                  # Azure CLI installed
pwsh -Version              # PowerShell >= 5.1
```

### 2. Update Configuration

```bash
# Edit terraform.tfvars
nano terraform.tfvars       # or use your editor

# Update this line with your Azure Subscription ID
subscription_id = "YOUR_SUBSCRIPTION_ID_HERE"
```

Get your subscription ID:
```bash
az account list --output table
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 3. Deploy Infrastructure

```bash
cd /Users/joe/DATA/CODE/AOG_SQL

# Initialize Terraform
terraform init

# Preview what will be created
terraform plan

# Deploy (type 'yes' when prompted)
terraform apply
```

### 4. Wait for Deployment

- **Terraform**: ~5 minutes to create resources
- **DC Setup**: ~10 minutes (custom script extension + reboot)
- **SQL Setup**: ~15 minutes (SQL install + domain join + reboot)
- **Total**: ~30 minutes

### 5. Verify Deployment

```bash
# Get all VM IPs and endpoints
terraform output credentials_summary

# Get Key Vault for password retrieval
terraform output key_vault_name

# Retrieve passwords from Azure Key Vault
VAULT=$(terraform output -raw key_vault_name)
az keyvault secret show --vault-name $VAULT --name domain-admin-password
```

### 6. Connect to VMs

```bash
# Get IPs
terraform output credentials_summary

# Connect via RDP
# Domain Controller: 10.38.0.4
# SQL-1 Primary: 10.38.1.4
# SQL-2 Primary: 10.38.2.4
```

### 7. Configure Always On Availability Group (Post-Deployment)

After VMs are domain-joined (~15 min after deployment):

```powershell
# Run on SQL-VM-1
./scripts/setup-ag.ps1
```

Follow the T-SQL commands provided in the script output.

## Common Tasks

### Restart a VM

```bash
az vm restart --resource-group rg-redcross-sql --name vm-sql-1
```

### Check VM Status

```bash
az vm get-instance-view --resource-group rg-redcross-sql --name vm-dc-1 \
  --query "instanceView.statuses"
```

### View Custom Script Extension Logs

```bash
# On the VM via RDP:
Get-Content C:\dc-setup.log
Get-Content C:\sql-setup.log
```

### Retrieve Password

```bash
VAULT=$(terraform output -raw key_vault_name)
az keyvault secret show --vault-name $VAULT --name domain-admin-password --query value -o tsv
```

### Destroy All Resources

```bash
terraform destroy
# Type 'yes' to confirm
```

## Troubleshooting Quick Fixes

**VMs not coming up?**
```bash
# Check custom script extension status
az vm extension show --resource-group rg-redcross-sql \
  --vm-name vm-dc-1 --name DC-VM1-Setup \
  --query "provisioningState"
```

**Can't connect to DC?**
```bash
# Check NSG rules
az network nsg rule list --resource-group rg-redcross-sql \
  --nsg-name nsg-dc --output table
```

**Domain join failed?**
1. Ensure DC VMs are fully rebooted (10 min wait)
2. Check DNS: `nslookup redcross.local 10.38.0.4` from SQL VM
3. View logs: `Get-Content C:\sql-setup.log` on SQL VM

**Always On setup issues?**
```sql
-- Enable Always On on SQL instance
Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\vm-sql-1.redcross.local\DEFAULT -Force
```

## Network IPs Quick Reference

| VM | Primary IP | Cluster IP | Listener IP |
|----|-----------|-----------|-----------|
| DC-1 | 10.38.0.4 | - | - |
| DC-2 | 10.38.0.5 | - | - |
| SQL-1 | 10.38.1.4 | 10.38.1.10 | 10.38.1.11 |
| SQL-2 | 10.38.2.4 | 10.38.2.10 | 10.38.2.11 |

## Credentials Quick Reference

| Item | Username | Location |
|------|----------|----------|
| Domain Admin | redcross\redcross_admin | Azure Key Vault: domain-admin-password |
| SQL Service | redcross\sql_service | Azure Key Vault: sql-service-password |
| Local Admin | Administrator | Azure Key Vault: local-admin-password |

## Next Steps

1. ✅ Run `terraform apply`
2. ⏳ Wait 30 minutes for VMs to complete setup
3. 🔐 Retrieve passwords from Key Vault
4. 🔗 Connect to VMs via RDP
5. 🗄️ Configure Always On Availability Group (see [setup-ag.ps1](scripts/setup-ag.ps1))
6. 📊 Add databases to AG
7. 🧪 Test failover

See [README.md](README.md) for detailed documentation.
