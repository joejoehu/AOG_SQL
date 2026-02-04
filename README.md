# RedCross SQL Server Always On Availability Group - Azure Terraform Deployment

## Project Overview

This Terraform configuration deploys a complete SQL Server 2022 Always On Availability Group infrastructure on Azure with the following components:

- **2 Domain Controller VMs** (VM-DC-1, VM-DC-2) running Windows Server 2022 with Active Directory and DNS services
- **2 SQL Server VMs** (VM-SQL-1, VM-SQL-2) running Windows Server 2022 with SQL Server 2022
- **3 Subnets** with specific CIDR blocks for DC and SQL tiers
- **Azure Key Vault** for secure password management
- **Always On Availability Group** configuration templates for post-deployment setup
- **Multiple Network Interfaces** per SQL VM for database, cluster, and listener traffic

## Infrastructure Topology

```
Azure Virtual Network: 10.38.0.0/16
│
├── DC Subnet: 10.38.0.0/24
│   ├── DC-VM-1 (AZ1): 10.38.0.4
│   └── DC-VM-2 (AZ2): 10.38.0.5
│
├── SQL Subnet 1: 10.38.1.0/24 (Availability Zone 1)
│   └── SQL-VM-1: Primary (10.38.1.4) + Cluster (10.38.1.10) + Listener (10.38.1.11)
│
└── SQL Subnet 2: 10.38.2.0/24 (Availability Zone 2)
    └── SQL-VM-2: Primary (10.38.2.4) + Cluster (10.38.2.10) + Listener (10.38.2.11)

Domain: redcross.local
Service Accounts: redcross_admin, sql_service
```

## Prerequisites

1. **Azure Subscription** - Active Azure subscription with sufficient quota
2. **Terraform** - Version 1.0 or later
3. **Azure CLI** - Installed and authenticated
4. **PowerShell** - Version 5.1 or later (for manual AG setup)
5. **Git** - For cloning scripts to GitHub (optional, for custom script extensions)

## File Structure

```
/AOG_SQL/
├── provider.tf              # Azure provider configuration
├── variables.tf             # Variable definitions
├── locals.tf                # Local values and random password generation
├── main.tf                  # Main Terraform resources
├── outputs.tf               # Output definitions
├── terraform.tfvars         # Variable values (UPDATE REQUIRED)
├── README.md               # This file
└── scripts/
    ├── configure-dc.ps1    # Domain Controller setup script
    ├── configure-sql.ps1   # SQL Server and domain join setup
    └── setup-ag.ps1        # Always On Availability Group configuration guide
```

## Pre-Deployment Steps

### 1. Update terraform.tfvars

Edit `terraform.tfvars` and update the following required values:

```hcl
subscription_id = "YOUR_SUBSCRIPTION_ID_HERE"  # REQUIRED: Your Azure Subscription ID
```

Optional customizations:
- `location` - Azure region (default: Switzerland North)
- `resource_group_name` - Resource group name
- `environment` - Environment identifier
- `tags` - Resource tags for cost tracking

### 2. Prepare PowerShell Scripts

The custom script extensions in `main.tf` reference scripts hosted on GitHub. You have two options:

**Option A: Host scripts on GitHub (Recommended)**
```bash
git clone https://github.com/your-repo/azure-scripts.git
cd azure-scripts
cp /path/to/scripts/* .
git add .
git commit -m "Add RedCross SQL deployment scripts"
git push
```

Then update the `fileUris` in `main.tf` to point to your GitHub repository:
```hcl
fileUris = ["https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/configure-dc.ps1"]
```

**Option B: Use Azure Storage Account**
```bash
az storage account create --name mystorageaccount --resource-group rg-redcross-sql --location eastus
az storage container create --name scripts --account-name mystorageaccount
az storage blob upload-batch --destination scripts --source ./scripts --account-name mystorageaccount
```

### 3. Authenticate to Azure

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

## Deployment Steps

### 1. Initialize Terraform

```bash
cd /Users/joe/DATA/CODE/AOG_SQL
terraform init
```

This initializes the Terraform working directory and downloads required providers.

### 2. Plan Deployment

```bash
terraform plan -out=tfplan
```

Review the plan to ensure all resources will be created as expected.

### 3. Apply Configuration

```bash
terraform apply tfplan
```

This will create:
- Resource Group
- Virtual Network with 3 subnets
- Network Security Groups with firewall rules
- Azure Key Vault with random passwords
- 2 Domain Controller VMs
- 2 SQL Server VMs with multiple NICs
- Custom script extensions for DC and SQL setup

