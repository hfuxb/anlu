param([string]$TdRunPath='D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\run.exe')
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
$previousStage=$env:CAR_TD_START_STAGE
$exitCode=$null
try {
 $env:CAR_TD_START_STAGE='all'
 Push-Location -LiteralPath $PSScriptRoot
 try {
  $script=Join-Path $PSScriptRoot 'build_bit.tcl'
  $process=Start-Process -FilePath $TdRunPath -ArgumentList ('"'+$script+'"') -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $PSScriptRoot 'td_tracking_stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'td_tracking_stderr.log')
  $exitCode=$process.ExitCode
 }finally{Pop-Location}
}finally{$env:CAR_TD_START_STAGE=$previousStage}
if($exitCode -ne 0){throw "TD exited with code $exitCode"}
$markers=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'td_bit\stages_all.log') -Raw
if($markers -notmatch 'CAR_BIT_BUILD_OK' -or $markers -match 'CAR_BIT_BUILD_FAILED'){throw 'TD build incomplete'}
$bit=Join-Path $package 'fpga\traffic_sign_td\td_project\bitstream\traffic_sign_td_lr_tracking_lock.bit'
Get-Item -LiteralPath $bit | Select-Object FullName,Length,LastWriteTime
Get-FileHash -LiteralPath $bit -Algorithm SHA256
