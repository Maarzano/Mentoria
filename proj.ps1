#!/usr/bin/env pwsh
# ==============================================================================
# proj.ps1 - FoodeApp | CLI de Desenvolvimento Local
#
# COMANDOS:
#   run    <svcs...>       Roda local com hot reload (dotnet watch / npm dev)
#   run -c <svcs...>       Roda via container Docker (Dockerfile do servico)
#   list                   Lista tudo com portas e status
#   status [itens]         Saude de itens especificos ou do que esta rodando
#   infra  [nomes]         Sobe infra Docker (todos ou especificos)
#   logs   [nomes]         Logs Docker (infra ou servico em container)
#   stop   [nomes]         Para containers (infra e/ou servicos)
#   down   [nomes]         Remove containers (infra e/ou servicos)
#
# FLAGS:
#   -c                     Modo container (usado com 'run')
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [switch]$c,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Services
)

# NOTA: Usar "Continue" e nao "Stop" porque docker compose escreve progresso
# no stderr, e PS 5.1 trata stderr de comandos nativos como erro terminante
# quando $ErrorActionPreference = "Stop".
$ErrorActionPreference = "Continue"
$repoRoot = $PSScriptRoot

# ==============================================================================
# Configuracao e Registro
# ==============================================================================

$registryPath = Join-Path $repoRoot "infra\local\services.json"
if (-not (Test-Path $registryPath)) {
    Write-Host "  [ERRO] services.json nao encontrado: $registryPath" -ForegroundColor Red
    exit 1
}
$registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json

# ==============================================================================
# .env — Fonte unica de variaveis para dev local
# ==============================================================================

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

# Helper: resolve porta do servico a partir do .env, com fallback para services.json
function Get-ServicePort {
    param([string]$Name, [PSObject]$Cfg)
    $envKey = ($Name -replace '-', '_').ToUpper() + "_PORT"
    $envVal = Get-ConfigValue -Key $envKey
    if ($envVal) { return [int]$envVal }
    return $Cfg.port
}

# Helper: monta env vars para um servico .NET a partir do .env centralizado
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

    # Database (se o servico declara campo "database" no services.json)
    if ($Cfg.database) {
        $dbName = Get-ConfigValue -Key $Cfg.database
        $env["Database__Host"]     = Get-ConfigValue -Key "POSTGRES_HOST"
        $env["Database__Port"]     = Get-ConfigValue -Key "POSTGRES_PORT"
        $env["Database__Database"] = $dbName
        $env["Database__Username"] = Get-ConfigValue -Key "POSTGRES_USER"
        $env["Database__Password"] = Get-ConfigValue -Key "POSTGRES_PASSWORD"
    }

    # Node frontends
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

# Modo container: -c flag
$script:ContainerMode = [bool]$c
$script:SVC_CONTAINER_PREFIX = "foodeapp"
$script:DEFAULT_DOTNET_CONTAINER_PORT = 8080

# ==============================================================================
# Output Helpers
# ==============================================================================

function Write-Header {
    param([string]$Title)
    $line = "=" * 60
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "  FoodeApp | $Title" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([int]$N, [int]$Total, [string]$Msg)
    if ($N -gt 0 -and $Total -gt 0) {
        Write-Host "  [$N/$Total] $Msg" -ForegroundColor Cyan
    } else {
        Write-Host "  > $Msg" -ForegroundColor Cyan
    }
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-WARN { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Yellow }
function Write-ERR  { param([string]$Msg) Write-Host "  [ERRO] $Msg" -ForegroundColor Red }
function Write-TIP  { param([string]$Msg) Write-Host "  DICA: $Msg" -ForegroundColor DarkYellow }
function Write-GRAY { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor DarkGray }

function Write-Footer {
    Write-Host ""
    Write-Host ("  " + "=" * 60) -ForegroundColor DarkCyan
    Write-Host ""
}

# ==============================================================================
# Utilidades
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

# ==============================================================================
# Containers de Servico (docker run a partir do Dockerfile)
# ==============================================================================

function Get-ComposeNetworkName {
    Push-Location $repoRoot
    try {
        $jsonRaw = docker compose config --format json 2>$null
        if ($jsonRaw) {
            $cfg = $jsonRaw | ConvertFrom-Json
            if ($cfg.name) { return "$($cfg.name)_default" }
        }
    } catch {} finally { Pop-Location }
    return "foodeapp_default"
}

function Get-ServiceContainerPort {
    param([PSObject]$Cfg)
    if ($Cfg.containerPort) { return $Cfg.containerPort }
    switch ($Cfg.type) {
        "dotnet" { return $script:DEFAULT_DOTNET_CONTAINER_PORT }
        default  { return $Cfg.port }
    }
}

function Get-ServiceContainerName {
    param([string]$Name)
    return "$($script:SVC_CONTAINER_PREFIX)-$Name"
}

function Get-ServiceImageName {
    param([string]$Name)
    return "$($script:SVC_CONTAINER_PREFIX)/${Name}:dev"
}

function Test-ServiceContainerRunning {
    param([string]$Name)
    $containerName = Get-ServiceContainerName -Name $Name
    $status = docker inspect --format='{{.State.Status}}' $containerName 2>$null
    return ($status -eq "running")
}

function Get-ServiceContainersStatus {
    $result = @{}
    $lines = docker ps -a --filter "label=foodeapp.type=service" --format "{{.Names}}|{{.Status}}" 2>$null
    if ($lines) {
        foreach ($line in $lines) {
            if ($line -and $line.Contains("|")) {
                $parts = $line.Split("|", 2)
                $containerName = $parts[0].Trim()
                $svcName = $containerName -replace "^$([regex]::Escape($script:SVC_CONTAINER_PREFIX))-", ""
                $result[$svcName] = $parts[1].Trim()
            }
        }
    }
    return $result
}

function Build-ContainerEnvArgs {
    param([string]$Name, [PSObject]$Cfg, [int]$ContainerPort)

    # Monta env vars do servico a partir do .env centralizado
    $localEnv = Build-ServiceEnv -Name $Name -Cfg $Cfg

    # Mapeia porta publicada → nome do servico de infra
    $portToInfra = @{}
    foreach ($infraName in $script:infraNames) {
        $ep = "$($script:infraEndpoints[$infraName])"
        foreach ($m in [regex]::Matches($ep, 'localhost:(\d+)')) {
            $portToInfra[[int]$m.Groups[1].Value] = $infraName
        }
    }

    $envArgs = @()
    foreach ($key in $localEnv.Keys) {
        $val = $localEnv[$key]

        if ($key -eq "ASPNETCORE_URLS") {
            # Container escuta em todas as interfaces
            $val = "http://0.0.0.0:$ContainerPort"
        }
        elseif ($key -like "Database__Host" -and $val -eq "localhost") {
            # Traduz para nome de rede do PostgreSQL no compose
            $port = if ($localEnv["Database__Port"]) { $localEnv["Database__Port"] } else { "5432" }
            $pgPort = [int]$port
            if ($portToInfra.ContainsKey($pgPort)) {
                $val = $portToInfra[$pgPort]
            }
        }
        elseif ($val -match "localhost:\d+") {
            # URL genérica: localhost:PORT → infraName:PORT
            foreach ($p in @($portToInfra.Keys)) {
                $infraN = $portToInfra[$p]
                $val = $val -replace "localhost:$p", "${infraN}:$p"
            }
        }

        $envArgs += "-e"
        $envArgs += "$key=$val"
    }
    return $envArgs
}

function Resolve-AllDeps {
    param(
        [string[]]$ServiceNames,
        [string[]]$Exclude = @()
    )

    $allDeps = @()
    $visited = @() + $Exclude + $ServiceNames
    $queue = New-Object System.Collections.Queue

    foreach ($name in $ServiceNames) {
        $prop = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $name }
        if ($prop -and $prop.Value.depends) {
            foreach ($dep in $prop.Value.depends) {
                if ($dep -notin $visited) {
                    $queue.Enqueue($dep)
                    $visited += $dep
                }
            }
        }
    }

    while ($queue.Count -gt 0) {
        $dep = $queue.Dequeue()
        $allDeps += $dep
        $prop = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $dep }
        if ($prop -and $prop.Value.depends) {
            foreach ($d in $prop.Value.depends) {
                if ($d -notin $visited) {
                    $queue.Enqueue($d)
                    $visited += $d
                }
            }
        }
    }

    return $allDeps
}

