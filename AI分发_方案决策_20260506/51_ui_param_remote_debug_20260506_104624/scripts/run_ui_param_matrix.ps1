$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$RfAmpVpp = 1.5
$RfOffsetV = 0.0
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs\ui_param_matrix"
$SummaryPath = Join-Path $Root "01_summary.csv"
$ParamStatsPath = Join-Path $Root "02_param_stats.csv"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-ApiGet([string]$Path) {
    Invoke-RestMethod -Method Get -Uri ($Api + $Path) -TimeoutSec 20
}

function Invoke-ApiPost([string]$Path, [object]$BodyObj) {
    $json = $BodyObj | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Post -Uri ($Api + $Path) -ContentType "application/json; charset=utf-8" -Body $json -TimeoutSec 25
}

function Safe-Stop() {
    try { Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR$DgChannel`:MOD OFF" } | Out-Null } catch {}
    try { Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $false } | Out-Null } catch {}
    try { Invoke-ApiPost "/api/channel/2/output" @{ enabled = $false } | Out-Null } catch {}
}

function Ensure-Serial() {
    $st = Invoke-ApiGet "/api/serial/status"
    if((-not $st.connected) -or ($st.settings.port -ne "COM15")) {
        try { Invoke-ApiPost "/api/serial/disconnect" @{} | Out-Null } catch {}
        Start-Sleep -Milliseconds 300
        Invoke-ApiPost "/api/serial/connect" @{ port="COM15"; baudrate=115200; bytesize=8; parity="None"; stopbits="1"; timeout=0.05; log_rx=$true } | Out-Null
    }
}

function Set-Carrier([int]$CarrierHz) {
    Invoke-ApiPost "/api/channel/$DgChannel/apply" @{
        waveform = "SIN"
        frequency = [double]$CarrierHz
        amplitude = [double]$RfAmpVpp
        offset = [double]$RfOffsetV
        phase = 0.0
        unit = "VPP"
        impedance_mode = "HIGHZ"
    } | Out-Null
    Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $true } | Out-Null
}

function Set-Modulation([hashtable]$Case) {
    if($Case.type -eq "CW") {
        Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR$DgChannel`:MOD OFF" } | Out-Null
        return
    }
    $body = @{
        mod_type = $Case.type
        enabled = $true
        source = "INT"
        internal_function = "SIN"
        rate_hz = [double]$Case.rate_hz
    }
    if($Case.type -eq "AM") {
        $body.depth_percent = [double]$Case.depth_percent
    } elseif($Case.type -eq "FM") {
        $body.deviation = [double]$Case.deviation_hz
    } elseif($Case.type -eq "ASK") {
        $body.amplitude_vpp = [double]$Case.ask_low_vpp
        $body.polarity = "POS"
    } elseif($Case.type -eq "FSK") {
        $body.hop_frequency_hz = [double]$Case.hop_frequency_hz
        $body.polarity = "POS"
    } elseif($Case.type -eq "PSK") {
        $body.phase_deg = [double]$Case.phase_deg
        $body.polarity = "POS"
    }
    Invoke-ApiPost "/api/channel/$DgChannel/modulation" $body | Out-Null
}

function Reset-Mcu() {
    & $Programmer -c port=SWD mode=UR reset=HWrst -rst | Out-Null
}

