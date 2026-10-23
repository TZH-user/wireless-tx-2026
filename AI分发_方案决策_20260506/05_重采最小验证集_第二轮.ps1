$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$SerialPort = "COM15"
$SerialBaud = 115200
$RfAmpVpp = 1.5
$RfOffsetV = 0.0
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$FwText = "fw_id,moddet_review2_20260506,build=20260506_0308,ask=edge_freq,psk=pos_only"

$Root = Join-Path $PSScriptRoot ("43_min_verify_after_fwid_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$LogDir = Join-Path $Root "logs"
$ReportPath = Join-Path $Root "01_testdata_output.md"
$SummaryPath = Join-Path $Root "summary.csv"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

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
        Copy-Item -LiteralPath $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Analyze-Log {
    param([string]$LogPath)
    $lines = Get-Content -LiteralPath $LogPath -Encoding UTF8
    $fw = @($lines | Where-Object { $_ -like "*$FwText*" })
    $sigdet = @($lines | Where-Object { $_ -match "sigdet_final" })
    $mods = @($lines | Where-Object { $_ -match "\[RX\]\s+mod," })
    [pscustomobject]@{
        fw_hit = ($fw.Count -gt 0)
        sigdet_hit = ($sigdet.Count -gt 0)
        fw_line = if ($fw.Count -gt 0) { $fw[0] } else { "" }
        sigdet_line = if ($sigdet.Count -gt 0) { $sigdet[0] } else { "" }
        mod_count = $mods.Count
        mod1 = if ($mods.Count -gt 0) { $mods[0] } else { "" }
        mod2 = if ($mods.Count -gt 1) { $mods[1] } else { "" }
    }
}

$cases = @(
    @{ id = "ASK_40M_a0p75_r10k"; type = "ASK"; carrier_hz = 40000000; rate_hz = 10000; ask_low_vpp = 0.75; wait_s = 12 },
    @{ id = "PSK_40M_p180_r10k"; type = "PSK"; carrier_hz = 40000000; rate_hz = 10000; phase_deg = 180; wait_s = 12 }
)

Ensure-Serial
$rows = @()
$idx = 0
foreach ($c in $cases) {
    $idx++
    $name = "{0:D2}_{1}" -f $idx, $c.id
    Write-Host ("[{0}/{1}] {2}" -f $idx, $cases.Count, $name)
    Set-Carrier -CarrierHz $c.carrier_hz
    Set-Modulation -Case $c
    Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
    Start-Sleep -Milliseconds 200
    Reset-Mcu
    Start-Sleep -Seconds ([int]$c.wait_s)
    $log = Export-MergedLog -Prefix $name
    $a = Analyze-Log -LogPath $log
    $rows += [pscustomobject]@{
        case_id = $c.id
        log_path = $log
        fw_id_hit = $a.fw_hit
        sigdet_final_hit = $a.sigdet_hit
        mod_count = $a.mod_count
        fw_line = $a.fw_line
        sigdet_line = $a.sigdet_line
        mod1 = $a.mod1
        mod2 = $a.mod2
    }
}

$rows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8

$md = @()
$md += "# Test Data AI Output (Round2 minimal verify recapture)"
$md += ""
$md += "- time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
$md += "- data_root: `"$Root`""
$md += "- required fw_id: `"$FwText`""
$md += ""
$md += "## Summary"
$md += ""
$md += "| case | fw_id_hit | sigdet_final_hit | mod_count | log_path |"
$md += "|---|---|---|---:|---|"
foreach ($r in $rows) {
    $md += "| $($r.case_id) | $($r.fw_id_hit) | $($r.sigdet_final_hit) | $($r.mod_count) | `"$($r.log_path)`" |"
}
$md += ""
$md += "## Key Lines"
$md += ""
foreach ($r in $rows) {
    $md += "### " + $r.case_id
    $md += "- fw_id: " + ($(if($r.fw_line){$r.fw_line}else{"<none>"}))
    $md += "- sigdet_final: " + ($(if($r.sigdet_line){$r.sigdet_line}else{"<none>"}))
    $md += "- mod1: " + ($(if($r.mod1){$r.mod1}else{"<none>"}))
    $md += "- mod2: " + ($(if($r.mod2){$r.mod2}else{"<none>"}))
    $md += ""
}

Set-Content -LiteralPath $ReportPath -Value $md -Encoding UTF8
Write-Host ("Capture complete: " + $Root)