function Invoke-ServiceContainerUp {
    param([string]$Name)

    $cfg = Get-ServiceConfig -Name $Name
    $containerName = Get-ServiceContainerName -Name $Name
    $imageName = Get-ServiceImageName -Name $Name
    $svcPath = Join-Path $repoRoot $cfg.path
    $dockerfile = Join-Path $svcPath "Dockerfile"

    if (-not (Test-Path $dockerfile)) {
        Write-ERR "$Name : Dockerfile nao encontrado em $($cfg.path)/Dockerfile"
        return $false
    }

    # Ja esta rodando?
    if (Test-ServiceContainerRunning -Name $Name) {
        Write-OK "$Name ja esta rodando como container."
        return $true
    }

    # Remove container parado se existir
    docker rm -f $containerName 2>$null | Out-Null

    # Build imagem (contexto é a raiz do projeto para acessar shared/)
    Write-Host "       [$Name] docker build..." -ForegroundColor DarkGray -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker build -t $imageName -f $dockerfile $repoRoot 2>$null
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }
    Write-Host " OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green

    # Network e portas
    $network = Get-ComposeNetworkName
    $hostPort = $cfg.port
    $containerPort = Get-ServiceContainerPort -Cfg $cfg

    # Env vars adaptadas para rede Docker
    $envArgs = Build-ContainerEnvArgs -Name $Name -Cfg $cfg -ContainerPort $containerPort

    # docker run
    Write-Host "       [$Name] docker run..." -ForegroundColor DarkGray -NoNewline
    $runArgs = @(
        "run", "-d",
        "--name", $containerName,
        "--network", $network,
        "-p", "${hostPort}:${containerPort}",
        "--label", "foodeapp.type=service",
        "--label", "foodeapp.service=$Name"
    )
    $runArgs += $envArgs
    $runArgs += $imageName

    & docker @runArgs 2>$null | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }
    Write-Host " OK (:$hostPort)" -ForegroundColor Green
    return $true
}

function Stop-ServiceContainer {
    param([string]$Name)
    $containerName = Get-ServiceContainerName -Name $Name
    docker stop $containerName 2>$null | Out-Null
    docker rm $containerName 2>$null | Out-Null
}

# ==============================================================================
# Pre-requisitos (smart restore/build)
# ==============================================================================

function Invoke-DotnetPrereqs {
    param([string]$Name, [PSObject]$Cfg)
    $svcPath = Join-Path $repoRoot $Cfg.path
    $projFullPath = Join-Path $svcPath $Cfg.entryProject

    if (-not (Test-Path $projFullPath)) {
        Write-WARN "$Name : csproj nao existe ainda."
        return $false
    }

    $projDir = Split-Path $projFullPath -Parent
    $assetsPath = Join-Path $projDir "obj\project.assets.json"
    $needsRestore = (-not (Test-Path $assetsPath))
    if (-not $needsRestore) {
        $needsRestore = (Get-Item $projFullPath).LastWriteTimeUtc -gt (Get-Item $assetsPath).LastWriteTimeUtc
    }

    if ($needsRestore) {
        Write-Host "       dotnet restore..." -ForegroundColor DarkGray -NoNewline
        dotnet restore $projFullPath --nologo -v quiet 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host " FALHOU" -ForegroundColor Red; return $false }
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host "       Dependencias OK (cache valido)." -ForegroundColor DarkGray
    }

    Write-Host "       dotnet build..." -ForegroundColor DarkGray -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $buildArgs = @("build", $projFullPath, "--nologo", "-v", "quiet", "-c", "Debug")
    if (-not $needsRestore) { $buildArgs += "--no-restore" }
    & dotnet @buildArgs 2>$null
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }

    Write-Host " OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
    return $true
}

