[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command not found in PATH."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $repoRoot
try {
    docker compose up --build -d

    Write-Host ""
    Write-Host "Local stack is up."
    Write-Host "Try:"
    Write-Host "  http://localhost:8080/healthz"
    Write-Host "  http://localhost:8080/ready"
    Write-Host "  http://localhost:8080/metrics"
    Write-Host ""
    Write-Host "Next:"
    Write-Host "  .\infra\scripts\local-status.ps1"
}
finally {
    Pop-Location
}
