# ==============================================================================
# commands/help.ps1 - Help geral (impresso quando proj.ps1 e chamado sem args)
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
    Write-Host "    1. .\proj.ps1 run svc-users        " -ForegroundColor White -NoNewline
    Write-Host "Sobe infra + hot reload no terminal" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 attach              " -ForegroundColor White -NoNewline
    Write-Host "Detecta rodando e configura F5" -ForegroundColor DarkGray
    Write-Host "    3. Ctrl+Shift+D -> Attach: Selected -> F5" -ForegroundColor White -NoNewline
    Write-Host "  <- breakpoints!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  FLUXO CONTAINER:" -ForegroundColor DarkYellow
    Write-Host "    1. .\proj.ps1 run -c svc-users     " -ForegroundColor White -NoNewline
    Write-Host "Build Dockerfile + docker run" -ForegroundColor DarkGray
    Write-Host "    2. .\proj.ps1 logs svc-users       " -ForegroundColor White -NoNewline
    Write-Host "Logs do container do servico" -ForegroundColor DarkGray
    Write-Host "    3. .\proj.ps1 stop svc-users       " -ForegroundColor White -NoNewline
    Write-Host "Para o container do servico" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  DEPENDENCIAS:" -ForegroundColor DarkYellow
    Write-Host "    .\proj.ps1 run svc-orders         " -ForegroundColor White -NoNewline
    Write-Host "Deps (svc-users) sobem como container" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run svc-orders svc-users " -ForegroundColor White -NoNewline
    Write-Host "Ambos local, sem container extra" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  EXEMPLOS:" -ForegroundColor White
    Write-Host "    .\proj.ps1 run svc-users" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 run -c svc-users svc-catalog" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 infra postgres grafana" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 logs svc-users" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 stop svc-users" -ForegroundColor DarkGray
    Write-Host "    .\proj.ps1 status svc-users postgres" -ForegroundColor DarkGray
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
