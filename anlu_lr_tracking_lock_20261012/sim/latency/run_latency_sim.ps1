param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin',[string[]]$Only=@())
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hdl=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source'
$tests=@(
 @{Name='tb_video_latency';Files=@("$hdl\video_latency.v","$hdl\video_in.v","$hdl\video_out.v");Marker='PASS VIDEO LATENCY'},
 @{Name='tb_latency_hdmi';Files=@("$hdl\video_latency.v","$hdl\video_latency_display.v","$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v");Marker='PASS LATENCY HDMI'},
 @{Name='tb_latency_hdmi_hold';Source='tb_latency_hdmi';Files=@("$hdl\video_latency.v","$hdl\video_latency_display.v","$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v");Marker='PASS LATENCY HDMI HOLD'}
)
foreach($test in $tests){
 if($Only.Count -gt 0 -and $test.Name -notin $Only){continue}
 $work=Join-Path $PSScriptRoot ('work\'+$test.Name)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  $sourceName=if($test.ContainsKey('Source')){$test.Source}else{$test.Name}
  & "$VivadoBin\xvlog.bat" @($test.Files) (Join-Path $PSScriptRoot ($sourceName+'.sv')) --sv -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw "Compile failed: $work"}
  & "$VivadoBin\xelab.bat" $test.Name -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw "Elaborate failed: $work"}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $log=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch $test.Marker -or $log -match '(?im)^\s*(Fatal:|ERROR:|FAIL)'){throw "Simulation failed: $work"}
  Copy-Item -LiteralPath run.log -Destination (Join-Path $project ('reports\'+$test.Name+'.log')) -Force
  Write-Output $test.Marker
 }finally{Pop-Location}
}
