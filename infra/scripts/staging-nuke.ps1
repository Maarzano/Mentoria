################################################################################
# staging-nuke.ps1 — Destroi ABSOLUTAMENTE TUDO do staging
#
# ☠ AVISO: Postgres (todos os dados), Redis, Key Vault, ACR, VNet, Front Door
#   serão deletados permanentemente. Esta ação é IRREVERSÍVEL para os dados.
#
# Quando usar:
#   - Reset completo do ambiente
#   - Encerramento do projeto
#   - Emergência de custo (precisa zerar o billing agora)
################################################################################
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_helpers.ps1"

Assert-Tool @('terraform')

Write-Header "Staging NUKE ☠"

Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "  ║  ATENÇÃO: TODOS OS DADOS SERÃO APAGADOS PARA SEMPRE  ║" -ForegroundColor Red
Write-Host "  ║  Postgres, Redis, Key Vault, ACR, VNet, Front Door   ║" -ForegroundColor Red
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

Confirm-Dangerous `
    -Prompt   "Para confirmar, digite exatamente a frase abaixo" `
    -Expected "DESTRUIR STAGING COMPLETAMENTE"

Write-Step "terraform destroy (staging — tudo)..."
Push-Location $TF_STAGING
terraform destroy -auto-approve
Pop-Location

Write-Host ""
Write-Done "Staging completamente destruído. Custo = R`$0."
Write-Host ""
Write-Host "  Para recriar do zero: .\staging-up.ps1" -ForegroundColor Gray
Write-Host ""
