variable "environment" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "storage_blob_hostname" {
  description = "Hostname do Blob Storage (ex: stfoodeappstaging.blob.core.windows.net)"
  type        = string
}

variable "kong_ingress_ip" {
  description = "IP público do Kong Ingress no AKS"
  type        = string
  default     = "1.2.3.4" # Substituído após deploy do AKS
}

variable "api_hostname" {
  description = "Hostname da API (custom domain, ex: api.foodeapp.com.br)"
  type        = string
  default     = "api.foodeapp.com.br"
}

variable "waf_mode" {
  description = "Detection (staging) | Prevention (production)"
  type        = string
  default     = "Detection"
}

variable "tags" {
  type    = map(string)
  default = {}
}
