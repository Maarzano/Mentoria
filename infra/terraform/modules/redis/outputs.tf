output "redis_id" {
  value = azurerm_redis_cache.main.id
}

output "redis_name" {
  value = azurerm_redis_cache.main.name
}

output "redis_hostname" {
  description = "Hostname do Redis (via private DNS)"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_port" {
  value = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_connection_string" {
  description = "Connection string SSL do Redis"
  value       = azurerm_redis_cache.main.primary_connection_string
  sensitive   = true
}
