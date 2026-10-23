$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$ScopeChannel = 2
$SerialPort = "COM15"
$SerialBaud = 115200
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$RequiredFwContains = "fw_id,"

# Manual fields (from user wiring statement + pending on-site checks)
$ScopeNode = "MCU_ADC_CH2_USER_WIRED_NEED_ONSITE_CONFIRM"
$GroundPoint = "NEED_USER_CONFIRM"
$VrefV = ""

$Root = Join-Path $PSScriptRoot ("55_scope_adc_verify_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$LogsDir = Join-Path $Root "logs"
$ScopeDir = Join-Path $Root "scope"
New-Item -ItemType Directory -Force -Path $Root, $LogsDir, $ScopeDir | Out-Null

$ReportMd = Join-Path $Root "00_测试采数AI_ADC示波器复核报告.md"
$CsvA = Join-Path $Root "01_scope_adc_cw_matrix.csv"
$CsvB = Join-Path $Root "02_scope_adc_frequency_matrix.csv"
$CsvC = Join-Path $Root "03_scope_adc_modulated_matrix.csv"

function Invoke-ApiGet {
    param([string]$Path)
    Invoke-RestMethod -Method Get -Uri ($Api + $Path)
}

function Invoke-ApiPost {
    param([string]$Path, [object]$BodyObj)
    $json = $BodyObj | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Post -Uri ($Api + $Path) -ContentType "application/json" -Body $json
}

function Try-ScopeQuery {
    param([string]$Cmd)
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-ApiPost "/api/scope/raw/query" @{ command = $Cmd }
            if ($null -ne $r.result) { return [string]$r.result }
        } catch {
            Start-Sleep -Milliseconds 150
        }
    }
    return ""
}

function Ensure-Serial {
    $st = Invoke-ApiGet "/api/serial/status"
    if (-not $st.connected) {
        Invoke-ApiPost "/api/serial/connect" @{
            port = $SerialPort
            baud_rate = $SerialBaud
            data_bits = 8
            parity = "None"
            stop_bits = "1"
            flow_control = "None"
            dtr_enable = $false
            rts_enable = $false
            rx_format = "ASCII"
        } | Out-Null
    }
}

function Set-Carrier {
    param([int]$CarrierHz, [double]$Vpp)
    Invoke-ApiPost "/api/channel/$DgChannel/apply" @{
        waveform = "SIN"
        frequency = [double]$CarrierHz
        amplitude = [double]$Vpp
        offset = 0.0
        phase = 0.0
        unit = "VPP"
        impedance_mode = "HIGHZ"
    } | Out-Null
    Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $true } | Out-Null
}

function Set-Modulation {
    param([hashtable]$Case)
    if ($Case.mod -eq "CW") {
        Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR${DgChannel}:MOD OFF" } | Out-Null
        return
    }

    $body = @{
        enabled = $true
        mod_type = $Case.mod
        source = "INT"
        internal_function = "SIN"
        rate_hz = [double]$Case.rate_hz
    }

    switch ($Case.mod) {
        "AM"  { $body.depth_percent = [double]$Case.depth_percent }
        "ASK" { $body.amplitude_vpp = [double]$Case.ask_low_vpp; $body.polarity = "POS" }
        "FM"  { $body.deviation = [double]$Case.deviation_hz }
        "FSK" { $body.hop_frequency_hz = [double]$Case.hop_frequency_hz; $body.polarity = "POS" }
        "PSK" { $body.phase_deg = [double]$Case.phase_deg; $body.polarity = "POS" }
        default { throw "Unsupported modulation type: $($Case.mod)" }
    }

    Invoke-ApiPost "/api/channel/$DgChannel/modulation" $body | Out-Null
}

function Reset-Mcu {
    & $Programmer -c port=SWD mode=UR reset=SWrst | Out-Null
}

