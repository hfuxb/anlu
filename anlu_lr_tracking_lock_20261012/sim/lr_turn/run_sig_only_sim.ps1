param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source=Join-Path $project 'fpga\traffic_sign_td\user_source\image\traffic_sign'
$work=Join-Path $PSScriptRoot 'work_sig_only'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try{
 & "$VivadoBin\xvlog.bat" (Join-Path $source 'traffic_sign_detector_96.v') (Join-Path $source 'traffic_sign_result_cdc.v') (Join-Path $PSScriptRoot 'tb_sig_only.sv') --sv -log compile.log *> compile_console.log
 if($LASTEXITCODE -ne 0){throw 'SIG-only compile failed'}
 & "$VivadoBin\xelab.bat" tb_sig_only -s snapshot -log elaborate.log *> elaborate_console.log
 if($LASTEXITCODE -ne 0){throw 'SIG-only elaborate failed'}
 & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
 $log=Get-Content -LiteralPath run.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS SIG ONLY detector' -or $log -match '(?im)^\s*(Fatal|ERROR|FAIL)'){throw 'SIG-only simulation failed'}
 Get-Content -LiteralPath run.log | Select-String 'event=|PASS|Fatal'
}finally{Pop-Location}
