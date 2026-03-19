variable "environment" {
  type    = string
  default = "production"
}

variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "vnet_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "subnet_cidrs" {
  type = object({
    aks               = string
    database          = string
    redis             = string
    private_endpoints = string
  })
  default = {
    aks               = "10.1.0.0/20"
    database          = "10.1.16.0/24"
    redis             = "10.1.17.0/24"
    private_endpoints = "10.1.18.0/24"
  }
}

variable "acr_name" {
  type    = string
  default = "acrfoodeappprod"
}

variable "key_vault_name" {
  type    = string
  default = "kv-foodeapp-prod"
}

variable "postgres_server_name" {
  type    = string
  default = "psql-foodeapp-production"
}

variable "redis_name" {
  type    = string
  default = "redis-foodeapp-production"
}

variable "storage_account_name" {
  type    = string
  default = "stfoodeappprod"
}

variable "postgres_admin_login" {
  type    = string
  default = "pgadmin"
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "aks_kubelet_identity_object_id" {
  type    = string
  default = ""
}

variable "aks_workload_identity_object_id" {
  type    = string
  default = ""
}

variable "cicd_service_principal_object_id" {
  type    = string
  default = ""
}

variable "kong_ingress_ip" {
  type    = string
  default = "0.0.0.0"
}

variable "api_hostname" {
  type    = string
  default = "api.foodeapp.com.br"
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = ["https://foodeapp.com.br", "https://www.foodeapp.com.br"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