function Export-SerialLog {
    param([string]$Prefix)
    $r = Invoke-ApiPost "/api/logs/export" @{ mode = "serial" }
    if ($r.file_path -and (Test-Path $r.file_path)) {
        $dst = Join-Path $LogsDir ($Prefix + "_" + (Split-Path $r.file_path -Leaf))
        Copy-Item -LiteralPath $r.file_path -Destination $dst -Force
        return $dst
    }
    return ""
}

function Export-ScopeCsv {
    param([string]$Prefix, [int]$Channel)
    $r = Invoke-ApiPost "/api/scope/waveform/export" @{ channel = $Channel; points = 20000 }
    if ($r.file_path -and (Test-Path $r.file_path)) {
        $dst = Join-Path $ScopeDir ($Prefix + "_" + (Split-Path $r.file_path -Leaf))
        Copy-Item -LiteralPath $r.file_path -Destination $dst -Force
        return $dst
    }
    return ""
}

function Parse-ScopeStats {
    param([string]$CsvPath)
    if (-not (Test-Path $CsvPath)) {
        return [pscustomobject]@{ vmax = 0.0; vmin = 0.0; vpp = 0.0; vavg = 0.0; flatline = $true }
    }
    $rows = Import-Csv -LiteralPath $CsvPath
    if (-not $rows -or $rows.Count -eq 0) {
        return [pscustomobject]@{ vmax = 0.0; vmin = 0.0; vpp = 0.0; vavg = 0.0; flatline = $true }
    }
    $vals = @()
    foreach ($r in $rows) {
        if ($null -ne $r.voltage_v -and $r.voltage_v -ne "") {
            $vals += [double]$r.voltage_v
        }
    }
    if ($vals.Count -eq 0) {
        return [pscustomobject]@{ vmax = 0.0; vmin = 0.0; vpp = 0.0; vavg = 0.0; flatline = $true }
    }
    $m = $vals | Measure-Object -Minimum -Maximum -Average
    $vpp = ([double]$m.Maximum - [double]$m.Minimum)
    return [pscustomobject]@{
        vmax = [math]::Round([double]$m.Maximum, 6)
        vmin = [math]::Round([double]$m.Minimum, 6)
        vpp = [math]::Round($vpp, 6)
        vavg = [math]::Round([double]$m.Average, 6)
        flatline = ($vpp -lt 0.001)
    }
}

function Parse-LogMetrics {
    param([string]$LogPath)
    $txt = Get-Content -LiteralPath $LogPath -Encoding UTF8

    $fwLineObj = @($txt | Select-String -Pattern "fw_id," | Select-Object -Last 1)
    $fwLine = ""
    if ($fwLineObj.Count -gt 0) { $fwLine = $fwLineObj[0].Line }
    $fwHit = ($txt | Select-String -SimpleMatch $RequiredFwContains -Quiet)

    $sigLineObj = @($txt | Select-String -Pattern "sigdet_final" | Select-Object -Last 1)
    $sigLine = ""
    $sigHit = ($sigLineObj.Count -gt 0)
    $sigLocked = $false
    $sigEst = ""
    if ($sigHit) {
        $sigLine = $sigLineObj[0].Line
        if ($sigLine -match "locked=(\d+)") { $sigLocked = ($Matches[1] -eq "1") }
        if ($sigLine -match "lock=(\d+)") { $sigLocked = ($Matches[1] -eq "1") }
        if ($sigLine -match "estimated_carrier=(\d+)") { $sigEst = $Matches[1] }
    }

    $rngLineObj = @($txt | Select-String -Pattern "adc_range," | Select-Object -Last 1)
    $rngLine = ""
    $rng = @{
        imin="";imax="";ivpp="";qmin="";qmax="";qvpp="";
        iclo="";ichi="";qclo="";qchi="";inlo="";inhi="";qnlo="";qnhi=""
    }
    if ($rngLineObj.Count -gt 0) {
        $rngLine = $rngLineObj[0].Line
        foreach($k in @("imin","imax","ivpp","qmin","qmax","qvpp","iclo","ichi","qclo","qchi","inlo","inhi","qnlo","qnhi")) {
            if ($rngLine -match ($k + "=(\d+)")) { $rng[$k] = $Matches[1] }
        }
    }

    return [pscustomobject]@{
        fw_hit = $fwHit
        fw_line = $fwLine
        sigdet_hit = $sigHit
        sigdet_line = $sigLine
        sigdet_locked = $sigLocked
        sigdet_est_hz = $sigEst
        adc_line = $rngLine
        adc = $rng
    }
}

