# ==============================================================================
# _output.ps1 - Helpers de impressao no console
# ==============================================================================

function Write-Header {
    param([string]$Title)
    $line = "=" * 60
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "  FoodeApp | $Title" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([int]$N, [int]$Total, [string]$Msg)
    if ($N -gt 0 -and $Total -gt 0) {
        Write-Host "  [$N/$Total] $Msg" -ForegroundColor Cyan
    } else {
        Write-Host "  > $Msg" -ForegroundColor Cyan
    }
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-WARN { param([string]$Msg) Write-Host "  [!!] $Msg" -ForegroundColor Yellow }
function Write-ERR  { param([string]$Msg) Write-Host "  [ERRO] $Msg" -ForegroundColor Red }
function Write-TIP  { param([string]$Msg) Write-Host "  DICA: $Msg" -ForegroundColor DarkYellow }
function Write-GRAY { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor DarkGray }

function Write-Footer {
    Write-Host ""
    Write-Host ("  " + "=" * 60) -ForegroundColor DarkCyan
    Write-Host ""
}
