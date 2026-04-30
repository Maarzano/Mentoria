# ==============================================================================
# commands/attach.ps1 - Conecta debugger a processos rodando
# ==============================================================================

function Invoke-Attach {
    param([string[]]$Names)

    Write-Header "Attach - Conectar Debug ao Processo em Execucao"

    $toAttach = @()

    if ($Names -and $Names.Count -gt 0) {
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
        Write-TIP "Inicie um servico:  .\proj.ps1 run svc-users"
        Write-Footer
        return
    }

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

Register-ProjCommand -Name 'attach' -Group 'Servicos' `
    -Summary 'Conecta debug ao processo ja rodando (F5)' `
    -Action { param($Services, $ContainerMode) Invoke-Attach -Names $Services }
