################################################################################
# prod-up.ps1 — Sobe TUDO em produção (Terraform + toda camada K8s)
#
# Uso:
#   .\prod-up.ps1               # Terraform + K8s
#   .\prod-up.ps1 -TfOnly       # Só Terraform
#   .\prod-up.ps1 -K8sOnly      # Só Helm + Kustomize (cluster já existe)
#
# ⚠ Produção tem purge_protection no Key Vault — destruir requer 90 dias.
#   Leia o terraform plan com muita atenção antes de confirmar.
################################################################################
[CmdletBinding()]
param(
    [switch]$TfOnly,
    [switch]$K8sOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('az', 'terraform', 'kubectl', 'helm', 'istioctl')
Assert-TFVars

Write-Header "Production UP"

# ─── 1. Terraform ─────────────────────────────────────────────────────────────
if (-not $K8sOnly) {
    Write-Step "Terraform init..."
    Push-Location $TF_PROD
    terraform init -upgrade

    Write-Step "Terraform plan — LEIA COM ATENÇÃO antes de confirmar..."
    terraform plan -out prod.tfplan
    Write-Host ""
    Confirm-Action "Revisei o plan e quero aplicar em PRODUÇÃO"

    Write-Step "Terraform apply..."
    terraform apply prod.tfplan
    $kubeconfigCmd = terraform output -raw get_kubeconfig_command
    Pop-Location

    Write-Step "Configurando kubectl..."
    Invoke-Expression $kubeconfigCmd
}

if ($TfOnly) {
    Write-Done "Terraform aplicado. Cluster de produção provisionado."
    exit 0
}

# ─── 2. FQDN do Postgres para o Keycloak ─────────────────────────────────────
$postgresFqdn = Get-TerraformOutput -TFDir $TF_PROD -OutputName "postgres_fqdn"
Write-Warn "Postgres FQDN = $postgresFqdn"
Write-Warn "Confirme que infra/k8s/base/keycloak/values.yaml tem externalDatabase.host = '$postgresFqdn'"
Write-Host ""
Confirm-Action "O values.yaml do Keycloak já tem o host correto?"

# ─── 3. Namespaces + Istio (config de produção) ───────────────────────────────
Write-Step "Namespaces..."
kubectl apply -f "$K8S_BASE\namespaces\namespaces.yaml"

Write-Step "Istio (production — tracing 10%, ingress gateway HA)..."
istioctl install -f "$K8S_BASE\istio\istio-operator-production.yaml" -y
kubectl apply -f "$K8S_BASE\istio\peer-authentication.yaml"
kubectl apply -f "$K8S_BASE\istio\authorization-policies.yaml"
kubectl wait --for=condition=ready pod -l app=istiod -n $NS_ISTIO --timeout=180s

# ─── 4. Infra: Kong (3 réplicas), Keycloak, RabbitMQ, Flagsmith ──────────────
Write-Step "Helm repos..."
helm repo add kong      https://charts.konghq.com                     --force-update | Out-Null
helm repo add bitnami   https://charts.bitnami.com/bitnami            --force-update | Out-Null
helm repo add flagsmith https://flagsmith.github.io/flagsmith-charts  --force-update | Out-Null
helm repo update | Out-Null

Write-Step "Kong (production — 3 réplicas)..."
helm upgrade --install kong kong/kong `
    --namespace $NS_SYSTEM --create-namespace `
    --values "$K8S_BASE\kong\values.yaml" `
    --set replicaCount=3 `
    --wait --timeout 5m
kubectl apply -f "$K8S_BASE\kong\plugins.yaml"

Write-Step "Keycloak (production — 2 réplicas, clustering JGroups)..."
helm upgrade --install keycloak bitnami/keycloak `
    --namespace $NS_SYSTEM `
    --values "$K8S_BASE\keycloak\values.yaml" `
    --wait --timeout 10m

Write-Step "RabbitMQ..."
helm upgrade --install rabbitmq bitnami/rabbitmq `
    --namespace $NS_SYSTEM `
    --values "$K8S_BASE\rabbitmq\values.yaml" `
    --wait --timeout 5m

Write-Step "Flagsmith..."
helm upgrade --install flagsmith flagsmith/flagsmith `
    --namespace $NS_SYSTEM `
    --values "$K8S_BASE\flagsmith\values.yaml" `
    --wait --timeout 5m

# ─── 5. Observabilidade (sem overrides de economia — recursos completos) ───────
Write-Step "Helm repos de observabilidade..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update | Out-Null
helm repo add grafana              https://grafana.github.io/helm-charts             --force-update | Out-Null
helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts --force-update | Out-Null
helm repo update | Out-Null

Write-Step "Prometheus + Alertmanager + Grafana (produção — recursos completos)..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace $NS_MONITORING --create-namespace `
    --values "$K8S_BASE\observability\kube-prometheus-stack-values.yaml" `
    --wait --timeout 10m

Write-Step "Loki (produção)..."
helm upgrade --install loki grafana/loki `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\loki-production-values.yaml" `
    --wait --timeout 5m

Write-Step "Tempo..."
helm upgrade --install tempo grafana/tempo `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\tempo-values.yaml" `
    --wait --timeout 5m

Write-Step "OpenTelemetry Collector (daemonset — 1 pod por nó)..."
helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\otel-collector-production-values.yaml" `
    --wait --timeout 5m

# ─── 6. Apps ─────────────────────────────────────────────────────────────────
Write-Step "Microserviços + BFFs (kustomize overlay production — 2 réplicas cada)..."
kubectl apply -k $K8S_PROD
kubectl wait --for=condition=available deployment --all -n $NS_PROD --timeout=300s

# ─── Resumo ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Done "Produção está de pé!"
Write-Host ""
Write-Host "  .\prod-status.ps1                  → ver nodes e pods" -ForegroundColor Gray
Write-Host "  .\port-forward.ps1 grafana-prod    → Grafana em localhost:3001" -ForegroundColor Gray
Write-Host ""
