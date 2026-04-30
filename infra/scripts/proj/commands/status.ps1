# ==============================================================================
# commands/status.ps1 - Saude do que esta rodando ou de itens especificos
# ==============================================================================

function Invoke-Status {
    param([string[]]$Targets)

    Write-Header "Status"
    $docker = Get-DockerStatus
    $svcContainers = Get-ServiceContainersStatus

    if ($Targets -and $Targets.Count -gt 0) {
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
        $anyRunning = $false

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
            Write-TIP "Rode um servico:  .\proj.ps1 run svc-users"
            Write-TIP "Rode via container: .\proj.ps1 run -c svc-users"
        }
    }

    Write-Footer
}

Register-ProjCommand -Name 'status' -Group 'Diagnostico' `
    -Summary 'Saude do que esta rodando (ou itens especificos)' `
    -Action { param($Services, $ContainerMode) Invoke-Status -Targets $Services }
