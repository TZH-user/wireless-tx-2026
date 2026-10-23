$ErrorActionPreference = "Stop"
$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$SerialPort = "COM15"
$SerialBaud = 115200
$RfVpp = 1.5
$Repeats = 5
$OutDir = "D:\CodexProject\2026年校电赛\AI分发_方案决策_20260506\56_carrier_lock_error_20260507_014652"
$LogDir = Join-Path $OutDir "logs"
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$FineSpanHz = 1200000
$FineStepHz = 50000
$ScanStartHz = 29000000
$ValidStopHz = 50000000

function Invoke-ApiGet($path) {
    Invoke-RestMethod -Uri ($Api + $path) -Method Get
}
function Invoke-ApiPost($path, $body) {
    Invoke-RestMethod -Uri ($Api + $path) -Method Post -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 8)
}
function Safety-Stop {
    try { Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR${DgChannel}:MOD OFF" } | Out-Null } catch {}
    try { Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $false } | Out-Null } catch {}
    try { Invoke-ApiPost "/api/channel/2/output" @{ enabled = $false } | Out-Null } catch {}
}
function Ensure-Serial {
    $st = Invoke-ApiGet "/api/serial/status"
    $curPort = $null
    if ($st.connected -and $st.settings) { $curPort = $st.settings.port }
    if ((-not $st.connected) -or ($curPort -ne $SerialPort)) {
        try { Invoke-ApiPost "/api/serial/disconnect" @{} | Out-Null } catch {}
        Start-Sleep -Milliseconds 300
        Invoke-ApiPost "/api/serial/connect" @{ port=$SerialPort; baudrate=$SerialBaud; bytesize=8; parity="None"; stopbits="1"; timeout=0.05; log_rx=$true } | Out-Null
    }
}
function Set-Cw($hz) {
    if ($RfVpp -gt 1.5) { throw "RF VPP limit exceeded: $RfVpp" }
    Invoke-ApiPost "/api/channel/$DgChannel/apply" @{ waveform="SIN"; frequency=[double]$hz; amplitude=[double]$RfVpp; offset=0.0; phase=0.0; unit="VPP"; impedance_mode="HIGHZ" } | Out-Null
    Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR${DgChannel}:MOD OFF" } | Out-Null
    Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled=$true } | Out-Null
}
function Reset-Mcu {
    & $Programmer -c port=SWD mode=UR reset=HWrst -rst | Out-Null
}
function Export-SerialLog($caseId, $repeatIdx) {
    $r = Invoke-ApiPost "/api/logs/export" @{ mode="serial" }
    $src = $r.file_path
    if (-not $src) { $src = $r.path }
    if (-not $src) { throw "export did not return a path" }
    $dst = Join-Path $LogDir ("{0}_rep{1}.log" -f $caseId, $repeatIdx)
    Copy-Item -LiteralPath $src -Destination $dst -Force
    return $dst
}
function Parse-Log($path) {
    $text = [System.IO.File]::ReadAllText($path)
    $fw = [regex]::Matches($text, 'fw_id,([^\r\n\|]+)') | Select-Object -Last 1
    $fin = [regex]::Matches($text, 'sigdet_final,final_lo=(\d+),est=(\d+),raw=(\d+),corr=(-?\d+),lk=(\d+),ms=(\d+)') | Select-Object -Last 1
    $edge = [regex]::Matches($text, 'sigdet_edge,l=(\d+),r=(\d+),p=(\d+),v=(\d+),t=(\d+),vi=(\d+),pi=(\d+),co=(\d+)') | Select-Object -Last 1
    $obj = [ordered]@{
        fw_id = if($fw){$fw.Groups[1].Value.Trim()}else{""}
        final_lo_hz = if($fin){[uint32]$fin.Groups[1].Value}else{0}
        estimated_carrier_hz = if($fin){[uint32]$fin.Groups[2].Value}else{0}
        raw_estimate_hz = if($fin){[uint32]$fin.Groups[3].Value}else{0}
        correction_hz = if($fin){[int32]$fin.Groups[4].Value}else{0}
        locked = if($fin){[uint32]$fin.Groups[5].Value}else{0}
        lock_ms = if($fin){[uint32]$fin.Groups[6].Value}else{0}
        left_edge_hz = if($edge){[uint32]$edge.Groups[1].Value}else{0}
        right_edge_hz = if($edge){[uint32]$edge.Groups[2].Value}else{0}
        peak_vpp = if($edge){[uint32]$edge.Groups[3].Value}else{0}
        valley_vpp = if($edge){[uint32]$edge.Groups[4].Value}else{0}
        threshold_vpp = if($edge){[uint32]$edge.Groups[5].Value}else{0}
        valley_idx = if($edge){[uint32]$edge.Groups[6].Value}else{0}
        peak_idx = if($edge){[uint32]$edge.Groups[7].Value}else{0}
        coarse_hz = if($edge){[uint32]$edge.Groups[8].Value}else{0}
    }
    return [pscustomobject]$obj
}
function Mean($values) {
    $arr = @($values | Where-Object { $_ -ne $null })
    if ($arr.Count -eq 0) { return "" }
    return [math]::Round((($arr | Measure-Object -Average).Average), 1)
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$rows = New-Object System.Collections.Generic.List[object]
$stratRows = New-Object System.Collections.Generic.List[object]
$cases = @(
    @{ id="A1"; mhz=30; hz=30000000 },
    @{ id="A2"; mhz=35; hz=35000000 },
    @{ id="A3"; mhz=40; hz=40000000 },
    @{ id="A4"; mhz=45; hz=45000000 },
    @{ id="A5"; mhz=50; hz=50000000 }
)

try {
    Ensure-Serial
    foreach($c in $cases) {
        Set-Cw $c.hz
        Start-Sleep -Milliseconds 400
        foreach($rep in 1..$Repeats) {
            Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
            Reset-Mcu
            Start-Sleep -Seconds 4
            $log = Export-SerialLog $c.id $rep
            $p = Parse-Log $log
            $fineStart = [math]::Max($ScanStartHz, [int64]$p.coarse_hz - $FineSpanHz)
            $valleyHz = if($p.coarse_hz -gt 0){ [int64]$fineStart + ([int64]$p.valley_idx * $FineStepHz) } else { 0 }
            $edgeMid = if(($p.left_edge_hz -gt 0) -and ($p.right_edge_hz -gt 0)){ [int64](($p.left_edge_hz + $p.right_edge_hz) / 2) } else { 0 }
            $rows.Add([pscustomobject]@{
                case_id=$c.id; repeat_idx=$rep; rf_mhz=$c.mhz; rf_vpp=$RfVpp; mod="CW";
                final_lo_hz=$p.final_lo_hz; estimated_carrier_hz=$p.estimated_carrier_hz; raw_estimate_hz=$p.raw_estimate_hz; correction_hz=$p.correction_hz;
                left_edge_hz=$p.left_edge_hz; right_edge_hz=$p.right_edge_hz; peak_vpp=$p.peak_vpp; valley_vpp=$p.valley_vpp; threshold_vpp=$p.threshold_vpp;
                lock_ms=$p.lock_ms; error_final_hz=([int64]$p.final_lo_hz - [int64]$c.hz); error_raw_hz=([int64]$p.raw_estimate_hz - [int64]$c.hz); locked=$p.locked; fw_id=$p.fw_id; log_path=$log;
                valley_hz=$valleyHz; edge_mid_hz=$edgeMid
            })
            Write-Host ("{0} rep{1}: final={2} raw={3} corr={4} err={5} lock={6}ms" -f $c.id,$rep,$p.final_lo_hz,$p.raw_estimate_hz,$p.correction_hz,([int64]$p.final_lo_hz-[int64]$c.hz),$p.lock_ms)
        }
    }
} finally {
    Safety-Stop
}

$baseline = Join-Path $OutDir "01_baseline_lock_error.csv"
$rows | Select-Object case_id,repeat_idx,rf_mhz,rf_vpp,mod,final_lo_hz,estimated_carrier_hz,raw_estimate_hz,correction_hz,left_edge_hz,right_edge_hz,peak_vpp,valley_vpp,threshold_vpp,lock_ms,error_final_hz,error_raw_hz,locked,fw_id,log_path | Export-Csv -Path $baseline -NoTypeInformation -Encoding UTF8

foreach($g in ($rows | Group-Object case_id)) {
    $first = $g.Group[0]
    $currentErr = Mean ($g.Group | ForEach-Object { $_.error_final_hz })
    $rawErr = Mean ($g.Group | ForEach-Object { $_.error_raw_hz })
    $valleyErr = Mean ($g.Group | ForEach-Object { if($_.valley_hz -gt 0){ [int64]$_.valley_hz - [int64]($_.rf_mhz * 1000000) } })
    $edgeErr = Mean ($g.Group | ForEach-Object { if($_.edge_mid_hz -gt 0){ [int64]$_.edge_mid_hz - [int64]($_.rf_mhz * 1000000) } })
    $recommended = "current_halfstep"
    if(($rawErr -ne "") -and ([math]::Abs([double]$rawErr) -lt [math]::Abs([double]$currentErr))) { $recommended = "no_correction" }
    if(($edgeErr -ne "") -and ([math]::Abs([double]$edgeErr) -lt [math]::Abs([double]$currentErr)) -and ([math]::Abs([double]$edgeErr) -lt [math]::Abs([double]$rawErr))) { $recommended = "edge_mid" }
    $stratRows.Add([pscustomobject]@{
        case_id=$first.case_id; rf_mhz=$first.rf_mhz; current_error_hz=$currentErr; no_correction_error_hz=$rawErr; valley_error_hz=$valleyErr; edge_mid_error_hz=$edgeErr; fit_or_avg_error_hz="NA_no_vpp_table"; recommended_strategy=$recommended
    })
}
$strategy = Join-Path $OutDir "02_strategy_offline_compare.csv"
$stratRows | Export-Csv -Path $strategy -NoTypeInformation -Encoding UTF8
Write-Host "baseline_csv=$baseline"
Write-Host "strategy_csv=$strategy"
Write-Host "safety_stop=done"