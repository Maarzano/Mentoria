################################################################################
# prod-status.ps1 — Visão geral do estado do cluster de produção
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('kubectl')

Write-Header "Production STATUS"

Write-Host "  NODES" -ForegroundColor White
Write-Host "  ─────" -ForegroundColor DarkGray
kubectl get nodes -o wide
Write-Host ""

Write-Host "  HPA — autoscaling" -ForegroundColor White
Write-Host "  ──────────────────" -ForegroundColor DarkGray
kubectl get hpa -n $NS_PROD
Write-Host ""

Write-Host "  PODS — $NS_PROD" -ForegroundColor White
Write-Host "  ───────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_PROD
Write-Host ""

Write-Host "  PODS — $NS_SYSTEM (Kong, Keycloak, RabbitMQ, Flagsmith)" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_SYSTEM
Write-Host ""

Write-Host "  PODS — $NS_MONITORING (Prometheus, Loki, Tempo, Grafana, OTel)" -ForegroundColor White
Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_MONITORING
Write-Host ""

Write-Host "  PODS — $NS_ISTIO" -ForegroundColor White
Write-Host "  ──────────────────" -ForegroundColor DarkGray
kubectl get pods -n $NS_ISTIO
Write-Host ""

Write-Host "  KONG External IP" -ForegroundColor White
Write-Host "  ─────────────────" -ForegroundColor DarkGray
kubectl get svc kong-kong-proxy -n $NS_SYSTEM
Write-Host ""