function Invoke-NodePrereqs {
    param([string]$Name, [PSObject]$Cfg)
    $svcPath = Join-Path $repoRoot $Cfg.path

    if (-not (Test-Path (Join-Path $svcPath "package.json"))) {
        Write-WARN "$Name : package.json nao existe ainda."
        return $false
    }

    $nodeModules = Join-Path $svcPath "node_modules"
    $lockFile    = Join-Path $svcPath "package-lock.json"
    $needsInstall = (-not (Test-Path $nodeModules))
    if (-not $needsInstall -and (Test-Path $lockFile)) {
        $needsInstall = (Get-Item $lockFile).LastWriteTimeUtc -gt (Get-Item $nodeModules).LastWriteTimeUtc
    }

    Push-Location $svcPath
    try {
        if ($needsInstall) {
            Write-Host "       npm ci..." -ForegroundColor DarkGray -NoNewline
            npm ci --silent 2>$null
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host "       node_modules OK (cache valido)." -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
    return $true
}

function Invoke-Prereqs {
    param([string]$Name, [PSObject]$Cfg)
    switch ($Cfg.type) {
        "dotnet" { return Invoke-DotnetPrereqs -Name $Name -Cfg $Cfg }
        "node"   { return Invoke-NodePrereqs   -Name $Name -Cfg $Cfg }
        default  { Write-WARN "Tipo desconhecido: $($Cfg.type)"; return $false }
    }
}

# ==============================================================================
# Helper: atualiza compound no launch.json preservando o restante do arquivo
# ==============================================================================

function Update-LaunchCompound {
    param(
        [string]$CompoundName,
        [string[]]$Configurations,
        [string]$PreLaunchTask = $null
    )
    $vscodePath = Join-Path $repoRoot "..\vscode" # nao usado diretamente
    $launchPath = Join-Path $repoRoot "..\.vscode\launch.json"
    if (-not (Test-Path $launchPath)) { return $false }

    $raw     = [System.IO.File]::ReadAllText($launchPath)
    $cleaned = $raw -replace '(?m)\s*//[^\n]*', '' -replace ',(\s*[}\]])', '$1'
    try { $launch = $cleaned | ConvertFrom-Json } catch { return $false }

    $compounds = @($launch.compounds)
    $found = $false
    for ($i = 0; $i -lt $compounds.Count; $i++) {
        if ($compounds[$i].name -eq $CompoundName) {
            $compounds[$i].configurations = $Configurations
            $found = $true; break
        }
    }
    if (-not $found) {
        $newC = [PSCustomObject]@{ name = $CompoundName; configurations = $Configurations; stopAll = $true }
        if ($PreLaunchTask) { $newC | Add-Member -NotePropertyName preLaunchTask -NotePropertyValue $PreLaunchTask }
        $compounds += $newC
    }
    $launch.compounds = $compounds
    $json = $launch | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($launchPath, $json, [System.Text.UTF8Encoding]::new($false))
    return $true
}

# ==============================================================================
# Comando: infra [nomes]
# ==============================================================================

function Invoke-InfraUp {
    param([string[]]$Targets)

    if (-not $Targets -or $Targets.Count -eq 0) { $Targets = $script:infraNames }

    foreach ($t in $Targets) {
        if ($t -notin $script:infraNames) {
            Write-ERR "'$t' nao e um servico de infra."
            Write-GRAY "Disponiveis: $($script:infraNames -join ', ')"
            return
        }
    }

    $isAll = ($Targets.Count -eq $script:infraNames.Count)
    $label = if ($isAll) { "todos ($($Targets.Count) containers)" } else { $Targets -join ", " }
    Write-Header "Subindo Infraestrutura: $label"

    Push-Location $repoRoot
    try {
        Write-Step 1 3 "docker compose up -d ..."
        Write-Host ""
        docker compose up -d @Targets
        Write-Host ""

        Write-Step 2 3 "Verificando saude dos containers..."

        if ("postgres" -in $Targets) {
            Write-Host "       postgres" -ForegroundColor White -NoNewline
            Write-Host " aguardando health check..." -ForegroundColor DarkGray -NoNewline
            $health = Wait-ComposeServiceHealthy -ServiceName "postgres" -TimeoutSeconds 30
            if ($health.Healthy) { Write-Host " healthy ($($health.ElapsedSeconds)s)" -ForegroundColor Green }
            else { Write-Host " timeout 30s" -ForegroundColor Yellow }
        }

        $docker = Get-DockerStatus
        foreach ($t in $Targets) {
            if ($t -eq "postgres") { continue }
            $st = $docker[$t]
            Write-Host "       $($t.PadRight(18))" -ForegroundColor White -NoNewline
            if ($st -and $st -match "Up") { Write-Host "UP" -ForegroundColor Green }
            elseif ($st) { Write-Host "$st" -ForegroundColor Yellow }
            else { Write-Host "???" -ForegroundColor Yellow }
        }

        Write-Host ""
        Write-Step 3 3 "Endpoints disponiveis:"
        Write-Host ""
        foreach ($t in $Targets) {
            $ep = $script:infraEndpoints[$t]
            Write-Host "       $($t.PadRight(18))" -ForegroundColor White -NoNewline
            Write-Host "$ep" -ForegroundColor Cyan
        }

        Write-Host ""
        Write-OK "Infraestrutura online!"
        Write-Host ""
        Write-TIP "Ver logs:     .\proj.ps1 logs <nome>"
        Write-TIP "VS Code:      Ctrl+Shift+P -> Tasks: Run Task -> logs: <nome>"
        Write-GRAY "Containers disponiveis: $($Targets -join ', ')"
    } finally { Pop-Location }
    Write-Footer
}

# ==============================================================================
# Comando: run <svcs...>
#
# 1 servico  -> roda dotnet watch no terminal atual (hot reload + logs)
# N servicos -> atualiza launch.json compound Debug: Selected + instrucoes F5
#
# NOTA: o CLI 'code --command' NAO funciona para disparar debug.
#       O VS Code nao expoe essa funcionalidade pelo CLI.
#       Para debug com breakpoints: Ctrl+Shift+D -> config -> F5.
# ==============================================================================

function Invoke-Run {
    param([string[]]$Names)

    if (-not $Names -or $Names.Count -eq 0) {
        Write-Header "Rodar Servicos"
        Write-Host "  Uso: .\proj.ps1 run <servico> [servico2 ...]" -ForegroundColor Yellow
        Write-Host "       .\proj.ps1 run -c <servico> [servico2 ...]  (via container)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Exemplos:" -ForegroundColor White
        Write-GRAY "    .\proj.ps1 run svc-auth                Local com hot reload"
        Write-GRAY "    .\proj.ps1 run svc-auth svc-catalog    Debug composto (local)"
        Write-GRAY "    .\proj.ps1 run -c svc-auth             Via container (Dockerfile)"
        Write-GRAY "    .\proj.ps1 run svc-orders              Deps (auth) sobem como container"
        Write-Host ""
        Write-TIP "Use '.\proj.ps1 list' para ver servicos disponiveis."
        Write-TIP "Dependencias configuradas em: infra/local/services.json (campo 'depends')"
        Write-Footer
        return
    }

    $isContainer = $script:ContainerMode

    # =====================================================
    # Container mode: build image + docker run
    # =====================================================
    if ($isContainer) {
        Write-Header "run -c $($Names -join ', ') (container mode)"

        # Step 1: Infra
        Write-Step 1 3 "Verificando infraestrutura Docker..."
        Push-Location $repoRoot
        try {
            if (Test-InfraRunning) {
                $docker = Get-DockerStatus
                $upCount = ($docker.Values | Where-Object { $_ -match "Up" }).Count
                Write-OK "Infra Docker rodando ($upCount containers UP)."
            } else {
                Write-WARN "Infra nao esta rodando. Subindo automaticamente..."
                Write-Host ""
                docker compose up -d @($script:infraNames)
                Write-Host ""
                Write-Host "       Aguardando PostgreSQL..." -ForegroundColor DarkGray -NoNewline
                $pgHealth = Wait-ComposeServiceHealthy -ServiceName "postgres" -TimeoutSeconds 25
                if ($pgHealth.Healthy) { Write-Host " healthy ($($pgHealth.ElapsedSeconds)s)" -ForegroundColor Green }
                else { Write-Host " timeout" -ForegroundColor Yellow }
                Write-OK "Infraestrutura online."
            }
        } finally { Pop-Location }

        # Step 2: Dependencias
        Write-Host ""
        Write-Step 2 3 "Resolvendo dependencias..."
        $deps = Resolve-AllDeps -ServiceNames $Names -Exclude $Names
        if ($deps.Count -gt 0) {
            Write-Host "       Dependencias: $($deps -join ', ')" -ForegroundColor DarkGray
            foreach ($dep in $deps) {
                $depCfg = Get-ServiceConfig -Name $dep
                if (Test-PortListening -Port $depCfg.port) {
                    Write-OK "$dep ja esta acessivel em :$($depCfg.port)"
                    continue
                }
                Invoke-ServiceContainerUp -Name $dep | Out-Null
            }
        } else {
            Write-GRAY "       Sem dependencias adicionais."
        }

        # Step 3: Start containers
        Write-Host ""
        Write-Step 3 3 "Subindo servicos como containers..."
        $anyOk = $false
        foreach ($name in $Names) {
            $cfg = Get-ServiceConfig -Name $name
            if (Test-PortListening -Port $cfg.port) {
                Write-WARN "$name : porta $($cfg.port) ja em uso. Pulando."
                continue
            }
            $ok = Invoke-ServiceContainerUp -Name $name
            if ($ok) { $anyOk = $true }
        }

        if ($anyOk) {
            Write-Host ""
            Write-OK "Servicos containerizados!"
            Write-Host ""
            foreach ($name in $Names) {
                $cfg = Get-ServiceConfig -Name $name
                if (Test-ServiceContainerRunning -Name $name) {
                    Write-Host "       $($name.PadRight(22)) " -ForegroundColor White -NoNewline
                    Write-Host "http://localhost:$($cfg.port)" -ForegroundColor Green
                }
            }
            Write-Host ""
            Write-TIP "Logs:    .\proj.ps1 logs $($Names[0])"
            Write-TIP "Status:  .\proj.ps1 status"
            Write-TIP "Parar:   .\proj.ps1 stop $($Names[0])"
        }
        Write-Footer
        return
    }

    # =====================================================
    # Local mode: hot reload + deps como container
    # =====================================================
    $totalSteps = 3
    if ($Names.Count -eq 1) {
        Write-Header "run $($Names[0]) (watch + hot reload)"
    } else {
        Write-Header "run $($Names -join ', ') (debug composto)"
    }

    # Step 1: Infra
    Write-Step 1 $totalSteps "Verificando infraestrutura Docker..."
    Push-Location $repoRoot
    try {
        if (Test-InfraRunning) {
            $docker = Get-DockerStatus
            $upCount = ($docker.Values | Where-Object { $_ -match "Up" }).Count
            Write-OK "Infra Docker rodando ($upCount containers UP)."
        } else {
            Write-WARN "Infra nao esta rodando. Subindo automaticamente..."
            Write-Host ""
            docker compose up -d @($script:infraNames)
            Write-Host ""
            Write-Host "       Aguardando PostgreSQL..." -ForegroundColor DarkGray -NoNewline
            $pgHealth = Wait-ComposeServiceHealthy -ServiceName "postgres" -TimeoutSeconds 25
            if ($pgHealth.Healthy) { Write-Host " healthy ($($pgHealth.ElapsedSeconds)s)" -ForegroundColor Green }
            else { Write-Host " timeout" -ForegroundColor Yellow }
            Write-OK "Infraestrutura online."
        }
    } finally { Pop-Location }

    # Dependencias: servicos nao listados que sao necessarios → container
    $deps = Resolve-AllDeps -ServiceNames $Names -Exclude $Names
    if ($deps.Count -gt 0) {
        Write-Host ""
        Write-Step 0 0 "Subindo dependencias como containers..."
        Write-Host "       Dependencias: $($deps -join ', ')" -ForegroundColor DarkGray
        foreach ($dep in $deps) {
            $depCfg = Get-ServiceConfig -Name $dep
            if (Test-PortListening -Port $depCfg.port) {
                Write-OK "$dep ja esta acessivel em :$($depCfg.port)"
                continue
            }
            Push-Location $repoRoot
            try {
                Invoke-ServiceContainerUp -Name $dep | Out-Null
            } finally { Pop-Location }
        }
    }

    # Step 2: Prereqs
    Write-Host ""
    Write-Step 2 $totalSteps "Preparando servicos..."
    $valid = @()
    foreach ($name in $Names) {
        $cfg = Get-ServiceConfig -Name $name
        if (-not (Test-ServiceReady -Name $name -Cfg $cfg)) {
            Write-WARN "$name : nao tem codigo implementado ainda. Pulando."
            continue
        }
        Write-Host "       [$name]" -ForegroundColor White
        $ok = Invoke-Prereqs -Name $name -Cfg $cfg
        if ($ok) { $valid += $name }
    }

    if ($valid.Count -eq 0) {
        Write-ERR "Nenhum servico pronto para rodar."
        Write-Footer
        return
    }

    # Step 3: Atualizar compounds + Launch
    Write-Host ""

    # Atualiza AMBOS os compounds (Debug: Selected e Attach: Selected)
    # antes de rodar, para que F5 ja esteja configurado corretamente
    $debugConfigs  = @($valid | ForEach-Object { "Debug: $_" })
    $attachConfigs = @($valid | ForEach-Object { "Attach: $_" })

    $okDebug  = Update-LaunchCompound -CompoundName "Debug: Selected"  -Configurations $debugConfigs  -PreLaunchTask "infra: ensure"
    $okAttach = Update-LaunchCompound -CompoundName "Attach: Selected" -Configurations $attachConfigs

    if ($okAttach) {
        Write-OK "Attach: Selected -> [$($valid -join ', ')]"
    }
    if ($okDebug) {
        Write-OK "Debug: Selected  -> [$($valid -join ', ')]"
    }

    if ($valid.Count -eq 1) {
        # === Single service: run dotnet watch no terminal atual ===
        $name = $valid[0]
        $cfg = Get-ServiceConfig -Name $name

        # Port conflict check
        if (Test-PortListening -Port $cfg.port) {
            Write-WARN "Porta $($cfg.port) ja esta em uso! $name pode ja estar rodando."
            Write-GRAY "Pare o processo existente (Ctrl+C) ou mude a porta em services.json."
            Write-Host ""
        }

        Write-Step 3 $totalSteps "Iniciando $name (dotnet watch)..."
        Write-Host ""
        Write-Host "       URL:   " -ForegroundColor DarkGray -NoNewline
        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor Green
        Write-Host "       Modo:  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($cfg.type) watch | hot reload ativo" -ForegroundColor White
        Write-Host ""
        Write-Host "  ============================================================" -ForegroundColor Magenta
        Write-Host "  ATTACH (conectar debug ao processo rodando):" -ForegroundColor Magenta
        Write-Host "    Ctrl+Shift+D -> 'Attach: $name' -> F5" -ForegroundColor White
        Write-Host "    Ou:  'Attach: Selected' -> F5 (config automatica)" -ForegroundColor White
        Write-Host ""
        Write-Host "  NOTA: ao salvar (hot reload), o watcher reinicia o processo." -ForegroundColor DarkGray
        Write-Host "  Pressione F5 novamente para re-attach apos o restart." -ForegroundColor DarkGray
        Write-Host "  ============================================================" -ForegroundColor Magenta
        Write-Host ""
        Write-GRAY "Para parar: Ctrl+C"
        Write-GRAY "Logs do servico aparecerao abaixo:"
        Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
        Write-Host ""

        $svcEnv = Build-ServiceEnv -Name $name -Cfg $cfg

        # Run in foreground
        $svcPath = Join-Path $repoRoot $cfg.path
        Push-Location $svcPath
        try {
            Invoke-WithScopedEnvironment -Vars $svcEnv -Action {
                switch ($cfg.type) {
                    "dotnet" { dotnet watch run --project $cfg.entryProject --no-restore }
                    "node"   { npm run dev }
                }
            }
        } finally { Pop-Location }

    } else {
        # === Multiple services: instrui para attach ===
        Write-Step 3 $totalSteps "$($valid.Count) servicos prontos."
        Write-Host ""
        foreach ($n in $valid) {
            $cc = Get-ServiceConfig -Name $n
            Write-Host "       $($n.PadRight(25))" -ForegroundColor White -NoNewline
            Write-Host "http://localhost:$($cc.port)" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "  ============================================================" -ForegroundColor Magenta
        Write-Host "  RODAR OS SERVICOS:" -ForegroundColor Magenta
        Write-Host "    Execute em terminais separados (ou VS Code tasks):" -ForegroundColor White
        foreach ($n in $valid) {
            Write-Host "      .\proj.ps1 run $n" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  OU VIA CONTAINER:" -ForegroundColor Magenta
        Write-Host "    .\proj.ps1 run -c $($valid -join ' ')" -ForegroundColor White
        Write-Host ""
        Write-Host "  ATTACH APOS RODAR:" -ForegroundColor Magenta
        Write-Host "    .\proj.ps1 attach               <- detecta automatico" -ForegroundColor White
        Write-Host "    Ctrl+Shift+D -> 'Attach: Selected' -> F5" -ForegroundColor White
        Write-Host "  ============================================================" -ForegroundColor Magenta
        Write-Footer
    }
}

# ==============================================================================
# Comando: attach [nomes]
#
# Detecta servicos rodando -> atualiza compound "Attach: Selected" -> F5
# ==============================================================================

function Invoke-Attach {
    param([string[]]$Names)

    Write-Header "Attach - Conectar Debug ao Processo em Execucao"

    $toAttach = @()

    if ($Names -and $Names.Count -gt 0) {
        # Nomes especificados explicitamente
        foreach ($name in $Names) {
            $cfg = Get-ServiceConfig -Name $name
            $ready = Test-ServiceReady -Name $name -Cfg $cfg
            if (-not $ready) {
                Write-WARN "$name : codigo nao implementado ainda."
                continue
            }
            if (Test-PortListening -Port $cfg.port) {
                $toAttach += $name
                Write-Host "       [RODANDO] $($name.PadRight(22)) " -ForegroundColor Green -NoNewline
                Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
            } else {
                Write-Host "       [PARADO]  $($name.PadRight(22)) " -ForegroundColor Yellow -NoNewline
                Write-Host":$($cfg.port)" -ForegroundColor DarkGray
            }
        }
    } else {
        # Auto-deteccao: varre todos os servicos com codigo implementado
        Write-Step 0 0 "Detectando servicos em execucao..."
        Write-Host ""
        foreach ($prop in $registry.services.PSObject.Properties) {
            $name = $prop.Name
            $cfg  = $prop.Value
            if (-not (Test-ServiceReady -Name $name -Cfg $cfg)) { continue }
            if (Test-PortListening -Port $cfg.port) {
                $toAttach += $name
                Write-Host "       [RODANDO] $($name.PadRight(22)) " -ForegroundColor Green -NoNewline
                Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
            }
        }
    }

    if ($toAttach.Count -eq 0) {
        Write-Host ""
        Write-Host "  Nenhum servico em execucao detectado." -ForegroundColor DarkGray
        Write-Host ""
        Write-TIP "Inicie um servico:  .\proj.ps1 run svc-auth"
        Write-Footer
        return
    }

    # Atualiza compound "Attach: Selected" com os servicos encontrados
    Write-Host ""
    $attachConfigs = @($toAttach | ForEach-Object { "Attach: $_" })
    $ok = Update-LaunchCompound -CompoundName "Attach: Selected" -Configurations $attachConfigs
    if ($ok) {
        Write-OK "Attach: Selected -> [$($toAttach -join ', ')]"
    }

    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Magenta
    Write-Host "  PROXIMO PASSO:" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "    1. Ctrl+Shift+D no VS Code" -ForegroundColor White
    Write-Host "    2. Selecione:  'Attach: Selected'" -ForegroundColor White
    Write-Host "    3. Pressione:  F5" -ForegroundColor White
    Write-Host ""
    if ($toAttach.Count -eq 1) {
        Write-Host "    Ou use o shortcut individual:" -ForegroundColor DarkGray
        Write-Host "    'Attach: $($toAttach[0])' -> F5" -ForegroundColor DarkGray
    } else {
        Write-Host "    Ou individualmente por servico:" -ForegroundColor DarkGray
        foreach ($n in $toAttach) {
            Write-Host "      'Attach: $n' -> F5" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  NOTA: ao salvar um arquivo, dotnet watch reinicia o processo." -ForegroundColor DarkGray
    Write-Host "  Breakpoints desconectam no restart - pressione F5 para re-attach." -ForegroundColor DarkGray
    Write-Host "  ============================================================" -ForegroundColor Magenta
    Write-Footer
}

# ==============================================================================
# Comando: list (inventario completo com status)
# ==============================================================================

function Invoke-List {
    Write-Header "Inventario Completo"

    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

    # --- Servicos ---
    Write-Section "Servicos de Aplicacao"
    Write-GRAY "Portas definidas em: infra/local/services.json"
    Write-Host ""

    foreach ($prop in $registry.services.PSObject.Properties) {
        $name = $prop.Name
        $cfg  = $prop.Value
        $ready = Test-ServiceReady -Name $name -Cfg $cfg
        $deps  = if ($cfg.depends -and $cfg.depends.Count -gt 0) { " deps:$($cfg.depends -join ',')" } else { "" }

        if (-not $ready) {
            Write-Host "  FUTURO    " -ForegroundColor DarkGray -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)$deps" -ForegroundColor DarkGray
            continue
        }

        $isContainer = $svcContainers.ContainsKey($name)
        $running = Test-PortListening -Port $cfg.port

        if ($isContainer) {
            Write-Host "  CONTAINER " -ForegroundColor Magenta -NoNewline
            Write-Host " $($name.PadRight(22)) " -ForegroundColor White -NoNewline
            Write-Host "$($cfg.type.PadRight(8)) " -ForegroundColor White -NoNewline
            Write-Host ":$($cfg.port)" -ForegroundColor Green
        } elseif ($running) {
            Write-Host "  LOCAL     " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(22)) " -ForegroundColor White -NoNewline
            Write-Host "$($cfg.type.PadRight(8)) " -ForegroundColor White -NoNewline
            Write-Host ":$($cfg.port)" -ForegroundColor Green
        } else {
            Write-Host "  PARADO    " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)$deps" -ForegroundColor White
        }
    }

    # --- Infra ---
    Write-Section "Infraestrutura Docker"

    foreach ($name in $script:infraNames) {
        $ep = $script:infraEndpoints[$name]
        $st = $docker[$name]

        if ($st -and $st -match "Up") {
            Write-Host "  UP        " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(18)) " -ForegroundColor White -NoNewline
            Write-Host "$ep" -ForegroundColor Cyan
        } elseif ($st) {
            Write-Host "  DOWN      " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(18)) $ep" -ForegroundColor DarkGray
        } else {
            Write-Host "  OFF       " -ForegroundColor DarkGray -NoNewline
            Write-Host " $($name.PadRight(18)) $ep" -ForegroundColor DarkGray
        }
    }

    Write-Footer
}

# ==============================================================================
# Comando: status [itens]
# Sem args  -> mostra SO o que esta rodando
# Com args  -> mostra saude dos itens especificos
# ==============================================================================

function Invoke-Status {
    param([string[]]$Targets)

    Write-Header "Status"
    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

    if ($Targets -and $Targets.Count -gt 0) {
        # --- Itens especificos ---
        foreach ($t in $Targets) {
            $type = Resolve-Target -Name $t

            switch ($type) {
                "infra" {
                    $st = $docker[$t]
                    $ep = $script:infraEndpoints[$t]
                    if ($st -and $st -match "Up") {
                        Write-Host "  [UP]        $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "$st" -ForegroundColor White
                        Write-Host "              $ep" -ForegroundColor DarkGray
                    } elseif ($st) {
                        Write-Host "  [DOWN]      $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
                        Write-Host "$st" -ForegroundColor White
                    } else {
                        Write-Host "  [OFF]       $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "container nao existe / nao criado" -ForegroundColor DarkGray
                    }
                }
                "service" {
                    $cfg = Get-ServiceConfig -Name $t
                    $ready = Test-ServiceReady -Name $t -Cfg $cfg
                    $isContainer = $svcContainers.ContainsKey($t)
                    $running = Test-PortListening -Port $cfg.port

                    if ($isContainer) {
                        Write-Host "  [CONTAINER] $($t.PadRight(18)) " -ForegroundColor Magenta -NoNewline
                        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
                        Write-Host "              $($svcContainers[$t])" -ForegroundColor DarkGray
                    } elseif ($running) {
                        Write-Host "  [LOCAL]     $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
                    } elseif (-not $ready) {
                        Write-Host "  [FUTURO]    $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "codigo nao implementado" -ForegroundColor DarkGray
                    } else {
                        Write-Host "  [PARADO]    $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
                        Write-Host ":$($cfg.port) (porta fechada)" -ForegroundColor DarkGray
                    }
                }
                default {
                    Write-ERR "'$t' nao reconhecido. Use nome de servico ou container de infra."
                    Write-GRAY "Servicos: $($registry.services.PSObject.Properties.Name -join ', ')"
                    Write-GRAY "Infra: $($script:infraNames -join ', ')"
                }
            }
        }
    } else {
        # --- Apenas o que esta rodando ---
        $anyRunning = $false

        # Docker infra
        $upContainers = @()
        foreach ($name in $script:infraNames) {
            $st = $docker[$name]
            if ($st -and $st -match "Up") { $upContainers += $name }
        }

        if ($upContainers.Count -gt 0) {
            Write-Section "Docker (rodando)"
            foreach ($name in $upContainers) {
                $st = $docker[$name]
                $ep = $script:infraEndpoints[$name]
                Write-Host "  [UP]        $($name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "$st" -ForegroundColor White
                Write-Host "              $ep" -ForegroundColor DarkGray
            }
            $anyRunning = $true
        }

        # Servicos em container
        if ($svcContainers.Count -gt 0) {
            Write-Section "Servicos em Container"
            foreach ($svcName in $svcContainers.Keys) {
                $svcCfg = ($registry.services.PSObject.Properties | Where-Object { $_.Name -eq $svcName }).Value
                $port = if ($svcCfg) { $svcCfg.port } else { '?' }
                Write-Host "  [CONTAINER] $($svcName.PadRight(18)) " -ForegroundColor Magenta -NoNewline
                Write-Host "http://localhost:$port" -ForegroundColor White
                Write-Host "              $($svcContainers[$svcName])" -ForegroundColor DarkGray
            }
            $anyRunning = $true
        }

        # Servicos locais
        $runningSvcs = @()
        foreach ($prop in $registry.services.PSObject.Properties) {
            $name = $prop.Name
            $cfg  = $prop.Value
            if ($svcContainers.ContainsKey($name)) { continue }
            if (-not (Test-ServiceReady -Name $name -Cfg $cfg)) { continue }
            if (Test-PortListening -Port $cfg.port) {
                $runningSvcs += @{ Name = $name; Port = $cfg.port }
            }
        }

        if ($runningSvcs.Count -gt 0) {
            Write-Section "Servicos Locais (rodando)"
            foreach ($svc in $runningSvcs) {
                Write-Host "  [LOCAL]     $($svc.Name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "http://localhost:$($svc.Port)" -ForegroundColor White
            }
            $anyRunning = $true
        }

        if (-not $anyRunning) {
            Write-Host "  Nenhum servico ou container esta rodando." -ForegroundColor DarkGray
            Write-Host ""
            Write-TIP "Suba a infra:     .\proj.ps1 infra"
            Write-TIP "Rode um servico:  .\proj.ps1 run svc-auth"
            Write-TIP "Rode via container: .\proj.ps1 run -c svc-auth"
        }
    }

    Write-Footer
}

# ==============================================================================
# Comando: logs [nomes]
# ==============================================================================

function Invoke-Logs {
    param([string[]]$Targets)

    Push-Location $repoRoot
    try {
        if (-not $Targets -or $Targets.Count -eq 0) {
            Write-Header "Logs Docker (infra)"
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-GRAY "Servicos em container: $($svcContainers.Keys -join ', ')"
                Write-GRAY "Use: .\proj.ps1 logs <nome-servico> para logs individuais"
                Write-Host ""
            }
            Write-GRAY "Ctrl+C para sair"
            Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
            Write-Host ""
            docker compose logs -f --tail 50
        } else {
            $infraTargets = @()
            $svcTargets = @()
            foreach ($t in $Targets) {
                if ($t -in $script:infraNames) { $infraTargets += $t }
                elseif ($registry.services.PSObject.Properties | Where-Object { $_.Name -eq $t }) { $svcTargets += $t }
                else {
                    Write-ERR "'$t' nao e um container de infra nem servico."
                    Write-GRAY "Infra: $($script:infraNames -join ', ')"
                    Write-GRAY "Servicos: $($registry.services.PSObject.Properties.Name -join ', ')"
                    return
                }
            }

            if ($svcTargets.Count -gt 0 -and $infraTargets.Count -gt 0) {
                Write-ERR "Nao e possivel misturar logs de infra e servicos em container."
                Write-GRAY "Execute em terminais separados."
                return
            }

            if ($svcTargets.Count -eq 1) {
                $containerName = Get-ServiceContainerName -Name $svcTargets[0]
                if (-not (Test-ServiceContainerRunning -Name $svcTargets[0])) {
                    Write-ERR "$($svcTargets[0]) nao esta rodando como container."
                    Write-TIP "Inicie com: .\proj.ps1 run -c $($svcTargets[0])"
                    return
                }
                Write-Header "Logs: $($svcTargets[0]) (container)"
                Write-GRAY "Ctrl+C para sair"
                Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
                Write-Host ""
                docker logs -f --tail 50 $containerName
            } elseif ($svcTargets.Count -gt 1) {
                Write-ERR "Logs de servicos em container suporta apenas um por vez."
                Write-GRAY "Use terminais separados: .\proj.ps1 logs $($svcTargets[0])"
                return
            } else {
                Write-Header "Logs: $($infraTargets -join ', ')"
                Write-GRAY "Ctrl+C para sair"
                Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
                Write-Host ""
                docker compose logs -f --tail 50 @infraTargets
            }
        }
    } finally { Pop-Location }
}

