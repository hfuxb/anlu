param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin',[string[]]$Only=@())
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src=Join-Path $project 'fpga\traffic_sign_td\user_source\image\stream'
$hdl=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source'
if($Only.Count -eq 0 -or 'tb_enhance' -in $Only){
 & python -X utf8 (Join-Path $PSScriptRoot 'generate_enhance_vectors.py')
 if($LASTEXITCODE -ne 0){throw 'Enhancement reference generation failed'}
}
foreach($name in @('tb_enhance','tb_environment','tb_override','tb_auto_recognition','tb_path_hdmi','tb_environment_full720')){
 if($Only.Count -gt 0 -and $name -notin $Only){continue}
 $work=Join-Path $PSScriptRoot ('work\'+$name)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  $files=@("$src\dehaze_enhance_96.v","$src\recognition_environment_96.v","$hdl\recognition_override_button.v")
  if($name -eq 'tb_auto_recognition'){$files+=@("$src\dehaze_stream_96.v",(Join-Path $project 'fpga\traffic_sign_td\user_source\image\traffic_sign\traffic_sign_detector_96.v'))}
  if($name -eq 'tb_path_hdmi'){$files+=@("$hdl\hdmi_mixer.v","$hdl\video_latency_display.v","$hdl\vtc\uivtc.v","$hdl\osd_char_lib.v","$hdl\anlogic_logo_rom.v")}
  & "$VivadoBin\xvlog.bat" @files (Join-Path $PSScriptRoot ($name+'.sv')) --sv -i $work -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw "Compile failed $name"}
  & "$VivadoBin\xelab.bat" $name -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw "Elaborate failed $name"}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $log=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS' -or $log -match '(?im)^\s*(Fatal:|ERROR:|FAIL)'){throw "Test failed $name"}
  Copy-Item -LiteralPath run.log -Destination (Join-Path $project ('reports\'+$name+'.log')) -Force
  Get-Content -LiteralPath run.log | Select-String 'PASS'
 }finally{Pop-Location}
}
