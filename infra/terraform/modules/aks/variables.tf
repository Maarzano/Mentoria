variable "environment" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes (ex: 1.29)"
  type        = string
  default     = "1.29"
}

variable "aks_subnet_id" {
  description = "ID da subnet do AKS (Azure CNI)"
  type        = string
}

# ─── System Node Pool ─────────────────────────────────────────────────────────

variable "system_vm_size" {
  description = "VM size do system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_count" {
  description = "Número de nós do system pool"
  type        = number
  default     = 3
}

# ─── Services Node Pool (microserviços + BFFs) ────────────────────────────────

variable "services_vm_size" {
  description = "VM size do services node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "services_node_count" {
  description = "Número inicial de nós do services pool"
  type        = number
  default     = 3
}

variable "services_node_min" {
  description = "Mínimo de nós do services pool (autoscale)"
  type        = number
  default     = 2
}

variable "services_node_max" {
  description = "Máximo de nós do services pool (autoscale)"
  type        = number
  default     = 10
}

# ─── Infra Node Pool (Kong, ZITADEL, RabbitMQ, Flagsmith) ────────────────────

variable "infra_vm_size" {
  description = "VM size do infra node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "infra_node_count" {
  description = "Número inicial de nós do infra pool"
  type        = number
  default     = 2
}

variable "infra_node_min" {
  description = "Mínimo de nós do infra pool (autoscale)"
  type        = number
  default     = 2
}

variable "infra_node_max" {
  description = "Máximo de nós do infra pool (autoscale)"
  type        = number
  default     = 4
}

# ─── Monitor Node Pool (Prometheus, Loki, Tempo, Grafana, OTel) ───────────────

variable "monitor_vm_size" {
  description = "VM size do monitor node pool (memória para Prometheus e Loki)"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "monitor_node_count" {
  description = "Número inicial de nós do monitor pool"
  type        = number
  default     = 1
}

variable "monitor_node_min" {
  description = "Mínimo de nós do monitor pool (autoscale)"
  type        = number
  default     = 1
}

variable "monitor_node_max" {
  description = "Máximo de nós do monitor pool (autoscale)"
  type        = number
  default     = 3
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "service_cidr" {
  description = "CIDR dos Kubernetes services (não pode colidir com VNet)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP do DNS interno do Kubernetes (deve estar dentro do service_cidr)"
  type        = string
  default     = "172.16.0.10"
}

# ─── Features ─────────────────────────────────────────────────────────────────

variable "enable_defender" {
  description = "Habilitar Microsoft Defender for Containers"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retenção de logs no Log Analytics"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
