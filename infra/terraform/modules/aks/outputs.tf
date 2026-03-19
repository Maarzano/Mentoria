output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "kube_config" {
  description = "Raw kubeconfig para uso no kubectl / GitHub Actions"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubelet_identity_object_id" {
  description = "Object ID da identidade kubelet — usado para AcrPull assignment"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
}

output "oidc_issuer_url" {
  description = "URL do OIDC issuer para workload identity federation"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "cluster_principal_id" {
  description = "Principal ID da managed identity do cluster"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "node_resource_group" {
  description = "Resource group gerenciado pelo AKS (nós, load balancers, etc.)"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}
