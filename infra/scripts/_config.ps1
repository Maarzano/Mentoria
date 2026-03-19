################################################################################
# _config.ps1 — Variáveis compartilhadas entre todos os scripts
# NÃO rodar diretamente. Usar via dot-source nos outros scripts:
#   . "$PSScriptRoot\_config.ps1"
################################################################################

# ─── Azure / AKS ──────────────────────────────────────────────────────────────
$STAGING_RG      = "rg-foodeapp-staging"
$STAGING_CLUSTER = "aks-foodeapp-staging"
$PROD_RG         = "rg-foodeapp-production"
$PROD_CLUSTER    = "aks-foodeapp-production"

# ─── Namespaces Kubernetes ────────────────────────────────────────────────────
$NS_STAGING    = "foodeapp-staging"
$NS_PROD       = "foodeapp-production"
$NS_SYSTEM     = "foodeapp-system"
$NS_MONITORING = "monitoring"
$NS_ISTIO      = "istio-system"

# ─── Caminhos Terraform ───────────────────────────────────────────────────────
$TF_STAGING = "$PSScriptRoot\..\terraform\envs\staging"
$TF_PROD    = "$PSScriptRoot\..\terraform\envs\production"

# ─── Caminhos K8s ─────────────────────────────────────────────────────────────
$K8S_BASE    = "$PSScriptRoot\..\k8s\base"
$K8S_STAGING = "$PSScriptRoot\..\k8s\overlays\staging"
$K8S_PROD    = "$PSScriptRoot\..\k8s\overlays\production"
