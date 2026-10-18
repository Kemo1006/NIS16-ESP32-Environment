# gui\Stamps.ps1 - "did the data change?" for run_gui.ps1 (oct. 18 2026).
# Dot-sourced by run_gui.ps1 at start-up. ASCII only (PS 5.1 misreads others).
#
# One cheap scan of datasets\exports + datasets\analysis (~2,600 files, well
# under 0.1 s): per run folder (attack/topology/location/scenario) the file
# count and the newest write time. Pages refresh only when this changed, and
# the Campaign's redo check re-runs only the runs that changed - instead of
# re-reading everything on every page open (slow) or never (stale: a Campaign
# tile said "0 children" after the children had been imported).

function Get-CellStamps {
    $map = @{}
    foreach ($area in 'exports', 'analysis') {
        $root = Join-Path $base "datasets\$area"
        if (-not (Test-Path $root)) { continue }
        $cut = $root.Length + 1
        foreach ($f in ([IO.DirectoryInfo]$root).EnumerateFiles('*', 'AllDirectories')) {
            $rel = $f.FullName.Substring($cut).Split('\')
            if ($rel.Count -lt 5) { continue }          # attack\topology\location\scenario\file
            $k = '{0}/{1}/{2}/{3}' -f $rel[0], $rel[1], $rel[2], $rel[3]
            $t = $f.LastWriteTimeUtc.Ticks
            $e = $map[$k]
            if ($e) { $e[0]++; if ($t -gt $e[1]) { $e[1] = $t } } else { $map[$k] = [long[]]@(1, $t) }
        }
    }
    return $map
}

function Get-DataStamp([hashtable]$Map = $null) {
    # one string for the whole data tree: equal = nothing changed anywhere
    if (-not $Map) { $Map = Get-CellStamps }
    $n = 0L; $t = 0L
    foreach ($e in $Map.Values) { $n += $e[0]; if ($e[1] -gt $t) { $t = $e[1] } }
    return "$($Map.Count)|$n|$t"
}

function Get-ChangedCells([hashtable]$Old, [hashtable]$New) {
    # run folders added, removed or changed between two Get-CellStamps maps
    $out = New-Object System.Collections.ArrayList
    foreach ($k in $New.Keys) { $o = $Old[$k]; if (-not $o -or $o[0] -ne $New[$k][0] -or $o[1] -ne $New[$k][1]) { [void]$out.Add($k) } }
    foreach ($k in $Old.Keys) { if (-not $New.ContainsKey($k)) { [void]$out.Add($k) } }
    return @($out)
}

$script:PageStamps = @{}
function Test-PageStale([string]$Page) {
    # $true the first time and whenever the data changed since this page last refreshed
    $s = Get-DataStamp
    if ($script:PageStamps[$Page] -eq $s) { return $false }
    $script:PageStamps[$Page] = $s
    return $true
}

function Get-RedoDocsStamp {
    # the files that change a verdict WITHOUT touching any data: the verification
    # log, the thesis checklist (D-rows) and the campaign plan
    $t = 0L
    foreach ($f in 'docs\dataset-verification.md', 'docs\deviations-limitations\THESIS-UPDATE-CHECKLIST.md', 'tools\campaign_plan.json') {
        $fp = Join-Path $base $f; if ([IO.File]::Exists($fp)) { $w = [IO.File]::GetLastWriteTimeUtc($fp).Ticks; if ($w -gt $t) { $t = $w } }
    }
    return $t
}

function Update-RedoIfChanged {
    # Campaign page opened (or an Analyse / Verify ended): re-check only the runs
    # whose data changed since the last redo list and merge them; the whole list
    # when many changed or when the verification log / checklist / plan changed
    # (those move verdicts of runs whose files did not change). Nothing changed =
    # nothing runs. The first full list (start-up) sets the baseline.
    if (-not $script:RedoCells) { return }
    $docs = Get-RedoDocsStamp
    if ($script:RedoDocs -and $docs -ne $script:RedoDocs) { $script:RedoDocs = $docs; Start-RedoList; return }
    $script:RedoDocs = $docs
    $now = Get-CellStamps
    $ch = @(Get-ChangedCells $script:RedoCells $now)
    if (-not $ch.Count) { return }
    if ($ch.Count -gt 8) { Start-RedoList } else { Start-RedoList -Only $ch }
}
