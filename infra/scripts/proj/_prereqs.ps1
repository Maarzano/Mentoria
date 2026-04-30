# ==============================================================================
# _prereqs.ps1 - Smart restore/build para .NET e Node
# ==============================================================================

function Invoke-DotnetPrereqs {
    param([string]$Name, [PSObject]$Cfg)
    $svcPath = Join-Path $repoRoot $Cfg.path
    $projFullPath = Join-Path $svcPath $Cfg.entryProject

    if (-not (Test-Path $projFullPath)) {
        Write-WARN "$Name : csproj nao existe ainda."
        return $false
    }

    $projDir = Split-Path $projFullPath -Parent
    $assetsPath = Join-Path $projDir "obj\project.assets.json"
    $needsRestore = (-not (Test-Path $assetsPath))
    if (-not $needsRestore) {
        $needsRestore = (Get-Item $projFullPath).LastWriteTimeUtc -gt (Get-Item $assetsPath).LastWriteTimeUtc
    }

    if ($needsRestore) {
        Write-Host "       dotnet restore..." -ForegroundColor DarkGray -NoNewline
        dotnet restore $projFullPath --nologo -v quiet 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Host " FALHOU" -ForegroundColor Red; return $false }
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host "       Dependencias OK (cache valido)." -ForegroundColor DarkGray
    }

    Write-Host "       dotnet build..." -ForegroundColor DarkGray -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $buildArgs = @("build", $projFullPath, "--nologo", "-v", "quiet", "-c", "Debug")
    if (-not $needsRestore) { $buildArgs += "--no-restore" }
    & dotnet @buildArgs 2>$null
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }

    Write-Host " OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green
    return $true
}

function Invoke-NodePrereqs {
    param([string]$Name, [PSObject]$Cfg)
    $svcPath = Join-Path $repoRoot $Cfg.path

    if (-not (Test-Path (Join-Path $svcPath "package.json"))) {
        Write-WARN "$Name : package.json nao existe ainda."
        return $false
    }

    $nodeModules = Join-Path $svcPath "node_modules"
    $lockFile    = Join-Path $svcPath "package-lock.json"
    $needsInstall = (-not (Test-Path $nodeModules))
    if (-not $needsInstall -and (Test-Path $lockFile)) {
        $needsInstall = (Get-Item $lockFile).LastWriteTimeUtc -gt (Get-Item $nodeModules).LastWriteTimeUtc
    }

    Push-Location $svcPath
    try {
        if ($needsInstall) {
            Write-Host "       npm ci..." -ForegroundColor DarkGray -NoNewline
            npm ci --silent 2>$null
            Write-Host " OK" -ForegroundColor Green
        } else {
            Write-Host "       node_modules OK (cache valido)." -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
    return $true
}

function Invoke-Prereqs {
    param([string]$Name, [PSObject]$Cfg)
    switch ($Cfg.type) {
        "dotnet" { return Invoke-DotnetPrereqs -Name $Name -Cfg $Cfg }
        "node"   { return Invoke-NodePrereqs   -Name $Name -Cfg $Cfg }
        default  { Write-WARN "Tipo desconhecido: $($Cfg.type)"; return $false }
    }
}