function Run-Case {
    param(
        [hashtable]$Case,
        [int]$ScopeCh,
        [string]$Probe,
        [string]$Coupling
    )

    $prefix = $Case.case_id + "_" + $Case.mod + "_" + $Case.rf_mhz + "M_v" + ($Case.rf_vpp.ToString().Replace(".","p"))
    Write-Host $prefix

    Set-Carrier -CarrierHz ([int]($Case.rf_mhz * 1000000)) -Vpp ([double]$Case.rf_vpp)
    Set-Modulation -Case $Case

    Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
    Start-Sleep -Milliseconds 200
    Reset-Mcu
    Start-Sleep -Seconds ([int]$Case.wait_s)

    $logPath = Export-SerialLog -Prefix $prefix
    $scopePath = Export-ScopeCsv -Prefix $prefix -Channel $ScopeCh
    $scope = Parse-ScopeStats -CsvPath $scopePath
    $logm = Parse-LogMetrics -LogPath $logPath

    $stopReason = ""
    $vrefTmp = 3.3
    if ($scope.vmax -gt ($vrefTmp + 0.3)) { $stopReason = "AUTO_STOP_SCOPE_VMAX_GT_VREFP0P3" }
    if ($scope.vmin -lt -0.3) { $stopReason = "AUTO_STOP_SCOPE_VMIN_LT_NEG0P3" }

    return [pscustomobject]@{
        case_id = $Case.case_id
        rf_mhz = $Case.rf_mhz
        rf_vpp = $Case.rf_vpp
        mod = $Case.mod
        scope_node = $ScopeNode
        probe_ratio = $Probe
        scope_coupling = $Coupling
        ground_point = $GroundPoint
        vref_v = $VrefV
        scope_vmax_v = $scope.vmax
        scope_vmin_v = $scope.vmin
        scope_vpp_v = $scope.vpp
        scope_vavg_v = $scope.vavg
        scope_flatline = $scope.flatline
        adc_imin = $logm.adc.imin
        adc_imax = $logm.adc.imax
        adc_ivpp = $logm.adc.ivpp
        adc_qmin = $logm.adc.qmin
        adc_qmax = $logm.adc.qmax
        adc_qvpp = $logm.adc.qvpp
        adc_iclo = $logm.adc.iclo
        adc_ichi = $logm.adc.ichi
        adc_qclo = $logm.adc.qclo
        adc_qchi = $logm.adc.qchi
        adc_inlo = $logm.adc.inlo
        adc_inhi = $logm.adc.inhi
        adc_qnlo = $logm.adc.qnlo
        adc_qnhi = $logm.adc.qnhi
        sigdet_hit = $logm.sigdet_hit
        sigdet_line = $logm.sigdet_line
        sigdet_locked = $logm.sigdet_locked
        sigdet_est_hz = $logm.sigdet_est_hz
        adc_range_line = $logm.adc_line
        fw_id_found = $logm.fw_hit
        fw_id_line = $logm.fw_line
        log_path = $logPath
        scope_file = $scopePath
        stop_reason = $stopReason
    }
}

Ensure-Serial

# Force scope channel display mapping
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN1:DISP OFF" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN2:DISP ON" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN3:DISP OFF" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN4:DISP OFF" } | Out-Null } catch {}

