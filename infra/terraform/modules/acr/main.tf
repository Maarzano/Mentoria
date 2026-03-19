################################################################################
# MODULE: acr
# Azure Container Registry — armazena as imagens Docker dos microserviços
################################################################################

resource "azurerm_container_registry" "main" {
  name                = var.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # Desabilita acesso público anônimo — apenas autenticado
  admin_enabled = false

  # Permite pull de dentro do AKS via managed identity
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "georeplications" {
    for_each = var.geo_replication_locations
    content {
      location                = georeplications.value
      zone_redundancy_enabled = false
    }
  }

  tags = var.tags
}

# Role assignment: AKS pull images from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = var.aks_kubelet_identity_object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}
