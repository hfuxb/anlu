param([string]$VivadoBin = 'D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work = Join-Path $PSScriptRoot 'work_transport'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$rtlFiles = @('car_uart_tx.v','car_uart_rx.v','car_command_tx.v','car_action_status_rx.v') |
    ForEach-Object { Join-Path (Join-Path $project 'rtl') $_ }
Push-Location -LiteralPath $work
try {
    & (Join-Path $VivadoBin 'xvlog.bat') @rtlFiles (Join-Path $PSScriptRoot 'tb_car_action_transport.sv') --sv -log 'compile.log' *> 'compile_console.log'
    if ($LASTEXITCODE -ne 0) { throw "Transport compile failed: $work\compile_console.log" }
    & (Join-Path $VivadoBin 'xelab.bat') tb_car_action_transport -s transport_snapshot -log 'elaborate.log' *> 'elaborate_console.log'
    if ($LASTEXITCODE -ne 0) { throw "Transport elaborate failed: $work\elaborate_console.log" }
    & (Join-Path $VivadoBin 'xsim.bat') transport_snapshot -runall -log 'run.log' *> 'run_console.log'
    $simExitCode = $LASTEXITCODE
    $log = Get-Content -LiteralPath 'run.log' -Raw
    if ($simExitCode -ne 0 -or $log -notmatch 'PASS ACTION TRANSPORT' -or $log -match '(?im)^\s*(Fatal|ERROR)\b') {
        throw "Transport simulation failed: $work\run.log"
    }
    Get-Content -LiteralPath 'run.log' | Select-String 'PASS|Fatal|ERROR'
} finally { Pop-Location }
