variable "subscription_id" {
  description = "Your subscription ID"
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-redcross-sql"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Switzerland North"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "redcross"
}

variable "vnet_name" {
  description = "Virtual Network name"
  type        = string
  default     = "vnet-redcross"
}

variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.38.0.0/16"
}

variable "dc_subnet_cidr" {
  description = "CIDR block for DC Subnet"
  type        = string
  default     = "10.38.0.0/24"
}

variable "sql_subnet_1_cidr" {
  description = "CIDR block for SQL Subnet 1"
  type        = string
  default     = "10.38.1.0/24"
}

variable "sql_subnet_2_cidr" {
  description = "CIDR block for SQL Subnet 2"
  type        = string
  default     = "10.38.2.0/24"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_E2s_v3"
}

variable "windows_version" {
  description = "Windows Server version"
  type        = string
  default     = "2022"
}

variable "sql_version" {
  description = "SQL Server version"
  type        = string
  default     = "2022"
}

variable "domain_name" {
  description = "Active Directory domain name"
  type        = string
  default     = "redcross.local"
}

variable "domain_admin_username" {
  description = "Domain admin username"
  type        = string
  default     = "redcross_admin"
}

variable "sql_service_account" {
  description = "SQL service account username"
  type        = string
  default     = "sql_service"
}

variable "storage_account_type" {
  description = "Storage account type for disks"
  type        = string
  default     = "Standard_LRS"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 128
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB"
  type        = number
  default     = 256
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    Project     = "RedCross-SQL"
    ManagedBy   = "Terraform"
  }
}
