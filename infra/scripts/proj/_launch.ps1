# ==============================================================================
# _launch.ps1 - Atualiza compounds no .vscode/launch.json
# ==============================================================================

function Update-LaunchCompound {
    param(
        [string]$CompoundName,
        [string[]]$Configurations,
        [string]$PreLaunchTask = $null
    )
    $vscodePath = Join-Path $repoRoot "..\vscode" # nao usado diretamente
    $launchPath = Join-Path $repoRoot "..\.vscode\launch.json"
    if (-not (Test-Path $launchPath)) { return $false }

    $raw     = [System.IO.File]::ReadAllText($launchPath)
    $cleaned = $raw -replace '(?m)\s*//[^\n]*', '' -replace ',(\s*[}\]])', '$1'
    try { $launch = $cleaned | ConvertFrom-Json } catch { return $false }

    $compounds = @($launch.compounds)
    $found = $false
    for ($i = 0; $i -lt $compounds.Count; $i++) {
        if ($compounds[$i].name -eq $CompoundName) {
            $compounds[$i].configurations = $Configurations
            $found = $true; break
        }
    }
    if (-not $found) {
        $newC = [PSCustomObject]@{ name = $CompoundName; configurations = $Configurations; stopAll = $true }
        if ($PreLaunchTask) { $newC | Add-Member -NotePropertyName preLaunchTask -NotePropertyValue $PreLaunchTask }
        $compounds += $newC
    }
    $launch.compounds = $compounds
    $json = $launch | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($launchPath, $json, [System.Text.UTF8Encoding]::new($false))
    return $true
}
