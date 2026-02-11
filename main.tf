# Data source for current context
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${substr(md5(azurerm_resource_group.main.id), 0, 8)}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  enabled_for_deployment     = true

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Set",
      "List",
      "Delete",
      "Recover",
      "Backup",
      "Restore",
      "Purge"
    ]
  }

  tags = local.common_tags
}

# Store Domain Admin Password in Key Vault
resource "azurerm_key_vault_secret" "domain_admin_password" {
  name         = "domain-admin-password"
  value        = local.domain_admin_password
  key_vault_id = azurerm_key_vault.main.id
}

# Store SQL Service Account Password in Key Vault
resource "azurerm_key_vault_secret" "sql_service_password" {
  name         = "sql-service-password"
  value        = local.sql_service_password
  key_vault_id = azurerm_key_vault.main.id
}

# Store Local Admin Password in Key Vault
resource "azurerm_key_vault_secret" "local_admin_password" {
  name         = "local-admin-password"
  value        = local.local_admin_password
  key_vault_id = azurerm_key_vault.main.id
}

# Store DSRM Password in Key Vault
resource "azurerm_key_vault_secret" "dsrm_password" {
  name         = "dsrm-password"
  value        = local.dsrm_password
  key_vault_id = azurerm_key_vault.main.id
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

# DC Subnet
resource "azurerm_subnet" "dc_subnet" {
  name                 = "subnet-dc"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.dc_subnet_cidr]
}

# SQL Subnet 1
resource "azurerm_subnet" "sql_subnet_1" {
  name                 = "subnet-sql-1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.sql_subnet_1_cidr]
}

# SQL Subnet 2
resource "azurerm_subnet" "sql_subnet_2" {
  name                 = "subnet-sql-2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.sql_subnet_2_cidr]
}

# Network Security Group for DC
resource "azurerm_network_security_group" "dc_nsg" {
  name                = "nsg-dc"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowDNS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowKerberos"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "88"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowLDAP"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "389"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowLDAPS"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "636"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowWinRM"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowICMP"
    priority                   = 105
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Security Group for SQL
resource "azurerm_network_security_group" "sql_nsg" {
  name                = "nsg-sql"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSQL"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSQLNamedPipes"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "445"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAG"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5022"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowDNS"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowWinRM"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowClusterComm"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.38.0.0/16"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Associate NSGs with Subnets
resource "azurerm_subnet_network_security_group_association" "dc_nsg_assoc" {
  subnet_id                 = azurerm_subnet.dc_subnet.id
  network_security_group_id = azurerm_network_security_group.dc_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "sql_nsg_1_assoc" {
  subnet_id                 = azurerm_subnet.sql_subnet_1.id
  network_security_group_id = azurerm_network_security_group.sql_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "sql_nsg_2_assoc" {
  subnet_id                 = azurerm_subnet.sql_subnet_2.id
  network_security_group_id = azurerm_network_security_group.sql_nsg.id
}

# ============================================================================
# NETWORK INTERFACES
# ============================================================================

# DC-VM-1 NIC
resource "azurerm_network_interface" "dc_vm1_nic" {
  name                = "nic-dc-vm1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.dc_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.0.4"
  }

  tags = local.common_tags
}

# DC-VM-2 NIC
resource "azurerm_network_interface" "dc_vm2_nic" {
  name                = "nic-dc-vm2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.dc_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.0.5"
  }

  tags = local.common_tags
}

# SQL-VM-1 NIC with multiple IP configurations
resource "azurerm_network_interface" "sql_vm1_nic" {
  name                = "nic-sql-vm1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.sql_subnet_1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.1.4"
    primary                       = true
  }

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = azurerm_subnet.sql_subnet_1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.1.10"
  }

  ip_configuration {
    name                          = "ipconfig3"
    subnet_id                     = azurerm_subnet.sql_subnet_1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.1.11"
  }

  tags = local.common_tags
}

