$ErrorActionPreference = "Stop"
$src = "D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation\Core\App\Signal\app_signal_detect.c"
$bak = "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\56_carrier_lock_error_20260507_014652\backups\app_signal_detect.c.bak_before_lockerr"
Copy-Item -LiteralPath $bak -Destination $src -Force
Write-Host "restored app_signal_detect.c from pre-lockerr backup"
