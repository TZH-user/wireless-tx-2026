$ErrorActionPreference = "Stop"
$Api = "http://127.0.0.1:8765"
$Dg = 1; $ScopeCh = 2
$Prog = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"; $ScopeDir = Join-Path $Root "scope"
New-Item -ItemType Directory -Force -Path $LogDir,$ScopeDir | Out-Null

function ag($p){ Invoke-RestMethod "$Api$p" -TimeoutSec 20 }
function ap($p,$b){ $j=$b|ConvertTo-Json -Depth 10 -Compress; Invoke-RestMethod -Method Post -Uri "$Api$p" -ContentType "application/json; charset=utf-8" -Body $j -TimeoutSec 25 }
function ss(){ try{ap "/api/raw/write" @{command=":SOUR${Dg}:MOD OFF"}|Out-Null}catch{}; try{ap "/api/channel/$Dg/output" @{enabled=$false}|Out-Null}catch{} }
function ser(){
    $s=ag "/api/serial/status"
    if((-not $s.connected) -or ($s.settings.port -ne "COM15")){try{ap "/api/serial/disconnect" @{}|Out-Null}catch{}; Start-Sleep -Milliseconds 300; ap "/api/serial/connect" @{port="COM15";baudrate=115200;bytesize=8;parity="None";stopbits="1";timeout=0.05;log_rx=$true}|Out-Null}
}
function sc($hz,$vpp){ ap "/api/channel/$Dg/apply" @{waveform="SIN";frequency=[double]$hz;amplitude=[double]$vpp;offset=0.0;phase=0.0;unit="VPP";impedance_mode="HIGHZ"}|Out-Null; ap "/api/channel/$Dg/output" @{enabled=$true}|Out-Null }
function sm($c){
    if($c.type -eq "CW"){ap "/api/raw/write" @{command=":SOUR${Dg}:MOD OFF"}|Out-Null; return}
    $b=@{mod_type=$c.type;enabled=$true;source="INT";internal_function="SIN";rate_hz=[double]$c.rate_hz}
    if($c.type-eq"AM"){$b.depth_percent=[double]$c.depth_percent}elseif($c.type-eq"FM"){$b.deviation=[double]$c.deviation_hz}elseif($c.type-eq"ASK"){$b.amplitude_vpp=[double]$c.ask_low_vpp;$b.polarity="POS"}elseif($c.type-eq"FSK"){$b.hop_frequency_hz=[double]$c.hop_frequency_hz;$b.polarity="POS"}elseif($c.type-eq"PSK"){$b.phase_deg=[double]$c.phase_deg;$b.polarity="POS"}
    ap "/api/channel/$Dg/modulation" $b|Out-Null
}
function rst(){ & $Prog -c port=SWD mode=UR reset=HWrst -rst|Out-Null }
function el($p){
    $r=ap "/api/logs/export" @{mode="merged"}
    if($r.file_path -and (Test-Path $r.file_path)){$d=Join-Path $LogDir ($p+"_"+[IO.Path]::GetFileName($r.file_path));Copy-Item $r.file_path $d -Force; return $d}
    return $null
}
function es($p){
    $r=ap "/api/scope/waveform/export" @{channel=$ScopeCh;points=20000}
    if($r.file_path -and (Test-Path $r.file_path)){$d=Join-Path $ScopeDir ($p+"_scope.csv");Copy-Item $r.file_path $d -Force; return $d}
    return $null
}

function Get-ScopeVpp($csvPath){
    if(-not (Test-Path $csvPath)){ return @{vmax=$null;vmin=$null;vpp=$null;vavg=$null} }
    $data = Import-Csv $csvPath
    $vals = @($data | ForEach-Object { [double]$_.Voltage } | Where-Object { $_ -ne $null })
    if($vals.Count -eq 0){ return @{vmax=$null;vmin=$null;vpp=$null;vavg=$null} }
    $vmax = [math]::Round(($vals|Measure-Object -Maximum).Maximum, 3)
    $vmin = [math]::Round(($vals|Measure-Object -Minimum).Minimum, 3)
    $vpp = [math]::Round($vmax - $vmin, 3)
    $vavg = [math]::Round(($vals|Measure-Object -Average).Average, 3)
    return @{vmax=$vmax;vmin=$vmin;vpp=$vpp;vavg=$vavg}
}

