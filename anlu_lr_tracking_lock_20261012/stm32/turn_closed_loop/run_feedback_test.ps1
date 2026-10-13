param([string]$Gcc = 'D:\Xilinx\Vivado\2019.2\tps\win64\msys64\mingw64\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
$testDir = $PSScriptRoot
$projectDir = (Resolve-Path (Join-Path $testDir '..\..')).Path
$firmwareDir = Join-Path $projectDir 'stm32\WHEELTEC_C50X_FPGA_PD89'
$stubDir = Join-Path $testDir 'feedback_stub'
$testExe = Join-Path $testDir 'test_fpga_feedback.exe'
$reportDir = Join-Path $projectDir 'reports'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$logPath = Join-Path $reportDir 'test_fpga_feedback.log'
$env:PATH = (Split-Path $Gcc) + ';' + $env:PATH
$compileArguments = @('-std=c99','-O2','-Wall','-Wextra','-Wno-unused-function',
    '-I', $stubDir, '-I', (Join-Path $firmwareDir 'BALANCE\Inc'),
    '-I', (Join-Path $firmwareDir 'HARDWARE\MPU6050'),
    '-I', (Join-Path $firmwareDir 'HARDWARE\ICM20948'),
    '-I', (Join-Path $firmwareDir 'HARDWARE\Inc'),
    (Join-Path $firmwareDir 'BALANCE\fpga_turn_feedback.c'),
    (Join-Path $testDir 'test_fpga_feedback.c'), '-lm','-o',$testExe)
$compileOutput = & $Gcc @compileArguments 2>&1
Set-Content -LiteralPath $logPath -Value ($compileOutput -join "`n") -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw "Checked gyro test compile failed: $compileOutput" }
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $firmwareDir 'BALANCE\fpga_turn_feedback.c')).Hash
"SOURCE_SHA256=$sourceHash" | Add-Content -LiteralPath $logPath -Encoding utf8
"HOST_TEST_SCOPE=Production fpga_turn_feedback.c; unmodified vendor register headers; mocked register/ACK/time/platform dependencies" |
    Add-Content -LiteralPath $logPath -Encoding utf8
$scenarios = @('healthy','insufficient','no_drdy_calibration','freshness','id','range','sleep',
    'variance','moving_reset','excess_bias_reset','startup_moving','saturation','unknown')
$totalCases = 0
foreach ($model in @(0,1)) {
    $countOutput = & $testExe $model count_ack 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ACK discovery failed: $countOutput" }
    $countOutput | Add-Content -LiteralPath $logPath -Encoding utf8
    $ackCount = [int]([regex]::Match(($countOutput -join "`n"),'ACK_COUNT=(\d+)').Groups[1].Value)
    if ($ackCount -lt 1) { throw 'Invalid ACK discovery result' }
    foreach ($scenario in $scenarios) {
        $output = & $testExe $model $scenario 2>&1
        $output | Add-Content -LiteralPath $logPath -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Checked gyro scenario failed: $model $scenario $output" }
        ++$totalCases
    }
    for ($ackIndex = 1; $ackIndex -le $ackCount; ++$ackIndex) {
        $output = & $testExe $model nack $ackIndex 2>&1
        $output | Add-Content -LiteralPath $logPath -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Checked gyro NACK scenario failed: $model ACK $ackIndex $output" }
        ++$totalCases
    }
    $startupOutput = & $testExe $model count_startup_ack 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Startup ACK discovery failed: $startupOutput" }
    $startupOutput | Add-Content -LiteralPath $logPath -Encoding utf8
    $startupAckCount = [int]([regex]::Match(($startupOutput -join "`n"),'ACK_COUNT=(\d+)').Groups[1].Value)
    if ($startupAckCount -lt $ackCount) { throw 'Invalid startup ACK discovery result' }
    for ($ackIndex = 1; $ackIndex -le $startupAckCount; ++$ackIndex) {
        $output = & $testExe $model nack_calibration $ackIndex 2>&1
        $output | Add-Content -LiteralPath $logPath -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "Calibration NACK scenario failed: $model ACK $ackIndex $output" }
        ++$totalCases
    }
}
"PASS CHECKED GYRO SUITE: $totalCases scenarios; actual firmware adapter compiled and executed" |
    Tee-Object -FilePath $logPath -Append
