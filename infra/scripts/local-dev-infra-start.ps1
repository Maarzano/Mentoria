[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command not found in PATH."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $repoRoot
try {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Iniciando Infraestrutura Local (Docker)                       ║" -ForegroundColor Cyan
    Write-Host "║  Serviços: PostgreSQL, OTel, Prometheus, Tempo, Loki, Grafana ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Remove containers de desenvolvimento anterior mas mantém volumes
    Write-Host "🧹 Limpando containers antigos..." -ForegroundColor Yellow
    docker compose down 2>$null | Out-Null

    # Inicia apenas infraestrutura (sem svc-auth)
    Write-Host "📦 Subindo infraestrutura..." -ForegroundColor Cyan
    docker compose up -d postgres otel-collector prometheus tempo loki promtail grafana

    Write-Host ""
    Write-Host "⏳ Aguardando PostgreSQL ficar healthy..." -ForegroundColor Yellow
    $maxRetries = 30
    $retries = 0
    while ($retries -lt $maxRetries) {
        $health = docker inspect --format='{{.State.Health.Status}}' foodeapp-postgres-auth 2>$null
        if ($health -eq "healthy") {
            Write-Host "   ✅ PostgreSQL healthy ($retries segundos)" -ForegroundColor Green
            break
        }
        $retries++
        Start-Sleep -Seconds 1
    }

    if ($retries -eq $maxRetries) {
        Write-Host "   ⚠️  PostgreSQL não ficou healthy após 30s (pode estar inicializando)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  ✅ Infraestrutura Online                                      ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "📍 Endereços:" -ForegroundColor Cyan
    Write-Host "   🗄️  PostgreSQL:      localhost:5432 (pgadmin/pgadmin123)" -ForegroundColor White
    Write-Host "   📊 Prometheus:      http://localhost:9090" -ForegroundColor White
    Write-Host "   📈 Grafana:         http://localhost:3000 (anonymous)" -ForegroundColor White
    Write-Host "   🔍 Tempo:           http://localhost:3200" -ForegroundColor White
    Write-Host "   📝 Loki:            http://localhost:3100" -ForegroundColor White
    Write-Host "   🔄 OTel Collector:  http://localhost:13133 (health)" -ForegroundColor White
    Write-Host ""
    Write-Host "🚀 Próximo passo: abra um novo terminal e rode:" -ForegroundColor Yellow
    Write-Host "   cd services\svc-auth" -ForegroundColor Gray
    Write-Host "   dotnet run --project src/FoodeApp.SvcAuth.Adapters.API" -ForegroundColor Gray
    Write-Host ""
}
finally {
    Pop-Location
}
