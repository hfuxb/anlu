param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin',[string[]]$Only=@())
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$src=Join-Path $project 'fpga\traffic_sign_td\user_source\image\stream'
& python (Join-Path $PSScriptRoot 'generate_vectors.py')
if($LASTEXITCODE -ne 0){throw 'Vector generation failed'}
$tests=@('tb_extra_modes','tb_motion_full720','tb_isp_modes')
foreach($name in $tests){
 if($Only.Count -gt 0 -and $name -notin $Only){continue}
 $work=Join-Path $PSScriptRoot ('work\'+$name)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  $files=@("$src\dehaze_stream_96.v","$src\motion_stream_96.v","$src\image_extra_modes_96.v")
  if($name -eq 'tb_isp_modes'){$files+=@("$src\image_process_stream_96.v",(Join-Path $project 'fpga\traffic_sign_td\user_source\image\integration\isp_top.v'),(Join-Path $project 'fpga\traffic_sign_td\user_source\lab_ex_2026_nosoft\hdl_source\isp\data96_128\data96_128.v'))}
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
