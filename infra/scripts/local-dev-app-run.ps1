[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")
$svcAuthPath = Join-Path $repoRoot "services\svc-auth"

Push-Location $svcAuthPath
try {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  🚀 svc-auth — Modo Desenvolvimento (dotnet run)               ║" -ForegroundColor Cyan
    Write-Host "║  Hot Reload Habilitado • Logs em tempo real                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚙️  Ambiente: Development" -ForegroundColor Yellow
    Write-Host "📍 Endpoint: http://localhost:8080" -ForegroundColor Yellow
    Write-Host "📚 Swagger:  http://localhost:8080/swagger" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "🔧 Propriedades:" -ForegroundColor Cyan
    Write-Host "   • ASPNETCORE_ENVIRONMENT=Development" -ForegroundColor Gray
    Write-Host "   • OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318" -ForegroundColor Gray
    Write-Host "   • Loki desabilitado para dev natico (use compose para logs)" -ForegroundColor Gray
    Write-Host "   • Hot reload ativo (modifique Program.cs e salve)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "📦 Restaurando dependências e compilando..." -ForegroundColor Yellow
    dotnet build --nologo src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj | Out-Null

    Write-Host ""
    Write-Host "▶️  Iniciando aplicação..." -ForegroundColor Cyan
    Write-Host ""

    # Rodar a app com watch mode
    $env:ASPNETCORE_ENVIRONMENT = "Development"
    $env:OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"
    $env:OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
    $env:OTEL_SERVICE_NAME = "svc-auth"
    $env:ConnectionStrings__Default = "Host=localhost;Port=5432;Database=foodeapp_auth;Username=pgadmin;Password=pgadmin123;Pooling=true"

    dotnet watch run --project src/FoodeApp.SvcAuth.Adapters.API/FoodeApp.SvcAuth.Adapters.API.csproj --no-restore
}
finally {
    Pop-Location
}
