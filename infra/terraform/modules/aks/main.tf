################################################################################
# MODULE: aks
# AKS cluster com workload identity, Key Vault CSI, Azure CNI + Calico network
# policy, Log Analytics e quatro node pools:
#   system   — kube-system (only_critical_addons_enabled)
#   services — microserviços + BFFs (sem taint, destino padrão)
#   infra    — Kong, Keycloak, RabbitMQ, Flagsmith (taint workload=infra)
#   monitor  — Prometheus, Loki, Tempo, Grafana, OTel (taint workload=monitor)
################################################################################

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-foodeapp-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-foodeapp-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  dns_prefix          = "foodeapp-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # ─── System Node Pool (infra: coreDNS, kube-system) ─────────────────────────
  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_vm_size
    vnet_subnet_id      = var.aks_subnet_id
    os_disk_size_gb     = 60
    type                = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true # Garante isolamento: system pool só roda pods de sistema

    upgrade_settings {
      max_surge = "33%"
    }

    node_labels = {
      "role" = "system"
    }
  }

  # ─── Managed Identity ────────────────────────────────────────────────────────
  identity {
    type = "SystemAssigned"
  }

  # ─── Azure CNI + Calico Network Policy ───────────────────────────────────────
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
  }

  # ─── OIDC Issuer + Workload Identity ─────────────────────────────────────────
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ─── Key Vault CSI Driver ────────────────────────────────────────────────────
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # ─── Azure Monitor / OMS ─────────────────────────────────────────────────────
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # ─── Microsoft Defender (produção) ───────────────────────────────────────────
  dynamic "microsoft_defender" {
    for_each = var.enable_defender ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }

  # ─── Auto-upgrade ────────────────────────────────────────────────────────────
  automatic_channel_upgrade = "patch"
  node_os_channel_upgrade   = "NodeImage"

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "-03:00"
  }

  # ─── Azure RBAC para Kubernetes ───────────────────────────────────────────────
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  tags = var.tags
}

# ─── Services Node Pool (microserviços + BFFs) ────────────────────────────────

resource "azurerm_kubernetes_cluster_node_pool" "services" {
  name                  = "services"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.services_vm_size
  node_count            = var.services_node_count
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 80
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.services_node_min
  max_count           = var.services_node_max

  upgrade_settings {
    max_surge = "33%"
  }

  node_labels = {
    "role"     = "services"
    "workload" = "foodeapp-services"
  }

  node_taints = [] # Sem taint — destino padrão para microserviços e BFFs

  tags = var.tags
}

# ─── Infra Node Pool (Kong, Keycloak, RabbitMQ, Flagsmith) ────────────────────

resource "azurerm_kubernetes_cluster_node_pool" "infra" {
  name                  = "infra"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.infra_vm_size
  node_count            = var.infra_node_count
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 80
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.infra_node_min
  max_count           = var.infra_node_max

  upgrade_settings {
    max_surge = "33%"
  }

  node_labels = {
    "role"     = "infra"
    "workload" = "platform-infra"
  }

  # Garante isolamento: apenas pods com toleration workload=infra:NoSchedule são aceitos
  node_taints = ["workload=infra:NoSchedule"]

  tags = var.tags
}

# ─── Monitor Node Pool (Prometheus, Loki, Tempo, Grafana, OTel) ───────────────

resource "azurerm_kubernetes_cluster_node_pool" "monitor" {
  name                  = "monitor"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.monitor_vm_size
  node_count            = var.monitor_node_count
  vnet_subnet_id        = var.aks_subnet_id
  os_disk_size_gb       = 128 # Prometheus e Loki são disk-intensive
  mode                  = "User"

  enable_auto_scaling = true
  min_count           = var.monitor_node_min
  max_count           = var.monitor_node_max

  upgrade_settings {
    max_surge = "33%"
  }

  node_labels = {
    "role"     = "monitor"
    "workload" = "observability"
  }

  # Garante isolamento: apenas pods com toleration workload=monitor:NoSchedule são aceitos
  node_taints = ["workload=monitor:NoSchedule"]

  tags = var.tags
}

# ─── Diagnostic Settings ──────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${var.environment}"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "guard"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ─── Role: AKS managed identity pode ler o ACR ───────────────────────────────
# (Role assignment feita no módulo ACR via var.aks_kubelet_identity_object_id)
