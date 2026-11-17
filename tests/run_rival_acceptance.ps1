param(
    [string]$Godot = (Join-Path $PSScriptRoot '../../../Godot_v4.7.2-stable_win64_console.exe'),
    [ValidateSet('standard','expert')][string]$Difficulty = 'expert',
    [switch]$SummarizeOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$originalAppData = $env:APPDATA
Push-Location -LiteralPath $projectRoot
try {
    if (-not $SummarizeOnly) {
        $engine = (Resolve-Path -LiteralPath $Godot).Path
        $env:APPDATA = Join-Path $projectRoot '.godot-local-profile/rival-acceptance'
        $cases = @(
            @{ Script='tests/godot_rival_pass_measurement.gd'; Args=@(); Log='.local/artifacts/rival_acceptance_measurement.log' },
            @{ Script='tests/godot_rival_acceptance.gd'; Args=@(); Log='.local/artifacts/rival_acceptance_traffic.log' },
            @{ Script='tests/godot_rival_acceptance.gd'; Args=@('--personalities'); Log='.local/artifacts/rival_acceptance_personalities.log' },
            @{ Script='tests/godot_rival_drift_probe.gd'; Args=@(); Log='.local/artifacts/rival_acceptance_drift_probe.log' },
            @{ Script='tests/godot_d3_abilities.gd'; Args=@(); Log='.local/artifacts/rival_acceptance_burst.log' }
        )
        foreach ($case in $cases) {
            & $engine --headless --fixed-fps 60 --log-file .local/artifacts/rival_acceptance_engine.log --path . --script $case.Script -- @($case.Args) "--ai-difficulty=$Difficulty" 2>&1 | Tee-Object -FilePath $case.Log
            if ($LASTEXITCODE -ne 0) { throw "Incomplete audit: $($case.Script) $($case.Args)" }
        }
    }
    $traffic = Get-Content -LiteralPath ".local/artifacts/rival_acceptance_traffic_$Difficulty.json" -Raw | ConvertFrom-Json
    $personalities = Get-Content -LiteralPath ".local/artifacts/rival_acceptance_personalities_$Difficulty.json" -Raw | ConvertFrom-Json
    $drift = Get-Content -LiteralPath .local/artifacts/rival_acceptance_drift_probe.json -Raw | ConvertFrom-Json
    $burst = Get-Content -LiteralPath .local/artifacts/d3_abilities_validation.json -Raw | ConvertFrom-Json
    foreach ($report in @($traffic,$personalities)) {
        foreach ($source in @(
            @('rivals_config_sha256','config/rivals.json'),
            @('driver_sha256','scripts/racing/RivalDriver.gd'),
            @('physics_sha256','scripts/driving/ArcadeCar.gd')
        )) {
            if ($report.($source[0]) -ne (Get-FileHash -LiteralPath $source[1] -Algorithm SHA256).Hash.ToLowerInvariant()) { throw "Stale audit: $($source[1]) changed." }
        }
    }
    $rows = @($traffic.cases | ForEach-Object { $_.rows }) + @($personalities.cases | ForEach-Object { $_.rows })
    $physics = @($rows | Where-Object {
        -not $_.physics_config_equal -or -not $_.speed_multiplier_normal -or $_.motion_residual_peak_m -gt 0.001 -or $_.teleport_recoveries -ne 0 -or $_.throttle_frames -eq 0 -or $_.brake_frames -eq 0 -or $_.steer_frames -eq 0
    }).Count -eq 0
    $probes = @($traffic.cases[0].frozen_controller_probes.PSObject.Properties.Value)
    $physics = $physics -and $probes.Count -eq 5 -and @($probes | Where-Object { -not $_.transform_unchanged -or -not $_.velocity_unchanged -or -not $_.throttle_requested -or -not $_.steering_requested }).Count -eq 0
    $passes = @($traffic.cases | ForEach-Object { $_.passes })
    $clean = @($passes | Where-Object { $_.measured_completed -and $_.defender_npc -and $_.defender_moving -and $_.pair_contact_frames -eq 0 -and $_.lateral_peak_m -gt 2.6 })
    $npcOnly = @($traffic.cases | Where-Object { $_.mode -eq 'npc_only' })[0]
    $sameCar = @($personalities.cases | ForEach-Object { $_.rows[0] })
    $times = @($sameCar.elapsed_s | Sort-Object)
    $initialPositions = @($sameCar | ForEach-Object { $_.initial_position | ConvertTo-Json -Compress } | Select-Object -Unique)
    $character = $initialPositions.Count -eq 1 -and @($sameCar.physics_config_hash | Select-Object -Unique).Count -eq 1 -and @($sameCar | Where-Object { -not $_.physics_config_equal -or $_.vehicle -ne 'VECTOR' -or -not $_.finished -or $_.laps -ne 2 }).Count -eq 0 -and ($times[-1]-$times[0]) -gt 1
    $criteria = [ordered]@{
        physical_controls = $physics
        verified_clean_npc_overtaking = $clean.Count -gt 0
        drift_turbo_burst_capability = [bool]($drift.npc_drift_demonstrated -and $burst.passed)
        npc_competition_without_player = [bool]($npcOnly.completed -and @($npcOnly.passes | Where-Object { $_.defender_npc -and $_.defender_moving }).Count -gt 0)
        observable_personalities_same_physics = [bool]$character
    }
    $summary = [ordered]@{
        audit_completed = [bool]($traffic.audit_completed -and $personalities.audit_completed -and $drift.audit_completed -and $burst.passed)
        difficulty = $Difficulty
        acceptance_approved = @($criteria.Values | Where-Object { -not $_ }).Count -eq 0
        criteria = $criteria
        human_fun_validated = $false
        driver_reported_passes = @($passes | Where-Object { $_.driver_reported_completed }).Count
        measured_passes = @($passes | Where-Object { $_.measured_completed }).Count
        clean_npc_passes = $clean.Count
        pass_verification = 'Each car uses its own continuous progress: initially behind, then 7 m ahead for 0.5 s, both still competing. Counter alone is insufficient.'
        note = 'Exit success means audit measurements completed. acceptance_approved and human_fun_validated determine the separate acceptance verdict.'
    }
    $json = $summary | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $projectRoot ".local/artifacts/rival_acceptance_verdict_$Difficulty.json"),$json,[System.Text.UTF8Encoding]::new($false))
    Write-Output $json
} finally {
    $env:APPDATA = $originalAppData
    Pop-Location
}
