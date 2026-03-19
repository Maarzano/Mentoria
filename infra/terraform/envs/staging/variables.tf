variable "environment" {
  type    = string
  default = "staging"
}

variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  type = object({
    aks               = string
    database          = string
    redis             = string
    private_endpoints = string
  })
  default = {
    aks               = "10.0.0.0/20"   # 4094 IPs para pods Azure CNI
    database          = "10.0.16.0/24"
    redis             = "10.0.17.0/24"
    private_endpoints = "10.0.18.0/24"
  }
}

# ─── Resource Names ───────────────────────────────────────────────────────────

variable "acr_name" {
  description = "Nome do ACR (alfanumérico, globalmente único)"
  type        = string
  default     = "acrfoodeappstaging"
}

variable "key_vault_name" {
  description = "Nome do Key Vault (máx 24 chars)"
  type        = string
  default     = "kv-foodeapp-stg"
}

variable "postgres_server_name" {
  type    = string
  default = "psql-foodeapp-staging"
}

variable "redis_name" {
  type    = string
  default = "redis-foodeapp-staging"
}

variable "storage_account_name" {
  description = "Nome da storage account (alfanumérico, máx 24 chars)"
  type        = string
  default     = "stfoodeappstaging"
}

# ─── Credentials ──────────────────────────────────────────────────────────────

variable "postgres_admin_login" {
  type    = string
  default = "pgadmin"
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
  # Definir via: export TF_VAR_postgres_admin_password="..."
  # ou via GitHub Actions secret
}

# ─── Identity references (populated after first apply) ─────────────────────

variable "aks_kubelet_identity_object_id" {
  description = "Obtido do output aks.kubelet_identity_object_id após 1ª execução"
  type        = string
  default     = ""
}

variable "aks_workload_identity_object_id" {
  description = "Object ID da workload identity para Key Vault"
  type        = string
  default     = ""
}

variable "cicd_service_principal_object_id" {
  description = "Object ID do service principal do GitHub Actions"
  type        = string
  default     = ""
}

# ─── CDN ──────────────────────────────────────────────────────────────────────

variable "kong_ingress_ip" {
  description = "IP público do Kong após deploy no AKS"
  type        = string
  default     = "0.0.0.0"
}

variable "api_hostname" {
  type    = string
  default = "api-staging.foodeapp.com.br"
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = ["https://staging.foodeapp.com.br", "http://localhost:3000"]
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  type    = map(string)
  default = {}
}
