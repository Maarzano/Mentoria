################################################################################
# MODULE: cdn
# Azure Front Door Standard — CDN + WAF + routing
# Origin groups: static-assets (Blob Storage) + api (Kong ingress no AKS)
################################################################################

resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "afd-foodeapp-${var.environment}"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"

  tags = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "fde-foodeapp-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  tags = var.tags
}

# ─── Origin Group: assets estáticos (Blob Storage) ───────────────────────────

resource "azurerm_cdn_frontdoor_origin_group" "static_assets" {
  name                     = "og-static-assets"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    interval_in_seconds = 100
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "blob_storage" {
  name                          = "origin-blob-storage"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static_assets.id

  enabled                        = true
  host_name                      = var.storage_blob_hostname
  origin_host_header             = var.storage_blob_hostname
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true
  priority                       = 1
  weight                         = 1000
}

# ─── Origin Group: API (Kong Ingress) ─────────────────────────────────────────

resource "azurerm_cdn_frontdoor_origin_group" "api" {
  name                     = "og-api"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  health_probe {
    interval_in_seconds = 30
    path                = "/health"
    protocol            = "Https"
    request_type        = "HEAD"
  }

  load_balancing {
    additional_latency_in_milliseconds = 0
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "kong_ingress" {
  name                          = "origin-kong"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api.id

  enabled                        = true
  host_name                      = var.kong_ingress_ip
  origin_host_header             = var.api_hostname
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = false # IP sem certificado próprio — Front Door faz TLS termination
  priority                       = 1
  weight                         = 1000
}

# ─── Rule Set: cache + security headers ──────────────────────────────────────

resource "azurerm_cdn_frontdoor_rule_set" "default" {
  name                     = "defaultruleset"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

resource "azurerm_cdn_frontdoor_rule" "security_headers" {
  name                      = "SecurityHeaders"
  cdn_frontdoor_rule_set_id = azurerm_cdn_frontdoor_rule_set.default.id
  order                     = 1
  behavior_on_match         = "Continue"

  actions {
    response_header_action {
      header_action = "Append"
      header_name   = "Strict-Transport-Security"
      value         = "max-age=31536000; includeSubDomains"
    }

    response_header_action {
      header_action = "Append"
      header_name   = "X-Content-Type-Options"
      value         = "nosniff"
    }

    response_header_action {
      header_action = "Append"
      header_name   = "X-Frame-Options"
      value         = "DENY"
    }
  }
}

# ─── Rotas ────────────────────────────────────────────────────────────────────

# Rota /assets/* → Blob Storage (com cache longo)
resource "azurerm_cdn_frontdoor_route" "static_assets" {
  name                          = "route-static-assets"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.static_assets.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.blob_storage.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.default.id]

  enabled               = true
  forwarding_protocol   = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match     = ["/assets/*", "/images/*"]
  supported_protocols   = ["Http", "Https"]

  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["text/html", "text/css", "application/javascript", "image/svg+xml"]
  }
}

# Rota /* → Kong API (sem cache)
resource "azurerm_cdn_frontdoor_route" "api" {
  name                          = "route-api"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.api.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.kong_ingress.id]
  cdn_frontdoor_rule_set_ids    = [azurerm_cdn_frontdoor_rule_set.default.id]

  enabled                = true
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  # Sem cache para a API
  cache {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = false
  }
}

# ─── WAF Policy ───────────────────────────────────────────────────────────────

resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                              = "waffoodeapp${var.environment}"
  resource_group_name               = var.resource_group_name
  sku_name                          = azurerm_cdn_frontdoor_profile.main.sku_name
  enabled                           = true
  mode                              = var.waf_mode # Detection (staging) / Prevention (production)

  # Regras gerenciadas OWASP
  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = var.tags
}

resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "sec-foodeapp-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