**Estimated deployment time: 20-30 minutes**

### 4. Monitor Deployment

```bash
# Watch deployment progress
az deployment group list --resource-group rg-redcross-sql

# Get VM deployment status
az vm get-instance-view --resource-group rg-redcross-sql --name vm-dc-1 \
  --query instanceView.statuses[?contains(code, 'PowerState')]

# View custom script extension status
az vm extension list --resource-group rg-redcross-sql --vm-name vm-dc-1
```

## Post-Deployment Configuration

### 1. Verify VM Deployment

```bash
# List all deployed VMs
az vm list --resource-group rg-redcross-sql --output table

# Get VM details and IPs
terraform output credentials_summary
```

### 2. Wait for Domain Controller Setup

The DC VMs will automatically reboot after AD/DNS installation. Wait 10-15 minutes before proceeding to SQL setup.

```bash
# Check DC-VM-1 status
az vm get-instance-view --resource-group rg-redcross-sql --name vm-dc-1 \
  --query "instanceView.statuses[?code=='PowerState/running']"
```

### 3. Wait for SQL Server VMs Setup

The SQL VMs will undergo domain join and custom configuration. They may reboot multiple times.

```bash
# Monitor custom script extension logs
az vm extension show --resource-group rg-redcross-sql \
  --vm-name vm-sql-1 --name SQL-VM1-Setup
```

### 4. Retrieve Credentials from Key Vault

```bash
# Get Key Vault name
VAULT_NAME=$(terraform output -raw key_vault_name)

# Retrieve passwords
az keyvault secret show --vault-name $VAULT_NAME --name domain-admin-password
az keyvault secret show --vault-name $VAULT_NAME --name sql-service-password
az keyvault secret show --vault-name $VAULT_NAME --name local-admin-password
```

### 5. Connect to VMs via RDP

```bash
# Get VM IPs
terraform output credentials_summary

# Connect via RDP (Windows)
mstsc /v:10.38.0.4  # DC-VM-1
mstsc /v:10.38.1.4  # SQL-VM-1
```

### 6. Verify Domain Join on SQL VMs

1. RDP to SQL-VM-1 or SQL-VM-2
2. Right-click "This PC" → Properties
3. Verify computer is member of "redcross.local" domain
4. Verify SQL Server service is running under "redcross\sql_service" account

## Always On Availability Group Configuration

After all VMs are deployed and domain-joined, configure the Always On Availability Group:

### Option 1: Using Provided Script (Automated Guide)

```powershell
# Run on SQL-VM-1 after domain join is complete
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
./setup-ag.ps1 -SQL1VMName "vm-sql-1" -SQL2VMName "vm-sql-2" -DomainName "redcross.local"
```

This script generates all the T-SQL commands needed for AG setup.

### Option 2: Manual Configuration (Step-by-Step)

See [scripts/setup-ag.ps1](scripts/setup-ag.ps1) for detailed T-SQL commands for:
1. Enabling Always On on both SQL instances
2. Creating database mirroring endpoints
3. Creating the Availability Group
4. Joining the secondary replica
5. Creating AG listener
6. Adding databases to AG

### Key Configuration Parameters

| Parameter | Value |
|-----------|-------|
| Availability Group Name | AG-RedCross |
| Listener Name | Listener-RedCross |
| Listener IPs | 10.38.1.11, 10.38.2.11 |
| Listener Port | 1433 |
| Database Endpoint Port | 5022 |
| Failover Mode | Automatic |
| Availability Mode | Synchronous Commit |
| Domain | redcross.local |
| Service Account | redcross\sql_service |

## Network Configuration Details

### Network Interface Cards (NICs) per SQL VM

Each SQL VM has 3 NICs for traffic separation:

| NIC Name | IP Address | Purpose | Subnet |
|----------|-----------|---------|--------|
| nic-sql-vm1-primary | 10.38.1.4 | Database connections | SQL-Subnet-1 |
| nic-sql-vm1-cluster | 10.38.1.10 | Cluster communication | SQL-Subnet-1 |
| nic-sql-vm1-listener | 10.38.1.11 | AG listener VIP | SQL-Subnet-1 |

### Network Security Group Rules

**DC NSG (Port Access):**
- RDP: 3389
- DNS: 53 (TCP/UDP)
- Kerberos: 88
- LDAP: 389
- LDAPS: 636
- WinRM: 5985-5986

