$ErrorActionPreference = "Stop"; $Api = "http://127.0.0.1:8765"; $Dg = 1
$Prog = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$Root = Split-Path -Parent $PSScriptRoot; $LogDir = Join-Path $Root "logs"
function ag($p){Invoke-RestMethod "$Api$p" -TimeoutSec 20}
function ap($p,$b){$j=$b|ConvertTo-Json -Depth 10 -Compress; Invoke-RestMethod -Method Post -Uri "$Api$p" -ContentType "application/json; charset=utf-8" -Body $j -TimeoutSec 25}
function stop(){try{ap "/api/raw/write" @{command=":SOUR${Dg}:MOD OFF"}|Out-Null}catch{}; try{ap "/api/channel/$Dg/output" @{enabled=$false}|Out-Null}catch{}}
function ser(){
    $s=ag "/api/serial/status"
    if((-not $s.connected) -or ($s.settings.port -ne "COM15")){try{ap "/api/serial/disconnect" @{}|Out-Null}catch{}; Start-Sleep -ms 300; ap "/api/serial/connect" @{port="COM15";baudrate=115200;bytesize=8;parity="None";stopbits="1";timeout=0.05;log_rx=$true}|Out-Null}
}
function sc($hz,$vpp){ap "/api/channel/$Dg/apply" @{waveform="SIN";frequency=[double]$hz;amplitude=[double]$vpp;offset=0.0;phase=0.0;unit="VPP";impedance_mode="HIGHZ"}|Out-Null; ap "/api/channel/$Dg/output" @{enabled=$true}|Out-Null}
function sm($c){
    if($c.type -eq "CW"){ap "/api/raw/write" @{command=":SOUR${Dg}:MOD OFF"}|Out-Null; return}
    $b=@{mod_type=$c.type;enabled=$true;source="INT";internal_function="SIN";rate_hz=[double]$c.rate_hz}
    if($c.type-eq"AM"){$b.depth_percent=[double]$c.depth_percent}elseif($c.type-eq"FM"){$b.deviation=[double]$c.deviation_hz}elseif($c.type-eq"ASK"){$b.amplitude_vpp=[double]$c.ask_low_vpp;$b.polarity="POS"}elseif($c.type-eq"FSK"){$b.hop_frequency_hz=[double]$c.hop_frequency_hz;$b.polarity="POS"}elseif($c.type-eq"PSK"){$b.phase_deg=[double]$c.phase_deg;$b.polarity="POS"}
    ap "/api/channel/$Dg/modulation" $b|Out-Null
}
function rst(){& $Prog -c port=SWD mode=UR reset=HWrst -rst|Out-Null}
function el($p){
    $r=ap "/api/logs/export" @{mode="merged"}
    if($r.file_path -and (Test-Path $r.file_path)){$d=Join-Path $LogDir ($p+"_"+[IO.Path]::GetFileName($r.file_path)); Copy-Item $r.file_path $d -Force; return $d}
    return $null
}

# Phase 5.2: Frequency check
Write-Host "=== 5.2 Frequency Check ==="
ser
$r52=@(); $idx=0
try{
    foreach($hz in @(30000000,40000000,50000000)){
        $mhz=[int]($hz/1000000)
        foreach($vpp in @(1.0,1.5,2.0)){
            $idx++; $name="{0:D2}_CW_${mhz}M_v{1:F1}VPP" -f $idx,$vpp -replace '\.','p'
            Write-Host "[5.2 $idx/9] $name"
            sc $hz $vpp; sm @{type="CW"}
            ap "/api/serial/logs/clear" @{}|Out-Null; rst; Start-Sleep 10
            $lp=el $name
            $r52+=[pscustomobject]@{case_id=$name;rf_vpp=$vpp;carrier_mhz=$mhz;log=$lp}
        }
    }
} finally { stop }
$r52|Export-Csv (Join-Path $Root "02_frequency_check.csv") -NoTypeInformation -Encoding UTF8

# Phase 5.3: Modulated peak check
Write-Host "=== 5.3 Modulated Peak Check ==="
ser
$r53=@(); $idx=0
$modes=@(
    @{id="AM";type="AM";rate_hz=10000;depth_percent=50}
    @{id="ASK";type="ASK";rate_hz=10000;ask_low_vpp=0.0}
    @{id="FM";type="FM";rate_hz=10000;deviation_hz=75000}
    @{id="FSK";type="FSK";rate_hz=10000;hop_frequency_hz=40020000}
    @{id="PSK";type="PSK";rate_hz=10000;phase_deg=180}
)
try{
    foreach($vpp in @(1.0,1.5,2.0)){
        foreach($m in $modes){
            $idx++; $name="{0:D2}_{1}_40M_v{2:F1}VPP" -f $idx,$m.id,$vpp -replace '\.','p'
            Write-Host "[5.3 $idx/15] $name"
            sc 40000000 $vpp; sm $m
            ap "/api/serial/logs/clear" @{}|Out-Null; rst; Start-Sleep 10
            $lp=el $name
            $r53+=[pscustomobject]@{case_id=$name;rf_vpp=$vpp;mod=$m.id;log=$lp}
        }
    }
} finally { stop }
$r53|Export-Csv (Join-Path $Root "03_modulated_peak_check.csv") -NoTypeInformation -Encoding UTF8

Write-Host "=== Complete ==="
$r52|Format-Table case_id,rf_vpp -AutoSize
$r53|Format-Table case_id,rf_vpp,mod -AutoSize