$scopeProbe = Try-ScopeQuery -Cmd ":CHAN${ScopeChannel}:PROB?"
$scopeCoupling = Try-ScopeQuery -Cmd ":CHAN${ScopeChannel}:COUP?"

$casesA = @(
    @{ case_id="A1"; rf_mhz=40; rf_vpp=0.5; mod="CW"; wait_s=10 },
    @{ case_id="A2"; rf_mhz=40; rf_vpp=1.0; mod="CW"; wait_s=10 },
    @{ case_id="A3"; rf_mhz=40; rf_vpp=1.5; mod="CW"; wait_s=10 },
    @{ case_id="A4"; rf_mhz=40; rf_vpp=2.0; mod="CW"; wait_s=10 }
)

$casesB = @(
    @{ case_id="B1"; rf_mhz=30; rf_vpp=1.5; mod="CW"; wait_s=10 },
    @{ case_id="B2"; rf_mhz=45; rf_vpp=1.5; mod="CW"; wait_s=10 },
    @{ case_id="B3"; rf_mhz=50; rf_vpp=1.5; mod="CW"; wait_s=10 }
)

$casesC = @(
    @{ case_id="C1"; rf_mhz=40; rf_vpp=1.5; mod="AM";  rate_hz=10000; depth_percent=50; wait_s=12 },
    @{ case_id="C2"; rf_mhz=40; rf_vpp=1.5; mod="ASK"; rate_hz=10000; ask_low_vpp=0.75; wait_s=12 },
    @{ case_id="C3"; rf_mhz=40; rf_vpp=1.5; mod="FM";  rate_hz=10000; deviation_hz=20000; wait_s=12 },
    @{ case_id="C4"; rf_mhz=40; rf_vpp=1.5; mod="FSK"; rate_hz=10000; hop_frequency_hz=40050000; wait_s=12 },
    @{ case_id="C5"; rf_mhz=40; rf_vpp=1.5; mod="PSK"; rate_hz=10000; phase_deg=180; wait_s=12 }
)

$rowsA = @()
$rowsB = @()
$rowsC = @()
$stopAll = $false

foreach ($c in $casesA) {
    if ($stopAll) { break }
    $r = Run-Case -Case $c -ScopeCh $ScopeChannel -Probe $scopeProbe -Coupling $scopeCoupling
    $rowsA += $r
    if ($r.stop_reason -ne "") { $stopAll = $true }
}

if (-not $stopAll) {
    foreach ($c in $casesB) {
        if ($stopAll) { break }
        $r = Run-Case -Case $c -ScopeCh $ScopeChannel -Probe $scopeProbe -Coupling $scopeCoupling
        $rowsB += $r
        if ($r.stop_reason -ne "") { $stopAll = $true }
    }
}

if (-not $stopAll) {
    foreach ($c in $casesC) {
        if ($stopAll) { break }
        $r = Run-Case -Case $c -ScopeCh $ScopeChannel -Probe $scopeProbe -Coupling $scopeCoupling
        $rowsC += $r
        if ($r.stop_reason -ne "") { $stopAll = $true }
    }
}

