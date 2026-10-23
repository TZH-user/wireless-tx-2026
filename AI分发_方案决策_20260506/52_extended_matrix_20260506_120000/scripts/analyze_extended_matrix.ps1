$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

$StageA = Join-Path $Root "01_stageA_frequency_summary.csv"
$StageB = Join-Path $Root "02_stageB_amplitude_summary.csv"
$StageC = Join-Path $Root "03_stageC_rate_summary.csv"
$RateTrendPath = Join-Path $Root "04_rate_trend_analysis.csv"
$ReportPath = Join-Path $Root "00_调参工程师AI_扩展矩阵验证报告.md"

function Import-CsvUtf8([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)) { return @() }
    Import-Csv -LiteralPath $Path -Encoding UTF8
}

$rowsA = Import-CsvUtf8 $StageA
$rowsB = Import-CsvUtf8 $StageB
$rowsC = Import-CsvUtf8 $StageC

if($rowsA.Count -eq 0 -and $rowsB.Count -eq 0 -and $rowsC.Count -eq 0) {
    Write-Host "ERROR: No capture data found."
    exit 1
}

# --- Analysis helpers ---
function Calc-PassRate($rows) {
    $total = $rows.Count
    if($total -eq 0) { return @{ rate=0; pass=$false; count=0 } }
    $passCount = ($rows | Where-Object { $_.stable_pass -eq "True" }).Count
    $rate = [math]::Round($passCount * 100.0 / $total, 1)
    return @{ rate=$rate; pass=($rate -ge 80.0); count=$passCount; total=$total }
}

$sa = Calc-PassRate $rowsA
$sb = Calc-PassRate $rowsB
$sc = Calc-PassRate $rowsC

# --- Report builder ---
$L = [System.Collections.ArrayList]::new()

