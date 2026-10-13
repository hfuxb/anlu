param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hdl=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source'
$work=Join-Path $PSScriptRoot 'work\tb_latency_display'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try {
 & "$VivadoBin\xvlog.bat" (Join-Path $hdl 'video_latency_display.v') (Join-Path $PSScriptRoot 'tb_latency_display.sv') --sv -log compile.log *> compile_console.log
 if($LASTEXITCODE -ne 0){throw "Compile failed: $work"}
 & "$VivadoBin\xelab.bat" tb_latency_display -s snapshot -log elaborate.log *> elaborate_console.log
 if($LASTEXITCODE -ne 0){throw "Elaborate failed: $work"}
 & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
 $log=Get-Content -LiteralPath run.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS LATENCY DISPLAY' -or $log -match '(?im)^\s*(Fatal:|ERROR:|FAIL)'){throw "Simulation failed: $work"}
 Copy-Item -LiteralPath run.log -Destination (Join-Path $project 'reports\tb_latency_display.log') -Force
 Write-Output ($log -split "`n" | Where-Object {$_ -match 'PASS|checks'})
} finally {Pop-Location}
