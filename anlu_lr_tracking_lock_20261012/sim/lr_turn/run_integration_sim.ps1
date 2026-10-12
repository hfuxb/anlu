param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source=Join-Path $project 'fpga\traffic_sign_td\user_source'
$hdl=Join-Path $source 'lab_ex_2026_nosoft\hdl_source'
$tests=@(
 @{Name='tb_lr_metadata';Files=@("$source\image\traffic_sign\traffic_sign_result_cdc.v");Marker='PASS LR metadata CDC'},
 @{Name='tb_lr_hdmi';Files=@("$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v");Marker='PASS LR HDMI'}
)
foreach($test in $tests){
 $work=Join-Path $PSScriptRoot ('work\'+$test.Name)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  & "$VivadoBin\xvlog.bat" @($test.Files) (Join-Path $PSScriptRoot ($test.Name+'.sv')) --sv -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw ('Compile failed '+$test.Name)}
  & "$VivadoBin\xelab.bat" $test.Name -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw ('Elaborate failed '+$test.Name)}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $log=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch $test.Marker){throw ('Simulation failed '+$test.Name)}
  Write-Output $test.Marker
 }finally{Pop-Location}
}
