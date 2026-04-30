# ==============================================================================
# commands/infra.ps1 - Sobe infraestrutura Docker
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

Register-ProjCommand -Name 'infra' -RequiresEnv -Group 'Infra' `
    -Summary 'Sobe containers de infra (todos ou especificos)' `
    -Action { param($Services, $ContainerMode) Invoke-InfraUp -Targets $Services }
