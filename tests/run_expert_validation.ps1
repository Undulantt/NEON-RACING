param(
    [string]$Godot = (Join-Path $PSScriptRoot '../../../Godot_v4.7.2-stable_win64_console.exe'),
    [switch]$SummarizeOnly,
    [switch]$Regression
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$originalAppData=$env:APPDATA
Push-Location -LiteralPath $projectRoot
try {
    if (-not $SummarizeOnly) {
        $engine=(Resolve-Path -LiteralPath $Godot).Path
        $env:APPDATA=Join-Path $projectRoot '.godot-local-profile/expert-validation'
        $cases=@(
            @{Script='godot_expert_menu';Args=@();Log='expert_menu'},
            @{Script='godot_expert_overtake';Args=@();Log='expert_overtake'},
            @{Script='godot_rival_acceptance';Args=@('--ai-difficulty=expert');Log='expert_final_traffic'},
            @{Script='godot_rival_acceptance';Args=@('--personalities','--ai-difficulty=expert');Log='expert_final_solo'},
            @{Script='godot_rival_acceptance';Args=@('--personalities','--ai-difficulty=standard');Log='expert_standard_solo'},
            @{Script='godot_rival_drift_probe';Args=@('--ai-difficulty=expert');Log='expert_drift'},
            @{Script='godot_d3_abilities';Args=@('--ai-difficulty=expert');Log='expert_burst'}
        )
        if($Regression){
            foreach($script in @('godot_checkpoint_spheres','godot_d3_rules','godot_d3_trajectory','godot_editor_laps')){
                $cases+=@{Script=$script;Args=@('--rivals=0');Log="expert_$script"}
            }
        }
        foreach($case in $cases){
            & $engine --headless --fixed-fps 60 --log-file .local/artifacts/expert_validation_engine.log --path . --script "tests/$($case.Script).gd" -- @($case.Args) 2>&1 | Tee-Object -FilePath ".local/artifacts/$($case.Log).log"
            if($LASTEXITCODE -ne 0){throw "Failed: $($case.Script) $($case.Args)"}
        }
    }
    function Read-Result([string]$name){Get-Content -LiteralPath ".local/artifacts/$name.json" -Raw|ConvertFrom-Json}
    $standard=Read-Result 'rival_acceptance_personalities_standard'
    $expert=Read-Result 'rival_acceptance_personalities_expert'
    $traffic=Read-Result 'rival_acceptance_traffic_expert'
    $drift=Read-Result 'rival_acceptance_drift_probe'
    $burst=Read-Result 'd3_abilities_validation'
    $pass=Read-Result 'expert_overtake'
    $menu=Read-Result 'expert_menu_validation'
    $driverHash=(Get-FileHash -LiteralPath scripts/racing/RivalDriver.gd -Algorithm SHA256).Hash.ToLowerInvariant()
    $physicsHash=(Get-FileHash -LiteralPath scripts/driving/ArcadeCar.gd -Algorithm SHA256).Hash.ToLowerInvariant()
    foreach($report in @($standard,$expert,$traffic)){
        if($report.driver_sha256 -ne $driverHash -or $report.physics_sha256 -ne $physicsHash){throw 'Source changed since measurements; rerun validation.'}
    }
    if($standard.difficulty -ne 'standard' -or $expert.difficulty -ne 'expert' -or $traffic.difficulty -ne 'expert' -or $drift.difficulty -ne 'expert' -or $burst.difficulty -ne 'expert'){throw 'Reports use different difficulty settings.'}
    $comparisons=@()
    for($index=0;$index -lt 3;$index++){
        $a=$standard.cases[$index].rows[0]
        $b=$expert.cases[$index].rows[0]
        $comparisons+=[ordered]@{
            personality=$standard.cases[$index].mode
            standard_seconds=$a.elapsed_s
            expert_seconds=$b.elapsed_s
            time_reduction_percent=(1-$b.elapsed_s/$a.elapsed_s)*100
            same_physics=$a.physics_config_hash -eq $b.physics_config_hash -and $a.physics_config_equal -and $b.physics_config_equal
        }
    }
    $rows=@($traffic.cases|ForEach-Object{$_.rows})+@($expert.cases|ForEach-Object{$_.rows})+@($standard.cases|ForEach-Object{$_.rows})
    $fair=@($rows|Where-Object{-not $_.physics_config_equal -or -not $_.speed_multiplier_normal -or $_.teleport_recoveries -ne 0 -or $_.motion_residual_peak_m -gt 0.001}).Count -eq 0
    $cleanRoad=@($rows|Where-Object{$_.offroad_frames -ne 0 -or $_.wall_contact_frames -ne 0 -or $_.checkpoint_recoveries -ne 0}).Count -eq 0
    $faster=@($comparisons|Where-Object{-not $_.same_physics -or $_.expert_seconds -ge $_.standard_seconds}).Count -eq 0
    $aggressive=@($drift.rows|Where-Object personality -eq 'aggressive')
    $earned=$drift.npc_drift_demonstrated -and $aggressive.Count -eq 3 -and @($aggressive|Where-Object{$_.drift_rewards -le 0 -or $_.boost_eligible_acceleration_frames -le 0}).Count -eq 0
    $events=@($traffic.cases|ForEach-Object{$_.passes})
    $summary=[ordered]@{
        passed=[bool]($standard.audit_completed -and $expert.audit_completed -and $traffic.audit_completed -and $fair -and $cleanRoad -and $faster -and $earned -and $pass.passed -and $burst.passed -and $menu.passed)
        comparisons=$comparisons
        physical_parameters_unchanged=[bool]$fair
        no_offroad_wall_or_checkpoint_recovery=[bool]$cleanRoad
        controlled_overtake_passed=[bool]$pass.passed
        aggressive_rivals_earn_and_use_drift_boost=[bool]$earned
        all_rivals_burst_capable=[bool]$burst.passed
        full_race_reported_passes=@($events|Where-Object driver_reported_completed).Count
        full_race_measured_passes=@($events|Where-Object measured_completed).Count
        ai_acceptance_complete=$false
        human_difficulty_validated=$false
        note='Validates the Expert level and specific capabilities. General overtaking against equally fast rivals and subjective difficulty remain pending; perfect-human performance is not guaranteed.'
    }
    $json=$summary|ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $projectRoot '.local/artifacts/expert_mode_validation.json'),$json,[System.Text.UTF8Encoding]::new($false))
    Write-Output $json
    if(-not $summary.passed){throw 'Expert validation failed; inspect the summary and per-case reports.'}
} finally {
    $env:APPDATA=$originalAppData
    Pop-Location
}
