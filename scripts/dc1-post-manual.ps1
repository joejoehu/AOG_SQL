# Log in as: CORP\Administrator (or your NetBIOS name)
# Password: Your Windows Administrator password

# Verify AD DS is running
Get-Service -Name NTDS, DNS, Netlogon | Select-Object Name, Status

# Verify domain functional level
Get-ADDomain | Select-Object Name, DomainMode, Forest

# Verify DNS zones
Get-DnsServerZone

# Check domain controller role
Get-ADDomainController | Select-Object Name, IPv4Address, IsGlobalCatalog

# Verify AD Sites and Services
Get-ADReplicationSite


# Add Google DNS as forwarders (or use Azure DNS 168.63.129.16)
Add-DnsServerForwarder -IPAddress "8.8.8.8", "8.8.4.4" -PassThru

# Or use Azure DNS
# Add-DnsServerForwarder -IPAddress "168.63.129.16" -PassThru

# Verify forwarders
Get-DnsServerForwarder

# Via Azure CLI (run from Azure Cloud Shell or local machine)
<# az network vnet update \
  --name vnet-redcross \
  --resource-group  rg-redcross-sql \
  --dns-servers 10.38.0.4  # Your DC's static IP #>

# Restart VMs in the VNet for DNS changes to take effect