################################################################################
# staging-aks-down.ps1 — Destroi SOMENTE o AKS (pausas longas: >1 semana)
#
# O que SOBREVIVE: Postgres, Redis, Key Vault, ACR, VNet, Front Door, Storage
# O que SOME: cluster AKS + todos os pods + helm releases + configurações K8s
#
# Custo enquanto destruído: ~R$400/mês
# Tempo para destruir: ~15 min
# Para recriar: .\staging-aks-up.ps1
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('terraform')

Write-Header "Staging AKS DOWN"

Write-Warn "O cluster AKS será destruído. Dados em Postgres e Redis são preservados."
Write-Warn "Todos os helm releases e configurações K8s serão perdidos."
Write-Host ""
Confirm-Dangerous `
    -Prompt   "Isso vai destruir o cluster inteiro. Quer continuar?" `
    -Expected "destruir aks"

Write-Step "terraform destroy -target=module.aks (staging)..."
Push-Location $TF_STAGING
terraform destroy `
    -target module.aks `
    -auto-approve
Pop-Location

Write-Host ""
Write-Done "AKS destruído. Postgres e Redis continuam rodando."
Write-Host ""
Write-Host "  Para recriar: .\staging-aks-up.ps1" -ForegroundColor Gray
Write-Host "  Custo agora:  ~R`$400/mês (só managed services)" -ForegroundColor Gray
Write-Host ""
