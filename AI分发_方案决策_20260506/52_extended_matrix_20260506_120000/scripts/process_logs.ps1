$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"

function Parse-LogFile($Path, $Expected) {
    if(-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{error="File not found: $Path"}
    }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $fw = @($lines | Where-Object { $_ -match 'fw_id,moddet' })
    $sig = @($lines | Where-Object { $_ -match 'sigdet_final' })
    $sigLine = if($sig.Count -gt 0){ $sig[0] } else { '' }

    $sigTime = $null
    if($sigLine -match '^\[([^\]]+)\]') {
        $sigTime = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null)
    }

    $mods = @()
    $uis = @()
    foreach($line in $lines) {
        $ts = $null
        if($line -match '^\[([^\]]+)\]') {
            try { $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss.fff', $null) } catch {}
        }
        if($sigTime -and $ts -and $ts -lt $sigTime) { continue }

        if($line -match '\[RX\]\s+mod,mode=') {
            $h = @{}
            if($line -match 'mode=([^,|]+)') { $h.mode = $matches[1] }
            if($line -match 'stable=([^,|]+)') { $h.stable = $matches[1] }
            if($line -match 'conf=([^,|]+)') { $h.conf = $matches[1] }
            if($line -match 'rate=([^,|]+)') { $h.rate = $matches[1] }
            if($line -match 'depth=([^,|]+)') { $h.depth = $matches[1] }
            if($line -match 'dev=([^,|]+)') { $h.dev = $matches[1] }
            if($line -match 'shift=([^,|]+)') { $h.shift = $matches[1] }
            if($h.ContainsKey('stable')) { $mods += [pscustomobject]$h }
        } elseif($line -match '\[RX\]\s+ui,mode=') {
            $h = @{}
            if($line -match 'mode=([^,|]+)') { $h.mode = $matches[1] }
            $uis += [pscustomobject]$h
        }
    }

    $stableCounts = @{}
    foreach($m in $mods) {
        $s = "$($m.stable)"
        if($s.Length -eq 0 -or $s -eq 'UNKNOWN') { continue }
        if(-not $stableCounts[$s]) { $stableCounts[$s] = 0 }
        $stableCounts[$s]++
    }
    $majority = ''
    $maxCnt = 0
    foreach($k in $stableCounts.Keys) {
        if($stableCounts[$k] -gt $maxCnt) { $maxCnt = $stableCounts[$k]; $majority = $k }
    }

    $countsStr = (($stableCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ';')

    $getNums = { param($arr,$key)
        $vals = @($arr | ForEach-Object { $_.$key } | Where-Object { $_ -and $_ -match '^\d+\.?\d*$' } | ForEach-Object { [double]$_ })
        if($vals.Count -eq 0) { return @{min='';avg='';max=''} }
        $m = $vals | Measure-Object -Min -Max -Average
        @{min=[math]::Round($m.Minimum,2); avg=[math]::Round($m.Average,2); max=[math]::Round($m.Maximum,2)}
    }
    $confS = & $getNums $mods 'conf'
    $rateS = & $getNums $mods 'rate'
    $depthS = & $getNums $mods 'depth'
    $devS = & $getNums $mods 'dev'
    $shiftS = & $getNums $mods 'shift'

    return [pscustomobject]@{
        fw_id_found = ($fw.Count -gt 0)
        sigdet_found = ($sig.Count -gt 0)
        mod_count = $mods.Count
        ui_count = $uis.Count
        stable_majority = $majority
        stable_counts = $countsStr
        stable_pass = ($majority -eq $Expected)
        conf_avg = $confS.avg; conf_min = $confS.min; conf_max = $confS.max
        rate_avg = $rateS.avg; rate_min = $rateS.min; rate_max = $rateS.max
        depth_avg = $depthS.avg; depth_min = $depthS.min; depth_max = $depthS.max
        dev_avg = $devS.avg; dev_min = $devS.min; dev_max = $devS.max
        shift_avg = $shiftS.avg; shift_min = $shiftS.min; shift_max = $shiftS.max
    }
}

function Process-Stage($StageDir, $ExpectedMap) {
    $rows = @()
    if(-not (Test-Path $StageDir)) { return $rows }
    $files = Get-ChildItem -LiteralPath $StageDir -Filter "*.log" | Sort-Object Name
    foreach($f in $files) {
        $caseId = $f.Name -replace '_\d{2}_(.+?)_merged_.*', '$1'
        $expected = ''
        foreach($key in $ExpectedMap.Keys) {
            if($caseId -match $key) { $expected = $ExpectedMap[$key]; break }
        }
        if($expected -eq '') { $expected = "UNKNOWN" }
        Write-Host "  $($f.Name) -> case=$caseId expected=$expected"
        $s = Parse-LogFile $f.FullName $expected
        $row = [pscustomobject]@{
            case_id = $caseId
            expected = $expected
            fw_id_found = $s.fw_id_found
            sigdet_found = $s.sigdet_found
            mod_count = $s.mod_count
            ui_count = $s.ui_count
            stable_majority = $s.stable_majority
            stable_counts = $s.stable_counts
            stable_pass = $s.stable_pass
            link_pass = ($s.fw_id_found -and $s.sigdet_found -and ($s.mod_count -ge 10) -and ($s.ui_count -ge 10))
            conf_avg = $s.conf_avg; rate_avg = $s.rate_avg; depth_avg = $s.depth_avg
            dev_avg = $s.dev_avg; shift_avg = $s.shift_avg
            rate_min = $s.rate_min; rate_max = $s.rate_max
        }
        $rows += $row
    }
    return $rows
}

# Expected maps by case ID pattern
$expMap = @{
    'CW'='CW'; 'AM'='AM'; 'ASK'='ASK'; 'FM'='FM'; 'FSK'='FSK'; 'PSK'='PSK'
}

Write-Host "=== Processing Stage A ==="
$stageA = Process-Stage (Join-Path $LogDir "stageA") $expMap
$stageA | Export-Csv -LiteralPath (Join-Path $Root "01_stageA_frequency_summary.csv") -NoTypeInformation -Encoding UTF8
Write-Host "Stage A: $($stageA.Count) cases"

Write-Host "=== Processing Stage B ==="
$stageB = Process-Stage (Join-Path $LogDir "stageB") $expMap
$stageB | Export-Csv -LiteralPath (Join-Path $Root "02_stageB_amplitude_summary.csv") -NoTypeInformation -Encoding UTF8
Write-Host "Stage B: $($stageB.Count) cases"

Write-Host "=== Processing Stage C ==="
$stageC = Process-Stage (Join-Path $LogDir "stageC") $expMap
$stageC | Export-Csv -LiteralPath (Join-Path $Root "03_stageC_rate_summary.csv") -NoTypeInformation -Encoding UTF8
Write-Host "Stage C: $($stageC.Count) cases"

Write-Host ""
Write-Host "=== Stage A Results ==="
$stageA | Format-Table case_id,expected,link_pass,stable_majority,stable_pass,rate_avg,depth_avg -AutoSize
Write-Host "=== Stage B Results ==="
$stageB | Format-Table case_id,expected,link_pass,stable_majority,stable_pass,rate_avg -AutoSize
Write-Host "=== Stage C Results ==="
$stageC | Format-Table case_id,expected,link_pass,stable_majority,stable_pass,rate_avg -AutoSize
