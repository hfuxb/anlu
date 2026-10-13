param([string]$GccBin='D:\Xilinx\Vivado\2019.2\tps\win64\msys64\mingw64\bin')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$oldPath=$env:PATH
try {
 $env:PATH=$GccBin+';'+$env:PATH
 Push-Location -LiteralPath $root
 try {
  foreach($kind in @('turn','owner')){
   $flags=@('-std=c99','-Wall','-Wextra','-Werror')
   if($kind -eq 'turn'){$flags+=@('-DFPGA_TURN_HOST_TEST')}
   else{$flags+=@('-I','stm32/turn_closed_loop/controller_stub')}
   $exe='stm32/turn_closed_loop/test_fpga_'+$kind+'.exe'
   & "$GccBin\gcc.exe" @flags -I stm32/WHEELTEC_C50X_FPGA_PD89/BALANCE/Inc stm32/WHEELTEC_C50X_FPGA_PD89/BALANCE/fpga_turn.c ('stm32/turn_closed_loop/test_fpga_'+$kind+'.c') -lm -o $exe
   if($LASTEXITCODE -ne 0){throw "C compile failed: $kind"}
   & (Join-Path $root $exe) | Tee-Object -FilePath ('reports/test_fpga_'+$kind+'.log')
   if($LASTEXITCODE -ne 0){throw "C test failed: $kind"}
  }
 }finally {Pop-Location}
}finally{$env:PATH=$oldPath}
