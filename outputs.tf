output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "key_vault_id" {
  description = "Key Vault ID"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Key Vault Name"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "virtual_network_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.main.id
}

output "virtual_network_name" {
  description = "Virtual Network Name"
  value       = azurerm_virtual_network.main.name
}

output "virtual_network_address_space" {
  description = "Virtual Network Address Space"
  value       = azurerm_virtual_network.main.address_space
}

# ============================================================================
# SUBNET OUTPUTS
# ============================================================================

output "dc_subnet_id" {
  description = "DC Subnet ID"
  value       = azurerm_subnet.dc_subnet.id
}

output "dc_subnet_name" {
  description = "DC Subnet Name"
  value       = azurerm_subnet.dc_subnet.name
}

output "dc_subnet_cidr" {
  description = "DC Subnet CIDR"
  value       = azurerm_subnet.dc_subnet.address_prefixes[0]
}

output "sql_subnet_1_id" {
  description = "SQL Subnet 1 ID"
  value       = azurerm_subnet.sql_subnet_1.id
}

output "sql_subnet_1_name" {
  description = "SQL Subnet 1 Name"
  value       = azurerm_subnet.sql_subnet_1.name
}

output "sql_subnet_1_cidr" {
  description = "SQL Subnet 1 CIDR"
  value       = azurerm_subnet.sql_subnet_1.address_prefixes[0]
}

output "sql_subnet_2_id" {
  description = "SQL Subnet 2 ID"
  value       = azurerm_subnet.sql_subnet_2.id
}

output "sql_subnet_2_name" {
  description = "SQL Subnet 2 Name"
  value       = azurerm_subnet.sql_subnet_2.name
}

output "sql_subnet_2_cidr" {
  description = "SQL Subnet 2 CIDR"
  value       = azurerm_subnet.sql_subnet_2.address_prefixes[0]
}

# ============================================================================
# DC VM OUTPUTS
# ============================================================================

output "dc_vm1_id" {
  description = "DC VM 1 ID"
  value       = azurerm_windows_virtual_machine.dc_vm1.id
}

output "dc_vm1_name" {
  description = "DC VM 1 Name"
  value       = azurerm_windows_virtual_machine.dc_vm1.name
}

output "dc_vm1_private_ip" {
  description = "DC VM 1 Private IP"
  value       = azurerm_network_interface.dc_vm1_nic.private_ip_address
}

output "dc_vm1_fqdn" {
  description = "DC VM 1 FQDN"
  value       = "vm-dc-1.redcross.local"
}

output "dc_vm2_id" {
  description = "DC VM 2 ID"
  value       = azurerm_windows_virtual_machine.dc_vm2.id
}

output "dc_vm2_name" {
  description = "DC VM 2 Name"
  value       = azurerm_windows_virtual_machine.dc_vm2.name
}

output "dc_vm2_private_ip" {
  description = "DC VM 2 Private IP"
  value       = azurerm_network_interface.dc_vm2_nic.private_ip_address
}

output "dc_vm2_fqdn" {
  description = "DC VM 2 FQDN"
  value       = "vm-dc-2.redcross.local"
}

# ============================================================================
# SQL VM 1 OUTPUTS
# ============================================================================

output "sql_vm1_id" {
  description = "SQL VM 1 ID"
  value       = azurerm_windows_virtual_machine.sql_vm1.id
}

output "sql_vm1_name" {
  description = "SQL VM 1 Name"
  value       = azurerm_windows_virtual_machine.sql_vm1.name
}

output "sql_vm1_primary_ip" {
  description = "SQL VM 1 Primary Network Interface IP (Database)"
  value       = "10.38.1.4"
}

output "sql_vm1_cluster_ip" {
  description = "SQL VM 1 Cluster Network Interface IP (Cluster Communication)"
  value       = "10.38.1.10"
}

output "sql_vm1_listener_ip" {
  description = "SQL VM 1 Listener Network Interface IP (AG Listener)"
  value       = "10.38.1.11"
}

output "sql_vm1_fqdn" {
  description = "SQL VM 1 FQDN"
  value       = "vm-sql-1.redcross.local"
}

# ============================================================================
# SQL VM 2 OUTPUTS
# ============================================================================

output "sql_vm2_id" {
  description = "SQL VM 2 ID"
  value       = azurerm_windows_virtual_machine.sql_vm2.id
}

output "sql_vm2_name" {
  description = "SQL VM 2 Name"
  value       = azurerm_windows_virtual_machine.sql_vm2.name
}

output "sql_vm2_primary_ip" {
  description = "SQL VM 2 Primary Network Interface IP (Database)"
  value       = "10.38.2.4"
}

output "sql_vm2_cluster_ip" {
  description = "SQL VM 2 Cluster Network Interface IP (Cluster Communication)"
  value       = "10.38.2.10"
}

output "sql_vm2_listener_ip" {
  description = "SQL VM 2 Listener Network Interface IP (AG Listener)"
  value       = "10.38.2.11"
}

