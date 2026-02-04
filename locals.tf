locals {
  vm_size                  = var.vm_size
  windows_version          = var.windows_version
  sql_version              = var.sql_version
  domain_name              = var.domain_name
  domain_admin_username    = var.domain_admin_username
  sql_service_account      = var.sql_service_account
  
  # Generate secure random passwords
  domain_admin_password    = random_password.domain_admin.result
  sql_service_password     = random_password.sql_service.result
  local_admin_password     = random_password.local_admin.result
  
  # Tags
  common_tags = merge(
    var.tags,
    {
      CreatedDate = timestamp()
    }
  )
}

# Generate secure random passwords
resource "random_password" "domain_admin" {
  length  = 32
  special = true
  override_special = "!@#$%^&*()-_=+[]{}<>:?"
}

resource "random_password" "sql_service" {
  length  = 32
  special = true
  override_special = "!@#$%^&*()-_=+[]{}<>:?"
}

resource "random_password" "local_admin" {
  length  = 32
  special = true
  override_special = "!@#$%^&*()-_=+[]{}<>:?"
}
