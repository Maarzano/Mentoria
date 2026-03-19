################################################################################
# staging-pause.ps1 — Para as VMs do AKS (az aks stop)
#
# O que acontece:
#   - VMs dos 4 node pools são desalocadas (sem cobrança de compute)
#   - Postgres, Redis, Key Vault, ACR e Front Door continuam rodando
#   - Estado do cluster (etcd, helm releases, ConfigMaps) é preservado
#   - Ao retomar com staging-resume.ps1, tudo volta exatamente igual
#
# Custo enquanto pausado: ~R$250/mês (só managed services)
# Tempo para pausar:  ~2 min
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('az')

Write-Header "Staging PAUSE"

Write-Step "Parando cluster '$STAGING_CLUSTER' (az aks stop)..."
Write-Host "  Isso desaloca as VMs mas preserva Postgres, Redis e todo o estado K8s." -ForegroundColor Gray
Write-Host ""

az aks stop `
    --resource-group $STAGING_RG `
    --name          $STAGING_CLUSTER

Write-Host ""
Write-Done "Cluster pausado. VMs desligadas."
Write-Host ""
Write-Host "  Para retomar: .\staging-resume.ps1" -ForegroundColor Gray
Write-Host "  Custo agora:  ~R`$250/mês (só Postgres + Redis + Front Door + ACR)" -ForegroundColor Gray
Write-Host ""
