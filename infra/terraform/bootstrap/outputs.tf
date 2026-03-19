output "storage_account_name" {
  description = "Nome da storage account do Terraform state"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Nome do container do Terraform state"
  value       = azurerm_storage_container.tfstate.name
}

output "resource_group_name" {
  description = "Resource group do Terraform state"
  value       = azurerm_resource_group.tfstate.name
}

output "backend_config_snippet" {
  description = "Bloco de backend para copiar nos envs/staging e envs/production"
  value = <<-EOT
    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "${azurerm_storage_container.tfstate.name}"
        key                  = "<ENV>/terraform.tfstate"
      }
    }
  EOT
}