# ==============================================================================
# Comando: stop [nomes]
# ==============================================================================

function Invoke-Stop {
    param([string[]]$Targets)

    Write-Header "Parando Containers"
    Push-Location $repoRoot
    try {
        if ($Targets -and $Targets.Count -gt 0) {
            $infraStops = @()
            $svcStops = @()
            foreach ($t in $Targets) {
                $type = Resolve-Target -Name $t
                if ($type -eq "infra") { $infraStops += $t }
                elseif ($type -eq "service") { $svcStops += $t }
                else {
                    Write-ERR "'$t' nao reconhecido."
                    return
                }
            }

            if ($svcStops.Count -gt 0) {
                foreach ($svc in $svcStops) {
                    if (Test-ServiceContainerRunning -Name $svc) {
                        Write-Step 0 0 "Parando container: $svc..."
                        Stop-ServiceContainer -Name $svc
                        Write-OK "$svc parado."
                    } else {
                        Write-GRAY "$svc nao esta rodando como container."
                        Write-GRAY "Se esta rodando local, use Ctrl+C no terminal dele."
                    }
                }
            }

            if ($infraStops.Count -gt 0) {
                Write-Step 0 0 "Parando infra: $($infraStops -join ', ')..."
                docker compose stop @infraStops
                Write-Host ""
                Write-OK "Parados: $($infraStops -join ', ')"
            }
        } else {
            # Parar tudo: containers de servico + infra
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-Step 0 0 "Parando containers de servico..."
                foreach ($svc in $svcContainers.Keys) {
                    Stop-ServiceContainer -Name $svc
                }
                Write-OK "Servicos parados: $($svcContainers.Keys -join ', ')"
            }

            Write-Step 0 0 "Parando todos os containers de infra..."
            docker compose stop
            Write-Host ""
            Write-OK "Todos containers parados."
        }

        Write-Host ""
        Write-GRAY "Estado preservado. Dados do banco continuam intactos."
        Write-TIP "Religar:  .\proj.ps1 infra"
        Write-TIP "Remover:  .\proj.ps1 down"
    } finally { Pop-Location }
    Write-Footer
}

