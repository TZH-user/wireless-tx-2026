$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$SerialPort = "COM15"
$SerialBaud = 115200
$RfAmpVpp = 1.5
$RfOffsetV = 0.0
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"

$Root = Join-Path $PSScriptRoot ("40_测试采数_第二轮_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$LogDir = Join-Path $Root "logs"
$SummaryPath = Join-Path $Root "summary.csv"
$ReportPath = Join-Path $Root "01_测试采数AI输出.md"

@($Root, $LogDir) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

function Invoke-ApiGet {
    param([string]$Path)
    Invoke-RestMethod -Method Get -Uri ($Api + $Path)
}

function Invoke-ApiPost {
    param([string]$Path, [object]$BodyObj)
    $json = $BodyObj | ConvertTo-Json -Depth 8 -Compress
    Invoke-RestMethod -Method Post -Uri ($Api + $Path) -ContentType "application/json" -Body $json
}

function Ensure-Serial {
    $st = Invoke-ApiGet "/api/serial/status"
    if (-not $st.connected) {
        Invoke-ApiPost "/api/serial/connect" @{
            port = $SerialPort
            baudrate = $SerialBaud
            bytesize = 8
            parity = "None"
            stopbits = "1"
            timeout = 0.05
            log_rx = $true
        } | Out-Null
    }
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
    if ($Case.type -eq "ASK") {
        $body.amplitude_vpp = [double]$Case.ask_low_vpp
        $body.polarity = "POS"
    } elseif ($Case.type -eq "PSK") {
        $body.phase_deg = [double]$Case.phase_deg
        $body.polarity = "POS"
    }
    Invoke-ApiPost "/api/channel/$DgChannel/modulation" $body | Out-Null
}

function Reset-Mcu {
    & $Programmer -c port=SWD mode=UR reset=SWrst | Out-Null
}

function Export-MergedLog {
    param([string]$Prefix)
    $resp = Invoke-ApiPost "/api/logs/export" @{ mode = "merged" }
    if ($null -ne $resp.file_path -and (Test-Path $resp.file_path)) {
        $dst = Join-Path $LogDir ($Prefix + "_merged_" + (Split-Path $resp.file_path -Leaf))
        Copy-Item -Path $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Extract-Stats {
    param([string]$LogPath)
    $lines = Get-Content -LiteralPath $LogPath -Encoding UTF8
    $fw = @($lines | Where-Object { $_ -match "fw_id," })
    $sig = @($lines | Where-Object { $_ -match "sigdet_final|sig,.*lk=1|sig,.*locked=1" })
    $mods = @($lines | Where-Object { $_ -match "\[RX\]\s+mod," })
    [pscustomobject]@{
        fw_id_found = ($fw.Count -gt 0)
        fw_id_line = if ($fw.Count -gt 0) { $fw[0] } else { "" }
        sigdet_final_found = ($sig.Count -gt 0)
        sigdet_line = if ($sig.Count -gt 0) { $sig[0] } else { "" }
        mod_count = $mods.Count
        mod_sample_1 = if ($mods.Count -gt 0) { $mods[0] } else { "" }
        mod_sample_2 = if ($mods.Count -gt 1) { $mods[1] } else { "" }
    }
}

$cases = @(
    @{ id = "CW_40M_SIGDET"; type = "CW"; carrier_hz = 40000000; wait_s = 14 },
    @{ id = "ASK_40M_a0p75_r10k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 10000; ask_low_vpp = 0.75; wait_s = 12 },
    @{ id = "PSK_40M_p180_r10k"; type = "PSK"; carrier_hz = 40000000; rate_hz = 10000; phase_deg = 180; wait_s = 12 }
)

Ensure-Serial
$rows = @()
$index = 0
foreach ($c in $cases) {
    $index++
    $name = "{0:D2}_{1}" -f $index, $c.id
    Write-Host ("[{0}/{1}] {2}" -f $index, $cases.Count, $name)
    Set-Carrier -CarrierHz $c.carrier_hz
    Set-Modulation -Case $c
    Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
    Reset-Mcu
    Start-Sleep -Seconds ([int]$c.wait_s)
    $logPath = Export-MergedLog -Prefix $name
    $s = Extract-Stats -LogPath $logPath
    $rows += [pscustomobject]@{
        case_id = $c.id
        log_path = $logPath
        fw_id_found = $s.fw_id_found
        fw_id_line = $s.fw_id_line
        sigdet_final_found = $s.sigdet_final_found
        sigdet_line = $s.sigdet_line
        mod_count = $s.mod_count
        mod_sample_1 = $s.mod_sample_1
        mod_sample_2 = $s.mod_sample_2
    }
}

$rows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8

$md = @()
$md += "# Test Data AI Output (Round2 Minimal Capture)"
$md += ""
$md += "- time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$md += "- data_root: `"$Root`""
$md += "- instrument: DG CH$DgChannel, SIN, 1.5Vpp, 0V offset, HIGHZ"
$md += "- serial: $SerialPort @ $SerialBaud"
$md += ""
$md += "## Summary"
$md += ""
$md += "| case | fw_id | sigdet_final | mod_count | log_path |"
$md += "|---|---|---|---:|---|"
foreach ($r in $rows) {
    $md += "| $($r.case_id) | $($r.fw_id_found) | $($r.sigdet_final_found) | $($r.mod_count) | `"$($r.log_path)`" |"
}
$md += ""
$md += "## Key Lines"
$md += ""
foreach ($r in $rows) {
    $md += "### " + $r.case_id
    $md += "- fw_id: " + ($(if($r.fw_id_line){$r.fw_id_line}else{"<none>"}))
    $md += "- sigdet: " + ($(if($r.sigdet_line){$r.sigdet_line}else{"<none>"}))
    $md += "- mod1: " + ($(if($r.mod_sample_1){$r.mod_sample_1}else{"<none>"}))
    $md += "- mod2: " + ($(if($r.mod_sample_2){$r.mod_sample_2}else{"<none>"}))
    $md += ""
}

Set-Content -LiteralPath $ReportPath -Value $md -Encoding UTF8
Write-Host ("Capture complete: " + $Root)