# SQL-VM-2 NIC with multiple IP configurations
resource "azurerm_network_interface" "sql_vm2_nic" {
  name                = "nic-sql-vm2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.sql_subnet_2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.2.4"
    primary                       = true
  }

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = azurerm_subnet.sql_subnet_2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.2.10"
  }

  ip_configuration {
    name                          = "ipconfig3"
    subnet_id                     = azurerm_subnet.sql_subnet_2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.38.2.11"
  }

  tags = local.common_tags
}

# ============================================================================
# STORAGE ACCOUNTS FOR VM DIAGNOSTICS
# ============================================================================

resource "azurerm_storage_account" "diag_storage" {
  name                     = "diag${substr(md5(azurerm_resource_group.main.id), 0, 16)}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

# ============================================================================
# DOMAIN CONTROLLER VMs
# ============================================================================

resource "azurerm_windows_virtual_machine" "dc_vm1" {
  name                = "vm-dc-1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_size
  zone                = "1"

  admin_username = local.domain_admin_username
  admin_password = local.domain_admin_password

  network_interface_ids = [
    azurerm_network_interface.dc_vm1_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.dc_vm1_nic,
    azurerm_key_vault_secret.domain_admin_password
  ]

  tags = local.common_tags
}


# ============================================================================

# STAGE 1 CUSTOM SCRIPT EXTENSION FOR DC-VM-1

# ============================================================================

resource "azurerm_virtual_machine_extension" "dc1_stage1_cse" {
  name                 = "dc1-stage1-cse"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc_vm1.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = ["https://raw.githubusercontent.com/joejoehu/AOG_SQL/main/scripts/dc1-pre.ps1"]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -Command \"& {Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force; .\\dc1-pre.ps1 -DSRMPasswordPlainText '${local.dsrm_password}'}\""
  })

  depends_on = [
    azurerm_windows_virtual_machine.dc_vm1,
    azurerm_windows_virtual_machine.dc_vm2,
    azurerm_windows_virtual_machine.sql_vm1,
    azurerm_windows_virtual_machine.sql_vm2,
    azurerm_virtual_machine_data_disk_attachment.dc_vm1_data_disk_attach,
    azurerm_virtual_machine_data_disk_attachment.dc_vm2_data_disk_attach,
    azurerm_virtual_machine_data_disk_attachment.sql_vm1_data_disk_attach,
    azurerm_virtual_machine_data_disk_attachment.sql_vm2_data_disk_attach
  ]

  tags = local.common_tags
}


resource "azurerm_windows_virtual_machine" "dc_vm2" {
  name                = "vm-dc-2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_size
  zone                = "2"

  admin_username = local.domain_admin_username
  admin_password = local.domain_admin_password

  network_interface_ids = [
    azurerm_network_interface.dc_vm2_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.dc_vm2_nic,
    azurerm_key_vault_secret.domain_admin_password
  ]

  tags = local.common_tags
}

# ============================================================================
# DATA DISKS FOR DOMAIN CONTROLLER VMs
# ============================================================================

# Data Disk for DC-VM-1
resource "azurerm_managed_disk" "dc_vm1_data_disk" {
  name                = "disk-dc-vm1-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_type = var.storage_account_type
  create_option       = "Empty"
  disk_size_gb        = var.data_disk_size_gb
  zone                = "1"

  tags = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "dc_vm1_data_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.dc_vm1_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.dc_vm1.id
  lun                = 0
  caching            = "None"
}

# Data Disk for DC-VM-2
resource "azurerm_managed_disk" "dc_vm2_data_disk" {
  name                = "disk-dc-vm2-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_type = var.storage_account_type
  create_option       = "Empty"
  disk_size_gb        = var.data_disk_size_gb
  zone                = "2"

  tags = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "dc_vm2_data_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.dc_vm2_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.dc_vm2.id
  lun                = 0
  caching            = "None"
}


# ============================================================================
# SQL SERVER VMs
# ============================================================================

