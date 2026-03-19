output "vnet_id" {
  description = "ID do VNet"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Nome do VNet"
  value       = azurerm_virtual_network.main.name
}

output "subnet_aks_id" {
  description = "ID da subnet do AKS"
  value       = azurerm_subnet.aks.id
}

output "subnet_database_id" {
  description = "ID da subnet do PostgreSQL"
  value       = azurerm_subnet.database.id
}

output "subnet_redis_id" {
  description = "ID da subnet do Redis"
  value       = azurerm_subnet.redis.id
}

output "subnet_private_endpoints_id" {
  description = "ID da subnet de private endpoints"
  value       = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_postgres_id" {
  description = "ID da private DNS zone do PostgreSQL"
  value       = azurerm_private_dns_zone.postgres.id
}

output "private_dns_zone_redis_id" {
  description = "ID da private DNS zone do Redis"
  value       = azurerm_private_dns_zone.redis.id
}

output "private_dns_zone_keyvault_id" {
  description = "ID da private DNS zone do Key Vault"
  value       = azurerm_private_dns_zone.keyvault.id
}

output "private_dns_zone_storage_id" {
  description = "ID da private DNS zone do Storage"
  value       = azurerm_private_dns_zone.storage.id
}

output "private_dns_zone_postgres_name" {
  description = "Nome da private DNS zone do PostgreSQL"
  value       = azurerm_private_dns_zone.postgres.name
}
