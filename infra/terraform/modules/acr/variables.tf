variable "registry_name" {
  description = "Nome do Azure Container Registry (deve ser globalmente único, alfanumérico)"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  description = "SKU do ACR: Basic | Standard | Premium"
  type        = string
  default     = "Standard"
}

variable "public_network_access_enabled" {
  description = "Permitir acesso público ao registry"
  type        = bool
  default     = true # true para facilitar push via GitHub Actions; false em produção fechada
}

variable "geo_replication_locations" {
  description = "Lista de regiões para geo-replicação (somente SKU Premium)"
  type        = list(string)
  default     = []
}

variable "aks_kubelet_identity_object_id" {
  description = "Object ID da identidade kubelet do AKS (para AcrPull)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
