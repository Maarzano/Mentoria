variable "key_vault_name" {
  description = "Nome do Key Vault (máx 24 chars, globalmente único)"
  type        = string
}

variable "environment" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "soft_delete_retention_days" {
  description = "Dias de retenção para soft delete"
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "Habilitar proteção contra purge definitivo"
  type        = bool
  default     = false # false em staging para facilitar limpeza; true em produção
}

variable "private_endpoints_subnet_id" {
  description = "ID da subnet de private endpoints"
  type        = string
}

variable "private_dns_zone_keyvault_id" {
  description = "ID da private DNS zone do Key Vault"
  type        = string
}

variable "cicd_service_principal_object_id" {
  description = "Object ID do service principal do GitHub Actions"
  type        = string
  default     = ""
}

variable "aks_workload_identity_object_id" {
  description = "Object ID da workload identity do AKS"
  type        = string
  default     = ""
}

variable "postgres_admin_password" {
  description = "Senha inicial do admin do PostgreSQL"
  type        = string
  sensitive   = true
  default     = "PLACEHOLDER-CHANGE-ME"
}

variable "redis_primary_key" {
  description = "Primary key do Redis Cache"
  type        = string
  sensitive   = true
  default     = "PLACEHOLDER-CHANGE-ME"
}

variable "tags" {
  type    = map(string)
  default = {}
}
