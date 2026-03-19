################################################################################
# MODULE: storage
# Azure Blob Storage — substitui Cloudflare R2
# 4 containers: products, merchants, users, documents
################################################################################

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.replication_type # LRS (staging) / ZRS (production)

  # Segurança
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  blob_properties {
    versioning_enabled = false

    # CORS para acesso direto do browser (upload de presigned URL)
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "PUT", "HEAD", "DELETE"]
      allowed_origins    = var.cors_allowed_origins
      exposed_headers    = ["ETag", "Content-Length", "Content-Type"]
      max_age_in_seconds = 3600
    }

    delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# ─── Containers ───────────────────────────────────────────────────────────────

# Fotos de produtos (acesso público via Azure Front Door)
resource "azurerm_storage_container" "products" {
  name                  = "products"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private" # Acesso via SAS ou Front Door apenas
}

# Logos e banners de estabelecimentos
resource "azurerm_storage_container" "merchants" {
  name                  = "merchants"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Fotos de perfil de usuários
resource "azurerm_storage_container" "users" {
  name                  = "users"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Documentos privados (CNPJ, contratos) — acesso apenas via signed URLs
resource "azurerm_storage_container" "documents" {
  name                  = "documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-storage-${var.environment}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-storage"
    private_dns_zone_ids = [var.private_dns_zone_storage_id]
  }

  tags = var.tags
}
