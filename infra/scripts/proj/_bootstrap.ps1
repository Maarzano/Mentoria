# ==============================================================================
# _bootstrap.ps1 - Carrega .env, services.json e metadados do compose
#
# Exporta no escopo do script chamador:
#   $registry              -> objeto do services.json
#   $script:DotEnv         -> hashtable com variaveis do .env
#   $script:infraNames     -> nomes dos containers de infra
#   $script:infraEndpoints -> mapa nome -> endpoint
# ==============================================================================

# ── Registro de servicos ──────────────────────────────────────────────────────
$registryPath = Join-Path $repoRoot "infra\local\services.json"
if (-not (Test-Path $registryPath)) {
    Write-Host "  [ERRO] services.json nao encontrado: $registryPath" -ForegroundColor Red
    exit 1
}
$registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ── .env ─────────────────────────────────────────────────────────────────────
function Import-DotEnv {
    param([string]$EnvFilePath)
    $values = @{}
    if (-not (Test-Path $EnvFilePath)) { return $values }
    foreach ($line in (Get-Content $EnvFilePath -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eqIdx = $trimmed.IndexOf("=")
        if ($eqIdx -le 0) { continue }
        $key = $trimmed.Substring(0, $eqIdx).Trim()
        $val = $trimmed.Substring($eqIdx + 1).Trim()
        $values[$key] = $val
    }
    return $values
}

function Get-ConfigValue {
    param([string]$Key)
    if ($script:DotEnv.ContainsKey($Key)) { return $script:DotEnv[$Key] }
    return $null
}

function Assert-RequiredEnvVars {
    $missing = @()
    $secrets = @("POSTGRES_USER", "POSTGRES_PASSWORD")
    foreach ($s in $secrets) {
        if (-not (Get-ConfigValue -Key $s)) {
            $missing += $s
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "  [ERRO] Variaveis obrigatorias nao definidas:" -ForegroundColor Red
        foreach ($m in $missing) {
            Write-Host "         - $m" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  Portas fazem fallback para services.json; credenciais exigem .env." -ForegroundColor Yellow
        Write-Host "  Crie o arquivo .env na raiz do projeto (copie de .env.example)." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

$script:DotEnv = Import-DotEnv -EnvFilePath (Join-Path $repoRoot ".env")

# ── Metadados do docker-compose (nomes + endpoints) ──────────────────────────
function Get-ComposeInfraMetadata {
    param([string]$ProjectRoot)

    $fallbackNames = @(
        "postgres", "otel-collector", "prometheus",
        "tempo", "loki", "promtail", "grafana"
    )

    $fallbackEndpoints = [ordered]@{
        "postgres"       = "localhost:5432"
        "otel-collector" = "localhost:4317 | localhost:4318 | localhost:13133"
        "prometheus"     = "localhost:9090"
        "tempo"          = "localhost:3200"
        "loki"           = "localhost:3100"
        "promtail"       = "(sem porta exposta)"
        "grafana"        = "localhost:3000"
    }

    $result = @{
        Names = $fallbackNames
        Endpoints = $fallbackEndpoints
    }

    Push-Location $ProjectRoot
    try {
        $servicesRaw = docker compose config --services 2>$null
        if (-not $servicesRaw) { return $result }

        $infraNames = @($servicesRaw | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($infraNames.Count -eq 0) { return $result }

        $composeConfig = $null
        $composeJsonRaw = docker compose config --format json 2>$null
        if ($composeJsonRaw) {
            try { $composeConfig = $composeJsonRaw | ConvertFrom-Json } catch {}
        }

        $endpoints = [ordered]@{}
        foreach ($name in $infraNames) {
            $svcEndpoints = @()

            if ($composeConfig -and $composeConfig.services) {
                $serviceProp = $composeConfig.services.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                if ($serviceProp) {
                    $service = $serviceProp.Value
                    $ports = @($service.ports)
                    foreach ($port in $ports) {
                        if (-not $port) { continue }
                        $published = "$( $port.published )".Trim()
                        $target = "$( $port.target )".Trim()
                        $proto = "$( $port.protocol )".Trim()
                        if (-not $proto) { $proto = 'tcp' }
                        if (-not $published) { continue }

                        $entry = if ($published -eq $target -and $proto -eq 'tcp') {
                            "localhost:$published"
                        } elseif ($published -eq $target) {
                            "localhost:$published/$proto"
                        } elseif ($proto -eq 'tcp') {
                            "localhost:$published -> $target"
                        } else {
                            "localhost:$published -> $target/$proto"
                        }

                        $svcEndpoints += $entry
                    }
                }
            }

            if ($svcEndpoints -and $svcEndpoints.Count -gt 0) {
                $endpoints[$name] = ($svcEndpoints | Select-Object -Unique) -join ' | '
            } else {
                $endpoints[$name] = '(sem porta exposta)'
            }
        }

        return @{ Names = $infraNames; Endpoints = $endpoints }
    } catch {
        return $result
    } finally {
        Pop-Location
    }
}

$composeMeta = Get-ComposeInfraMetadata -ProjectRoot $repoRoot
$script:infraNames = $composeMeta.Names
$script:infraEndpoints = $composeMeta.Endpoints

# Constantes de container de servico
$script:SVC_CONTAINER_PREFIX = "foodeapp"
$script:DEFAULT_DOTNET_CONTAINER_PORT = 8080
