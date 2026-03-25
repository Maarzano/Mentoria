variable "environment" {
  type    = string
  default = "homelab"
}

variable "kube_config_path" {
  description = "Caminho para o kubeconfig do K3S"
  type        = string
  default     = "~/.kube/config"
}

# ─── PostgreSQL ──────────────────────────────────────────────────────────────

variable "postgres_admin_login" {
  type    = string
  default = "pgadmin"
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "databases" {
  description = "Lista de databases a criar (ADR-002: banco único, multi-schema)"
  type        = list(string)
  default = [
    "foodeapp_auth",
    "foodeapp_establishments",
    "foodeapp_catalog",
    "foodeapp_events",
    "foodeapp_location",
    "foodeapp_orders",
    "foodeapp_notifications",
    "foodeapp_payments"
  ]
}

# ─── Redis ───────────────────────────────────────────────────────────────────

variable "redis_password" {
  type      = string
  sensitive = true
}

# ─── RabbitMQ ────────────────────────────────────────────────────────────────

variable "rabbitmq_username" {
  type    = string
  default = "foodeapp"
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

# ─── Grafana ─────────────────────────────────────────────────────────────────

variable "grafana_admin_password" {
  type      = string
  sensitive = true
  default   = "admin"
}
