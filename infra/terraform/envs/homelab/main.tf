################################################################################
# ENV: homelab
#
# Infraestrutura HomeLab em K3S local via Helm.
# Diferente de staging/production que usam recursos Azure, o homelab
# roda tudo dentro do K3S (PostgreSQL, Redis, RabbitMQ, observabilidade).
#
# Pré-requisito: K3S instalado e kubeconfig disponível.
#   export KUBECONFIG=~/.kube/config   (ou --var kube_config_path=...)
#
# terraform init && terraform apply
# kubectl apply -k ../../k8s/overlays/homelab/
################################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = var.kube_config_path
}

provider "helm" {
  kubernetes {
    config_path = var.kube_config_path
  }
}

locals {
  labels = {
    environment = var.environment
    project     = "foodeapp"
    managed-by  = "terraform"
  }
}

# ─── Namespaces ──────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name   = "foodeapp-${var.environment}"
    labels = merge(local.labels, { "istio-injection" = "disabled" })
  }
}

resource "kubernetes_namespace" "system" {
  metadata {
    name   = "foodeapp-system"
    labels = merge(local.labels, { "istio-injection" = "disabled" })
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = local.labels
  }
}

# ─── PostgreSQL (Bitnami Helm) ───────────────────────────────────────────────

resource "helm_release" "postgresql" {
  name       = "postgresql"
  namespace  = kubernetes_namespace.system.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = "16.4.1"

  set {
    name  = "auth.postgresPassword"
    value = var.postgres_admin_password
  }
  set {
    name  = "auth.username"
    value = var.postgres_admin_login
  }
  set {
    name  = "auth.password"
    value = var.postgres_admin_password
  }
  set {
    name  = "primary.persistence.size"
    value = "10Gi"
  }
  set {
    name  = "primary.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "primary.resources.requests.cpu"
    value = "250m"
  }
  # Cria os 8 databases do FoodeApp (ADR-002)
  set {
    name  = "primary.initdb.scripts.create-databases\\.sql"
    value = join("\n", [for db in var.databases : "CREATE DATABASE \"${db}\";"])
  }
}

# ─── Redis (Bitnami Helm) ───────────────────────────────────────────────────

resource "helm_release" "redis" {
  name       = "redis"
  namespace  = kubernetes_namespace.system.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = "20.6.2"

  set {
    name  = "auth.password"
    value = var.redis_password
  }
  set {
    name  = "master.persistence.size"
    value = "2Gi"
  }
  set {
    name  = "replica.replicaCount"
    value = "0"
  }
  set {
    name  = "master.resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "master.resources.requests.cpu"
    value = "100m"
  }
}

# ─── RabbitMQ (Bitnami Helm) ────────────────────────────────────────────────

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq"
  namespace  = kubernetes_namespace.system.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq"
  version    = "15.1.2"

  set {
    name  = "auth.username"
    value = var.rabbitmq_username
  }
  set {
    name  = "auth.password"
    value = var.rabbitmq_password
  }
  set {
    name  = "persistence.size"
    value = "2Gi"
  }
  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "200m"
  }
}

# ─── Observabilidade: kube-prometheus-stack (Prometheus + Grafana) ────────────

resource "helm_release" "monitoring" {
  name       = "monitoring"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.8.1"

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }
  set {
    name  = "grafana.persistence.size"
    value = "2Gi"
  }
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }
}

# ─── Loki (log aggregation) ─────────────────────────────────────────────────

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.24.0"

  set {
    name  = "loki.commonConfig.replication_factor"
    value = "1"
  }
  set {
    name  = "singleBinary.replicas"
    value = "1"
  }
  set {
    name  = "loki.storage.type"
    value = "filesystem"
  }
}

# ─── Tempo (tracing) ────────────────────────────────────────────────────────

resource "helm_release" "tempo" {
  name       = "tempo"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.12.0"
}

# ─── OpenTelemetry Collector ─────────────────────────────────────────────────

resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.108.0"

  set {
    name  = "mode"
    value = "deployment"
  }
  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }
}
