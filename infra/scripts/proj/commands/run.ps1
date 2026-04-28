# ==============================================================================
# commands/run.ps1 - Roda servico local (watch) ou via container (-c)
# ==============================================================================

function Invoke-Run {
    param([string[]]$Names)

    if (-not $Names -or $Names.Count -eq 0) {
        Write-Header "Rodar Servicos"
        Write-Host "  Uso: .\proj.ps1 run <servico> [servico2 ...]" -ForegroundColor Yellow
        Write-Host "       .\proj.ps1 run -c <servico> [servico2 ...]  (via container)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Exemplos:" -ForegroundColor White
        Write-GRAY "    .\proj.ps1 run svc-users                Local com hot reload"
        Write-GRAY "    .\proj.ps1 run svc-users svc-catalog    Debug composto (local)"
        Write-GRAY "    .\proj.ps1 run -c svc-users             Via container (Dockerfile)"
        Write-GRAY "    .\proj.ps1 run svc-orders              Deps (users) sobem como container"
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

    Write-Host ""

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
        $name = $valid[0]
        $cfg = Get-ServiceConfig -Name $name

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

Register-ProjCommand -Name 'run' -RequiresEnv -Group 'Servicos' `
    -Summary 'Roda local (watch) ou via container (-c)' `
    -Action { param($Services, $ContainerMode) Invoke-Run -Names $Services }
