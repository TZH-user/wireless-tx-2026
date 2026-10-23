$ErrorActionPreference = "Stop"

$Api = "http://127.0.0.1:8765"
$DgChannel = 1
$RfAmpVpp = 1.5
$RfOffsetV = 0.0
$Programmer = "C:\Users/<user>\AppData\Local\stm32cube\bundles\programmer\2.22.0+st.1\bin\STM32_Programmer_CLI.exe"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs\tune1_matrix"
$SummaryPath = Join-Path $Root "metrics\tune1_matrix_summary.csv"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-ApiGet([string]$Path) {
    Invoke-RestMethod -Method Get -Uri ($Api + $Path) -TimeoutSec 15
}

function Invoke-ApiPost([string]$Path, [object]$BodyObj) {
    $json = $BodyObj | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Post -Uri ($Api + $Path) -ContentType "application/json; charset=utf-8" -Body $json -TimeoutSec 20
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
    if ($Case.type -eq "CW") {
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

    if ($Case.type -eq "AM") {
        $body.depth_percent = [double]$Case.depth_percent
    } elseif ($Case.type -eq "FM") {
        $body.deviation = [double]$Case.deviation_hz
    } elseif ($Case.type -eq "ASK") {
        $body.amplitude_vpp = [double]$Case.ask_low_vpp
        $body.polarity = "POS"
    } elseif ($Case.type -eq "FSK") {
        $body.hop_frequency_hz = [double]$Case.hop_frequency_hz
        $body.polarity = "POS"
    } elseif ($Case.type -eq "PSK") {
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
    if ($null -ne $resp.file_path -and (Test-Path -LiteralPath $resp.file_path)) {
        $dst = Join-Path $LogDir ($Prefix + "_merged_" + (Split-Path $resp.file_path -Leaf))
        Copy-Item -LiteralPath $resp.file_path -Destination $dst -Force
        return $dst
    }
    return $null
}

function Parse-ModLine([string]$Line) {
    if ($Line -match "mod,(mode|m)=([^,\r\n]+)") { return $matches[2] }
    return ""
}

function Extract-Stats([string]$LogPath, [string]$Expected) {
    $lines = Get-Content -LiteralPath $LogPath -Encoding UTF8
    $fw = @($lines | Where-Object { $_ -match "fw_id," })
    $sig = @($lines | Where-Object { $_ -match "sigdet_final" })
    $mods = @($lines | Where-Object { $_ -match "\[RX\]\s+mod," })
    $modes = @()
    foreach ($line in $mods) {
        $mode = Parse-ModLine $line
        if ($mode.Length -gt 0 -and $mode -ne "UNKNOWN") { $modes += $mode }
    }
    $modeCounts = @{}
    foreach ($m in $modes) {
        if (-not $modeCounts.ContainsKey($m)) { $modeCounts[$m] = 0 }
        $modeCounts[$m]++
    }
    $majority = ""
    $maxCount = 0
    foreach ($k in $modeCounts.Keys) {
        if ($modeCounts[$k] -gt $maxCount) { $maxCount = $modeCounts[$k]; $majority = $k }
    }
    [pscustomobject]@{
        expected = $Expected
        fw_id_found = ($fw.Count -gt 0)
        sigdet_final_found = ($sig.Count -gt 0)
        mod_count = $mods.Count
        first_mode = if ($modes.Count -gt 0) { $modes[0] } else { "" }
        majority_mode = $majority
        majority_count = $maxCount
        all_modes = (($modeCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ";")
        first_mod_line = if ($mods.Count -gt 0) { $mods[0] } else { "" }
        last_mod_line = if ($mods.Count -gt 0) { $mods[-1] } else { "" }
        sigdet_line = if ($sig.Count -gt 0) { $sig[0] } else { "" }
        fw_id_line = if ($fw.Count -gt 0) { $fw[0] } else { "" }
    }
}

function Safe-Stop() {
    try { Invoke-ApiPost "/api/raw/write" @{ command = ":SOUR$DgChannel`:MOD OFF" } | Out-Null } catch {}
    try { Invoke-ApiPost "/api/channel/$DgChannel/output" @{ enabled = $false } | Out-Null } catch {}
}
$cases = @()
foreach ($f in @(30000000, 40000000, 50000000)) {
    $mhz = [int]($f / 1000000)
    $cases += @{ id="CW_${mhz}M"; expected="CW"; type="CW"; carrier_hz=$f; wait_s=12 }
    $cases += @{ id="AM_${mhz}M_10k_50pct"; expected="AM"; type="AM"; carrier_hz=$f; rate_hz=10000; depth_percent=50; wait_s=12 }
    $cases += @{ id="FM_${mhz}M_10k_dev75k"; expected="FM"; type="FM"; carrier_hz=$f; rate_hz=10000; deviation_hz=75000; wait_s=12 }
    $cases += @{ id="ASK_${mhz}M_10k_low0"; expected="ASK"; type="ASK"; carrier_hz=$f; rate_hz=10000; ask_low_vpp=0.0; wait_s=12 }
    $cases += @{ id="FSK_${mhz}M_10k_hop20k"; expected="FSK"; type="FSK"; carrier_hz=$f; rate_hz=10000; hop_frequency_hz=($f + 20000); wait_s=12 }
    $cases += @{ id="PSK_${mhz}M_10k_180"; expected="PSK"; type="PSK"; carrier_hz=$f; rate_hz=10000; phase_deg=180; wait_s=12 }
}
$rows = @()
$idx = 0
try {
foreach ($c in $cases) {
    $idx++
    $name = "{0:D2}_{1}" -f $idx, $c.id
    Write-Host "[$idx/$($cases.Count)] $name"
    Set-Carrier ([int]$c.carrier_hz)
    Set-Modulation $c
    Invoke-ApiPost "/api/serial/logs/clear" @{} | Out-Null
    Reset-Mcu
    Start-Sleep -Seconds ([int]$c.wait_s)
    $logPath = Export-MergedLog $name
    $s = Extract-Stats $logPath $c.expected
    $rows += [pscustomobject]@{
        case_id = $c.id
        expected = $c.expected
        first_mode = $s.first_mode
        majority_mode = $s.majority_mode
        pass_majority = ($s.majority_mode -eq $c.expected)
        mod_count = $s.mod_count
        all_modes = $s.all_modes
        fw_id_found = $s.fw_id_found
        sigdet_final_found = $s.sigdet_final_found
        log_path = $logPath
        fw_id_line = $s.fw_id_line
        sigdet_line = $s.sigdet_line
        first_mod_line = $s.first_mod_line
        last_mod_line = $s.last_mod_line
    }
}

}
finally {
    Safe-Stop
}
$rows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8
$rows | Format-Table case_id,expected,first_mode,majority_mode,pass_majority,mod_count,all_modes -AutoSize
Write-Host "summary=$SummaryPath"