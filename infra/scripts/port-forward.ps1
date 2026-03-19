################################################################################
# port-forward.ps1 — Port-forward para serviços internos do cluster
#
# Uso:
#   .\port-forward.ps1 grafana          → localhost:3000  (staging)
#   .\port-forward.ps1 grafana-prod     → localhost:3001  (prod)
#   .\port-forward.ps1 rabbitmq         → localhost:15672 (staging)
#   .\port-forward.ps1 keycloak         → localhost:8080  (staging)
#   .\port-forward.ps1 prometheus       → localhost:9090  (staging)
#   .\port-forward.ps1 tempo            → localhost:3100  (staging)
#
# Para parar: Ctrl+C
################################################################################
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('grafana', 'grafana-prod', 'rabbitmq', 'keycloak', 'prometheus', 'tempo')]
    [string]$Service
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('kubectl')

switch ($Service) {

    'grafana' {
        $url  = "http://localhost:3000"
        $ns   = $NS_MONITORING
        $svc  = "svc/kube-prometheus-stack-grafana"
        $port = "3000:80"
        $hint = "Login: admin / senha definida no values.yaml (CHANGE-ME-VIA-SECRET)"
    }

    'grafana-prod' {
        $url  = "http://localhost:3001"
        $ns   = $NS_MONITORING
        $svc  = "svc/kube-prometheus-stack-grafana"
        $port = "3001:80"
        $hint = "Login: admin / senha definida no values.yaml (CHANGE-ME-VIA-SECRET)"
        Write-Warn "Certifique-se de que o kubeconfig aponta para o cluster de PRODUÇÃO."
        Write-Warn "Use: az aks get-credentials --resource-group $PROD_RG --name $PROD_CLUSTER --overwrite-existing"
    }

    'rabbitmq' {
        $url  = "http://localhost:15672"
        $ns   = $NS_SYSTEM
        $svc  = "svc/rabbitmq"
        $port = "15672:15672"
        $hint = "Login: user / senha definida no secret 'rabbitmq-secret'"
    }

    'keycloak' {
        $url  = "http://localhost:8080"
        $ns   = $NS_SYSTEM
        $svc  = "svc/keycloak"
        $port = "8080:80"
        $hint = "Login: admin / senha definida no secret 'keycloak-admin-secret'"
    }

    'prometheus' {
        $url  = "http://localhost:9090"
        $ns   = $NS_MONITORING
        $svc  = "svc/kube-prometheus-stack-prometheus"
        $port = "9090:9090"
        $hint = "Interface do Prometheus para queries PromQL diretas."
    }

    'tempo' {
        $url  = "http://localhost:3100"
        $ns   = $NS_MONITORING
        $svc  = "svc/tempo"
        $port = "3100:3100"
        $hint = "API de traces do Tempo (usado pelo Grafana como datasource)."
    }
}

Write-Host ""
Write-Host "  ─── Port-forward: $Service ─────────────────────────────" -ForegroundColor Magenta
Write-Host "  Acessar em: $url" -ForegroundColor Cyan
Write-Host "  $hint" -ForegroundColor Gray
Write-Host "  Para parar: Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

kubectl port-forward $svc $port -n $ns
