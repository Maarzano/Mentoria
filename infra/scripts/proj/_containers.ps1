# ==============================================================================
# _containers.ps1 - Gestao de containers de servico (docker run + Dockerfile)
# ==============================================================================

function Get-ComposeNetworkName {
    Push-Location $repoRoot
    try {
        $jsonRaw = docker compose config --format json 2>$null
        if ($jsonRaw) {
            $cfg = $jsonRaw | ConvertFrom-Json
            if ($cfg.name) { return "$($cfg.name)_default" }
        }
    } catch {} finally { Pop-Location }
    return "foodeapp_default"
}

function Get-ServiceContainerPort {
    param([PSObject]$Cfg)
    if ($Cfg.containerPort) { return $Cfg.containerPort }
    switch ($Cfg.type) {
        "dotnet" { return $script:DEFAULT_DOTNET_CONTAINER_PORT }
        default  { return $Cfg.port }
    }
}

function Get-ServiceContainerName {
    param([string]$Name)
    return "$($script:SVC_CONTAINER_PREFIX)-$Name"
}

function Get-ServiceImageName {
    param([string]$Name)
    return "$($script:SVC_CONTAINER_PREFIX)/${Name}:dev"
}

function Test-ServiceContainerRunning {
    param([string]$Name)
    $containerName = Get-ServiceContainerName -Name $Name
    $status = docker inspect --format='{{.State.Status}}' $containerName 2>$null
    return ($status -eq "running")
}

function Get-ServiceContainersStatus {
    $result = @{}
    $lines = docker ps -a --filter "label=foodeapp.type=service" --format "{{.Names}}|{{.Status}}" 2>$null
    if ($lines) {
        foreach ($line in $lines) {
            if ($line -and $line.Contains("|")) {
                $parts = $line.Split("|", 2)
                $containerName = $parts[0].Trim()
                $svcName = $containerName -replace "^$([regex]::Escape($script:SVC_CONTAINER_PREFIX))-", ""
                $result[$svcName] = $parts[1].Trim()
            }
        }
    }
    return $result
}

function Build-ContainerEnvArgs {
    param([string]$Name, [PSObject]$Cfg, [int]$ContainerPort)

    $localEnv = Build-ServiceEnv -Name $Name -Cfg $Cfg

    $portToInfra = @{}
    foreach ($infraName in $script:infraNames) {
        $ep = "$($script:infraEndpoints[$infraName])"
        foreach ($m in [regex]::Matches($ep, 'localhost:(\d+)')) {
            $portToInfra[[int]$m.Groups[1].Value] = $infraName
        }
    }

    $envArgs = @()
    foreach ($key in $localEnv.Keys) {
        $val = $localEnv[$key]

        if ($key -eq "ASPNETCORE_URLS") {
            $val = "http://0.0.0.0:$ContainerPort"
        }
        elseif ($key -like "Database__Host" -and $val -eq "localhost") {
            $port = if ($localEnv["Database__Port"]) { $localEnv["Database__Port"] } else { "5432" }
            $pgPort = [int]$port
            if ($portToInfra.ContainsKey($pgPort)) {
                $val = $portToInfra[$pgPort]
            }
        }
        elseif ($val -match "localhost:\d+") {
            foreach ($p in @($portToInfra.Keys)) {
                $infraN = $portToInfra[$p]
                $val = $val -replace "localhost:$p", "${infraN}:$p"
            }
        }

        $envArgs += "-e"
        $envArgs += "$key=$val"
    }
    return $envArgs
}

function Resolve-AllDeps {
    param(
        [string[]]$ServiceNames,
        [string[]]$Exclude = @()
    )

    $allDeps = @()
    $visited = @() + $Exclude + $ServiceNames
    $queue = New-Object System.Collections.Queue

    foreach ($name in $ServiceNames) {
        $prop = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $name }
        if ($prop -and $prop.Value.depends) {
            foreach ($dep in $prop.Value.depends) {
                if ($dep -notin $visited) {
                    $queue.Enqueue($dep)
                    $visited += $dep
                }
            }
        }
    }

    while ($queue.Count -gt 0) {
        $dep = $queue.Dequeue()
        $allDeps += $dep
        $prop = $registry.services.PSObject.Properties | Where-Object { $_.Name -eq $dep }
        if ($prop -and $prop.Value.depends) {
            foreach ($d in $prop.Value.depends) {
                if ($d -notin $visited) {
                    $queue.Enqueue($d)
                    $visited += $d
                }
            }
        }
    }

    return $allDeps
}

function Invoke-ServiceContainerUp {
    param([string]$Name)

    $cfg = Get-ServiceConfig -Name $Name
    $containerName = Get-ServiceContainerName -Name $Name
    $imageName = Get-ServiceImageName -Name $Name
    $svcPath = Join-Path $repoRoot $cfg.path
    $dockerfile = Join-Path $svcPath "Dockerfile"

    if (-not (Test-Path $dockerfile)) {
        Write-ERR "$Name : Dockerfile nao encontrado em $($cfg.path)/Dockerfile"
        return $false
    }

    if (Test-ServiceContainerRunning -Name $Name) {
        Write-OK "$Name ja esta rodando como container."
        return $true
    }

    docker rm -f $containerName 2>$null | Out-Null

    Write-Host "       [$Name] docker build..." -ForegroundColor DarkGray -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker build -t $imageName -f $dockerfile $repoRoot 2>$null
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }
    Write-Host " OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Green

    $network = Get-ComposeNetworkName
    $hostPort = $cfg.port
    $containerPort = Get-ServiceContainerPort -Cfg $cfg

    $envArgs = Build-ContainerEnvArgs -Name $Name -Cfg $cfg -ContainerPort $containerPort

    Write-Host "       [$Name] docker run..." -ForegroundColor DarkGray -NoNewline
    $runArgs = @(
        "run", "-d",
        "--name", $containerName,
        "--network", $network,
        "-p", "${hostPort}:${containerPort}",
        "--label", "foodeapp.type=service",
        "--label", "foodeapp.service=$Name"
    )
    $runArgs += $envArgs
    $runArgs += $imageName

    & docker @runArgs 2>$null | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host " FALHOU" -ForegroundColor Red
        return $false
    }
    Write-Host " OK (:$hostPort)" -ForegroundColor Green
    return $true
}

function Stop-ServiceContainer {
    param([string]$Name)
    $containerName = Get-ServiceContainerName -Name $Name
    docker stop $containerName 2>$null | Out-Null
    docker rm $containerName 2>$null | Out-Null
}
