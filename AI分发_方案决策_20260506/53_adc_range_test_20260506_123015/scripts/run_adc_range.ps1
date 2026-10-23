$ErrorActionPreference = "Stop"
$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$Prog = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function ApiGet($p){ Invoke-RestMethod -Method Get -Uri "$Api$p" -TimeoutSec 20 }
function ApiPost($p,$b){ $j=$b|ConvertTo-Json -Depth 10 -Compress; Invoke-RestMethod -Method Post -Uri "$Api$p" -ContentType "application/json; charset=utf-8" -Body $j -TimeoutSec 25 }
function SafeStop(){ try{ApiPost "/api/raw/write" @{command=":SOUR${DgChannel}:MOD OFF"}|Out-Null}catch{}; try{ApiPost "/api/channel/$DgChannel/output" @{enabled=$false}|Out-Null}catch{} }

function EnsureSerial(){
    $s=ApiGet "/api/serial/status"
    if((-not $s.connected) -or ($s.settings.port -ne "COM15")){
        try{ApiPost "/api/serial/disconnect" @{}|Out-Null}catch{}
        Start-Sleep -ms 300
        ApiPost "/api/serial/connect" @{port="COM15";baudrate=115200;bytesize=8;parity="None";stopbits="1";timeout=0.05;log_rx=$true}|Out-Null
    }
}

function SetCarrier($hz,$vpp){
    ApiPost "/api/channel/$DgChannel/apply" @{waveform="SIN";frequency=[double]$hz;amplitude=[double]$vpp;offset=0.0;phase=0.0;unit="VPP";impedance_mode="HIGHZ"}|Out-Null
    ApiPost "/api/channel/$DgChannel/output" @{enabled=$true}|Out-Null
}

function SetMod($c){
    if($c.type -eq "CW"){ ApiPost "/api/raw/write" @{command=":SOUR${DgChannel}:MOD OFF"}|Out-Null; return }
    $b=@{mod_type=$c.type;enabled=$true;source="INT";internal_function="SIN";rate_hz=[double]$c.rate_hz}
    if($c.type-eq"AM"){$b.depth_percent=[double]$c.depth_percent}
    elseif($c.type-eq"FM"){$b.deviation=[double]$c.deviation_hz}
    elseif($c.type-eq"ASK"){$b.amplitude_vpp=[double]$c.ask_low_vpp;$b.polarity="POS"}
    elseif($c.type-eq"FSK"){$b.hop_frequency_hz=[double]$c.hop_frequency_hz;$b.polarity="POS"}
    elseif($c.type-eq"PSK"){$b.phase_deg=[double]$c.phase_deg;$b.polarity="POS"}
    ApiPost "/api/channel/$DgChannel/modulation" $b|Out-Null
}

function ResetMcu(){ & $Prog -c port=SWD mode=UR reset=HWrst -rst | Out-Null }

function ExportLog($prefix){
    $r=ApiPost "/api/logs/export" @{mode="merged"}
    if($r.file_path -and (Test-Path $r.file_path)){
        $dst=Join-Path $LogDir ($prefix+"_"+[System.IO.Path]::GetFileName($r.file_path))
        Copy-Item $r.file_path $dst -Force; return $dst
    }
    return $null
}

function ParseCase($logPath){
    $lines=Get-Content -LiteralPath $logPath -Encoding UTF8
    $fw=@($lines|Where-Object{$_-match'fw_id,adc_range'})
    $sig=@($lines|Where-Object{$_-match'sigdet_final'})
    $adc=@($lines|Where-Object{$_-match'adc_range,'})
    return @{
        fw_found=($fw.Count -gt 0)
        sig_found=($sig.Count -gt 0)
        adc_lines=$adc.Count
        adc_samples=($adc|ForEach-Object{if($_-match'n=(\d+)'){[long]$matches[1]}else{0}}|Measure-Object -Sum).Sum
    }
}

# === Stage 5.1: CW amplitude sweep ===
Write-Host "=== 5.1 CW Amplitude Sweep 40MHz ==="
EnsureSerial
$results51=@()
$idx=0
try{
    foreach($vpp in @(0.2,0.4,0.6,0.8,1.0,1.2,1.4,1.6,1.8,2.0)){
        $idx++
        $name=("{0:D2}_CW_40M_v{1:F1}VPP" -f $idx,$vpp) -replace '\.','p'
        Write-Host "[$idx/10] $name"
        SetCarrier 40000000 $vpp
        SetMod @{type="CW"}
        ApiPost "/api/serial/logs/clear" @{}|Out-Null
        ResetMcu
        Start-Sleep 10
        $lp=ExportLog $name
        $s=ParseCase $lp
        $results51+=[pscustomobject]@{case_id=$name;rf_vpp=$vpp;carrier_mhz=40;mod="CW";fw_found=$s.fw_found;sig_found=$s.sig_found;adc_lines=$s.adc_lines;adc_samples=$s.adc_samples;log=$lp}
    }
} finally { SafeStop }

$results51|Export-Csv (Join-Path $Root "01_cw_amplitude_sweep.csv") -NoTypeInformation -Encoding UTF8
$results51|Format-Table case_id,rf_vpp,fw_found,sig_found,adc_lines -AutoSize