resource "azurerm_windows_virtual_machine" "sql_vm1" {
  name                = "vm-sql-1"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_size
  zone                = "1"

  admin_username = local.domain_admin_username
  admin_password = local.domain_admin_password

  network_interface_ids = [
    azurerm_network_interface.sql_vm1_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2022-ws2022"
    sku       = "sqldev-gen2"
    version   = "latest"
  }

  depends_on = [
    azurerm_windows_virtual_machine.dc_vm1,
    azurerm_windows_virtual_machine.dc_vm2
  ]

  tags = local.common_tags
}

resource "azurerm_windows_virtual_machine" "sql_vm2" {
  name                = "vm-sql-2"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = local.vm_size
  zone                = "2"

  admin_username = local.domain_admin_username
  admin_password = local.domain_admin_password

  network_interface_ids = [
    azurerm_network_interface.sql_vm2_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.storage_account_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2022-ws2022"
    sku       = "sqldev-gen2"
    version   = "latest"
  }

  depends_on = [
    azurerm_windows_virtual_machine.dc_vm1,
    azurerm_windows_virtual_machine.dc_vm2
  ]

  tags = local.common_tags
}

# ============================================================================
# DATA DISKS FOR SQL SERVER VMs
# ============================================================================

# Data Disk for SQL-VM-1
resource "azurerm_managed_disk" "sql_vm1_data_disk" {
  name                = "disk-sql-vm1-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_type = var.storage_account_type
  create_option       = "Empty"
  disk_size_gb        = var.data_disk_size_gb
  zone                = "1"

  tags = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "sql_vm1_data_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.sql_vm1_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.sql_vm1.id
  lun                = 0
  caching            = "ReadWrite"
}

# Data Disk for SQL-VM-2
resource "azurerm_managed_disk" "sql_vm2_data_disk" {
  name                = "disk-sql-vm2-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_type = var.storage_account_type
  create_option       = "Empty"
  disk_size_gb        = var.data_disk_size_gb
  zone                = "2"

  tags = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "sql_vm2_data_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.sql_vm2_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.sql_vm2.id
  lun                = 0
  caching            = "ReadWrite"
}



# ============================================================================
# STAGE 2 CUSTOM SCRIPT EXTENSION - JOIN SQL-VM-1 TO DOMAIN
# ============================================================================
resource "azurerm_virtual_machine_extension" "sql1_stage2_cse" {
  name                 = "sql1-stage2-cse"
  virtual_machine_id   = azurerm_windows_virtual_machine.sql_vm1.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = ["https://raw.githubusercontent.com/joejoehu/AOG_SQL/main/scripts/join-domain.ps1"]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -Command \"& {Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force; .\\join-domain.ps1 -DomainAdminPassword '${local.domain_admin_password}'}\""
  })

  depends_on = [
    azurerm_virtual_machine_extension.dc1_stage1_cse,
    azurerm_virtual_machine_data_disk_attachment.sql_vm1_data_disk_attach
  ]

  tags = local.common_tags
}

# ============================================================================
# STAGE 3 CUSTOM SCRIPT EXTENSION - JOIN SQL-VM-2 TO DOMAIN
# ============================================================================
resource "azurerm_virtual_machine_extension" "sql2_stage3_cse" {
  name                 = "sql2-stage3-cse"
  virtual_machine_id   = azurerm_windows_virtual_machine.sql_vm2.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    fileUris = ["https://raw.githubusercontent.com/joejoehu/AOG_SQL/main/scripts/join-domain.ps1"]
  })

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -Command \"& {Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force; .\\join-domain.ps1 -DomainAdminPassword '${local.domain_admin_password}'}\""
  })

  depends_on = [
    azurerm_virtual_machine_extension.sql1_stage2_cse,
    azurerm_virtual_machine_data_disk_attachment.sql_vm2_data_disk_attach
  ]

  tags = local.common_tags
}
