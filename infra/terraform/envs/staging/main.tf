################################################################################
# ENV: staging
# Chama todos os módulos com configurações de staging (menor custo, sem HA)
################################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  backend "azurerm" {
    # Preencher após rodar o bootstrap — execute:
    #   terraform output -chdir=infra/terraform/bootstrap storage_account_name
    resource_group_name  = "rg-foodeapp-tfstate"        # sempre fixo
    storage_account_name = "stfoodeapptfstatekxz3zk"    # criado pelo bootstrap
    container_name       = "tfstate"                    # sempre fixo
    key                  = "staging/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# ─── Resource Group Principal ─────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "rg-foodeapp-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ─── Locals ───────────────────────────────────────────────────────────────────

locals {
  tags = merge(var.tags, {
    environment = var.environment
    project     = "foodeapp"
    managed-by  = "terraform"
  })
}

# ─── MÓDULO: Networking ───────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  environment         = var.environment
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  vnet_cidr           = var.vnet_cidr
  subnet_cidrs        = var.subnet_cidrs
  tags                = local.tags
}

# ─── MÓDULO: ACR ──────────────────────────────────────────────────────────────

module "acr" {
  source = "../../modules/acr"

  registry_name                  = var.acr_name
  resource_group_name            = azurerm_resource_group.main.name
  location                       = var.location
  sku                            = "Standard"
  public_network_access_enabled  = true
  # Populated after AKS is created — second apply
  aks_kubelet_identity_object_id = var.aks_kubelet_identity_object_id
  tags                           = local.tags
}

# ─── MÓDULO: Key Vault ────────────────────────────────────────────────────────

module "keyvault" {
  source = "../../modules/keyvault"

  key_vault_name                   = var.key_vault_name
  environment                      = var.environment
  resource_group_name              = azurerm_resource_group.main.name
  location                         = var.location
  soft_delete_retention_days       = 7
  purge_protection_enabled         = false
  private_endpoints_subnet_id      = module.networking.subnet_private_endpoints_id
  private_dns_zone_keyvault_id     = module.networking.private_dns_zone_keyvault_id
  cicd_service_principal_object_id = var.cicd_service_principal_object_id
  aks_workload_identity_object_id  = var.aks_workload_identity_object_id
  postgres_admin_password          = var.postgres_admin_password
  redis_primary_key                = module.redis.redis_primary_connection_string
  tags                             = local.tags

  depends_on = [module.networking]
}

# ─── MÓDULO: PostgreSQL ───────────────────────────────────────────────────────

module "database" {
  source = "../../modules/database"

  server_name                  = var.postgres_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  admin_login                  = var.postgres_admin_login
  admin_password               = var.postgres_admin_password
  sku_name                     = "B_Standard_B2ms"  # 2 vCPUs, 4GB RAM
  storage_mb                   = 32768              # 32 GB
  backup_retention_days        = 7
  geo_redundant_backup         = false
  high_availability_enabled    = false              # Sem HA em staging
  max_connections              = "150"
  database_subnet_id           = module.networking.subnet_database_id
  private_dns_zone_postgres_id = module.networking.private_dns_zone_postgres_id
  tags                         = local.tags

  depends_on = [module.networking]
}

# ─── MÓDULO: Redis ────────────────────────────────────────────────────────────

module "redis" {
  source = "../../modules/redis"

  redis_name                  = var.redis_name
  environment                 = var.environment
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  sku_name                    = "Standard"
  capacity                    = 1   # 1 GB
  family                      = "C"
  private_endpoints_subnet_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_redis_id   = module.networking.private_dns_zone_redis_id
  tags                        = local.tags

  depends_on = [module.networking]
}

# ─── MÓDULO: Storage ──────────────────────────────────────────────────────────

module "storage" {
  source = "../../modules/storage"

  storage_account_name        = var.storage_account_name
  environment                 = var.environment
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  replication_type            = "LRS"
  cors_allowed_origins        = var.cors_allowed_origins
  private_endpoints_subnet_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_storage_id = module.networking.private_dns_zone_storage_id
  tags                        = local.tags

  depends_on = [module.networking]
}

# ─── MÓDULO: AKS ──────────────────────────────────────────────────────────────

module "aks" {
  source = "../../modules/aks"

  environment         = var.environment
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  aks_subnet_id       = module.networking.subnet_aks_id
  kubernetes_version  = var.kubernetes_version

  # System pool — kube-system
  system_vm_size    = "Standard_D2s_v3"
  system_node_count = 2

  # Services pool — microserviços + BFFs (sem taint, destino padrão)
  services_vm_size    = "Standard_D4s_v3"
  services_node_count = 2
  services_node_min   = 2
  services_node_max   = 6

  # Infra pool — Kong, Keycloak, RabbitMQ, Flagsmith
  infra_vm_size    = "Standard_D2s_v3"
  infra_node_count = 2
  infra_node_min   = 2
  infra_node_max   = 3

  # Monitor pool — Prometheus, Loki, Tempo, Grafana, OTel
  monitor_vm_size    = "Standard_D4s_v3"
  monitor_node_count = 1
  monitor_node_min   = 1
  monitor_node_max   = 2

  service_cidr   = "172.16.0.0/16"
  dns_service_ip = "172.16.0.10"

  enable_defender    = false
  log_retention_days = 30
  tags               = local.tags

  depends_on = [module.networking, module.acr]
}

# ─── MÓDULO: Azure Front Door ─────────────────────────────────────────────────

module "cdn" {
  source = "../../modules/cdn"

  environment           = var.environment
  resource_group_name   = azurerm_resource_group.main.name
  storage_blob_hostname = module.storage.primary_blob_endpoint
  kong_ingress_ip       = var.kong_ingress_ip
  api_hostname          = var.api_hostname
  waf_mode              = "Detection"
  tags                  = local.tags

  depends_on = [module.storage, module.aks]
}