**SQL NSG (Port Access):**
- RDP: 3389
- SQL Server: 1433
- Named Pipes: 445
- Always On: 5022
- DNS: 53 (TCP/UDP)
- WinRM: 5985-5986
- Cluster Communication: All ports from VNet (10.38.0.0/16)

## Troubleshooting

### Custom Script Extension Failures

If custom script extensions fail, check the logs on the VMs:

```powershell
# Connect to the VM via RDP and check:
Get-Content C:\dc-setup.log   # For DC VMs
Get-Content C:\sql-setup.log  # For SQL VMs
```

Also check Azure logs:
```bash
az vm extension show --resource-group rg-redcross-sql \
  --vm-name vm-dc-1 --name DC-VM1-Setup \
  --query typeHandlerVersion
```

### Domain Join Issues

1. Verify DC VMs have completed setup and rebooted
2. Check DNS resolution: `nslookup redcross.local 10.38.0.4`
3. Verify network connectivity to DC subnet
4. Check firewall rules for required ports

### SQL Server Always On Issues

1. Verify SQL Server is installed and running
2. Check SQL Server service account is "redcross\sql_service"
3. Verify certificate-based authentication is configured
4. Check database mirroring endpoints on port 5022
5. Test connectivity between cluster IPs (10.38.1.10 → 10.38.2.10)

## Security Best Practices

1. **Store Passwords Securely**: All passwords are generated and stored in Azure Key Vault
   ```bash
   az keyvault secret show --vault-name $VAULT_NAME --name domain-admin-password
   ```

2. **Rotate Passwords After Deployment**:
   - Change local admin passwords via Control Panel
   - Update domain admin password via Active Directory Users and Computers
   - Update SQL service account password via SQL Server Configuration Manager

3. **Network Isolation**: 
   - NSGs restrict traffic to required ports only
   - VMs are not exposed to public internet
   - Use Azure Bastion or VPN for remote access

4. **Enable Monitoring**:
   ```bash
   # Enable VM insights
   az vm extension set --resource-group rg-redcross-sql \
     --vm-name vm-dc-1 --name DependencyAgentLinux
   ```

## Cost Optimization

### Estimated Monthly Costs (Switzerland North, Standard LRS)
- **4x Standard_E2s_v3 VMs**: ~$400/month
- **Azure Key Vault**: <$1/month
- **Disks (8x 128GB)**: ~$64/month
- **Virtual Network & NSGs**: <$1/month
- **Total Estimated**: ~$465/month

To reduce costs:
- Use Standard_B2s for lower traffic scenarios
- Delete unused VMs during non-business hours
- Use Reserved Instances for long-term deployments
- Implement VM auto-shutdown policies

## Cleanup

To delete all resources created by this Terraform configuration:

```bash
# Review what will be deleted
terraform plan -destroy

# Delete all resources
terraform destroy

# Confirm the prompt
yes
```

This will remove:
- All VMs and disks
- Virtual Network and subnets
- NSGs and network interfaces
- Key Vault
- Resource Group (if using default)

## Outputs

After successful deployment, Terraform outputs include:

```bash
# View all outputs
terraform output

# View specific output
terraform output credentials_summary
terraform output ag_configuration_guide
```

Key outputs:
- Resource Group name
- Virtual Network ID
- VM names and IPs
- Key Vault URI
- Connection strings for clients
- AG configuration parameters

## Support and Documentation

### Key Files
- [scripts/configure-dc.ps1](scripts/configure-dc.ps1) - DC setup script
- [scripts/configure-sql.ps1](scripts/configure-sql.ps1) - SQL setup script
- [scripts/setup-ag.ps1](scripts/setup-ag.ps1) - AG configuration guide
- [terraform.tfvars](terraform.tfvars) - Configuration values

### Official Documentation
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [SQL Server Always On AG](https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-availability-groups-sql-server)
- [Windows Server Active Directory](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/ad-ds-overview)

## Version Information

- **Terraform**: >= 1.0
- **Azure Provider**: >= 3.0
- **Windows Server**: 2022 Datacenter
- **SQL Server**: 2022 Standard Edition
- **Created**: February 4, 2026

## License and Disclaimer

This Terraform configuration is provided as-is. Ensure you have appropriate Azure subscriptions, licenses, and permissions before deployment. Test in non-production environments first.

---

**Last Updated**: February 4, 2026
**Author**: Cloud Infrastructure Team