$rowsA | Export-Csv -LiteralPath $CsvA -NoTypeInformation -Encoding UTF8
$rowsB | Export-Csv -LiteralPath $CsvB -NoTypeInformation -Encoding UTF8
$rowsC | Export-Csv -LiteralPath $CsvC -NoTypeInformation -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# 00_测试采数AI_ADC示波器复核报告')
$md.Add('')
$md.Add('time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$md.Add('data_root: "' + $Root + '"')
$md.Add('scope_channel_used: CH' + $ScopeChannel)
$md.Add('scope_node: ' + $ScopeNode)
$md.Add('probe_ratio: ' + ($(if($scopeProbe){$scopeProbe}else{'<unavailable>'})))
$md.Add('scope_coupling: ' + ($(if($scopeCoupling){$scopeCoupling}else{'<unavailable>'})))
$md.Add('ground_point: ' + $GroundPoint)
$md.Add('vref_v: ' + ($(if($VrefV){$VrefV}else{'<unmeasured>'})))
$md.Add('stop_triggered: ' + $stopAll)
$md.Add('')

$md.Add('## A1~A4 (CW 40MHz)')
$md.Add('| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |')
$md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|')
foreach ($r in $rowsA) {
    $md.Add('| ' + $r.case_id + ' | ' + $r.rf_vpp + ' | ' + $r.scope_vmax_v + ' | ' + $r.scope_vmin_v + ' | ' + $r.scope_vpp_v + ' | ' + $r.adc_imin + ' | ' + $r.adc_imax + ' | ' + $r.adc_qmin + ' | ' + $r.adc_qmax + ' | ' + $r.fw_id_found + ' | ' + $r.sigdet_hit + ' | ' + $r.stop_reason + ' |')
}
$md.Add('')

$md.Add('## B1~B3 (CW Frequency Cross Check)')
$md.Add('| case | rf_mhz | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |')
$md.Add('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|')
foreach ($r in $rowsB) {
    $md.Add('| ' + $r.case_id + ' | ' + $r.rf_mhz + ' | ' + $r.rf_vpp + ' | ' + $r.scope_vmax_v + ' | ' + $r.scope_vmin_v + ' | ' + $r.scope_vpp_v + ' | ' + $r.adc_imin + ' | ' + $r.adc_imax + ' | ' + $r.adc_qmin + ' | ' + $r.adc_qmax + ' | ' + $r.fw_id_found + ' | ' + $r.sigdet_hit + ' | ' + $r.stop_reason + ' |')
}
$md.Add('')

$md.Add('## C1~C5 (Modulated Peak Check)')
$md.Add('| case | mod | rf_vpp | scope_vmax | scope_vmin | scope_vpp | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id | sigdet_hit | stop_reason |')
$md.Add('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|')
foreach ($r in $rowsC) {
    $md.Add('| ' + $r.case_id + ' | ' + $r.mod + ' | ' + $r.rf_vpp + ' | ' + $r.scope_vmax_v + ' | ' + $r.scope_vmin_v + ' | ' + $r.scope_vpp_v + ' | ' + $r.adc_imin + ' | ' + $r.adc_imax + ' | ' + $r.adc_qmin + ' | ' + $r.adc_qmax + ' | ' + $r.fw_id_found + ' | ' + $r.sigdet_hit + ' | ' + $r.stop_reason + ' |')
}
$md.Add('')

$md.Add('## 任务书问题回答（自动侧）')
$md.Add('1. 4V 是否为 PC4 电压：自动测试无法独立确认，当前仅按用户链路描述记录为 CH2 接 MCU ADC 节点，需现场测点复核。')
$md.Add('2. VREF+/VDDA：本轮未实测，需万用表补录。')
$md.Add('3. raw 无 near/clip 与高电压并存：若测点不在 PC4 或存在前级钳位/分压，可能出现该现象。')
$md.Add('4. 安全 RF VPP 上限：在未完成 VREF 实测与测点实锤前，仅可暂用 1.5VPP。')
$md.Add('5. 后续算法测试幅度建议：默认 1.5VPP；若现场确认 PC4 接近 VREF+，降到 1.0VPP。')
$md.Add('6. 是否需要硬件处理：待 VREF 与 PC4 实测后由方案决策 AI 最终裁定。')
$md.Add('')
$md.Add('## 输出文件')
$md.Add('- 01_scope_adc_cw_matrix.csv')
$md.Add('- 02_scope_adc_frequency_matrix.csv')
$md.Add('- 03_scope_adc_modulated_matrix.csv')
$md.Add('- logs/*.log')
$md.Add('- scope/*.csv')

Set-Content -LiteralPath $ReportMd -Value $md -Encoding UTF8
Write-Host ("VERIFY_DONE: " + $Root)
