param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hdl=Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source'
$work=Join-Path $PSScriptRoot 'work\tb_osd_font'
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location -LiteralPath $work
try{
 & "$VivadoBin\xvlog.bat" "$hdl\osd_char_lib.v" (Join-Path $PSScriptRoot 'tb_osd_font.sv') --sv -log compile.log *> compile_console.log
 if($LASTEXITCODE -ne 0){throw 'Font compile failed'}
 & "$VivadoBin\xelab.bat" tb_osd_font -s snapshot -timescale '1ns/1ps' -log elaborate.log *> elaborate_console.log
 if($LASTEXITCODE -ne 0){throw 'Font elaborate failed'}
 & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
 $log=Get-Content -LiteralPath run.log -Raw
 if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS OSD uniform font'){throw 'Font simulation failed'}
 Write-Output ($log -split "`n" | Where-Object {$_ -match 'PASS OSD uniform font'})
}finally{Pop-Location}
