variable "storage_account_name" {
  description = "Nome da storage account (máx 24 chars, alfanumérico, globalmente único)"
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

variable "replication_type" {
  description = "LRS (staging) | ZRS (production)"
  type        = string
  default     = "LRS"
}

variable "cors_allowed_origins" {
  description = "Origens permitidas no CORS (domínios do frontend)"
  type        = list(string)
  default     = ["*"]
}

variable "private_endpoints_subnet_id" {
  type = string
}

variable "private_dns_zone_storage_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