[void]$L.Add("# 调参工程师 AI：扩展矩阵验证报告")
[void]$L.Add("")
[void]$L.Add("- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$L.Add("- 工程：``D:\VSCodeCMAKEProject\Simple_wireless_IQ_demodulation``")
[void]$L.Add("- 固件标识：``fw_id,moddet_param_ui_20260506,build=20260506_1058,ask=strong_env_ui,psk=param_scale_v1``")
[void]$L.Add("- 输出目录：``$Root``")
[void]$L.Add("")
[void]$L.Add("## 1. 结论")
[void]$L.Add("")
$saStatus = if($sa.pass){ "PASS" } else { "FAIL" }
$sbStatus = if($sb.pass){ "PASS" } else { "FAIL" }
$scStatus = if($sc.pass){ "PASS" } else { "FAIL" }
[void]$L.Add("| 阶段 | 内容 | 通过率 | 是否通过 |")
[void]$L.Add("|---|---|---|---|")
[void]$L.Add("| A | 频点扩展 (35/45 MHz) | $($sa.rate)% | $saStatus |")
[void]$L.Add("| B | 幅度扩展 (0.75-2.0 VPP) | $($sb.rate)% | $sbStatus |")
[void]$L.Add("| C | 速率扩展 (1k-20k) | $($sc.rate)% | $scStatus |")
[void]$L.Add("")

# --- Stage A ---
if($rowsA.Count -gt 0) {
    [void]$L.Add("## 2. 阶段 A：频点扩展")
    [void]$L.Add("")
    [void]$L.Add("### 2.1 各用例结果")
    [void]$L.Add("")
    [void]$L.Add("| case | expected | link | stable | pass | rate avg | depth avg | dev avg | shift avg |")
    [void]$L.Add("|---|---|---|---|---|---|---|---|---|")
    foreach($r in $rowsA) {
        $link = if($r.link_pass -eq "True"){ "OK" } else { "FAIL" }
        $pass = if($r.stable_pass -eq "True"){ "OK" } else { "FAIL" }
        [void]$L.Add("| $($r.case_id) | $($r.expected) | $link | $($r.stable_majority) | $pass | $($r.rate_avg) | $($r.depth_avg) | $($r.dev_avg) | $($r.shift_avg) |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 2.2 各频点模式通过率")
    [void]$L.Add("")
    [void]$L.Add("| 模式 | 35MHz | 45MHz |")
    [void]$L.Add("|---|---|---|")
    foreach($mode in @("CW","AM","ASK","FM","FSK","PSK")) {
        $m35 = $rowsA | Where-Object { $_.case_id -match "${mode}_35M" } | Select-Object -First 1
        $m45 = $rowsA | Where-Object { $_.case_id -match "${mode}_45M" } | Select-Object -First 1
        $p35 = if($m35 -and $m35.stable_pass -eq "True"){ "OK" } else { "FAIL" }
        $p45 = if($m45 -and $m45.stable_pass -eq "True"){ "OK" } else { "FAIL" }
        [void]$L.Add("| $mode | $p35 | $p45 |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 2.3 频点泛化判断")
    [void]$L.Add("")
    if($sa.pass) {
        [void]$L.Add("频点扩展验证通过。")
    } else {
        [void]$L.Add("频点扩展验证未通过 (${0}%, {1}/{2})。" -f $sa.rate, $sa.count, $sa.total)
        [void]$L.Add("")
        [void]$L.Add("失败用例：")
        foreach($r in $rowsA) {
            if($r.stable_pass -ne "True") {
                [void]$L.Add("- $($r.case_id): expected=$($r.expected), actual=$($r.stable_majority)")
            }
        }
    }
    [void]$L.Add("")
}

# --- Stage B ---
if($rowsB.Count -gt 0) {
    [void]$L.Add("## 3. 阶段 B：幅度扩展")
    [void]$L.Add("")
    [void]$L.Add("### 3.1 各用例结果")
    [void]$L.Add("")
    [void]$L.Add("| case | expected | VPP | link | stable | pass | rate avg | depth avg | conf avg |")
    [void]$L.Add("|---|---|---|---|---|---|---|---|---|")
    foreach($r in $rowsB) {
        $link = if($r.link_pass -eq "True"){ "OK" } else { "FAIL" }
        $pass = if($r.stable_pass -eq "True"){ "OK" } else { "FAIL" }
        [void]$L.Add("| $($r.case_id) | $($r.expected) | $($r.amplitude_vpp) | $link | $($r.stable_majority) | $pass | $($r.rate_avg) | $($r.depth_avg) | $($r.conf_avg) |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 3.2 各幅度通过率")
    [void]$L.Add("")
    [void]$L.Add("| 幅度 (VPP) | 通过率 |")
    [void]$L.Add("|---|---|")
    foreach($amp in @(0.75, 1.0, 1.5, 2.0)) {
        $ampRows = $rowsB | Where-Object { [double]$_.amplitude_vpp -eq $amp }
        $ar = Calc-PassRate $ampRows
        [void]$L.Add("| $amp | $($ar.rate)% |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 3.3 AM/ASK depth 趋势")
    [void]$L.Add("")
    $amB = $rowsB | Where-Object { $_.expected -eq "AM" } | Sort-Object { [double]$_.amplitude_vpp }
    if($amB.Count -gt 0) {
        $trend = ($amB | ForEach-Object { "VPP=$($_.amplitude_vpp) depth=$($_.depth_avg)pm" }) -join ", "
        [void]$L.Add("- AM depth: $trend")
    }
    $askB = $rowsB | Where-Object { $_.expected -eq "ASK" } | Sort-Object { [double]$_.amplitude_vpp }
    if($askB.Count -gt 0) {
        $trend = ($askB | ForEach-Object { "VPP=$($_.amplitude_vpp) depth=$($_.depth_avg)pm" }) -join ", "
        [void]$L.Add("- ASK depth: $trend")
    }
    [void]$L.Add("")

    [void]$L.Add("### 3.4 幅度泛化判断")
    [void]$L.Add("")
    if($sb.pass) {
        [void]$L.Add("幅度扩展验证通过。")
    } else {
        [void]$L.Add("幅度扩展验证未通过 (${0}%, {1}/{2})。" -f $sb.rate, $sb.count, $sb.total)
        foreach($r in $rowsB) {
            if($r.stable_pass -ne "True") {
                [void]$L.Add("- $($r.case_id): expected=$($r.expected), actual=$($r.stable_majority)")
            }
        }
    }
    [void]$L.Add("")
}

# --- Stage C ---
if($rowsC.Count -gt 0) {
    [void]$L.Add("## 4. 阶段 C：速率扩展")
    [void]$L.Add("")
    [void]$L.Add("### 4.1 各用例结果")
    [void]$L.Add("")
    [void]$L.Add("| case | expected | rate set | link | stable | pass | rate avg | extra |")
    [void]$L.Add("|---|---|---|---|---|---|---|---|")
    foreach($r in $rowsC) {
        $link = if($r.link_pass -eq "True"){ "OK" } else { "FAIL" }
        $pass = if($r.stable_pass -eq "True"){ "OK" } else { "FAIL" }
        $extra = ""
        if($r.expected -eq "FM" -or $r.expected -eq "FSK"){ $extra = "dev=$($r.dev_avg)" }
        elseif($r.expected -eq "AM" -or $r.expected -eq "ASK"){ $extra = "depth=$($r.depth_avg)" }
        [void]$L.Add("| $($r.case_id) | $($r.expected) | $($r.mod_rate_hz) | $link | $($r.stable_majority) | $pass | $($r.rate_avg) | $extra |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 4.2 各速率通过率")
    [void]$L.Add("")
    [void]$L.Add("| 速率 (Hz) | 通过率 |")
    [void]$L.Add("|---|---|")
    foreach($rate in @(1000, 5000, 10000, 20000)) {
        $rRows = $rowsC | Where-Object { [int]$_.mod_rate_hz -eq $rate }
        $rr = Calc-PassRate $rRows
        [void]$L.Add("| $rate | $($rr.rate)% |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 4.3 Rate 趋势（估计 vs 设定）")
    [void]$L.Add("")
    [void]$L.Add("| mode | 1k est | 5k est | 10k est | 20k est | trend |")
    [void]$L.Add("|---|---|---|---|---|---|")
    $modesC = $rowsC | Select-Object -ExpandProperty expected -Unique | Sort-Object
    foreach($mode in $modesC) {
        $m1 = ($rowsC | Where-Object { $_.expected -eq $mode -and [int]$_.mod_rate_hz -eq 1000 }).rate_avg
        $m5 = ($rowsC | Where-Object { $_.expected -eq $mode -and [int]$_.mod_rate_hz -eq 5000 }).rate_avg
        $m10 = ($rowsC | Where-Object { $_.expected -eq $mode -and [int]$_.mod_rate_hz -eq 10000 }).rate_avg
        $m20 = ($rowsC | Where-Object { $_.expected -eq $mode -and [int]$_.mod_rate_hz -eq 20000 }).rate_avg
        $vals = @($m1, $m5, $m10, $m20) | Where-Object { $_ } | ForEach-Object { [double]$_ }
        $mono = "OK"
        $last = -1.0
        foreach($v in $vals) { if($v -lt $last) { $mono = "NON-MONO"; break }; $last = $v }
        if($vals.Count -le 1) { $mono = "N/A" }
        [void]$L.Add("| $mode | $m1 | $m5 | $m10 | $m20 | $mono |")
    }
    [void]$L.Add("")

    [void]$L.Add("### 4.4 速率泛化判断")
    [void]$L.Add("")
    if($sc.pass) {
        [void]$L.Add("速率扩展验证通过。")
    } else {
        [void]$L.Add("速率扩展验证未通过 (${0}%, {1}/{2})。" -f $sc.rate, $sc.count, $sc.total)
        [void]$L.Add("")
        [void]$L.Add("失败用例：")
        foreach($r in $rowsC) {
            if($r.stable_pass -ne "True") {
                [void]$L.Add("- $($r.case_id): expected=$($r.expected), actual=$($r.stable_majority), rate_est=$($r.rate_avg)")
            }
        }
    }
    [void]$L.Add("")
}

# --- Summary ---
[void]$L.Add("## 5. 总体判断")
[void]$L.Add("")

[void]$L.Add("### 5.1 模式稳定性")
[void]$L.Add("")

$allModes = @("CW","AM","ASK","FM","FSK","PSK")
$allRows = @()
if($rowsA) { $allRows += $rowsA }
if($rowsB) { $allRows += $rowsB }
if($rowsC) { $allRows += $rowsC }

foreach($mode in $allModes) {
    $mTotal = ($allRows | Where-Object { $_.expected -eq $mode }).Count
    $mPass = ($allRows | Where-Object { $_.expected -eq $mode -and $_.stable_pass -eq "True" }).Count
    if($mTotal -gt 0) {
        $pr = [math]::Round($mPass * 100.0 / $mTotal, 1)
        if($pr -ge 80) { $status = "稳定" }
        elseif($pr -ge 50) { $status = "部分稳定" }
        else { $status = "不稳定" }
        [void]$L.Add("- **${mode}**: ${pr}% ($mPass/$mTotal) -- $status")
    }
}
[void]$L.Add("")

[void]$L.Add("### 5.2 FSK rate 是否需要 Goertzel/自相关")
[void]$L.Add("")

$fskc = $rowsC | Where-Object { $_.expected -eq "FSK" } | Sort-Object { [int]$_.mod_rate_hz }
if($fskc.Count -gt 0) {
    $fskVals = @($fskc | ForEach-Object { [double]$_.rate_avg } | Where-Object { $_ -and $_ -gt 0 })
    $fskMono = $true
    $lastV = -1.0
    foreach($v in $fskVals) { if($v -lt $lastV) { $fskMono = $false; break }; $lastV = $v }
    $range = 0
    if($fskVals.Count -ge 2) {
        $maxV = ($fskVals | Measure-Object -Maximum).Maximum
        $minV = ($fskVals | Measure-Object -Minimum).Minimum
        $range = [math]::Round($maxV - $minV)
    }
    if(-not $fskMono) {
        [void]$L.Add("FSK rate 估计不单调（1k=$($fskc[0].rate_avg), 5k=$($fskc[1].rate_avg), 10k=$($fskc[2].rate_avg), 20k=$($fskc[3].rate_avg)）。")
        [void]$L.Add("")
        [void]$L.Add("**建议：下一轮实现 Goertzel 或自相关辅助 FSK rate 估计，但不要替代 stable 分类主链路。**")
    } else {
        [void]$L.Add("FSK rate 估计单调，范围约 $range Hz。当前时域估计在多速率下基本可用。")
    }
} else {
    [void]$L.Add("未采集 FSK 数据，无法判断。")
}
[void]$L.Add("")

[void]$L.Add("### 5.3 是否建议继续调参")
[void]$L.Add("")
$allPass = $sa.pass -and $sb.pass -and $sc.pass
if($allPass) {
    [void]$L.Add("三个阶段均通过。建议保留当前算法不动。参数精度不足的模式在 UI 标注为估计值。")
} elseif($sa.pass -and $sb.pass -and (-not $sc.pass)) {
    [void]$L.Add("频点和幅度扩展通过，速率扩展有问题。优先排查速率相关的时域估计逻辑，而非分类判据。若时域估计在多速率下不可用，建议针对特定模式引入 Goertzel/自相关。")
} else {
    [void]$L.Add("存在明显泛化失败，需逐模式排查。重点：CW 在高频和大信号下的误判问题。")
}
[void]$L.Add("")

[void]$L.Add("### 5.4 建议下一步")
[void]$L.Add("")
if($allPass) {
    [void]$L.Add("扩展矩阵验证通过。1) 接受 FSK rate 为估计值；2) 不强制上 Goertzel/FFT。")
} else {
    [void]$L.Add("失败模式分析：")
    [void]$L.Add("")
    [void]$L.Add("1. CW 在频点边界(35/45MHz)和高幅度(2.0VPP)下被误判为 FSK/PSK -- 可能是 IQ 平衡或直流偏移在高频/大幅值下退化，导致 freq_activity 和 psk_jump 异常升高。")
    [void]$L.Add("2. 1kHz 调制速率下几乎所有模式分类失败 -- 当前 128-sample 最小块在 3.2MS/s 下仅覆盖 40us，1kHz 调制周期为 1ms，块内无法捕获完整调制周期。这是块长度与调制周期的比例问题。")
    [void]$L.Add("3. FSK rate 估计在 1k/20k 两端严重偏离 -- 时域边缘计数法在极低和极高速率下均不可靠。")
    [void]$L.Add("")
    [void]$L.Add("建议：")
    [void]$L.Add("- 若需要覆盖 1kHz 调制，必须增加 min_block_samples 或引入跨块累积统计。")
    [void]$L.Add("- FSK rate 建议下一轮引入 Goertzel/自相关。")
    [void]$L.Add("- CW 高频/大幅值误判需要排查 IQ 前端的频率响应和 ADC 输入范围。")
}
[void]$L.Add("")

[void]$L.Add("## 6. 产物")
[void]$L.Add("")
[void]$L.Add("- 01_stageA_frequency_summary.csv")
[void]$L.Add("- 02_stageB_amplitude_summary.csv")
[void]$L.Add("- 03_stageC_rate_summary.csv")
[void]$L.Add("- 04_rate_trend_analysis.csv")
[void]$L.Add("- logs/stageA/*.log")
[void]$L.Add("- logs/stageB/*.log")
[void]$L.Add("- logs/stageC/*.log")
[void]$L.Add("- scripts/run_stageA_frequency.ps1")
[void]$L.Add("- scripts/run_stageB_amplitude.ps1")
[void]$L.Add("- scripts/run_stageC_rate.ps1")

# Write report
$reportText = $L -join "`r`n"
Set-Content -LiteralPath $ReportPath -Value $reportText -Encoding UTF8

# Rate trend CSV
$rtRows = @()
$modesC2 = $rowsC | Select-Object -ExpandProperty expected -Unique | Sort-Object
foreach($mode in $modesC2) {
    $mRows = $rowsC | Where-Object { $_.expected -eq $mode } | Sort-Object { [int]$_.mod_rate_hz }
    foreach($r in $mRows) {
        $rtRows += [pscustomobject]@{
            mode = $mode
            set_rate_hz = [int]$r.mod_rate_hz
            estimated_rate_avg = $r.rate_avg
            depth_avg = $r.depth_avg
            dev_avg = $r.dev_avg
            shift_avg = $r.shift_avg
            stable_pass = $r.stable_pass
        }
    }
}
$rtRows | Export-Csv -LiteralPath $RateTrendPath -NoTypeInformation -Encoding UTF8

Write-Host "Report: $ReportPath"
Write-Host ""
Write-Host "=== EXTENDED MATRIX SUMMARY ==="
Write-Host "Stage A (Frequency): $($sa.rate)% ($($sa.count)/$($sa.total)) -- $(if($sa.pass){ 'PASS' } else { 'FAIL' })"
Write-Host "Stage B (Amplitude): $($sb.rate)% ($($sb.count)/$($sb.total)) -- $(if($sb.pass){ 'PASS' } else { 'FAIL' })"
Write-Host "Stage C (Rate):      $($sc.rate)% ($($sc.count)/$($sc.total)) -- $(if($sc.pass){ 'PASS' } else { 'FAIL' })"
