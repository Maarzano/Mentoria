################################################################################
# MODULE: database
# PostgreSQL Flexible Server v15 com integração VNet, PostGIS e HA opcional
################################################################################

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = var.server_name
  resource_group_name    = var.resource_group_name
  location               = var.location

  version                = "15"
  administrator_login    = var.admin_login
  administrator_password = var.admin_password

  # Integração VNet via delegation
  delegated_subnet_id    = var.database_subnet_id
  private_dns_zone_id    = var.private_dns_zone_postgres_id

  # SKU: Burstable (staging) ou GeneralPurpose (production)
  sku_name               = var.sku_name

  storage_mb             = var.storage_mb
  backup_retention_days  = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup

  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  availability_zone = "1"

  maintenance_window {
    day_of_week  = 0 # Domingo
    start_hour   = 3 # 3am (fora do horário de pico)
    start_minute = 0
  }

  tags = var.tags
}

# ─── Configurações de Servidor ────────────────────────────────────────────────

# Habilita monitoramento de queries (pg_stat_statements) — visível no Grafana / query insights
resource "azurerm_postgresql_flexible_server_configuration" "shared_preload_libraries" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "pg_stat_statements"
}

# Habilita extensões necessárias pelos serviços:
#   postgis  → svc-location (geo-queries, ST_Distance, ST_Within, GIST index)
#   pgcrypto → geração de UUIDs e funções de hash (gen_random_uuid, crypt)
# ATENÇÃO: apenas libera a extensão no servidor. Para ativar em um banco especifico:
#   psql -h <fqdn> -U pgadmin -d foodeapp_locations -c "CREATE EXTENSION IF NOT EXISTS postgis;"
resource "azurerm_postgresql_flexible_server_configuration" "azure_extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "postgis,pgcrypto"
}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = var.max_connections
}

resource "azurerm_postgresql_flexible_server_configuration" "log_min_duration_statement" {
  name      = "log_min_duration_statement"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "1000" # Log queries > 1s
}

# ─── Databases (um por schema/serviço) ───────────────────────────────────────

locals {
  databases = [
    "foodeapp_auth",
    "foodeapp_establishments",
    "foodeapp_catalog",
    "foodeapp_events",
    "foodeapp_locations",
    "foodeapp_orders",
    "foodeapp_notifications",
    "foodeapp_payments",
    "foodeapp_flags",    # Flagsmith feature flags (ADR-029)
  ]
}

resource "azurerm_postgresql_flexible_server_database" "services" {
  for_each  = toset(local.databases)
  name      = each.value
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# ─── Firewall: bloqueia tudo — acesso apenas via VNet delegation ──────────────

resource "azurerm_postgresql_flexible_server_firewall_rule" "deny_all" {
  name             = "deny-public-access"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