# ==============================================================================
# Comando: down [nomes]
# ==============================================================================

function Invoke-Down {
    param([string[]]$Targets)

    Write-Header "Removendo Containers"
    Push-Location $repoRoot
    try {
        if ($Targets -and $Targets.Count -gt 0) {
            $infraDowns = @()
            $svcDowns = @()
            foreach ($t in $Targets) {
                $type = Resolve-Target -Name $t
                if ($type -eq "infra") { $infraDowns += $t }
                elseif ($type -eq "service") { $svcDowns += $t }
                else {
                    Write-ERR "'$t' nao reconhecido."
                    return
                }
            }

            if ($svcDowns.Count -gt 0) {
                foreach ($svc in $svcDowns) {
                    $containerName = Get-ServiceContainerName -Name $svc
                    Write-Step 0 0 "Removendo container: $svc..."
                    docker rm -f $containerName 2>$null | Out-Null
                    Write-OK "$svc removido."
                }
            }

            if ($infraDowns.Count -gt 0) {
                Write-Step 0 0 "Parando e removendo infra: $($infraDowns -join ', ')..."
                docker compose stop @infraDowns 2>$null
                docker compose rm -f @infraDowns
                Write-Host ""
                Write-OK "Removidos: $($infraDowns -join ', ')"
            }
        } else {
            # Remover tudo: containers de servico + infra
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-Step 0 0 "Removendo containers de servico..."
                foreach ($svc in $svcContainers.Keys) {
                    $containerName = Get-ServiceContainerName -Name $svc
                    docker rm -f $containerName 2>$null | Out-Null
                }
                Write-OK "Servicos removidos: $($svcContainers.Keys -join ', ')"
            }

            Write-Step 0 0 "Removendo todos os containers de infra..."
            docker compose down --remove-orphans
            Write-Host ""
            Write-OK "Todos containers removidos."
        }

        Write-Host ""
        Write-GRAY "Volumes preservados (dados do banco continuam)."
        Write-TIP "Recriar:  .\proj.ps1 infra"
    } finally { Pop-Location }
    Write-Footer
}

