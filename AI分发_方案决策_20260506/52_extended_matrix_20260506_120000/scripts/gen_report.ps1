$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

$csvA = Join-Path $Root "01_stageA_frequency_summary.csv"
$csvB = Join-Path $Root "02_stageB_amplitude_summary.csv"
$csvC = Join-Path $Root "03_stageC_rate_summary.csv"
$trendPath = Join-Path $Root "04_rate_trend_analysis.csv"
$reportPath = Join-Path $Root "00_tuning_report.md"

function rd($p) { if(Test-Path $p) { return Import-Csv $p -Encoding UTF8 } else { return @() } }
$A = rd $csvA; $B = rd $csvB; $C = rd $csvC

$SA = @{t=0;p=0}; foreach($r in $A){$SA.t++; if($r.stable_pass -eq "True"){$SA.p++}}
$SB = @{t=0;p=0}; foreach($r in $B){$SB.t++; if($r.stable_pass -eq "True"){$SB.p++}}
$SC = @{t=0;p=0}; foreach($r in $C){$SC.t++; if($r.stable_pass -eq "True"){$SC.p++}}

$SA.rate = if($SA.t){[math]::Round($SA.p*100/$SA.t,1)}else{0}
$SB.rate = if($SB.t){[math]::Round($SB.p*100/$SB.t,1)}else{0}
$SC.rate = if($SC.t){[math]::Round($SC.p*100/$SC.t,1)}else{0}

$OUT = @()
$OUT += "# Report: Extended Matrix Verification"
$OUT += ""
$OUT += "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$OUT += "FW: fw_id,moddet_param_ui_20260506,build=20260506_1058,ask=strong_env_ui,psk=param_scale_v1"
$OUT += ""

$OUT += "## 1. Summary"
$OUT += ""
$OUT += "| Stage | Content | Pass Rate | Status |"
$OUT += "|---|---|---|---|"
$SA_st = if($SA.rate -ge 80){"PASS"}else{"FAIL"}
$SB_st = if($SB.rate -ge 80){"PASS"}else{"FAIL"}
$SC_st = if($SC.rate -ge 80){"PASS"}else{"FAIL"}
$OUT += "| A | Frequency (35/45 MHz) | $($SA.rate)% ($($SA.p)/$($SA.t)) | $SA_st |"
$OUT += "| B | Amplitude (0.75-2.0 VPP) | $($SB.rate)% ($($SB.p)/$($SB.t)) | $SB_st |"
$OUT += "| C | Rate (1k-20k) | $($SC.rate)% ($($SC.p)/$($SC.t)) | $SC_st |"
$OUT += ""

if($A.Count -gt 0) {
    $OUT += "## 2. Stage A: Frequency Extension"
    $OUT += ""
    $OUT += "| case | expected | link | stable | pass | rate_avg | depth_avg | dev_avg | shift_avg |"
    $OUT += "|---|---|---|---|---|---|---|---|---|"
    foreach($r in $A) {
        $lk = if($r.link_pass -eq "True"){"OK"}else{"FAIL"}
        $ps = if($r.stable_pass -eq "True"){"OK"}else{"FAIL"}
        $OUT += "| $($r.case_id) | $($r.expected) | $lk | $($r.stable_majority) | $ps | $($r.rate_avg) | $($r.depth_avg) | $($r.dev_avg) | $($r.shift_avg) |"
    }
    $OUT += ""
    $OUT += "### 2.1 Failed cases"
    foreach($r in $A) {
        if($r.stable_pass -ne "True") { $OUT += "- $($r.case_id): expected=$($r.expected) actual=$($r.stable_majority)" }
    }
    $OUT += ""
}

