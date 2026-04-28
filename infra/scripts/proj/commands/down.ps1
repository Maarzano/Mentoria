# ==============================================================================
# commands/down.ps1 - Remove containers (infra e/ou servicos)
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

Register-ProjCommand -Name 'down' -Group 'Infra' `
    -Summary 'Remove containers (infra e/ou servicos)' `
    -Action { param($Services, $ContainerMode) Invoke-Down -Targets $Services }