# ==============================================================================
# Help
# ==============================================================================

function Show-Help {
    $line = "=" * 60
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "  FoodeApp | CLI de Desenvolvimento Local" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SERVICOS:" -ForegroundColor White
    Write-Host "    run    <svc...>    " -ForegroundColor Green -NoNewline
    Write-Host "Roda local com hot reload (dotnet watch / npm dev)" -ForegroundColor Gray
    Write-Host "    run -c <svc...>    " -ForegroundColor Green -NoNewline
    Write-Host "Roda via container Docker (Dockerfile do servico)" -ForegroundColor Gray
    Write-Host "    attach [svcs...]   " -ForegroundColor Green -NoNewline
    Write-Host "Conecta debug ao processo ja rodando (F5)" -ForegroundColor Gray
    Write-Host "    list               " -ForegroundColor Green -NoNewline
    Write-Host "Lista tudo com status e portas" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  INFRA DOCKER:" -ForegroundColor White
    Write-Host "    infra [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Sobe containers de infra (todos ou especificos)" -ForegroundColor Gray
    Write-Host "    logs  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Logs Docker (infra ou servico em container)" -ForegroundColor Gray
    Write-Host "    stop  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Para containers (infra e/ou servicos)" -ForegroundColor Gray
    Write-Host "    down  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Remove containers (infra e/ou servicos)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  DIAGNOSTICO:" -ForegroundColor White
    Write-Host "    status [itens]     " -ForegroundColor Green -NoNewline
    Write-Host "Saude do que esta rodando (ou itens especificos)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  FLUXO LOCAL (debug com hot reload):" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 run svc-auth        " -ForegroundColor White -NoNewline
    Write-Host "Sobe infra + hot reload no terminal" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 attach              " -ForegroundColor White -NoNewline
    Write-Host "Detecta rodando e configura F5" -ForegroundColor DarkGray
    Write-Host "    3. Ctrl+Shift+D -> Attach: Selected -> F5" -ForegroundColor White -NoNewline
    Write-Host "  <- breakpoints!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  FLUXO CONTAINER:" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 run -c svc-auth     " -ForegroundColor White -NoNewline
    Write-Host "Build Dockerfile + docker run" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 logs svc-auth       " -ForegroundColor White -NoNewline
    Write-Host "Logs do container do servico" -ForegroundColor DarkGray
    Write-Host "    3. .\proj.ps1 stop svc-auth       " -ForegroundColor White -NoNewline
    Write-Host "Para o container do servico" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  DEPENDENCIAS:" -ForegroundColor DarkYellow
    Write-Host "    .\proj.ps1 run svc-orders         " -ForegroundColor White -NoNewline
    Write-Host "Deps (svc-auth) sobem como container" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run svc-orders svc-auth " -ForegroundColor White -NoNewline
    Write-Host "Ambos local, sem container extra" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  EXEMPLOS:" -ForegroundColor White
    Write-Host "    .\proj.ps1 run svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run -c svc-auth svc-catalog" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 infra postgres grafana" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 logs svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 stop svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 status svc-auth postgres" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  REFERENCIA:" -ForegroundColor DarkGray
    Write-Host "    Portas/Deps: " -ForegroundColor DarkGray -NoNewline
    Write-Host "infra/local/services.json" -ForegroundColor Cyan
    Write-Host "    Debug:       " -ForegroundColor DarkGray -NoNewline
    Write-Host "Ctrl+Shift+D -> selecione config -> F5" -ForegroundColor Cyan
    Write-Host "    Logs:        " -ForegroundColor DarkGray -NoNewline
   Write-Host "  NOTA: ao salvar um arquivo, dotnet watch reinicia o processo." -ForegroundColor DarkGray
    Write-Host "  Breakpoints desconectam no restart - pressione F5 para re-attach." -ForegroundColor DarkGray
    Write-Host "  ============================================================" -ForegroundColor Magenta
    Write-Footer
}

# ==============================================================================
# Comando: list (inventario completo com status)
# ==============================================================================

function Invoke-List {
    Write-Header "Inventario Completo"

    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

    # --- Servicos ---
    Write-Section "Servicos de Aplicacao"
    Write-GRAY "Portas definidas em: infra/local/services.json"
    Write-Host ""

    foreach ($prop in $registry.services.PSObject.Properties) {
        $name = $prop.Name
        $cfg  = $prop.Value
        $ready = Test-ServiceReady -Name $name -Cfg $cfg
        $deps  = if ($cfg.depends -and $cfg.depends.Count -gt 0) { " deps:$($cfg.depends -join ',')" } else { "" }

        if (-not $ready) {
            Write-Host "  FUTURO    " -ForegroundColor DarkGray -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)$deps" -ForegroundColor DarkGray
            continue
        }

        $isContainer = $svcContainers.ContainsKey($name)
        $running = Test-PortListening -Port $cfg.port

        if ($isContainer) {
            Write-Host "  CONTAINER " -ForegroundColor Magenta -NoNewline
            Write-Host " $($name.PadRight(22)) " -ForegroundColor White -NoNewline
            Write-Host "$($cfg.type.PadRight(8)) " -ForegroundColor White -NoNewline
            Write-Host ":$($cfg.port)" -ForegroundColor Green
        } elseif ($running) {
            Write-Host "  LOCAL     " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(22)) " -ForegroundColor White -NoNewline
            Write-Host "$($cfg.type.PadRight(8)) " -ForegroundColor White -NoNewline
            Write-Host ":$($cfg.port)" -ForegroundColor Green
        } else {
            Write-Host "  PARADO    " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)$deps" -ForegroundColor White
        }
    }

    # --- Infra ---
    Write-Section "Infraestrutura Docker"

    foreach ($name in $script:infraNames) {
        $ep = $script:infraEndpoints[$name]
        $st = $docker[$name]

        if ($st -and $st -match "Up") {
            Write-Host "  UP        " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(18)) " -ForegroundColor White -NoNewline
            Write-Host "$ep" -ForegroundColor Cyan
        } elseif ($st) {
            Write-Host "  DOWN      " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(18)) $ep" -ForegroundColor DarkGray
        } else {
            Write-Host "  OFF       " -ForegroundColor DarkGray -NoNewline
            Write-Host " $($name.PadRight(18)) $ep" -ForegroundColor DarkGray
        }
    }

    Write-Footer
}

