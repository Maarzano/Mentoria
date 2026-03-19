################################################################################
# ENV: production
# Chama todos os módulos com configurações de produção (HA, SKUs maiores, WAF Prevention)
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
    key                  = "production/terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-foodeapp-${var.environment}"
  location = var.location
  tags     = local.tags
}

locals {
  tags = merge(var.tags, {
    environment = var.environment
    project     = "foodeapp"
    managed-by  = "terraform"
  })
}

module "networking" {
  source = "../../modules/networking"

  environment         = var.environment
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  vnet_cidr           = var.vnet_cidr
  subnet_cidrs        = var.subnet_cidrs
  tags                = local.tags
}

module "acr" {
  source = "../../modules/acr"

  registry_name                 = var.acr_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.location
  sku                           = "Standard"
  public_network_access_enabled = true
  aks_kubelet_identity_object_id = var.aks_kubelet_identity_object_id
  tags                          = local.tags
}

module "keyvault" {
  source = "../../modules/keyvault"

  key_vault_name                   = var.key_vault_name
  environment                      = var.environment
  resource_group_name              = azurerm_resource_group.main.name
  location                         = var.location
  soft_delete_retention_days       = 90
  purge_protection_enabled         = true   # OBRIGATÓRIO em produção
  private_endpoints_subnet_id      = module.networking.subnet_private_endpoints_id
  private_dns_zone_keyvault_id     = module.networking.private_dns_zone_keyvault_id
  cicd_service_principal_object_id = var.cicd_service_principal_object_id
  aks_workload_identity_object_id  = var.aks_workload_identity_object_id
  postgres_admin_password          = var.postgres_admin_password
  redis_primary_key                = module.redis.redis_primary_connection_string
  tags                             = local.tags

  depends_on = [module.networking]
}

module "database" {
  source = "../../modules/database"

  server_name                  = var.postgres_server_name
  resource_group_name          = azurerm_resource_group.main.name
  location                     = var.location
  admin_login                  = var.postgres_admin_login
  admin_password               = var.postgres_admin_password
  sku_name                     = "GP_Standard_D4s_v3"  # 4 vCPUs, 16GB RAM
  storage_mb                   = 131072                # 128 GB
  backup_retention_days        = 35
  geo_redundant_backup         = true
  high_availability_enabled    = true                  # ZoneRedundant em produção
  max_connections              = "400"
  database_subnet_id           = module.networking.subnet_database_id
  private_dns_zone_postgres_id = module.networking.private_dns_zone_postgres_id
  tags                         = local.tags

  depends_on = [module.networking]
}

module "redis" {
  source = "../../modules/redis"

  redis_name                  = var.redis_name
  environment                 = var.environment
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  sku_name                    = "Premium"
  capacity                    = 1       # P1 = 6 GB
  family                      = "P"
  private_endpoints_subnet_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_redis_id   = module.networking.private_dns_zone_redis_id
  tags                        = local.tags

  depends_on = [module.networking]
}

module "storage" {
  source = "../../modules/storage"

  storage_account_name        = var.storage_account_name
  environment                 = var.environment
  resource_group_name         = azurerm_resource_group.main.name
  location                    = var.location
  replication_type            = "ZRS"  # Zone-redundant em produção
  cors_allowed_origins        = var.cors_allowed_origins
  private_endpoints_subnet_id = module.networking.subnet_private_endpoints_id
  private_dns_zone_storage_id = module.networking.private_dns_zone_storage_id
  tags                        = local.tags

  depends_on = [module.networking]
}

module "aks" {
  source = "../../modules/aks"

  environment         = var.environment
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  aks_subnet_id       = module.networking.subnet_aks_id
  kubernetes_version  = var.kubernetes_version

  # System pool — kube-system
  system_vm_size    = "Standard_D4s_v3"
  system_node_count = 3

  # Services pool — microserviços + BFFs (sem taint, destino padrão)
  services_vm_size    = "Standard_D8s_v3"  # 8 vCPUs, 32GB RAM
  services_node_count = 4
  services_node_min   = 3
  services_node_max   = 20

  # Infra pool — Kong, Keycloak, RabbitMQ, Flagsmith
  infra_vm_size    = "Standard_D4s_v3"  # 4 vCPUs, 16GB RAM
  infra_node_count = 2
  infra_node_min   = 2
  infra_node_max   = 4

  # Monitor pool — Prometheus, Loki, Tempo, Grafana, OTel (memory-optimized)
  monitor_vm_size    = "Standard_E4s_v3"  # 4 vCPUs, 32GB RAM — ideal para Prometheus + Loki
  monitor_node_count = 2
  monitor_node_min   = 2
  monitor_node_max   = 4

  service_cidr   = "172.17.0.0/16"  # CIDR diferente do staging para evitar conflito
  dns_service_ip = "172.17.0.10"

  enable_defender    = true
  log_retention_days = 90
  tags               = local.tags

  depends_on = [module.networking, module.acr]
}

module "cdn" {
  source = "../../modules/cdn"

  environment           = var.environment
  resource_group_name   = azurerm_resource_group.main.name
  storage_blob_hostname = module.storage.primary_blob_endpoint
  kong_ingress_ip       = var.kong_ingress_ip
  api_hostname          = var.api_hostname
  waf_mode              = "Prevention"  # Bloqueia ameaças em produção
  tags                  = local.tags

  depends_on = [module.storage, module.aks]
}
