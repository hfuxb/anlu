param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work=Join-Path $PSScriptRoot 'work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try {
    $awb=Join-Path $project 'fpga\traffic_sign_td\user_source\image\awb\active\awb.v'
    $tb=Join-Path $PSScriptRoot 'tb_awb_grayworld.sv'
    & (Join-Path $VivadoBin 'xvlog.bat') $awb $tb --sv -log compile.log *> compile_console.log
    if ($LASTEXITCODE -ne 0) { throw 'AWB compile failed; see sim/awb/work/compile_console.log' }
    & (Join-Path $VivadoBin 'xelab.bat') tb_awb_grayworld -s snapshot -log elaborate.log *> elaborate_console.log
    if ($LASTEXITCODE -ne 0) { throw 'AWB elaboration failed; see sim/awb/work/elaborate_console.log' }
    & (Join-Path $VivadoBin 'xsim.bat') snapshot -runall -log run.log *> run_console.log
    if ($LASTEXITCODE -ne 0 -or
        (Get-Content -LiteralPath run.log -Raw) -notmatch 'PASS AWB frame-based gray-world control') {
        throw 'AWB simulation failed; see sim/awb/work/run.log'
    }
    Write-Output 'PASS AWB frame-based gray-world control'
} finally {
    Pop-Location
}
