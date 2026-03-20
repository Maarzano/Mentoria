#!/usr/bin/env pwsh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# LOCAL DEV QUICKSTART — Copy/Paste de Tudo
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           LOCAL DEV QUICK START — MENTORIA SVCAUTH            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$menu = @"
Escolha uma opção:

1️⃣ INICIAR TUDO (Infra + App)
   → Abre 2 terminais: Infra no primeiro, App no segundo
   → Ctrl+C em qualquer um para parar

2️⃣ APENAS INFRA (Docker - PostgreSQL, OTel, Prometheus, Tempo, Loki, Grafana)
   → Use se quer apenas a stack de observabilidade
   → Digite `dotnet run` em outro terminal para a app

3️⃣ APENAS APP (dotnet watch run)
   → Use se infra já está rodando
   → Hot-reload automático ao salvar código

4️⃣ PARAR TUDO
   → Remove containers Docker

5️⃣ STATUS CHECK
   → Valida saúde de todos os endpoints

0️⃣ SAIR

"@

Write-Host $menu -ForegroundColor White

$choice = Read-Host "Digite sua escolha (0-5)"

switch ($choice) {
    "1" {
        Write-Host "`n▶️ Iniciando Terminal 1 (Infra)..." -ForegroundColor Cyan
        Write-Host "   Aguarde a mensagem: ✅ Infraestrutura Online`n" -ForegroundColor Yellow
        
        $infra_cmd = {
            cd c:\Repo\Mentoria\Mentoria
            .\infra\scripts\local-dev-infra-start.ps1
        }
        
        # Abrir novo PowerShell com infra
        Start-Process pwsh -ArgumentList "-NoExit -Command `"$infra_cmd`"" -WindowStyle Normal

        Start-Sleep -Seconds 8

        Write-Host "▶️ Iniciando Terminal 2 (App)..." -ForegroundColor Cyan
        
        $app_cmd = {
            cd c:\Repo\Mentoria\Mentoria\services\svc-auth
            ..\..\infra\scripts\local-dev-app-run.ps1
        }
        
        Start-Process pwsh -ArgumentList "-NoExit -Command `"$app_cmd`"" -WindowStyle Normal

        Write-Host "`n✅ Ambos terminais abertos!" -ForegroundColor Green
        Write-Host "`n📍 Acesse:" -ForegroundColor Cyan
        Write-Host "   API:        http://localhost:8080" -ForegroundColor White
        Write-Host "   Swagger:    http://localhost:8080/swagger" -ForegroundColor White
        Write-Host "   Grafana:    http://localhost:3000" -ForegroundColor White
        Write-Host "   Prometheus: http://localhost:9090" -ForegroundColor White
        Write-Host "`n💡 Dica: Modifique código em svc-auth, salve com Ctrl+S e veja o hot-reload no Terminal 2!" -ForegroundColor Yellow
    }

    "2" {
        Write-Host "`n▶️ Iniciando apenas Infraestrutura..." -ForegroundColor Cyan
        cd c:\Repo\Mentoria\Mentoria
        .\infra\scripts\local-dev-infra-start.ps1
        
        Write-Host "`n💡 Próximo: abra outro terminal e rode:" -ForegroundColor Yellow
        Write-Host "   cd services\svc-auth" -ForegroundColor Gray
        Write-Host "   dotnet watch run --project src/FoodeApp.SvcAuth.Adapters.API" -ForegroundColor Gray
    }

    "3" {
        Write-Host "`n▶️ Iniciando apenas App..." -ForegroundColor Cyan
        cd c:\Repo\Mentoria\Mentoria\services\svc-auth
        .\..\..\infra\scripts\local-dev-app-run.ps1
    }

    "4" {
        Write-Host "`n🧹 Parando tudo..." -ForegroundColor Yellow
        cd c:\Repo\Mentoria\Mentoria
        docker compose down --remove-orphans
        Write-Host "`n✅ Tudo parado!" -ForegroundColor Green
    }

    "5" {
        Write-Host "`n🔍 Verificando saúde dos serviços..." -ForegroundColor Cyan
        cd c:\Repo\Mentoria\Mentoria
        .\infra\scripts\local-status.ps1
    }

    "0" {
        Write-Host "`nAté logo! 👋" -ForegroundColor Yellow
        exit
    }

    default {
        Write-Host "`n❌ Opção inválida!" -ForegroundColor Red
    }
}

Write-Host ""