# ==============================================================================
# Comando: status [itens]
# Sem args  -> mostra SO o que esta rodando
# Com args  -> mostra saude dos itens especificos
# ==============================================================================

function Invoke-Status {
    param([string[]]$Targets)

    Write-Header "Status"
    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

    if ($Targets -and $Targets.Count -gt 0) {
        # --- Itens especificos ---
        foreach ($t in $Targets) {
            $type = Resolve-Target -Name $t

            switch ($type) {
                "infra" {
                    $st = $docker[$t]
                    $ep = $script:infraEndpoints[$t]
                    if ($st -and $st -match "Up") {
                        Write-Host "  [UP]        $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "$st" -ForegroundColor White
                        Write-Host "              $ep" -ForegroundColor DarkGray
                    } elseif ($st) {
                        Write-Host "  [DOWN]      $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
                        Write-Host "$st" -ForegroundColor White
                    } else {
                        Write-Host "  [OFF]       $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "container nao existe / nao criado" -ForegroundColor DarkGray
                    }
                }
                "service" {
                    $cfg = Get-ServiceConfig -Name $t
                    $ready = Test-ServiceReady -Name $t -Cfg $cfg
                    $isContainer = $svcContainers.ContainsKey($t)
                    $running = Test-PortListening -Port $cfg.port

                    if ($isContainer) {
                        Write-Host "  [CONTAINER] $($t.PadRight(18)) " -ForegroundColor Magenta -NoNewline
                        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
                        Write-Host "              $($svcContainers[$t])" -ForegroundColor DarkGray
                    } elseif ($running) {
                        Write-Host "  [LOCAL]     $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
                    } elseif (-not $ready) {
                        Write-Host "  [FUTURO]    $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "codigo nao implementado" -ForegroundColor DarkGray
                    } else {
                        Write-Host "  [PARADO]    $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
                        Write-Host ":$($cfg.port) (porta fechada)" -ForegroundColor DarkGray
                    }
                }
                default {
                    Write-ERR "'$t' nao reconhecido. Use nome de servico ou container de infra."
                    Write-GRAY "Servicos: $($registry.services.PSObject.Properties.Name -join ', ')"
                    Write-GRAY "Infra: $($script:infraNames -join ', ')"
                }
            }
        }
    } else {
        # --- Apenas o que esta rodando ---
        $anyRunning = $false

        # Docker infra
        $upContainers = @()
        foreach ($name in $script:infraNames) {
            $st = $docker[$name]
            if ($st -and $st -match "Up") { $upContainers += $name }
        }

        if ($upContainers.Count -gt 0) {
            Write-Section "Docker (rodando)"
            foreach ($name in $upContainers) {
                $st = $docker[$name]
                $ep = $script:infraEndpoints[$name]
                Write-Host "  [UP]        $($name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "$st" -ForegroundColor White
                Write-Host "              $ep" -ForegroundColor DarkGray
            }
            $anyRunning = $true
        }

        # Servicos em container
        if ($svcContainers.Count -gt 0) {
            Write-Section "Servicos em Container"
            foreach ($svcName in $svcContainers.Keys) {
                $svcCfg = ($registry.services.PSObject.Properties | Where-Object { $_.Name -eq $svcName }).Value
                $port = if ($svcCfg) { $svcCfg.port } else { '?' }
                Write-Host "  [CONTAINER] $($svcName.PadRight(18)) " -ForegroundColor Magenta -NoNewline
                Write-Host "http://localhost:$port" -ForegroundColor White
                Write-Host "              $($svcContainers[$svcName])" -ForegroundColor DarkGray
            }
            $anyRunning = $true
        }

        # Servicos locais
        $runningSvcs = @()
        foreach ($prop in $registry.services.PSObject.Properties) {
            $name = $prop.Name
            $cfg  = $prop.Value
            if ($svcContainers.ContainsKey($name)) { continue }
            if (-not (Test-ServiceReady -Name $name -Cfg $cfg)) { continue }
            if (Test-PortListening -Port $cfg.port) {
                $runningSvcs += @{ Name = $name; Port = $cfg.port }
            }
        }

        if ($runningSvcs.Count -gt 0) {
            Write-Section "Servicos Locais (rodando)"
            foreach ($svc in $runningSvcs) {
                Write-Host "  [LOCAL]     $($svc.Name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "http://localhost:$($svc.Port)" -ForegroundColor White
            }
            $anyRunning = $true
        }

        if (-not $anyRunning) {
            Write-Host "  Nenhum servico ou container esta rodando." -ForegroundColor DarkGray
            Write-Host ""
            Write-TIP "Suba a infra:     .\proj.ps1 infra"
            Write-TIP "Rode um servico:  .\proj.ps1 run svc-auth"
            Write-TIP "Rode via container: .\proj.ps1 run -c svc-auth"
        }
    }

    Write-Footer
}

# ==============================================================================
# Comando: logs [nomes]
# ==============================================================================

function Invoke-Logs {
    param([string[]]$Targets)

    Push-Location $repoRoot
    try {
        if (-not $Targets -or $Targets.Count -eq 0) {
            Write-Header "Logs Docker (infra)"
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-GRAY "Servicos em container: $($svcContainers.Keys -join ', ')"
                Write-GRAY "Use: .\proj.ps1 logs <nome-servico> para logs individuais"
                Write-Host ""
            }
            Write-GRAY "Ctrl+C para sair"
            Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
            Write-Host ""
            docker compose logs -f --tail 50
        } else {
            $infraTargets = @()
            $svcTargets = @()
            foreach ($t in $Targets) {
                if ($t -in $script:infraNames) { $infraTargets += $t }
                elseif ($registry.services.PSObject.Properties | Where-Object { $_.Name -eq $t }) { $svcTargets += $t }
                else {
                    Write-ERR "'$t' nao e um container de infra nem servico."
                    Write-GRAY "Infra: $($script:infraNames -join ', ')"
                    Write-GRAY "Servicos: $($registry.services.PSObject.Properties.Name -join ', ')"
                    return
                }
            }

            if ($svcTargets.Count -gt 0 -and $infraTargets.Count -gt 0) {
                Write-ERR "Nao e possivel misturar logs de infra e servicos em container."
                Write-GRAY "Execute em terminais separados."
                return
            }

            if ($svcTargets.Count -eq 1) {
                $containerName = Get-ServiceContainerName -Name $svcTargets[0]
                if (-not (Test-ServiceContainerRunning -Name $svcTargets[0])) {
                    Write-ERR "$($svcTargets[0]) nao esta rodando como container."
                    Write-TIP "Inicie com: .\proj.ps1 run -c $($svcTargets[0])"
                    return
                }
                Write-Header "Logs: $($svcTargets[0]) (container)"
                Write-GRAY "Ctrl+C para sair"
                Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
                Write-Host ""
                docker logs -f --tail 50 $containerName
            } elseif ($svcTargets.Count -gt 1) {
                Write-ERR "Logs de servicos em container suporta apenas um por vez."
                Write-GRAY "Use terminais separados: .\proj.ps1 logs $($svcTargets[0])"
                return
            } else {
                Write-Header "Logs: $($infraTargets -join ', ')"
                Write-GRAY "Ctrl+C para sair"
                Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
                Write-Host ""
                docker compose logs -f --tail 50 @infraTargets
            }
        }
    } finally { Pop-Location }
}

# ==============================================================================
# Comando: stop [nomes]
# ==============================================================================

