output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "URL do Container Registry para push de imagens"
  value       = module.acr.login_server
}

output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "aks_kubelet_identity_object_id" {
  description = "Copiar para acr.aks_kubelet_identity_object_id no 2º apply"
  value       = module.aks.kubelet_identity_object_id
}

output "aks_oidc_issuer_url" {
  description = "URL OIDC para configurar workload identity federation"
  value       = module.aks.oidc_issuer_url
}

output "postgres_fqdn" {
  description = "FQDN do PostgreSQL (via private DNS)"
  value       = module.database.server_fqdn
}

output "redis_hostname" {
  value = module.redis.redis_hostname
}

output "storage_blob_endpoint" {
  value = module.storage.primary_blob_endpoint
}

output "frontdoor_hostname" {
  description = "FQDN do Azure Front Door (*.azurefd.net)"
  value       = module.cdn.frontdoor_endpoint_hostname
}

output "key_vault_uri" {
  value = module.keyvault.key_vault_uri
}

output "get_kubeconfig_command" {
  description = "Comando para baixar kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --overwrite-existing"
}
