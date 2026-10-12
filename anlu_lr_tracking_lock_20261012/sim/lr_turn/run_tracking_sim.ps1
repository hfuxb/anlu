param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$work=Join-Path $PSScriptRoot 'work_tracking'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try {
 $rtl=Join-Path $project 'fpga\traffic_sign_td\user_source\image\traffic_sign\traffic_sign_detector_96.v'
 & "$VivadoBin\xvlog.bat" $rtl (Join-Path $PSScriptRoot 'tb_lr_tracking.sv') --sv -log compile.log *> compile_console.log
 if($LASTEXITCODE -ne 0){throw 'Tracking compile failed'}
 & "$VivadoBin\xelab.bat" tb_lr_tracking -s snapshot -log elaborate.log *> elaborate_console.log
 if($LASTEXITCODE -ne 0){throw 'Tracking elaborate failed'}
 & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
 $log=Get-Content -LiteralPath run.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS LR tracking lock'){throw 'Tracking simulation failed'}
 Get-Content -LiteralPath run.log | Select-String 'SCENE|frame=|PASS|Fatal'
}finally{Pop-Location}
