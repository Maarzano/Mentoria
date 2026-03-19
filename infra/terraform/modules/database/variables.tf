variable "server_name" {
  description = "Nome do PostgreSQL Flexible Server (globalmente único)"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "admin_login" {
  description = "Login do administrador do PostgreSQL"
  type        = string
  default     = "pgadmin"
}

variable "admin_password" {
  description = "Senha do administrador (use Key Vault em produção)"
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "SKU: B_Standard_B2ms (staging) | GP_Standard_D4s_v3 (production)"
  type        = string
  default     = "B_Standard_B2ms"
}

variable "storage_mb" {
  description = "Storage em MB"
  type        = number
  default     = 32768 # 32 GB
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "geo_redundant_backup" {
  type    = bool
  default = false
}

variable "high_availability_enabled" {
  description = "Habilitar HA zone-redundant (recomendado apenas em produção)"
  type        = bool
  default     = false
}

variable "max_connections" {
  description = "Número máximo de conexões"
  type        = string
  default     = "200"
}

variable "database_subnet_id" {
  description = "ID da subnet com delegation para PostgreSQL"
  type        = string
}

variable "private_dns_zone_postgres_id" {
  description = "ID da private DNS zone do PostgreSQL"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