function Invoke-Stop {
    param([string[]]$Targets)

    Write-Header "Parando Containers"
    Push-Location $repoRoot
    try {
        if ($Targets -and $Targets.Count -gt 0) {
            $infraStops = @()
            $svcStops = @()
            foreach ($t in $Targets) {
                $type = Resolve-Target -Name $t
                if ($type -eq "infra") { $infraStops += $t }
                elseif ($type -eq "service") { $svcStops += $t }
                else {
                    Write-ERR "'$t' nao reconhecido."
                    return
                }
            }

            if ($svcStops.Count -gt 0) {
                foreach ($svc in $svcStops) {
                    if (Test-ServiceContainerRunning -Name $svc) {
                        Write-Step 0 0 "Parando container: $svc..."
                        Stop-ServiceContainer -Name $svc
                        Write-OK "$svc parado."
                    } else {
                        Write-GRAY "$svc nao esta rodando como container."
                        Write-GRAY "Se esta rodando local, use Ctrl+C no terminal dele."
                    }
                }
            }

            if ($infraStops.Count -gt 0) {
                Write-Step 0 0 "Parando infra: $($infraStops -join ', ')..."
                docker compose stop @infraStops
                Write-Host ""
                Write-OK "Parados: $($infraStops -join ', ')"
            }
        } else {
            # Parar tudo: containers de servico + infra
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-Step 0 0 "Parando containers de servico..."
                foreach ($svc in $svcContainers.Keys) {
                    Stop-ServiceContainer -Name $svc
                }
                Write-OK "Servicos parados: $($svcContainers.Keys -join ', ')"
            }

            Write-Step 0 0 "Parando todos os containers de infra..."
            docker compose stop
            Write-Host ""
            Write-OK "Todos containers parados."
        }

        Write-Host ""
        Write-GRAY "Estado preservado. Dados do banco continuam intactos."
        Write-TIP "Religar:  .\proj.ps1 infra"
        Write-TIP "Remover:  .\proj.ps1 down"
    } finally { Pop-Location }
    Write-Footer
}

# ==============================================================================
# Comando: down [nomes]
# ==============================================================================

function Invoke-Down {
    param([string[]]$Targets)

    Write-Header "Removendo Containers"
    Push-Location $repoRoot
    try {
        if ($Targets -and $Targets.Count -gt 0) {
            $infraDowns = @()
            $svcDowns = @()
            foreach ($t in $Targets) {
                $type = Resolve-Target -Name $t
                if ($type -eq "infra") { $infraDowns += $t }
                elseif ($type -eq "service") { $svcDowns += $t }
                else {
                    Write-ERR "'$t' nao reconhecido."
                    return
                }
            }

            if ($svcDowns.Count -gt 0) {
                foreach ($svc in $svcDowns) {
                    $containerName = Get-ServiceContainerName -Name $svc
                    Write-Step 0 0 "Removendo container: $svc..."
                    docker rm -f $containerName 2>$null | Out-Null
                    Write-OK "$svc removido."
                }
            }

            if ($infraDowns.Count -gt 0) {
                Write-Step 0 0 "Parando e removendo infra: $($infraDowns -join ', ')..."
                docker compose stop @infraDowns 2>$null
                docker compose rm -f @infraDowns
                Write-Host ""
                Write-OK "Removidos: $($infraDowns -join ', ')"
            }
        } else {
            # Remover tudo: containers de servico + infra
            $svcContainers = Get-ServiceContainersStatus
            if ($svcContainers.Count -gt 0) {
                Write-Step 0 0 "Removendo containers de servico..."
                foreach ($svc in $svcContainers.Keys) {
                    $containerName = Get-ServiceContainerName -Name $svc
                    docker rm -f $containerName 2>$null | Out-Null
                }
                Write-OK "Servicos removidos: $($svcContainers.Keys -join ', ')"
            }

            Write-Step 0 0 "Removendo todos os containers de infra..."
            docker compose down --remove-orphans
            Write-Host ""
            Write-OK "Todos containers removidos."
        }

        Write-Host ""
        Write-GRAY "Volumes preservados (dados do banco continuam)."
        Write-TIP "Recriar:  .\proj.ps1 infra"
    } finally { Pop-Location }
    Write-Footer
}

# ==============================================================================
# Help
# ==============================================================================

function Show-Help {
    $line = "=" * 60
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "  FoodeApp | CLI de Desenvolvimento Local" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  SERVICOS:" -ForegroundColor White
    Write-Host "    run    <svc...>    " -ForegroundColor Green -NoNewline
    Write-Host "Roda local com hot reload (dotnet watch / npm dev)" -ForegroundColor Gray
    Write-Host "    run -c <svc...>    " -ForegroundColor Green -NoNewline
    Write-Host "Roda via container Docker (Dockerfile do servico)" -ForegroundColor Gray
    Write-Host "    attach [svcs...]   " -ForegroundColor Green -NoNewline
    Write-Host "Conecta debug ao processo ja rodando (F5)" -ForegroundColor Gray
    Write-Host "    list               " -ForegroundColor Green -NoNewline
    Write-Host "Lista tudo com status e portas" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  INFRA DOCKER:" -ForegroundColor White
    Write-Host "    infra [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Sobe containers de infra (todos ou especificos)" -ForegroundColor Gray
    Write-Host "    logs  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Logs Docker (infra ou servico em container)" -ForegroundColor Gray
    Write-Host "    stop  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Para containers (infra e/ou servicos)" -ForegroundColor Gray
    Write-Host "    down  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Remove containers (infra e/ou servicos)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  DIAGNOSTICO:" -ForegroundColor White
    Write-Host "    status [itens]     " -ForegroundColor Green -NoNewline
    Write-Host "Saude do que esta rodando (ou itens especificos)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  FLUXO LOCAL (debug com hot reload):" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 run svc-auth        " -ForegroundColor White -NoNewline
    Write-Host "Sobe infra + hot reload no terminal" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 attach              " -ForegroundColor White -NoNewline
    Write-Host "Detecta rodando e configura F5" -ForegroundColor DarkGray
    Write-Host "    3. Ctrl+Shift+D -> Attach: Selected -> F5" -ForegroundColor White -NoNewline
    Write-Host "  <- breakpoints!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  FLUXO CONTAINER:" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 run -c svc-auth     " -ForegroundColor White -NoNewline
    Write-Host "Build Dockerfile + docker run" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 logs svc-auth       " -ForegroundColor White -NoNewline
    Write-Host "Logs do container do servico" -ForegroundColor DarkGray
    Write-Host "    3. .\proj.ps1 stop svc-auth       " -ForegroundColor White -NoNewline
    Write-Host "Para o container do servico" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  DEPENDENCIAS:" -ForegroundColor DarkYellow
    Write-Host "    .\proj.ps1 run svc-orders         " -ForegroundColor White -NoNewline
    Write-Host "Deps (svc-auth) sobem como container" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run svc-orders svc-auth " -ForegroundColor White -NoNewline
    Write-Host "Ambos local, sem container extra" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  EXEMPLOS:" -ForegroundColor White
    Write-Host "    .\proj.ps1 run svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run -c svc-auth svc-catalog" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 infra postgres grafana" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 logs svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 stop svc-auth" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 status svc-auth postgres" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  REFERENCIA:" -ForegroundColor DarkGray
    Write-Host "    Portas/Deps: " -ForegroundColor DarkGray -NoNewline
    Write-Host "infra/local/services.json" -ForegroundColor Cyan
    Write-Host "    Debug:       " -ForegroundColor DarkGray -NoNewline
    Write-Host "Ctrl+Shift+D -> selecione config -> F5" -ForegroundColor Cyan
    Write-Host "    Logs:        " -ForegroundColor DarkGray -NoNewline
    Write-Host "Ctrl+Shift+P -> Tasks: Run Task -> logs: <nome>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
}

# ==============================================================================
# Main
# ==============================================================================

if (-not $Command) {
    Show-Help
    exit 0
}

switch ($Command.ToLower()) {
    "run"    { Assert-RequiredEnvVars; Invoke-Run      -Names   $Services }
    "attach" { Invoke-Attach  -Names   $Services }
    "list"   { Invoke-List }
    "status" { Invoke-Status   -Targets $Services }
    "infra"  { Assert-RequiredEnvVars; Invoke-InfraUp  -Targets $Services }
    "logs"   { Invoke-Logs     -Targets $Services }
    "stop"   { Invoke-Stop     -Targets $Services }
    "down"   { Invoke-Down     -Targets $Services }
    default  {
        Write-Host ""
        Write-Host "  [ERRO] Comando desconhecido: '$Command'" -ForegroundColor Red
        Write-Host "  Comandos: run | attach | list | status | infra | logs | stop | down" -ForegroundColor Yellow
        Write-Host "  Execute sem parametros para ver ajuda completa." -ForegroundColor DarkGray
        Write-Host ""
    }
}
