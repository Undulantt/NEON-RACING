param(
    [string]$Godot = (Join-Path $PSScriptRoot '../../../Godot_v4.7.2-stable_win64_console.exe'),
    [int[]]$RivalCounts = @(1, 2, 3, 5),
    [switch]$Traffic,
    [switch]$AbilitiesAudit,
    [switch]$Regression
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = (Resolve-Path -LiteralPath $Godot).Path
$originalAppData = $env:APPDATA
Push-Location -LiteralPath $projectRoot
try {
    $env:APPDATA = Join-Path $projectRoot '.godot-local-profile/d3-validation'
    $cases = @(
        @{ Script = 'tests/godot_checkpoint_spheres.gd'; Arguments = @(); Log = '.local/artifacts/checkpoint_spheres_validation.log' },
        @{ Script = 'tests/godot_checkpoint_drift.gd'; Arguments = @(); Log = '.local/artifacts/checkpoint_physical_drift_validation.log' },
        @{ Script = 'tests/godot_d3_trajectory.gd'; Arguments = @(); Log = '.local/artifacts/d3_trajectory_geometry.log' },
        @{ Script = 'tests/godot_d3_rules.gd'; Arguments = @(); Log = '.local/artifacts/d3_rules.log' },
        @{ Script = 'tests/godot_d3_abilities.gd'; Arguments = @(); Log = '.local/artifacts/d3_abilities.log' }
    )
    foreach ($count in $RivalCounts) {
        if ($count -lt 0 -or $count -gt 5) { throw 'Rivals must be between 0 and 5.' }
        $extra = @("--rivals=$count")
        if ($count -eq 5) { $extra += '--lifecycle-d3' }
        $cases += @{ Script = 'tests/godot_phase_d3.gd'; Arguments = $extra; Log = ".local/artifacts/d3_final_$count.log" }
    }
    if ($Traffic) {
        $cases += @{ Script = 'tests/godot_phase_d3.gd'; Arguments = @('--rivals=5', '--stationary-player'); Log = '.local/artifacts/d3_parked_grid.log' }
        $cases += @{ Script = 'tests/godot_phase_d3.gd'; Arguments = @('--rivals=5', '--stationary-player', '--single-file-grid'); Log = '.local/artifacts/d3_parked_legacy.log' }
    }
    if ($AbilitiesAudit) {
        $cases += @{ Script = 'tests/godot_phase_d3.gd'; Arguments = @('--rivals=5', '--audit-abilities'); Log = '.local/artifacts/d3_ability_race_audit.log' }
    }
    if ($Regression) {
        $cases += @{ Script = 'tests/godot_editor_laps.gd'; Arguments = @('--rivals=0'); Log = '.local/artifacts/d3_regression_verified.log' }
    }
    foreach ($case in $cases) {
        & $engine --headless --fixed-fps 60 --log-file .local/artifacts/d3_engine.log --path . --script $case.Script -- @($case.Arguments) 2>&1 | Tee-Object -FilePath $case.Log
        if ($LASTEXITCODE -ne 0) { throw "Failed: $($case.Script) $($case.Arguments)" }
    }
} finally {
    $env:APPDATA = $originalAppData
    Pop-Location
}
