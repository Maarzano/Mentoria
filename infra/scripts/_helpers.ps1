################################################################################
# _helpers.ps1 — Funções utilitárias compartilhadas
# NÃO rodar diretamente. Usar via dot-source nos outros scripts:
#   . "$PSScriptRoot\_helpers.ps1"
################################################################################

function Write-Step  { param([string]$Msg) Write-Host "  → $Msg" -ForegroundColor Cyan }
function Write-Done  { param([string]$Msg) Write-Host "  ✓ $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "  ⚠ $Msg" -ForegroundColor Yellow }
function Write-Fatal { param([string]$Msg) Write-Host "  ✗ $Msg" -ForegroundColor Red; exit 1 }

function Write-Header {
    param([string]$Title)
    $line = "─" * ($Title.Length + 4)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Magenta
    Write-Host "  ─ $Title ─" -ForegroundColor Magenta
    Write-Host "  $line" -ForegroundColor Magenta
    Write-Host ""
}

# Pede confirmação simples (yes/no)
function Confirm-Action {
    param([string]$Prompt)
    $resp = Read-Host "  $Prompt [yes/no]"
    if ($resp -ne "yes") {
        Write-Host "  Cancelado." -ForegroundColor Yellow
        exit 0
    }
}

# Pede confirmação digitando uma frase específica (para operações destrutivas)
function Confirm-Dangerous {
    param([string]$Prompt, [string]$Expected)
    Write-Host "  $Prompt" -ForegroundColor Red
    $resp = Read-Host "  Digite exatamente '$Expected' para confirmar"
    if ($resp -ne $Expected) {
        Write-Host "  Confirmação incorreta. Cancelado." -ForegroundColor Yellow
        exit 0
    }
}

# Roda 'terraform output -raw <nome>' e retorna o valor
function Get-TerraformOutput {
    param([string]$TFDir, [string]$OutputName)
    Push-Location $TFDir
    try {
        $value = terraform output -raw $OutputName 2>$null
        return $value
    } finally {
        Pop-Location
    }
}

# Roda o comando que vem do output do terraform (ex: az aks get-credentials ...)
function Invoke-TerraformOutput {
    param([string]$TFDir, [string]$OutputName)
    $cmd = Get-TerraformOutput -TFDir $TFDir -OutputName $OutputName
    Write-Step "Executando: $cmd"
    Invoke-Expression $cmd
}

# Verifica se uma ferramenta de linha de comando está instalada
function Assert-Tool {
    param([string[]]$Tools)
    foreach ($tool in $Tools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Fatal "'$tool' não encontrado no PATH. Instale antes de continuar."
        }
    }
}

# Verifica se a variável de ambiente TF_VAR_postgres_admin_password está definida
function Assert-TFVars {
    if (-not $env:TF_VAR_postgres_admin_password) {
        Write-Fatal @"
TF_VAR_postgres_admin_password não definido.
Execute no terminal antes de rodar este script:
  `$env:TF_VAR_postgres_admin_password = 'SuaSenhaSegura123!'
"@
    }
}
