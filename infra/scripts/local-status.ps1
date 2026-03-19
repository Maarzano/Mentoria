[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker command not found in PATH."
}

function Test-Endpoint {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Url
    )

    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 5 -ErrorAction Stop
        Write-Host ("[OK]   {0} -> {1} ({2})" -f $Name, $resp.StatusCode, $Url) -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $code = [int]$_.Exception.Response.StatusCode
            Write-Host ("[FAIL] {0} -> {1} ({2})" -f $Name, $code, $Url) -ForegroundColor Yellow
        }
        else {
            Write-Host ("[DOWN] {0} -> ({1})" -f $Name, $Url) -ForegroundColor Red
        }
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Push-Location $repoRoot
try {
    docker compose ps

    Write-Host ""
    Test-Endpoint -Name "healthz" -Url "http://localhost:8080/healthz"
    Test-Endpoint -Name "ready"   -Url "http://localhost:8080/ready"
    Test-Endpoint -Name "metrics" -Url "http://localhost:8080/metrics"
}
finally {
    Pop-Location
}
