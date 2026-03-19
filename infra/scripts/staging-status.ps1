################################################################################
# staging-status.ps1 — Visão geral do estado do cluster de staging
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('kubectl')

Write-Header "Staging STATUS"

Write-Host "  NODES" -ForegroundColor White
Write-Host "  ─────" -ForegroundColor DarkGray
kubectl get nodes -o wide
Write-Host ""

Write-Host "  PODS — $NS_STAGING (microserviços + BFFs)" -ForegroundColor White
Write-Host "  ──────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_STAGING
Write-Host ""

Write-Host "  PODS — $NS_SYSTEM (Kong, Keycloak, RabbitMQ, Flagsmith)" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_SYSTEM
Write-Host ""

Write-Host "  PODS — $NS_MONITORING (Prometheus, Loki, Tempo, Grafana, OTel)" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_MONITORING
Write-Host ""

Write-Host "  PODS — $NS_ISTIO (Istio control plane)" -ForegroundColor White
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_ISTIO
Write-Host ""

Write-Host "  KONG External IP" -ForegroundColor White
Write-Host "  ─────────────────" -ForegroundColor DarkGray
kubectl get svc kong-kong-proxy -n $NS_SYSTEM 2>$null `
    || Write-Warn "Kong não encontrado — cluster pode estar pausado ou K8s não instalado."
Write-Host ""
