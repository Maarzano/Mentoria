variable "redis_name" {
  description = "Nome do Redis Cache (globalmente único)"
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

variable "sku_name" {
  description = "Standard (staging) | Premium (production)"
  type        = string
  default     = "Standard"
}

variable "capacity" {
  description = "Tamanho: 0=250MB, 1=1GB, 2=6GB, 3=13GB, 4=26GB"
  type        = number
  default     = 1
}

variable "family" {
  description = "C (Standard/Basic) | P (Premium)"
  type        = string
  default     = "C"
}

variable "private_endpoints_subnet_id" {
  type = string
}

variable "private_dns_zone_redis_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
