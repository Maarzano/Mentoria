variable "environment" {
  description = "Nome do ambiente (staging | production)"
  type        = string
}

variable "resource_group_name" {
  description = "Nome do resource group onde os recursos serão criados"
  type        = string
}

variable "location" {
  description = "Região Azure"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR do VNet principal"
  type        = string
}

variable "subnet_cidrs" {
  description = "CIDRs das subnets"
  type = object({
    aks               = string
    database          = string
    redis             = string
    private_endpoints = string
  })
}

variable "tags" {
  description = "Tags a aplicar em todos os recursos"
  type        = map(string)
  default     = {}
}