function Export-MergedLog([string]$Prefix) {
    $resp = Invoke-ApiPost "/api/logs/export" @{ mode = "merged" }
    if($null -ne $resp.file_path -and (Test-Path -LiteralPath $resp.file_path)) {
        $dst = Join-Path $LogDir ($Prefix + "_merged_" + (Split-Path $resp.file_path -Leaf))
        Copy-Item -LiteralPath $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Get-Timestamp([string]$Line) {
    if($Line -match '^\[([^\]]+)\]') {
        return [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
    }
    return $null
}

function Parse-Fields([string]$Line) {
    $h = @{}
    if($Line -match '\[RX\]\s+(mod|ui),') { $h['record'] = $matches[1] }
    foreach($key in @('mode','inst','stable','conf','rate','depth','dev','shift','blk','car','ac','env','edge','freq','psk','hist','pos','neg','bias')) {
        $pat = $key + '=([^,\s|]+)'
        if($Line -match $pat) { $h[$key] = $matches[1] }
    }
    return $h
}

function Stats([object[]]$Values) {
    $nums = @($Values | Where-Object { $_ -ne $null -and $_ -ne '' } | ForEach-Object { [double]$_ })
    if($nums.Count -eq 0) { return @{ min=$null; avg=$null; max=$null } }
    $m = $nums | Measure-Object -Minimum -Maximum -Average
    return @{ min=[math]::Round($m.Minimum,2); avg=[math]::Round($m.Average,2); max=[math]::Round($m.Maximum,2) }
}

function Extract-Case([string]$LogPath, [string]$Expected) {
    $lines = Get-Content -LiteralPath $LogPath -Encoding UTF8
    $fw = @($lines | Where-Object { $_ -match 'fw_id,moddet_param_ui_20260506' })
    $sigLines = @($lines | Where-Object { $_ -match 'sigdet_final' })
    $sigLine = if($sigLines.Count -gt 0){ $sigLines[0] } else { '' }
    $tSig = Get-Timestamp $sigLine
    $mods = @()
    $uis = @()
    foreach($line in $lines) {
        $ts = Get-Timestamp $line
        if($tSig -and $ts -and $ts -lt $tSig) { continue }
        if($line -match '\[RX\]\s+mod,mode=') {
            $f = Parse-Fields $line
            if($f.ContainsKey('stable')) { $mods += [pscustomobject]$f }
        } elseif($line -match '\[RX\]\s+ui,mode=') {
            $f = Parse-Fields $line
            if($f.ContainsKey('mode')) { $uis += [pscustomobject]$f }
        }
    }

    $stableCounts = @{}
    foreach($m in $mods) {
        $stable = [string]$m.stable
        if($stable.Length -eq 0 -or $stable -eq 'UNKNOWN') { continue }
        if(-not $stableCounts.ContainsKey($stable)) { $stableCounts[$stable] = 0 }
        $stableCounts[$stable]++
    }
    $stableMajority = ''
    $stableMax = 0
    foreach($k in $stableCounts.Keys) {
        if($stableCounts[$k] -gt $stableMax) { $stableMax = $stableCounts[$k]; $stableMajority = $k }
    }

    $conf = Stats @($mods | ForEach-Object { $_.conf })
    $rate = Stats @($mods | ForEach-Object { $_.rate })
    $depth = Stats @($mods | ForEach-Object { $_.depth })
    $dev = Stats @($mods | ForEach-Object { $_.dev })
    $shift = Stats @($mods | ForEach-Object { $_.shift })

    return [pscustomobject]@{
        fw_id_found = ($fw.Count -gt 0)
        fw_id_line = if($fw.Count -gt 0){ $fw[0] } else { '' }
        sigdet_found = ($sigLines.Count -gt 0)
        sigdet_line = $sigLine
        mod_count = $mods.Count
        ui_count = $uis.Count
        stable_majority = $stableMajority
        stable_counts = (($stableCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ';')
        stable_pass = ($stableMajority -eq $Expected)
        conf_min = $conf.min; conf_avg = $conf.avg; conf_max = $conf.max
        rate_min = $rate.min; rate_avg = $rate.avg; rate_max = $rate.max
        depth_min = $depth.min; depth_avg = $depth.avg; depth_max = $depth.max
        dev_min = $dev.min; dev_avg = $dev.avg; dev_max = $dev.max
        shift_min = $shift.min; shift_avg = $shift.avg; shift_max = $shift.max
        first_mod = if($mods.Count -gt 0){ ($mods[0] | ConvertTo-Json -Compress) } else { '' }
        first_ui = if($uis.Count -gt 0){ ($uis[0] | ConvertTo-Json -Compress) } else { '' }
    }
}

$cases = @(
    @{ id="CW_40M"; expected="CW"; type="CW"; carrier_hz=40000000; wait_s=12 },
    @{ id="AM_40M_10k_50pct"; expected="AM"; type="AM"; carrier_hz=40000000; rate_hz=10000; depth_percent=50; wait_s=12 },
    @{ id="ASK_40M_10k_low0"; expected="ASK"; type="ASK"; carrier_hz=40000000; rate_hz=10000; ask_low_vpp=0.0; wait_s=12 },
    @{ id="FM_40M_10k_dev75k"; expected="FM"; type="FM"; carrier_hz=40000000; rate_hz=10000; deviation_hz=75000; wait_s=12 },
    @{ id="FSK_40M_10k_hop20k"; expected="FSK"; type="FSK"; carrier_hz=40000000; rate_hz=10000; hop_frequency_hz=40020000; wait_s=12 },
    @{ id="PSK_40M_10k_180"; expected="PSK"; type="PSK"; carrier_hz=40000000; rate_hz=10000; phase_deg=180; wait_s=12 }
)

Ensure-Serial
$rows = @()
$paramRows = @()
$idx = 0
try {
    foreach($c in $cases) {
        $idx++
        $name = "{0:D2}_{1}" -f $idx, $c.id
        Write-Host "[$idx/$($cases.Count)] $name"
        Set-Carrier ([int]$c.carrier_hz)
        Set-Modulation $c
        Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
        Reset-Mcu
        Start-Sleep -Seconds ([int]$c.wait_s)
        $logPath = Export-MergedLog $name
        $s = Extract-Case $logPath $c.expected
        $rows += [pscustomobject]@{
            case_id = $c.id
            expected = $c.expected
            fw_id_found = $s.fw_id_found
            sigdet_found = $s.sigdet_found
            mod_count = $s.mod_count
            ui_count = $s.ui_count
            stable_majority = $s.stable_majority
            stable_counts = $s.stable_counts
            stable_pass = $s.stable_pass
            link_pass = ($s.fw_id_found -and $s.sigdet_found -and ($s.mod_count -ge 10) -and ($s.ui_count -ge 10))
            log_path = $logPath
        }
        $paramRows += [pscustomobject]@{
            case_id = $c.id
            expected = $c.expected
            conf_min = $s.conf_min; conf_avg = $s.conf_avg; conf_max = $s.conf_max
            rate_min = $s.rate_min; rate_avg = $s.rate_avg; rate_max = $s.rate_max
            depth_min = $s.depth_min; depth_avg = $s.depth_avg; depth_max = $s.depth_max
            dev_min = $s.dev_min; dev_avg = $s.dev_avg; dev_max = $s.dev_max
            shift_min = $s.shift_min; shift_avg = $s.shift_avg; shift_max = $s.shift_max
            first_mod = $s.first_mod
            first_ui = $s.first_ui
        }
    }
}
finally {
    Safe-Stop
}

$rows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8
$paramRows | Export-Csv -LiteralPath $ParamStatsPath -NoTypeInformation -Encoding UTF8
$rows | Format-Table case_id,expected,link_pass,stable_majority,stable_pass,mod_count,ui_count,stable_counts -AutoSize
$paramRows | Format-Table case_id,rate_avg,depth_avg,dev_avg,shift_avg,conf_avg -AutoSize
Write-Host "summary=$SummaryPath"
Write-Host "param_stats=$ParamStatsPath"