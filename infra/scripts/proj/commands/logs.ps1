# ==============================================================================
# commands/logs.ps1 - Logs Docker (infra ou servico em container)
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

Register-ProjCommand -Name 'logs' -Group 'Infra' `
    -Summary 'Logs Docker (infra ou servico em container)' `
    -Action { param($Services, $ContainerMode) Invoke-Logs -Targets $Services }
