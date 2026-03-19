output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_kubelet_identity_object_id" {
  value = module.aks.kubelet_identity_object_id
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "postgres_fqdn" {
  value = module.database.server_fqdn
}

output "redis_hostname" {
  value = module.redis.redis_hostname
}

output "storage_blob_endpoint" {
  value = module.storage.primary_blob_endpoint
}

output "frontdoor_hostname" {
  value = module.cdn.frontdoor_endpoint_hostname
}

output "key_vault_uri" {
  value = module.keyvault.key_vault_uri
}

output "get_kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --overwrite-existing"
}