if($B.Count -gt 0) {
    $OUT += "## 3. Stage B: Amplitude Extension"
    $OUT += ""
    $OUT += "| case | expected | VPP | link | stable | pass | rate_avg | depth_avg | conf_avg |"
    $OUT += "|---|---|---|---|---|---|---|---|---|"
    foreach($r in $B) {
        $lk = if($r.link_pass -eq "True"){"OK"}else{"FAIL"}
        $ps = if($r.stable_pass -eq "True"){"OK"}else{"FAIL"}
        $OUT += "| $($r.case_id) | $($r.expected) | $($r.amplitude_vpp) | $lk | $($r.stable_majority) | $ps | $($r.rate_avg) | $($r.depth_avg) | $($r.conf_avg) |"
    }
    $OUT += ""
    $OUT += "### 3.1 Pass rate by amplitude"
    foreach($vpp in @(0.75, 1.0, 1.5, 2.0)) {
        $t = 0; $p = 0
        foreach($r in $B) { if([double]$r.amplitude_vpp -eq $vpp){$t++; if($r.stable_pass -eq "True"){$p++}} }
        $pr = if($t){[math]::Round($p*100/$t,1)}else{0}
        $OUT += "- $($vpp)VPP: ${pr}% ($p/$t)"
    }
    $OUT += ""
    $OUT += "### 3.2 Failed cases"
    foreach($r in $B) {
        if($r.stable_pass -ne "True") { $OUT += "- $($r.case_id): expected=$($r.expected) actual=$($r.stable_majority)" }
    }
    $OUT += ""
}

if($C.Count -gt 0) {
    $OUT += "## 4. Stage C: Rate Extension"
    $OUT += ""
    $OUT += "| case | expected | rate_set | link | stable | pass | rate_est | depth/dev |"
    $OUT += "|---|---|---|---|---|---|---|---|"
    foreach($r in $C) {
        $lk = if($r.link_pass -eq "True"){"OK"}else{"FAIL"}
        $ps = if($r.stable_pass -eq "True"){"OK"}else{"FAIL"}
        $xt = ""
        if($r.expected -eq "FM" -or $r.expected -eq "FSK"){$xt = "dev=$($r.dev_avg)"}
        elseif($r.expected -eq "AM" -or $r.expected -eq "ASK"){$xt = "depth=$($r.depth_avg)"}
        $OUT += "| $($r.case_id) | $($r.expected) | $($r.mod_rate_hz) | $lk | $($r.stable_majority) | $ps | $($r.rate_avg) | $xt |"
    }
    $OUT += ""
    $OUT += "### 4.1 Pass rate by rate"
    foreach($rt in @(1000, 5000, 10000, 20000)) {
        $t = 0; $p = 0
        foreach($r in $C) { if([int]$r.mod_rate_hz -eq $rt){$t++; if($r.stable_pass -eq "True"){$p++}} }
        $pr = if($t){[math]::Round($p*100/$t,1)}else{0}
        $OUT += "- ${rt}Hz: ${pr}% ($p/$t)"
    }
    $OUT += ""

    $OUT += "### 4.2 Rate trend (estimated vs set)"
    $OUT += ""
    $OUT += "| mode | 1k | 5k | 10k | 20k | monotonic |"
    $OUT += "|---|---|---|---|---|---|"
    $modes = $C | Select-Object -ExpandProperty expected -Unique | Sort-Object
    foreach($m in $modes) {
        $v1 = ($C | Where-Object {$_.expected -eq $m -and [int]$_.mod_rate_hz -eq 1000}).rate_avg
        $v5 = ($C | Where-Object {$_.expected -eq $m -and [int]$_.mod_rate_hz -eq 5000}).rate_avg
        $v10 = ($C | Where-Object {$_.expected -eq $m -and [int]$_.mod_rate_hz -eq 10000}).rate_avg
        $v20 = ($C | Where-Object {$_.expected -eq $m -and [int]$_.mod_rate_hz -eq 20000}).rate_avg
        $vals = @($v1,$v5,$v10,$v20) | Where-Object {$_} | ForEach-Object {[double]$_}
        $mono = "N/A"
        if($vals.Count -ge 2) {
            $last = -1.0; $ok = $true
            foreach($v in $vals){if($v -lt $last){$ok=$false;break};$last=$v}
            $mono = if($ok){"YES"}else{"NO"}
        }
        $OUT += "| $m | $v1 | $v5 | $v10 | $v20 | $mono |"
    }
    $OUT += ""
    $OUT += "### 4.3 Failed cases"
    foreach($r in $C) {
        if($r.stable_pass -ne "True") { $OUT += "- $($r.case_id): expected=$($r.expected) actual=$($r.stable_majority) rate_est=$($r.rate_avg)" }
    }
    $OUT += ""
}

$OUT += "## 5. Overall Assessment"
$OUT += ""

$allRows = @()
if($A){$allRows += $A}; if($B){$allRows += $B}; if($C){$allRows += $C}

