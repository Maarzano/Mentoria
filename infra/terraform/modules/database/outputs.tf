output "server_id" {
  value = azurerm_postgresql_flexible_server.main.id
}

output "server_name" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "server_fqdn" {
  description = "FQDN do PostgreSQL servidor (via private DNS)"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_names" {
  description = "Lista de databases criadas"
  value       = [for db in azurerm_postgresql_flexible_server_database.services : db.name]
}
