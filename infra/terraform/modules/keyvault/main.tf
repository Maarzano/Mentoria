################################################################################
# MODULE: keyvault
# Azure Key Vault — armazena secrets (DB password, Redis key, API keys)
################################################################################

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
  location            = var.location

  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.purge_protection_enabled

  # Sem acesso público — acesso apenas via private endpoint
  public_network_access_enabled = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  tags = var.tags
}

# ─── Access Policies ──────────────────────────────────────────────────────────

# Pipeline CI/CD (GitHub Actions via service principal) pode ler/escrever secrets
resource "azurerm_key_vault_access_policy" "cicd" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.cicd_service_principal_object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Backup", "Restore"
  ]
}

# AKS workload identity pode ler secrets
resource "azurerm_key_vault_access_policy" "aks_workload_identity" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.aks_workload_identity_object_id

  secret_permissions = [
    "Get", "List"
  ]
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-keyvault-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-keyvault-${var.environment}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-keyvault"
    private_dns_zone_ids = [var.private_dns_zone_keyvault_id]
  }

  tags = var.tags
}

# ─── Secrets Placeholder ──────────────────────────────────────────────────────
# Os valores são placeholders — substituir manualmente ou via pipeline

resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-admin-password"
  value        = var.postgres_admin_password
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value] # Não sobrescreve se já existir um valor definido manualmente
  }
}

resource "azurerm_key_vault_secret" "redis_primary_key" {
  name         = "redis-primary-key"
  value        = var.redis_primary_key
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "mercadopago_access_token" {
  name         = "mercadopago-access-token"
  value        = "PLACEHOLDER-CHANGE-ME"
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "keycloak_admin_password" {
  name         = "keycloak-admin-password"
  value        = "PLACEHOLDER-CHANGE-ME"
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "rabbitmq_password" {
  name         = "rabbitmq-password"
  value        = "PLACEHOLDER-CHANGE-ME"
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }
}