output "sql_vm2_fqdn" {
  description = "SQL VM 2 FQDN"
  value       = "vm-sql-2.redcross.local"
}

# ============================================================================
# KEY VAULT SECRETS OUTPUTS
# ============================================================================

output "domain_admin_secret_id" {
  description = "Domain Admin Password Secret ID"
  value       = azurerm_key_vault_secret.domain_admin_password.id
  sensitive   = true
}

output "sql_service_secret_id" {
  description = "SQL Service Account Password Secret ID"
  value       = azurerm_key_vault_secret.sql_service_password.id
  sensitive   = true
}

output "local_admin_secret_id" {
  description = "Local Admin Password Secret ID"
  value       = azurerm_key_vault_secret.local_admin_password.id
  sensitive   = true
}

output "dsrm_secret_id" {
  description = "DSRM Password Secret ID"
  value       = azurerm_key_vault_secret.dsrm_password.id
  sensitive   = true
}

# ============================================================================
# CREDENTIALS SUMMARY (For Reference)
# ============================================================================

output "credentials_summary" {
  description = "Summary of credentials and connection information"
  value = {
    domain_name                  = "redcross.local"
    domain_admin_username        = "redcross\\redcross_admin"
    sql_service_account          = "redcross\\sql_service"
    dc_vm1_ip                    = azurerm_network_interface.dc_vm1_nic.private_ip_address
    dc_vm2_ip                    = azurerm_network_interface.dc_vm2_nic.private_ip_address
    sql_vm1_primary_ip           = "10.38.1.4"
    sql_vm2_primary_ip           = "10.38.2.4"
    ag_listener_ips              = ["10.38.1.11", "10.38.2.11"]
    ag_listener_port             = "1433"
    sql_endpoint_port            = "5022"
    vault_name                   = azurerm_key_vault.main.name
    retrieve_domain_admin_secret = "az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name domain-admin-password"
    retrieve_sql_service_secret  = "az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name sql-service-password"
    retrieve_local_admin_secret  = "az keyvault secret show --vault-name ${azurerm_key_vault.main.name} --name local-admin-password"
  }
  sensitive = true
}

# ============================================================================
# AG LISTENER CONFIGURATION GUIDE
# ============================================================================

output "ag_configuration_guide" {
  description = "Guide for Always On Availability Group configuration"
  value = {
    step_1_enable_always_on              = "Run: Enable-SqlAlwaysOn -Path SQLSERVER:\\SQL\\vm-sql-1.redcross.local\\DEFAULT -Force on both SQL VMs"
    step_2_create_endpoints              = "Create database mirroring endpoints on port 5022 with certificate-based authentication"
    step_3_create_ag                     = "Create AG 'AG-RedCross' with automatic failover and synchronous-commit mode"
    step_4_join_secondary                = "Run: ALTER AVAILABILITY GROUP [AG-RedCross] JOIN on secondary SQL Server"
    step_5_create_listener               = "Create AG listener 'Listener-RedCross' on IPs 10.38.1.11 and 10.38.2.11, port 1433"
    step_6_add_databases                 = "Add user databases to AG using backup/restore process"
    ag_name                              = "AG-RedCross"
    listener_name                        = "Listener-RedCross"
    listener_ips                         = ["10.38.1.11", "10.38.2.11"]
    listener_port                        = "1433"
    sql_primary_fqdn                     = "vm-sql-1.redcross.local"
    sql_secondary_fqdn                   = "vm-sql-2.redcross.local"
    sql_primary_endpoint_url             = "TCP://vm-sql-1.redcross.local:5022"
    sql_secondary_endpoint_url           = "TCP://vm-sql-2.redcross.local:5022"
    documentation_file                   = "./scripts/setup-ag.ps1"
  }
}

# ============================================================================
# DEPLOYMENT VALIDATION CHECKLIST
# ============================================================================

output "validation_checklist" {
  description = "Post-deployment validation steps"
  value = {
    verify_dc_reachability                = "ping 10.38.0.4 and 10.38.0.5 from the SQL VMs"
    verify_domain_join                    = "Check 'System Properties' on SQL VMs to verify domain membership"
    verify_dns_resolution                 = "nslookup vm-sql-1.redcross.local from SQL VMs"
    verify_sql_service_account            = "Check Active Directory Users and Computers for redcross\\sql_service"
    verify_sql_service_startup            = "Verify SQL Server service is running under redcross\\sql_service account"
    verify_cluster_communication          = "Test connectivity on cluster NIC IPs (10.38.1.10, 10.38.2.10)"
    verify_listener_ips                   = "Verify listener NIC IPs are reachable (10.38.1.11, 10.38.2.11)"
    verify_ag_endpoints                   = "Verify database mirroring endpoints created on port 5022"
    retrieve_passwords_from_vault         = "Use Azure CLI: az keyvault secret show --vault-name <vault-name> --name <secret-name>"
    passwords_location                    = "All passwords stored in Azure Key Vault: ${azurerm_key_vault.main.name}"
  }
}
