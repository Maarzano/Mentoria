# ==============================================================================
# commands/list.ps1 - Inventario completo com status
# ==============================================================================

function Invoke-List {
    Write-Header "Inventario Completo"

    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

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

Register-ProjCommand -Name 'list' -Group 'Diagnostico' `
    -Summary 'Lista tudo com status e portas' `
    -Action { param($Services, $ContainerMode) Invoke-List }
