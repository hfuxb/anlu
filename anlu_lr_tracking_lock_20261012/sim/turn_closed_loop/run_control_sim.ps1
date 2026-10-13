param([string]$VivadoBin='D:\Xilinx\Vivado\2019.2\bin',[string[]]$Only=@())
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$rtl=@(Get-ChildItem -LiteralPath (Join-Path $project 'rtl') -Filter '*.v' | Sort-Object Name | ForEach-Object {$_.FullName})
foreach($name in @('tb_action_decision','tb_action_control')){
 if($Only.Count -gt 0 -and $name -notin $Only){continue}
 $work=Join-Path $PSScriptRoot ('work\'+$name)
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 Push-Location -LiteralPath $work
 try{
  & "$VivadoBin\xvlog.bat" @rtl (Join-Path $PSScriptRoot ($name+'.sv')) --sv -log compile.log *> compile_console.log
  if($LASTEXITCODE -ne 0){throw "Compile failed $name"}
  & "$VivadoBin\xelab.bat" $name -s snapshot -log elaborate.log *> elaborate_console.log
  if($LASTEXITCODE -ne 0){throw "Elaborate failed $name"}
  & "$VivadoBin\xsim.bat" snapshot -runall -log run.log *> run_console.log
  $log=Get-Content -LiteralPath run.log -Raw
  if($LASTEXITCODE -ne 0 -or $log -notmatch 'PASS' -or $log -match '(?im)^\s*(Fatal:|ERROR:|FAIL)'){throw "Simulation failed $name"}
  Copy-Item -LiteralPath run.log -Destination (Join-Path $project ('reports\'+$name+'.log')) -Force
  Get-Content -LiteralPath run.log | Select-String 'PASS'
 }finally{Pop-Location}
}
