# ==============================================================================
# _registry.ps1 - Registry de comandos (ponto de extensao)
#
# Cada arquivo em commands/*.ps1 deve chamar Register-ProjCommand para se
# inscrever. O dispatcher principal usa esse registry para rotear o comando.
# ==============================================================================

$script:ProjCommands = [ordered]@{}

function Register-ProjCommand {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Action,
        [switch]$RequiresEnv,
        [string]$Summary = "",
        [string]$Group = "Geral"
    )
    $script:ProjCommands[$Name.ToLower()] = @{
        Name        = $Name.ToLower()
        Action      = $Action
        RequiresEnv = [bool]$RequiresEnv
        Summary     = $Summary
        Group       = $Group
    }
}

function Get-ProjCommand {
    param([string]$Name)
    if (-not $Name) { return $null }
    $key = $Name.ToLower()
    if ($script:ProjCommands.Contains($key)) { return $script:ProjCommands[$key] }
    return $null
}

function Get-ProjCommandNames {
    return @($script:ProjCommands.Keys)
}
