param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin',[string[]]$Only=@())
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hdl=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source'
foreach($test in @('tb_coordinate_hdmi','tb_coordinate_latch')){
if($Only.Count -gt 0 -and $test -notin $Only){continue}
$work=Join-Path $PSScriptRoot ('work\'+$test)
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try{
 $files=@("$hdl\vtc\uivtc.v","$hdl\hdmi_mixer.v","$hdl\video_latency_display.v","$hdl\anlogic_logo_rom.v","$hdl\osd_char_lib.v",(Join-Path $PSScriptRoot ($test+'.sv')))
 & "$VivadoBin\xvlog.bat" @files --sv -log compile.log *> compile_console.log
 if($LASTEXITCODE -ne 0){throw "Coordinate compile failed: $work"}
 & "$VivadoBin\xelab.bat" $test -s snapshot -log elaborate.log *> elaborate_console.log
 if($LASTEXITCODE -ne 0){throw "Coordinate elaborate failed: $work"}
 & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
 $log=Get-Content -LiteralPath run.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS COORDINATE' -or $log -match '(?im)^\s*(Fatal:|ERROR:|FAIL)'){throw "Coordinate simulation failed: $work"}
 Copy-Item -LiteralPath run.log -Destination (Join-Path $project ('reports\'+$test+'.log')) -Force
 Write-Output ('PASS '+$test)
}finally{Pop-Location}
}
