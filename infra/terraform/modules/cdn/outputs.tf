output "frontdoor_profile_id" {
  value = azurerm_cdn_frontdoor_profile.main.id
}

output "frontdoor_endpoint_hostname" {
  description = "FQDN padrão do endpoint do Azure Front Door (*.azurefd.net)"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "frontdoor_endpoint_id" {
  value = azurerm_cdn_frontdoor_endpoint.main.id
}

output "waf_policy_id" {
  value = azurerm_cdn_frontdoor_firewall_policy.main.id
}
