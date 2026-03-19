################################################################################
# staging-up.ps1 — Sobe TUDO no staging (Terraform + toda camada K8s)
#
# Uso:
#   .\staging-up.ps1               # Terraform + K8s
#   .\staging-up.ps1 -TfOnly       # Só Terraform
#   .\staging-up.ps1 -K8sOnly      # Só Helm + Kustomize (cluster já existe)
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

Write-Header "Staging UP"

# ─── 1. Terraform ─────────────────────────────────────────────────────────────
if (-not $K8sOnly) {
    Write-Step "Terraform init..."
    Push-Location $TF_STAGING
    terraform init -upgrade
    Write-Step "Terraform apply..."
    terraform apply -auto-approve
    $kubeconfigCmd = terraform output -raw get_kubeconfig_command
    Pop-Location

    Write-Step "Configurando kubectl..."
    Invoke-Expression $kubeconfigCmd
}

if ($TfOnly) {
    Write-Done "Terraform aplicado. Cluster provisionado."
    exit 0
}

# ─── 2. Informar FQDN do Postgres (necessário antes do Keycloak) ──────────────
$postgresFqdn = Get-TerraformOutput -TFDir $TF_STAGING -OutputName "postgres_fqdn"
Write-Warn "Postgres FQDN = $postgresFqdn"
Write-Warn "Confirme que infra/k8s/base/keycloak/values.yaml tem externalDatabase.host = '$postgresFqdn'"
Write-Host ""
Confirm-Action "O values.yaml do Keycloak já tem o host correto?"

# ─── 3. Namespaces + Istio ────────────────────────────────────────────────────
Write-Step "Namespaces..."
kubectl apply -f "$K8S_BASE\namespaces\namespaces.yaml"

Write-Step "Istio (staging — tracing 100%)..."
istioctl install -f "$K8S_BASE\istio\istio-operator.yaml" -y
kubectl apply -f "$K8S_BASE\istio\peer-authentication.yaml"
kubectl apply -f "$K8S_BASE\istio\authorization-policies.yaml"
kubectl wait --for=condition=ready pod -l app=istiod -n $NS_ISTIO --timeout=120s

# ─── 4. Infra: Kong, Keycloak, RabbitMQ, Flagsmith ───────────────────────────
Write-Step "Helm repos..."
helm repo add kong        https://charts.konghq.com                              --force-update | Out-Null
helm repo add bitnami     https://charts.bitnami.com/bitnami                    --force-update | Out-Null
helm repo add flagsmith   https://flagsmith.github.io/flagsmith-charts          --force-update | Out-Null
helm repo update | Out-Null

Write-Step "Kong..."
helm upgrade --install kong kong/kong `
    --namespace $NS_SYSTEM --create-namespace `
    --values "$K8S_BASE\kong\values.yaml" `
    --wait --timeout 5m
kubectl apply -f "$K8S_BASE\kong\plugins.yaml"

Write-Step "Keycloak..."
helm upgrade --install keycloak bitnami/keycloak `
    --namespace $NS_SYSTEM `
    --values "$K8S_BASE\keycloak\values.yaml" `
    --wait --timeout 8m

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

# ─── 5. Observabilidade (com overrides de staging = menos recursos) ───────────
Write-Step "Helm repos de observabilidade..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update | Out-Null
helm repo add grafana              https://grafana.github.io/helm-charts             --force-update | Out-Null
helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts --force-update | Out-Null
helm repo update | Out-Null

Write-Step "Prometheus + Alertmanager + Grafana (staging — recursos reduzidos)..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace $NS_MONITORING --create-namespace `
    --values "$K8S_BASE\observability\kube-prometheus-stack-values.yaml" `
    --values "$K8S_BASE\observability\prometheus-staging-values.yaml" `
    --wait --timeout 8m

Write-Step "Loki (staging)..."
helm upgrade --install loki grafana/loki `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\loki-values.yaml" `
    --values "$K8S_BASE\observability\loki-staging-values.yaml" `
    --wait --timeout 5m

Write-Step "Tempo..."
helm upgrade --install tempo grafana/tempo `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\tempo-values.yaml" `
    --wait --timeout 5m

Write-Step "OpenTelemetry Collector..."
helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector `
    --namespace $NS_MONITORING `
    --values "$K8S_BASE\observability\otel-collector-values.yaml" `
    --wait --timeout 5m

# ─── 6. Apps: Microserviços + BFFs ───────────────────────────────────────────
Write-Step "Microserviços + BFFs (kustomize overlay staging)..."
kubectl apply -k $K8S_STAGING
kubectl wait --for=condition=available deployment --all -n $NS_STAGING --timeout=180s

# ─── Resumo ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Done "Staging está de pé!"
Write-Host ""
Write-Host "  Próximos passos:" -ForegroundColor White
Write-Host "    .\staging-status.ps1            → ver nodes e pods" -ForegroundColor Gray
Write-Host "    .\port-forward.ps1 grafana       → Grafana em localhost:3000" -ForegroundColor Gray
Write-Host "    .\port-forward.ps1 rabbitmq      → RabbitMQ em localhost:15672" -ForegroundColor Gray
Write-Host "    .\port-forward.ps1 keycloak      → Keycloak em localhost:8080" -ForegroundColor Gray
Write-Host ""
Write-Warn "Não esqueça: .\staging-pause.ps1 quando terminar de usar!"
Write-Host ""
