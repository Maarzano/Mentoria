output "storage_account_id" {
  value = azurerm_storage_account.main.id
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "URL base do Blob Storage"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Access key primária (use apenas em bootstrap; prefira managed identity)"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "containers" {
  description = "Mapa com os nomes dos containers criados"
  value = {
    products  = azurerm_storage_container.products.name
    merchants = azurerm_storage_container.merchants.name
    users     = azurerm_storage_container.users.name
    documents = azurerm_storage_container.documents.name
  }
}
