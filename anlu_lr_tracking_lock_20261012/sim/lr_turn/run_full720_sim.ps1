param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work=Join-Path $PSScriptRoot 'work_full720'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try {
    $rtl=Join-Path $project 'fpga\traffic_sign_td\user_source\image\traffic_sign\traffic_sign_detector_96.v'
    & (Join-Path $VivadoBin 'xvlog.bat') $rtl (Join-Path $PSScriptRoot 'tb_lr_full720.sv') --sv -log compile.log *> compile_console.log
    if($LASTEXITCODE -ne 0){throw 'LR compilation failed'}
    & (Join-Path $VivadoBin 'xelab.bat') tb_lr_full720 -s snapshot -log elaborate.log *> elaborate_console.log
    if($LASTEXITCODE -ne 0){throw 'LR elaboration failed'}
    & (Join-Path $VivadoBin 'xsim.bat') snapshot -runall -log run.log *> run_console.log
    if($LASTEXITCODE -ne 0 -or (Get-Content run.log -Raw) -notmatch 'PASS LR real-sign') {throw 'LR simulation failed'}
    Get-Content -LiteralPath run.log | Select-String 'CASE|result|PASS|FAIL'
}finally{Pop-Location}

