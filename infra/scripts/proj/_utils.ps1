# ==============================================================================
# _utils.ps1 - Utilitarios de status, portas, env e ambiente
# ==============================================================================

function Test-PortListening {
    param([int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(300)
        if ($ok) { try { $tcp.EndConnect($ar) } catch {} }
        $tcp.Close(); $tcp.Dispose()
        return $ok
    } catch {
        return $false
    }
}

function Get-ServiceConfig {
    param([string]$Name)
    $prop = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $Name }
    if (-not $prop) {
        Write-ERR "Servico '$Name' nao encontrado."
        Write-GRAY "Use '.\proj.ps1 list' para ver disponiveis."
        exit 1
    }
    return $prop.Value
}

function Test-ServiceReady {
    param([string]$Name, [PSObject]$Cfg)
    $svcPath = Join-Path $repoRoot $Cfg.path
    switch ($Cfg.type) {
        "dotnet" {
            $sln = Get-ChildItem $svcPath -Filter "*.sln" -ErrorAction SilentlyContinue
            return ($null -ne $sln -and $sln.Count -gt 0)
        }
        "node" { return (Test-Path (Join-Path $svcPath "package.json")) }
    }
    return $false
}

function Get-DockerStatus {
    $result = @{}
    Push-Location $repoRoot
    try {
        $lines = docker compose ps --format "{{.Service}}|{{.Status}}" 2>$null
        if ($lines) {
            foreach ($line in $lines) {
                if ($line -and $line.Contains("|")) {
                    $parts = $line.Split("|", 2)
                    $result[$parts[0].Trim()] = $parts[1].Trim()
                }
            }
        }
    } catch {}
    finally { Pop-Location }
    return $result
}

function Test-InfraRunning {
    $s = Get-DockerStatus
    return ($s.Count -gt 0)
}

function Resolve-Target {
    param([string]$Name)
    if ($Name -in $script:infraNames) { return "infra" }
    $svcProp = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $Name }
    if ($svcProp) { return "service" }
    return "unknown"
}

function Wait-ComposeServiceHealthy {
    param(
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )

    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        $containerId = (docker compose ps -q $ServiceName 2>$null | Select-Object -First 1)
        if (-not $containerId) {
            Start-Sleep -Seconds 1
            continue
        }

        $health = docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $containerId 2>$null
        if ($health -eq "healthy" -or $health -eq "running") {
            return @{ Healthy = $true; ElapsedSeconds = $i }
        }

        Start-Sleep -Seconds 1
    }

    return @{ Healthy = $false; ElapsedSeconds = $TimeoutSeconds }
}

# ── Resolucao de portas e env vars de servico ────────────────────────────────
function Get-ServicePort {
    param([string]$Name, [PSObject]$Cfg)
    $envKey = ($Name -replace '-', '_').ToUpper() + "_PORT"
    $envVal = Get-ConfigValue -Key $envKey
    if ($envVal) { return [int]$envVal }
    return $Cfg.port
}

function Build-ServiceEnv {
    param([string]$Name, [PSObject]$Cfg)

    $port = Get-ServicePort -Name $Name -Cfg $Cfg

    $env = @{
        "ASPNETCORE_ENVIRONMENT" = "Development"
        "ASPNETCORE_URLS"        = "http://localhost:$port"
        "OTEL_EXPORTER_OTLP_ENDPOINT" = (Get-ConfigValue -Key "OTEL_EXPORTER_OTLP_ENDPOINT")
        "OTEL_EXPORTER_OTLP_PROTOCOL" = (Get-ConfigValue -Key "OTEL_EXPORTER_OTLP_PROTOCOL")
        "OTEL_SERVICE_NAME"      = $Name
    }

    if ($Cfg.database) {
        $dbName = Get-ConfigValue -Key $Cfg.database
        $env["Database__Host"]     = Get-ConfigValue -Key "POSTGRES_HOST"
        $env["Database__Port"]     = Get-ConfigValue -Key "POSTGRES_PORT"
        $env["Database__Database"] = $dbName
        $env["Database__Username"] = Get-ConfigValue -Key "POSTGRES_USER"
        $env["Database__Password"] = Get-ConfigValue -Key "POSTGRES_PASSWORD"
    }

    if ($Cfg.type -eq "node" -and $Name -eq "web") {
        $bffPort = Get-ServicePort -Name "bff-web" -Cfg ($registry.services."bff-web")
        $env["PORT"] = "$port"
        $env["REACT_APP_API_URL"] = "http://localhost:$bffPort"
    }
    if ($Cfg.type -eq "node" -and $Name -eq "mobile") {
        $bffPort = Get-ServicePort -Name "bff-mobile" -Cfg ($registry.services."bff-mobile")
        $env["EXPO_DEVTOOLS_LISTEN_ADDRESS"] = "0.0.0.0"
        $env["REACT_NATIVE_API_URL"] = "http://localhost:$bffPort"
    }

    return $env
}

function Invoke-WithScopedEnvironment {
    param([hashtable]$Vars, [scriptblock]$Action)

    $snapshot = @{}
    foreach ($key in $Vars.Keys) {
        $snapshot[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, "$($Vars[$key])", "Process")
    }

    try {
        & $Action
    }
    finally {
        foreach ($key in $Vars.Keys) {
            [Environment]::SetEnvironmentVariable($key, $snapshot[$key], "Process")
        }
    }
}
