################################################################################
# MODULE: redis
# Azure Cache for Redis com private endpoint
################################################################################

resource "azurerm_redis_cache" "main" {
  name                = var.redis_name
  resource_group_name = var.resource_group_name
  location            = var.location

  capacity            = var.capacity
  family              = var.family
  sku_name            = var.sku_name

  # Desabilita acesso sem TLS
  enable_non_ssl_port          = false
  minimum_tls_version          = "1.2"
  public_network_access_enabled = false

  redis_configuration {
    # Notificações de keyspace para cache invalidation via Outbox
    notify_keyspace_events = "KEA"

    # Eviction policy: quanto o Redis fica cheio, remove as LRU keys
    maxmemory_policy       = "allkeys-lru"

    # Persistência RDB (snapshot) — só em Premium
    rdb_backup_enabled     = var.sku_name == "Premium" ? true : false
    rdb_backup_frequency   = var.sku_name == "Premium" ? 60 : null
  }

  # Zones de disponibilidade (Premium only)
  zones = var.sku_name == "Premium" ? ["1", "2"] : null

  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 3
  }

  tags = var.tags
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-redis-${var.environment}"
    private_connection_resource_id = azurerm_redis_cache.main.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-redis"
    private_dns_zone_ids = [var.private_dns_zone_redis_id]
  }

  tags = var.tags
}