function Parse-AdcRange($logPath){
    $lines = Get-Content -LiteralPath $logPath -Encoding UTF8
    $fw = @($lines|Where-Object{$_-match'fw_id,adc_range'})
    $sig = @($lines|Where-Object{$_-match'sigdet_final'})
    $adcs = @($lines|Where-Object{$_-match'\[RX\] adc_range,'})

    $imin=0;$imax=0;$qmin=0;$qmax=0;$ivpp=0;$qvpp=0
    $iclo=0;$ichi=0;$qclo=0;$qchi=0;$inlo=0;$inhi=0;$qnlo=0;$qnhi=0

    foreach($a in $adcs){
        if($a -match 'imin=(\d+)'){[uint32]::TryParse($matches[1],[ref]$imin)|Out-Null}
        if($a -match 'imax=(\d+)'){[uint32]::TryParse($matches[1],[ref]$imax)|Out-Null}
        if($a -match 'qmin=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qmin)|Out-Null}
        if($a -match 'qmax=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qmax)|Out-Null}
        if($a -match 'ivpp=(\d+)'){[uint32]::TryParse($matches[1],[ref]$ivpp)|Out-Null}
        if($a -match 'qvpp=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qvpp)|Out-Null}
        if($a -match 'iclo=(\d+)'){[uint32]::TryParse($matches[1],[ref]$iclo)|Out-Null}
        if($a -match 'ichi=(\d+)'){[uint32]::TryParse($matches[1],[ref]$ichi)|Out-Null}
        if($a -match 'qclo=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qclo)|Out-Null}
        if($a -match 'qchi=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qchi)|Out-Null}
        if($a -match 'inlo=(\d+)'){[uint32]::TryParse($matches[1],[ref]$inlo)|Out-Null}
        if($a -match 'inhi=(\d+)'){[uint32]::TryParse($matches[1],[ref]$inhi)|Out-Null}
        if($a -match 'qnlo=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qnlo)|Out-Null}
        if($a -match 'qnhi=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qnhi)|Out-Null}
    }
    # Use the last adc_range line (most recent, post-lock)
    if($adcs.Count -gt 0){
        $last=$adcs[-1]
        if($last -match 'imin=(\d+)'){[uint32]::TryParse($matches[1],[ref]$imin)|Out-Null}
        if($last -match 'imax=(\d+)'){[uint32]::TryParse($matches[1],[ref]$imax)|Out-Null}
        if($last -match 'qmin=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qmin)|Out-Null}
        if($last -match 'qmax=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qmax)|Out-Null}
        if($last -match 'ivpp=(\d+)'){[uint32]::TryParse($matches[1],[ref]$ivpp)|Out-Null}
        if($last -match 'qvpp=(\d+)'){[uint32]::TryParse($matches[1],[ref]$qvpp)|Out-Null}
    }
    $sigStr = if($sig.Count -gt 0){$sig[-1]}else{''}
    $locked = $sigStr -match 'locked=1'
    $estHz = if($sigStr -match 'estimated_carrier=(\d+)'){[int]$matches[1]}else{0}

    return @{
        fw_found=($fw.Count -gt 0); sig_locked=$locked; sig_est_hz=$estHz
        adc_lines=$adcs.Count; imin=$imin; imax=$imax; ivpp=$ivpp; qmin=$qmin; qmax=$qmax; qvpp=$qvpp
        iclo=$iclo; ichi=$ichi; qclo=$qclo; qchi=$qchi; inlo=$inlo; inhi=$inhi; qnlo=$qnlo; qnhi=$qnhi
    }
}

$cases = @(
    @{id="A1_CW_40M_0p5VPP"; hz=40000000; vpp=0.5; type="CW"}
    @{id="A2_CW_40M_1p0VPP"; hz=40000000; vpp=1.0; type="CW"}
    @{id="A3_CW_40M_1p5VPP"; hz=40000000; vpp=1.5; type="CW"}
    @{id="A4_CW_40M_2p0VPP"; hz=40000000; vpp=2.0; type="CW"}
)

Write-Host "=== ADC+Scope CW Matrix ==="
ser
$rows = @(); $idx = 0; $abort = $false
try {
    foreach($c in $cases){
        if($abort){ Write-Host "ABORTING: over-voltage detected in previous case"; break }
        $idx++; $name = "D{0:D2}_{1}" -f $idx, $c.id
        Write-Host "[$idx/$($cases.Count)] $name (RF=$($c.vpp)VPP)"
        sc $c.hz ([double]$c.vpp); sm $c
        ap "/api/serial/logs/clear" @{}|Out-Null
        rst; Start-Sleep 10

        $scopeCSV = es $name
        $logPath = el $name
        $sv = Get-ScopeVpp $scopeCSV
        $adc = Parse-AdcRange $logPath

        # Safety check: if scope Vmax > 3.3V on ADC pin, abort
        $overVoltage = $false
        if($sv.vmax -and [double]$sv.vmax -gt 3.3){ $overVoltage = $true; $abort = $true }
        if($sv.vmin -and [double]$sv.vmin -lt 0.0){ $overVoltage = $true; $abort = $true }

        $rows += [pscustomobject]@{
            case_id=$name; rf_mhz=40; rf_vpp=$c.vpp; mod="CW"
            scope_vmax=$sv.vmax; scope_vmin=$sv.vmin; scope_vpp=$sv.vpp; scope_vavg=$sv.vavg
            adc_imin=$adc.imin; adc_imax=$adc.imax; adc_ivpp=$adc.ivpp
            adc_qmin=$adc.qmin; adc_qmax=$adc.qmax; adc_qvpp=$adc.qvpp
            adc_iclo=$adc.iclo; adc_ichi=$adc.ichi; adc_qclo=$adc.qclo; adc_qchi=$adc.qchi
            adc_inlo=$adc.inlo; adc_inhi=$adc.inhi; adc_qnlo=$adc.qnlo; adc_qnhi=$adc.qnhi
            sig_locked=$adc.sig_locked; sig_est_hz=$adc.sig_est_hz
            fw_found=$adc.fw_found; adc_lines=$adc.adc_lines
            over_voltage=$overVoltage; log_path=$logPath; scope_file=$scopeCSV
        }
    }
} finally { ss }

$rows | Export-Csv (Join-Path $Root "01_scope_adc_cw_matrix.csv") -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "=== Results ==="
$rows | Format-Table case_id,rf_vpp,scope_vmax,scope_vmin,scope_vpp,adc_imin,adc_imax,adc_ivpp,qmin,qmax,qvpp,over_voltage -AutoSize
Write-Host ""
if($abort){ Write-Host "!!! OVER-VOLTAGE DETECTED !!!" }else{ Write-Host "No over-voltage detected in CW sweep" }
