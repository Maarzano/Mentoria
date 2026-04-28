#!/usr/bin/env pwsh
# ==============================================================================
# proj.ps1 - FoodeApp | CLI de Desenvolvimento Local (entry-point)
#
# Este arquivo apenas faz bootstrap, dot-source dos modulos e despacha o
# comando. Toda a logica vive em infra/scripts/proj/.
#
# ESTRUTURA:
#   infra/scripts/proj/
#     _bootstrap.ps1   .env, services.json, metadados do compose
#     _output.ps1      Write-Header/OK/WARN/ERR/TIP/GRAY/Step/Footer
#     _utils.ps1       Test-PortListening, Get-ServiceConfig, Build-ServiceEnv...
#     _containers.ps1  docker run/build de servicos (modo -c)
#     _prereqs.ps1     dotnet restore/build, npm ci
#     _launch.ps1      Update-LaunchCompound (.vscode/launch.json)
#     _registry.ps1    Register-ProjCommand (ponto de extensao)
#     commands/*.ps1   1 arquivo por comando, auto-registrado
#
# COMO ADICIONAR UM NOVO COMANDO:
#   1. Crie infra/scripts/proj/commands/<nome>.ps1
#   2. Defina sua funcao Invoke-Foo
#   3. Chame Register-ProjCommand -Name 'foo' -Action { ... }
#   E so. O dispatcher detecta automaticamente.
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [switch]$c,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Services
)

# NOTA: Usar "Continue" e nao "Stop" porque docker compose escreve progresso
# no stderr, e PS 5.1 trata stderr de comandos nativos como erro terminante
# quando $ErrorActionPreference = "Stop".
$ErrorActionPreference = "Continue"
$repoRoot = $PSScriptRoot

# Modo container (-c flag)
$script:ContainerMode = [bool]$c

# ------------------------------------------------------------------------------
# Carregamento dos modulos (ordem importa)
# ------------------------------------------------------------------------------
$projModulesDir = Join-Path $repoRoot "infra\scripts\proj"
if (-not (Test-Path $projModulesDir)) {
    Write-Host "  [ERRO] Diretorio de modulos nao encontrado: $projModulesDir" -ForegroundColor Red
    exit 1
}

# Modulos base (ordem deliberada por dependencias)
$baseModules = @(
    "_output.ps1",      # Write-* helpers (sem deps)
    "_bootstrap.ps1",   # .env + registry + infra metadata
    "_utils.ps1",       # status/port/env helpers
    "_containers.ps1",  # docker run de servicos
    "_prereqs.ps1",     # restore/build cache
    "_launch.ps1",      # launch.json compounds
    "_registry.ps1"     # Register-ProjCommand
)
foreach ($m in $baseModules) {
    $path = Join-Path $projModulesDir $m
    if (-not (Test-Path $path)) {
        Write-Host "  [ERRO] Modulo ausente: $m" -ForegroundColor Red
        exit 1
    }
    . $path
}

# Comandos: auto-discovery em commands/*.ps1
# Cada arquivo deve definir sua funcao e chamar Register-ProjCommand (exceto help).
$commandsDir = Join-Path $projModulesDir "commands"
if (Test-Path $commandsDir) {
    foreach ($file in Get-ChildItem -Path $commandsDir -Filter "*.ps1" -File | Sort-Object Name) {
        . $file.FullName
    }
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
if (-not $Command) {
    Show-Help
    exit 0
}

$cmd = Get-ProjCommand -Name $Command
if (-not $cmd) {
    Write-Host ""
    Write-Host "  [ERRO] Comando desconhecido: '$Command'" -ForegroundColor Red
    $known = (Get-ProjCommandNames) -join ' | '
    Write-Host "  Comandos: $known" -ForegroundColor Yellow
    Write-Host "  Execute sem parametros para ver ajuda completa." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

if ($cmd.RequiresEnv) { Assert-RequiredEnvVars }

& $cmd.Action $Services $script:ContainerMode
