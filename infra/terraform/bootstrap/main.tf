################################################################################
# BOOTSTRAP — Roda UMA VEZ manualmente para criar o backend do Terraform state
# Comando: terraform init && terraform apply
# Após criado, o restante dos envs usa este storage como backend.
################################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-foodeapp-tfstate"
  location = var.location

  tags = {
    project     = "foodeapp"
    managed-by  = "terraform-bootstrap"
  }
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "stfoodeapptfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Segurança mínima para o state backend
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }

  tags = {
    project    = "foodeapp"
    managed-by = "terraform-bootstrap"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