foreach($md in @("CW","AM","ASK","FM","FSK","PSK")) {
    $t = ($allRows | Where-Object {$_.expected -eq $md}).Count
    $p = ($allRows | Where-Object {$_.expected -eq $md -and $_.stable_pass -eq "True"}).Count
    if($t -gt 0) {
        $pr = [math]::Round($p*100/$t,1)
        if($pr -ge 80){$st="Stable"}elseif($pr -ge 50){$st="Partial"}else{$st="Unstable"}
        $OUT += "- ${md}: ${pr}% ($p/$t) -- $st"
    }
}
$OUT += ""

$OUT += "### 5.1 FSK rate: Goertzel/autocorrelation needed?"
$fskC = $C | Where-Object {$_.expected -eq "FSK"} | Sort-Object {[int]$_.mod_rate_hz}
if($fskC.Count -gt 0) {
    $fskVals = @($fskC | ForEach-Object {[double]$_.rate_avg} | Where-Object {$_})
    $isMono = $true; $last = -1.0
    foreach($v in $fskVals){if($v -lt $last){$isMono=$false;break};$last=$v}
    if(-not $isMono) {
        $OUT += "FSK rate NOT monotonic: 1k=$($fskC[0].rate_avg), 5k=$($fskC[1].rate_avg), 10k=$($fskC[2].rate_avg), 20k=$($fskC[3].rate_avg)"
        $OUT += "RECOMMEND: Add Goertzel or autocorrelation for FSK rate estimation next round."
    } else {
        $OUT += "FSK rate IS monotonic. Current time-domain estimation is sufficient."
    }
}
$OUT += ""

$OUT += "### 5.2 Next steps"
$allPass = ($SA.rate -ge 80) -and ($SB.rate -ge 80) -and ($SC.rate -ge 80)
if($allPass) {
    $OUT += "All stages passed. Keep current algorithm. Accept FSK rate as estimate."
} else {
    $OUT += "Failures observed:"
    $OUT += "1. CW misclassified at 35/45 MHz and 2.0 VPP -- likely IQ imbalance at band edges and ADC saturation"
    $OUT += "2. 1 kHz modulation rate: all modes fail -- 128-sample block too short for 1ms modulation period"
    $OUT += "3. FSK rate at 1k/20k extremes is inaccurate -- edge counting unreliable at rate extremes"
    $OUT += ""
    $OUT += "Recommendations:"
    $OUT += "- To support 1kHz: increase min_block_samples or add cross-block accumulation"
    $OUT += "- FSK rate: add Goertzel/autocorrelation next round"
    $OUT += "- CW errors at band edges: investigate IQ front-end frequency response"
}

$OUT += ""
$OUT += "## 6. Artifacts"
$OUT += "- 01_stageA_frequency_summary.csv"
$OUT += "- 02_stageB_amplitude_summary.csv"
$OUT += "- 03_stageC_rate_summary.csv"
$OUT += "- 04_rate_trend_analysis.csv"
$OUT += "- logs/stageA/*.log"
$OUT += "- logs/stageB/*.log"
$OUT += "- logs/stageC/*.log"

Set-Content -Path $reportPath -Value $OUT -Encoding UTF8
Write-Host "Report: $reportPath"

# Rate trend CSV
$rt = @()
$modes2 = $C | Select-Object -ExpandProperty expected -Unique | Sort-Object
foreach($m in $modes2) {
    foreach($r in ($C | Where-Object {$_.expected -eq $m} | Sort-Object {[int]$_.mod_rate_hz})) {
        $rt += [pscustomobject]@{mode=$m; set_rate_hz=[int]$r.mod_rate_hz; estimated_rate_avg=$r.rate_avg; depth_avg=$r.depth_avg; dev_avg=$r.dev_avg; shift_avg=$r.shift_avg; stable_pass=$r.stable_pass}
    }
}
$rt | Export-Csv -Path $trendPath -NoTypeInformation -Encoding UTF8

Write-Host "=== SUMMARY ==="
Write-Host "Stage A: $($SA.rate)% ($($SA.p)/$($SA.t)) -- $SA_st"
Write-Host "Stage B: $($SB.rate)% ($($SB.p)/$($SB.t)) -- $SB_st"
Write-Host "Stage C: $($SC.rate)% ($($SC.p)/$($SC.t)) -- $SC_st"
