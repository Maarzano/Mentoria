[CmdletBinding()]
param(
    [switch]$Volumes
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command not found in PATH."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $repoRoot
try {
    if ($Volumes) {
        docker compose down -v
    }
    else {
        docker compose down
    }
}
finally {
    Pop-Location
}
