output "registry_id" {
  value = azurerm_container_registry.main.id
}

output "registry_name" {
  value = azurerm_container_registry.main.name
}

output "login_server" {
  description = "URL do registry para push/pull de imagens"
  value       = azurerm_container_registry.main.login_server
}
