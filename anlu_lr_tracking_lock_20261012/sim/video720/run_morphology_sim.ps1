param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$rtl=Join-Path $project 'fpga\traffic_sign_td\user_source\image\stream\image_process_stream_96.v'
foreach($test in @('tb_morphology_opening','tb_image_process_stream_96_full')){
 $work=Join-Path $PSScriptRoot ('work\'+$test)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  $packer=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source\isp\data96_128\data96_128.v'
  & "$VivadoBin\xvlog.bat" $rtl $packer --sv (Join-Path $PSScriptRoot ($test+'.sv')) -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw "$test compile failed"}
  & "$VivadoBin\xelab.bat" $test -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw "$test elaborate failed"}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $log=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch '(PASS MORPHOLOGY OPENING|FULL FRAME STREAM TEST PASSED)' -or $log -match '(?im)^\s*(Fatal|ERROR|\[FAIL\])'){throw "$test simulation failed"}
  Copy-Item -LiteralPath run.log -Destination (Join-Path $project ('reports\'+$test+'_720p.log')) -Force
  Get-Content -LiteralPath run.log | Select-String 'PASS|RESULT'
 }finally{Pop-Location}
}
