################################################################################
# staging-aks-up.ps1 — Recria o AKS e reinstala toda a camada K8s
#
# Usa quando o cluster foi destruído com staging-aks-down.ps1
# Postgres e Redis já existem — só o cluster precisa ser recriado.
# Tempo: ~30 min
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('az', 'terraform', 'kubectl', 'helm', 'istioctl')
Assert-TFVars

Write-Header "Staging AKS UP (recriação)"

# ─── 1. Terraform: restora só o módulo AKS ────────────────────────────────────
Write-Step "terraform apply -target=module.aks (staging)..."
Push-Location $TF_STAGING
terraform apply `
    -target module.aks `
    -auto-approve
$kubeconfigCmd = terraform output -raw get_kubeconfig_command
Pop-Location

Write-Step "Configurando kubectl..."
Invoke-Expression $kubeconfigCmd

# ─── 2. Reinstala toda a camada K8s ──────────────────────────────────────────
Write-Step "Reinstalando camada K8s via staging-up.ps1 -K8sOnly..."
& "$PSScriptRoot\staging-up.ps1" -K8sOnly
