#!/usr/bin/env pwsh
# ==============================================================================
# proj.ps1 - FoodeApp | CLI de Desenvolvimento Local
#
# COMANDOS:
#   run    <svcs...>   Roda servico com hot reload (dotnet watch) + dicas debug
#   list               Lista tudo com portas e status (rodando/parado/futuro)
#   status [itens]     Saude de itens especificos ou do que esta rodando
#   infra  [nomes]     Sobe infra Docker (todos ou especificos)
#   logs   [nomes]     Logs Docker no terminal atual
#   stop   [nomes]     Para containers (preserva estado)
#   down   [nomes]     Remove containers
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

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

$script:infraNames = @(
    "postgres", "otel-collector", "prometheus",
    "tempo", "loki", "promtail", "grafana"
)

$script:infraEndpoints = [ordered]@{
    "postgres"       = "localhost:5432"
    "otel-collector" = "localhost:4317 (gRPC) | :4318 (HTTP) | :13133 (health)"
    "prometheus"     = "http://localhost:9090"
    "tempo"          = "http://localhost:3200"
    "loki"           = "http://localhost:3100"
    "promtail"       = "(agent interno, sem porta exposta)"
    "grafana"        = "http://localhost:3000"
}

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
            $healthy = $false
            for ($i = 0; $i -lt 30; $i++) {
                $h = docker inspect --format='{{.State.Health.Status}}' foodeapp-postgres-auth 2>$null
                if ($h -eq "healthy") { $healthy = $true; break }
                Start-Sleep -Seconds 1
            }
            if ($healthy) { Write-Host " healthy (${i}s)" -ForegroundColor Green }
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
        Write-Host ""
        Write-Host "  Exemplos:" -ForegroundColor White
        Write-GRAY "    .\proj.ps1 run svc-auth                Hot reload + logs"
        Write-GRAY "    .\proj.ps1 run svc-auth svc-catalog    Configura debug composto"
        Write-Host ""
        Write-TIP "Use '.\proj.ps1 list' para ver servicos disponiveis."
        Write-Footer
        return
    }

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
            $pgOk = $false
            for ($i = 0; $i -lt 25; $i++) {
                $h = docker inspect --format='{{.State.Health.Status}}' foodeapp-postgres-auth 2>$null
                if ($h -eq "healthy") { $pgOk = $true; break }
                Start-Sleep -Seconds 1
            }
            if ($pgOk) { Write-Host " healthy (${i}s)" -ForegroundColor Green }
            else { Write-Host " timeout" -ForegroundColor Yellow }
            Write-OK "Infraestrutura online."
        }
    } finally { Pop-Location }

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

        # Set env vars
        if ($cfg.env) {
            $cfg.env.PSObject.Properties | ForEach-Object {
                [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value, "Process")
            }
        }

        # Run in foreground
        $svcPath = Join-Path $repoRoot $cfg.path
        Push-Location $svcPath
        try {
            switch ($cfg.type) {
                "dotnet" { dotnet watch run --project $cfg.entryProject --no-restore }
                "node"   { npm run dev }
            }
        } finally { Pop-Location }

    } else {
        # === Multiple services: instrui para attach ===
        Write-Step 3 $totalSteps "$($valid.Count) servicos prontos."
        Write-Host ""
        foreach ($n in $valid) {
            $c = Get-ServiceConfig -Name $n
            Write-Host "       $($n.PadRight(25))" -ForegroundColor White -NoNewline
            Write-Host "http://localhost:$($c.port)" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "  ============================================================" -ForegroundColor Magenta
        Write-Host "  RODAR OS SERVICOS:" -ForegroundColor Magenta
        Write-Host "    Execute em terminais separados (ou VS Code tasks):" -ForegroundColor White
        foreach ($n in $valid) {
            $c = Get-ServiceConfig -Name $n
            Write-Host "      .\_proj.ps1_ run $n" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  ATTACH APOS RODAR:" -ForegroundColor Magenta
        Write-Host "    .\.proj.ps1 attach               <- detecta automatico" -ForegroundColor White
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

    # --- Servicos ---
    Write-Section "Servicos de Aplicacao"
    Write-GRAY "Portas definidas em: infra/local/services.json"
    Write-Host ""

    foreach ($prop in $registry.services.PSObject.Properties) {
        $name = $prop.Name
        $cfg  = $prop.Value
        $ready = Test-ServiceReady -Name $name -Cfg $cfg

        if (-not $ready) {
            Write-Host "  FUTURO  " -ForegroundColor DarkGray -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)" -ForegroundColor DarkGray
            continue
        }

        $running = Test-PortListening -Port $cfg.port
        if ($running) {
            Write-Host "  RODANDO " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(22)) " -ForegroundColor White -NoNewline
            Write-Host "$($cfg.type.PadRight(8)) " -ForegroundColor White -NoNewline
            Write-Host ":$($cfg.port)" -ForegroundColor Green
        } else {
            Write-Host "  PARADO  " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(22)) $($cfg.type.PadRight(8)) :$($cfg.port)" -ForegroundColor White
        }
    }

    # --- Infra ---
    Write-Section "Infraestrutura Docker"

    foreach ($name in $script:infraNames) {
        $ep = $script:infraEndpoints[$name]
        $st = $docker[$name]

        if ($st -and $st -match "Up") {
            Write-Host "  UP      " -ForegroundColor Green -NoNewline
            Write-Host " $($name.PadRight(18)) " -ForegroundColor White -NoNewline
            Write-Host "$ep" -ForegroundColor Cyan
        } elseif ($st) {
            Write-Host "  DOWN    " -ForegroundColor Yellow -NoNewline
            Write-Host " $($name.PadRight(18)) $ep" -ForegroundColor DarkGray
        } else {
            Write-Host "  OFF     " -ForegroundColor DarkGray -NoNewline
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

    if ($Targets -and $Targets.Count -gt 0) {
        # --- Itens especificos ---
        foreach ($t in $Targets) {
            $type = Resolve-Target -Name $t

            switch ($type) {
                "infra" {
                    $st = $docker[$t]
                    $ep = $script:infraEndpoints[$t]
                    if ($st -and $st -match "Up") {
                        Write-Host "  [UP]      $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "$st" -ForegroundColor White
                        Write-Host "            $ep" -ForegroundColor DarkGray
                    } elseif ($st) {
                        Write-Host "  [DOWN]    $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
                        Write-Host "$st" -ForegroundColor White
                    } else {
                        Write-Host "  [OFF]     $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "container nao existe / nao criado" -ForegroundColor DarkGray
                    }
                }
                "service" {
                    $cfg = Get-ServiceConfig -Name $t
                    $ready = Test-ServiceReady -Name $t -Cfg $cfg
                    if (-not $ready) {
                        Write-Host "  [FUTURO]  $($t.PadRight(18)) " -ForegroundColor DarkGray -NoNewline
                        Write-Host "codigo nao implementado" -ForegroundColor DarkGray
                        continue
                    }
                    $running = Test-PortListening -Port $cfg.port
                    if ($running) {
                        Write-Host "  [RODANDO] $($t.PadRight(18)) " -ForegroundColor Green -NoNewline
                        Write-Host "http://localhost:$($cfg.port)" -ForegroundColor White
                    } else {
                        Write-Host "  [PARADO]  $($t.PadRight(18)) " -ForegroundColor Yellow -NoNewline
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

        # Docker
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
                Write-Host "  [UP]      $($name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "$st" -ForegroundColor White
                Write-Host "            $ep" -ForegroundColor DarkGray
            }
            $anyRunning = $true
        }

        # Servicos de aplicacao
        $runningSvcs = @()
        foreach ($prop in $registry.services.PSObject.Properties) {
            $name = $prop.Name
            $cfg  = $prop.Value
            if (-not (Test-ServiceReady -Name $name -Cfg $cfg)) { continue }
            if (Test-PortListening -Port $cfg.port) {
                $runningSvcs += @{ Name = $name; Port = $cfg.port }
            }
        }

        if ($runningSvcs.Count -gt 0) {
            Write-Section "Servicos de Aplicacao (rodando)"
            foreach ($svc in $runningSvcs) {
                Write-Host "  [RODANDO] $($svc.Name.PadRight(18)) " -ForegroundColor Green -NoNewline
                Write-Host "http://localhost:$($svc.Port)" -ForegroundColor White
            }
            $anyRunning = $true
        }

        if (-not $anyRunning) {
            Write-Host "  Nenhum servico ou container esta rodando." -ForegroundColor DarkGray
            Write-Host ""
            Write-TIP "Suba a infra:     .\proj.ps1 infra"
            Write-TIP "Rode um servico:  .\proj.ps1 run svc-auth"
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
            Write-Header "Logs Docker (todos os containers)"
            Write-GRAY "Ctrl+C para sair"
            Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
            Write-Host ""
            docker compose logs -f --tail 50
        } else {
            foreach ($t in $Targets) {
                if ($t -notin $script:infraNames) {
                    Write-ERR "'$t' nao e um container de infra."
                    Write-GRAY "Disponiveis: $($script:infraNames -join ', ')"
                    return
                }
            }
            Write-Header "Logs: $($Targets -join ', ')"
            Write-GRAY "Ctrl+C para sair"
            Write-Host "  $("-" * 60)" -ForegroundColor DarkGray
            Write-Host ""
            docker compose logs -f --tail 50 @Targets
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
            foreach ($t in $Targets) {
                if ($t -notin $script:infraNames) {
                    Write-ERR "'$t' nao e um container de infra."
                    Write-GRAY "Disponiveis: $($script:infraNames -join ', ')"
                    Write-GRAY "Para parar um servico de aplicacao, use Ctrl+C no terminal dele."
                    return
                }
            }
            Write-Step 0 0 "Parando: $($Targets -join ', ')..."
            docker compose stop @Targets
            Write-Host ""
            Write-OK "Parados: $($Targets -join ', ')"
        } else {
            Write-Step 0 0 "Parando todos os containers..."
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
            foreach ($t in $Targets) {
                if ($t -notin $script:infraNames) {
                    Write-ERR "'$t' nao e um container de infra."
                    Write-GRAY "Disponiveis: $($script:infraNames -join ', ')"
                    return
                }
            }
            Write-Step 0 0 "Parando e removendo: $($Targets -join ', ')..."
            docker compose stop @Targets 2>$null
            docker compose rm -f @Targets
            Write-Host ""
            Write-OK "Removidos: $($Targets -join ', ')"
        } else {
            Write-Step 0 0 "Removendo todos os containers..."
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
    Write-Host "Roda com hot reload (dotnet watch / npm dev)" -ForegroundColor Gray
    Write-Host "    attach [svcs...]   " -ForegroundColor Green -NoNewline
    Write-Host "Conecta debug ao processo ja rodando (F5)" -ForegroundColor Gray
    Write-Host "    list               " -ForegroundColor Green -NoNewline
    Write-Host "Lista tudo com status e portas" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  INFRA DOCKER:" -ForegroundColor White
    Write-Host "    infra [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Sobe containers (todos ou especificos)" -ForegroundColor Gray
    Write-Host "    logs  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Logs Docker no terminal" -ForegroundColor Gray
    Write-Host "    stop  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Para containers (preserva estado)" -ForegroundColor Gray
    Write-Host "    down  [nomes]      " -ForegroundColor Green -NoNewline
    Write-Host "Remove containers" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  DIAGNOSTICO:" -ForegroundColor White
    Write-Host "    status [itens]     " -ForegroundColor Green -NoNewline
    Write-Host "Saude do que esta rodando (ou itens especificos)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  FLUXO RECOMENDADO (debug com hot reload):" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 infra              " -ForegroundColor White -NoNewline
    Write-Host "Sobe banco + observabilidade" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 run svc-auth        " -ForegroundColor White -NoNewline
    Write-Host "Hot reload + logs no terminal" -ForegroundColor DarkGray
    Write-Host "    3. .\proj.ps1 attach              " -ForegroundColor White -NoNewline
    Write-Host "Detecta o que esta rodando e configura F5" -ForegroundColor DarkGray
    Write-Host "    4. Ctrl+Shift+D -> Attach: Selected -> F5" -ForegroundColor White -NoNewline
    Write-Host "  <- breakpoints ativos!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  EXEMPLOS:" -ForegroundColor White
    Write-Host "    .\proj.ps1 run svc-auth svc-catalog" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 attach                   " -ForegroundColor DarkGray -NoNewline
    Write-Host "<- auto-detecta rodando" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 attach svc-auth svc-catalog" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 infra postgres grafana" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 logs postgres" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 status svc-auth postgres" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 stop otel-collector" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 down postgres" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  REFERENCIA:" -ForegroundColor DarkGray
    Write-Host "    Portas:  " -ForegroundColor DarkGray -NoNewline
    Write-Host "infra/local/services.json" -ForegroundColor Cyan
    Write-Host "    Debug:   " -ForegroundColor DarkGray -NoNewline
    Write-Host "Ctrl+Shift+D -> selecione config -> F5" -ForegroundColor Cyan
    Write-Host "    Logs:    " -ForegroundColor DarkGray -NoNewline
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
    "run"    { Invoke-Run      -Names   $Services }
    "attach" { Invoke-Attach  -Names   $Services }
    "list"   { Invoke-List }
    "status" { Invoke-Status   -Targets $Services }
    "infra"  { Invoke-InfraUp  -Targets $Services }
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
