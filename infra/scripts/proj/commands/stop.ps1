# ==============================================================================
# commands/stop.ps1 - Para containers (infra e/ou servicos)
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

Register-ProjCommand -Name 'stop' -Group 'Infra' `
    -Summary 'Para containers (infra e/ou servicos)' `
    -Action { param($Services, $ContainerMode) Invoke-Stop -Targets $Services }
