$ErrorActionPreference = "Stop"

$Root = Join-Path $PSScriptRoot ("采集数据_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$RawDir = Join-Path $Root "raw_iq"
$ScopeDir = Join-Path $Root "scope"
$LogDir = Join-Path $Root "logs"
$ContextDir = Join-Path $Root "context"
$MetricDir = Join-Path $Root "metrics"
$ManifestPath = Join-Path $Root "manifest.jsonl"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$ScopeChannel = 3
$RfAmpVpp = 1.5
$RfOffsetV = 0.0
$SerialPort = "COM15"
$SerialBaud = 115200
$StableSerialLogDir = "D:\CodexProject\IQ_AutoCapture_20260505\serial"

$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$AdcBase = 0x30000000
$AdcBytes = 32768
$CounterBase = 0x20019070

@($Root, $RawDir, $ScopeDir, $LogDir, $ContextDir, $MetricDir) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

function Invoke-ApiGet {
    param([string]$Path)
    Invoke-RestMethod -Method Get -Uri ($Api + $Path)
}

function Invoke-ApiPost {
    param([string]$Path, [object]$BodyObj)
    $json = $BodyObj | ConvertTo-Json -Depth 8 -Compress
    Invoke-RestMethod -Method Post -Uri ($Api + $Path) -ContentType "application/json" -Body $json
}

function Set-Carrier {
    param([int]$CarrierHz)
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

function Set-Modulation {
    param([hashtable]$Case)
    if ($Case.type -eq "CW") {
        Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR$DgChannel:MOD OFF" } | Out-Null
        return
    }

    $body = @{
        mod_type = $Case.type
        enabled = $true
        source = "INT"
        internal_function = "SIN"
        rate_hz = [double]$Case.rate_hz
    }
    switch ($Case.type) {
        "AM"  { $body.depth_percent = [double]$Case.depth_percent }
        "ASK" { $body.amplitude_vpp = [double]$Case.ask_low_vpp; $body.polarity = "POS" }
        "FM"  { $body.deviation = [double]$Case.deviation_hz }
        "FSK" { $body.hop_frequency_hz = [double]$Case.hop_freq_hz; $body.polarity = "POS" }
        "PSK" { $body.phase_deg = [double]$Case.phase_deg; $body.polarity = "POS" }
        default { throw "Unsupported modulation type: $($Case.type)" }
    }
    Invoke-ApiPost "/api/channel/$DgChannel/modulation" $body | Out-Null
}

function Ensure-Serial {
    $st = Invoke-ApiGet "/api/serial/status"
    if (-not $st.connected) {
        Invoke-ApiPost "/api/serial/connect" @{
            port = $SerialPort
            baudrate = $SerialBaud
            bytesize = 8
            parity = "N"
            stopbits = 1
            timeout = 0.05
            log_rx = $true
        } | Out-Null
    }
}

function Reset-Mcu {
    & $Programmer -c port=SWD mode=UR reset=SWrst | Out-Null
}

function Read-AdcBuffers {
    param([string]$OutBin)
    & $Programmer -c port=SWD mode=HotPlug -halt -r $AdcBase $AdcBytes $OutBin -run | Out-Null
}

function Read-Counters {
    param([string]$OutTxt)
    $txt = & $Programmer -c port=SWD mode=HotPlug -halt -r32 $CounterBase 20 -run
    Set-Content -Path $OutTxt -Value $txt -Encoding UTF8
}

function Export-Logs {
    param([string]$Prefix)
    $resp = Invoke-ApiPost "/api/logs/export" @{ mode = "merged" }
    if ($null -ne $resp.file_path -and (Test-Path $resp.file_path)) {
        $dst = Join-Path $LogDir ($Prefix + "_" + (Split-Path $resp.file_path -Leaf))
        Copy-Item -Path $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Export-Scope {
    param([string]$Prefix)
    $resp = Invoke-ApiPost "/api/scope/waveform/export" @{ channel = $ScopeChannel; points = 20000 }
    if ($null -ne $resp.file_path -and (Test-Path $resp.file_path)) {
        $dst = Join-Path $ScopeDir ($Prefix + "_" + (Split-Path $resp.file_path -Leaf))
        Copy-Item -Path $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Extract-MetricsLines {
    param([string]$MergedLogPath, [string]$OutPath)
    if (-not (Test-Path $MergedLogPath)) { return 0 }
    $lines = Get-Content -Path $MergedLogPath -Encoding UTF8 | Where-Object {
        $_ -match "\[RX\]\s+sig," -or $_ -match "\[RX\]\s+mod,"
    }
    Set-Content -Path $OutPath -Value $lines -Encoding UTF8
    return $lines.Count
}

function Add-Manifest {
    param([hashtable]$Row)
    ($Row | ConvertTo-Json -Depth 10 -Compress) | Add-Content -Path $ManifestPath -Encoding UTF8
}

$cases = @(
    @{ id = "CW_40M"; type = "CW"; carrier_hz = 40000000 },
    @{ id = "AM_40M_d50_r10k"; type = "AM"; carrier_hz = 40000000; rate_hz = 10000; depth_percent = 50 },
    @{ id = "ASK_40M_a0p75_r10k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 10000; ask_low_vpp = 0.75 },
    @{ id = "ASK_40M_a0p50_r10k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 10000; ask_low_vpp = 0.50 },
    @{ id = "ASK_40M_a1p00_r10k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 10000; ask_low_vpp = 1.00 },
    @{ id = "ASK_40M_a0p75_r5k";  type = "ASK"; carrier_hz = 40000000; rate_hz = 5000;  ask_low_vpp = 0.75 },
    @{ id = "ASK_40M_a0p75_r20k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 20000; ask_low_vpp = 0.75 },
    @{ id = "FM_40M_dev20k_r10k"; type = "FM"; carrier_hz = 40000000; rate_hz = 10000; deviation_hz = 20000 },
    @{ id = "FSK_40M_hop50k_r10k"; type = "FSK"; carrier_hz = 40000000; rate_hz = 10000; hop_freq_hz = 40050000 },
    @{ id = "PSK_40M_p180_r10k"; type = "PSK"; carrier_hz = 40000000; rate_hz = 10000; phase_deg = 180 },
    @{ id = "PSK_40M_p180_r5k";  type = "PSK"; carrier_hz = 40000000; rate_hz = 5000;  phase_deg = 180 },
    @{ id = "PSK_40M_p180_r20k"; type = "PSK"; carrier_hz = 40000000; rate_hz = 20000; phase_deg = 180 }
)

$oldSerialLogDir = (Invoke-ApiGet "/api/serial/status").log_dir
Invoke-ApiPost "/api/serial/log-dir" @{ log_dir = $StableSerialLogDir } | Out-Null
Ensure-Serial
$null = Invoke-ApiGet "/api/ai/context"

$idx = 0
foreach ($c in $cases) {
    $idx++
    $name = "{0:D2}_{1}" -f $idx, $c.id
    Write-Host ("[{0}/{1}] {2}" -f $idx, $cases.Count, $name)
    $start = Get-Date
    $errText = $null
    $rawPath = Join-Path $RawDir ($name + "_adc_buffers.bin")
    $counterPath = Join-Path $ContextDir ($name + "_adc_counters.txt")
    $ctxPath = Join-Path $ContextDir ($name + "_context.json")
    $metricPath = Join-Path $MetricDir ($name + "_sig_mod_lines.txt")
    $mergedLogPath = $null
    $scopePath = $null
    $metricLineCount = 0

    try {
        Set-Carrier -CarrierHz $c.carrier_hz
        Set-Modulation -Case $c
        Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
        Reset-Mcu
        Start-Sleep -Seconds 10
        Read-AdcBuffers -OutBin $rawPath
        Read-Counters -OutTxt $counterPath
        $scopePath = Export-Scope -Prefix $name
        $mergedLogPath = Export-Logs -Prefix $name
        $ctx = Invoke-ApiGet "/api/ai/context"
        ($ctx | ConvertTo-Json -Depth 10) | Set-Content -Path $ctxPath -Encoding UTF8
        if ($mergedLogPath) {
            $metricLineCount = Extract-MetricsLines -MergedLogPath $mergedLogPath -OutPath $metricPath
        }
    } catch {
        $errText = $_.Exception.Message
    }

    $rawBytes = 0
    $nonzeroBytes = 0
    if (Test-Path $rawPath) {
        $rawBytes = (Get-Item $rawPath).Length
        $bytes = [IO.File]::ReadAllBytes($rawPath)
        foreach ($b in $bytes) {
            if ($b -ne 0) { $nonzeroBytes++ }
        }
    }

    Add-Manifest @{
        index = $idx
        name = $name
        id = $c.id
        requested = $c
        started_at = $start.ToString("yyyy-MM-dd HH:mm:ss.fff")
        finished_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        dg_channel = $DgChannel
        scope_channel = $ScopeChannel
        serial_port = $SerialPort
        rf_amplitude_vpp = $RfAmpVpp
        rf_offset_v = $RfOffsetV
        raw_iq = @{ path = $rawPath; bytes = $rawBytes; nonzero_bytes = $nonzeroBytes }
        adc_counters_path = $counterPath
        context_path = $ctxPath
        merged_log_path = $mergedLogPath
        metrics_lines_path = $metricPath
        metrics_line_count = $metricLineCount
        scope_csv_path = $scopePath
        error = $errText
    }
}

Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR$DgChannel:MOD OFF" } | Out-Null
if ($oldSerialLogDir) {
    Invoke-ApiPost "/api/serial/log-dir" @{ log_dir = [string]$oldSerialLogDir } | Out-Null
}
Write-Host ("Capture complete: " + $Root)
