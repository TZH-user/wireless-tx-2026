$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$ScopeChannel = 2
$SerialPort = "COM15"
$SerialBaud = 115200
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$RequiredFwContains = "fw_id,"
$RequiredFwExact = ""

$Root = Join-Path $PSScriptRoot ("55_scope_adc_verify_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$LogsDir = Join-Path $Root "logs"
$ScopeDir = Join-Path $Root "scope"
New-Item -ItemType Directory -Force -Path $Root, $LogsDir, $ScopeDir | Out-Null

$ReportMd = Join-Path $Root "00_testdata_ai_adc_scope_verify_report.md"
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

function Resolve-ScopeChannel {
    if ($ScopeChannel -ge 1 -and $ScopeChannel -le 4) {
        return [int]$ScopeChannel
    }
    try {
        $st = Invoke-ApiGet "/api/scope/status"
        $displayed = @($st.channels | Where-Object { $_.display -eq $true } | Select-Object -ExpandProperty channel)
        if ($displayed.Count -gt 0) {
            return [int]$displayed[0]
        }
    } catch {}
    return 2
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

function Set-CW {
    param([double]$Vpp)
    Invoke-ApiPost "/api/channel/$DgChannel/apply" @{
        waveform = "SIN"
        frequency = 40000000.0
        amplitude = $Vpp
        offset = 0.0
        phase = 0.0
        unit = "VPP"
        impedance_mode = "HIGHZ"
    } | Out-Null
    Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR${DgChannel}:MOD OFF" } | Out-Null
    Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $true } | Out-Null
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
        vpp  = [math]::Round($vpp, 6)
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
    $fwHit = $false
    if ($RequiredFwExact -ne "") {
        $fwHit = ($txt | Select-String -SimpleMatch $RequiredFwExact -Quiet)
    } elseif ($RequiredFwContains -ne "") {
        $fwHit = ($txt | Select-String -SimpleMatch $RequiredFwContains -Quiet)
    }
    $sigLine = @($txt | Select-String -Pattern "sigdet_final" | Select-Object -Last 1)
    $sigHit = ($sigLine.Count -gt 0)
    $sigLocked = $false
    $sigEst = ""
    if ($sigHit) {
        $line = $sigLine[0].Line
        if ($line -match "locked=(\d+)") { $sigLocked = ($Matches[1] -eq "1") }
        if ($line -match "lock=(\d+)") { $sigLocked = ($Matches[1] -eq "1") }
        if ($line -match "estimated_carrier=(\d+)") { $sigEst = $Matches[1] }
    }

    $rngLineObj = @($txt | Select-String -Pattern "adc_range," | Select-Object -Last 1)
    $rng = @{
        imin="";imax="";ivpp="";qmin="";qmax="";qvpp="";
        iclo="";ichi="";qclo="";qchi="";inlo="";inhi="";qnlo="";qnhi=""
    }
    if ($rngLineObj.Count -gt 0) {
        $line = $rngLineObj[0].Line
        foreach($k in @("imin","imax","ivpp","qmin","qmax","qvpp","iclo","ichi","qclo","qchi","inlo","inhi","qnlo","qnhi")) {
            if ($line -match ($k + "=(\d+)")) { $rng[$k] = $Matches[1] }
        }
    }
    return [pscustomobject]@{
        fw_hit = $fwHit
        fw_line = $fwLine
        sigdet_hit = $sigHit
        sigdet_locked = $sigLocked
        sigdet_est_hz = $sigEst
        adc = $rng
    }
}

$effectiveScopeChannel = Resolve-ScopeChannel
$scopeProbe = ""
$scopeCoupling = ""

Ensure-Serial

try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN1:DISP OFF" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN2:DISP ON" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN3:DISP OFF" } | Out-Null } catch {}
try { Invoke-ApiPost "/api/scope/raw/write" @{ command = ":CHAN4:DISP OFF" } | Out-Null } catch {}

$cases = @(
    @{ case_id="A1"; rf_mhz=40; rf_vpp=0.5; mod="CW" },
    @{ case_id="A2"; rf_mhz=40; rf_vpp=1.0; mod="CW" },
    @{ case_id="A3"; rf_mhz=40; rf_vpp=1.5; mod="CW" },
    @{ case_id="A4"; rf_mhz=40; rf_vpp=2.0; mod="CW" }
)

$results = @()
$stopAll = $false
foreach ($c in $cases) {
    if ($stopAll) { break }
    $prefix = ("{0}_CW_40M_v{1}" -f $c.case_id, ($c.rf_vpp.ToString().Replace(".","p")))
    Write-Host $prefix
    Set-CW -Vpp ([double]$c.rf_vpp)
    Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
    Start-Sleep -Milliseconds 200
    Reset-Mcu
    Start-Sleep -Seconds 10
    $logPath = Export-SerialLog -Prefix $prefix
    $scopePath = Export-ScopeCsv -Prefix $prefix -Channel $effectiveScopeChannel
    $scope = Parse-ScopeStats -CsvPath $scopePath
    $logm = Parse-LogMetrics -LogPath $logPath

    $stopReason = ""
    # 暂以 3.3V 为临时参考，仅作自动预警；最终以人工VREF实测为准
    $vrefTmp = 3.3
    if ($scope.vmax -gt ($vrefTmp + 0.3)) { $stopReason = "AUTO_STOP_SCOPE_VMAX_GT_VREFP0P3"; $stopAll = $true }
    if ($scope.vmin -lt -0.3) { $stopReason = "AUTO_STOP_SCOPE_VMIN_LT_NEG0P3"; $stopAll = $true }

    $results += [pscustomobject]@{
        case_id = $c.case_id
        rf_mhz = $c.rf_mhz
        rf_vpp = $c.rf_vpp
        mod = $c.mod
        scope_node = ("CH" + $effectiveScopeChannel + "_UNKNOWN_NODE")
        probe_ratio = $scopeProbe
        scope_coupling = $scopeCoupling
        vref_v = ""
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
        sigdet_locked = $logm.sigdet_locked
        sigdet_est_hz = $logm.sigdet_est_hz
        fw_id_found = $logm.fw_hit
        fw_id_line = $logm.fw_line
        log_path = $logPath
        scope_file = $scopePath
        stop_reason = $stopReason
    }
}

$results | Export-Csv -LiteralPath $CsvA -NoTypeInformation -Encoding UTF8
@() | Export-Csv -LiteralPath $CsvB -NoTypeInformation -Encoding UTF8
@() | Export-Csv -LiteralPath $CsvC -NoTypeInformation -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# ADC Scope Verify Report (A1-A4)')
$md.Add('')
$md.Add('time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$md.Add('data_root: "' + $Root + '"')
$md.Add('stage: A1~A4 only (CW 40MHz)')
$md.Add('scope_channel_used: CH' + $effectiveScopeChannel)
$md.Add('note: no parameter analysis; manual scope node/probe ground/VREF fields are pending.')
$md.Add('')
$md.Add('## Auto Summary (A1~A4)')
$md.Add('')
$md.Add('| case | rf_vpp | scope_vmax | scope_vmin | scope_vpp | flatline | adc_imin | adc_imax | adc_qmin | adc_qmax | fw_id_hit | sigdet_hit | sigdet_locked | stop_reason |')
$md.Add('|---|---:|---:|---:|---:|---|---:|---:|---:|---:|---|---|---|---|')
foreach ($r in $results) {
    $md.Add('| ' + $r.case_id + ' | ' + $r.rf_vpp + ' | ' + $r.scope_vmax_v + ' | ' + $r.scope_vmin_v + ' | ' + $r.scope_vpp_v + ' | ' + $r.scope_flatline + ' | ' + $r.adc_imin + ' | ' + $r.adc_imax + ' | ' + $r.adc_qmin + ' | ' + $r.adc_qmax + ' | ' + $r.fw_id_found + ' | ' + $r.sigdet_hit + ' | ' + $r.sigdet_locked + ' | ' + $r.stop_reason + ' |')
}
$md.Add('')
$md.Add('## Manual Fields To Fill')
$md.Add('')
$md.Add('- scope node name (must confirm if it is PC4 ADC pin)')
$md.Add('- probe ratio and scope channel ratio consistency')
$md.Add('- coupling mode and ground point')
$md.Add('- VREF+/VDDA measured value')
$md.Add('')
$md.Add('## Output Files')
$md.Add('')
$md.Add('- 01_scope_adc_cw_matrix.csv')
$md.Add('- 02_scope_adc_frequency_matrix.csv (empty this run)')
$md.Add('- 03_scope_adc_modulated_matrix.csv (empty this run)')
$md.Add('- logs/')
$md.Add('- scope/')

Set-Content -LiteralPath $ReportMd -Value $md -Encoding UTF8
Write-Host ("VERIFY_DONE: " + $Root)
