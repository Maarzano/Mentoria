################################################################################
# staging-resume.ps1 — Liga as VMs do AKS (az aks start)
#
# O que acontece:
#   - VMs são realocadas e os nodes voltam ao cluster
#   - K8s reagenda automaticamente todos os pods que estavam rodando
#   - Não precisa reinstalar Helm charts ou rodar kustomize de novo
#
# Tempo para ficar pronto: ~8 min
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('az', 'kubectl')

Write-Header "Staging RESUME"

Write-Step "Iniciando cluster '$STAGING_CLUSTER' (az aks start)..."
az aks start `
    --resource-group $STAGING_RG `
    --name          $STAGING_CLUSTER

Write-Step "Atualizando kubeconfig..."
az aks get-credentials `
    --resource-group $STAGING_RG `
    --name          $STAGING_CLUSTER `
    --overwrite-existing

Write-Step "Aguardando nodes ficarem prontos (pode levar ~5 min)..."
kubectl wait --for=condition=ready node --all --timeout=600s

Write-Host ""
Write-Done "Cluster retomado e nodes prontos!"
Write-Host ""

# Mostra um status rápido
Write-Host "  Nodes:" -ForegroundColor White
kubectl get nodes -o wide
Write-Host ""
Write-Host "  Dica: aguarde ~2 min para todos os pods subirem, depois:" -ForegroundColor Gray
Write-Host "    .\staging-status.ps1    → verificar pods" -ForegroundColor Gray
Write-Host "    .\port-forward.ps1 grafana → Grafana em localhost:3000" -ForegroundColor Gray
Write-Host ""
