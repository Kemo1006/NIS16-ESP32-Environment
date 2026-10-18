# tools\CliFeatures.ps1 - the CLI side of three GUI features (oct. 18 2026), so
# run_wizard.ps1 and menu.ps1 offer the same thing as run_gui.ps1:
#   Invoke-CollectRunCli   - collect one run from every plugged-in child's SD card
#                            (tools\collect_run.py; one port at a time)
#   Invoke-RunSummaryCli   - per-board health card of a run (tools\run_summary.py)
#   Invoke-UndoImportCli   - undo the newest import (moves, never deletes;
#                            Undo-ImportBatch in tools\ImportBatch.ps1)
# Dot-sourced by both launchers, which already have $base and ImportBatch.ps1.
# ASCII only (Windows PowerShell 5.1 misreads other characters).

function Get-CliPresets {
    # every preset, newest first: @{ Path; Owner; Attack; Topology; Location; Scenario; Boards; RootMac; Saved }
    $out = @()
    foreach ($f in @(Get-ChildItem (Join-Path $base 'presets') -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)) {
        try { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $j.attack -or -not $j.topology -or -not $j.location) { continue }
        $root = @($j.boards | Where-Object { $_.Role -eq 'root' -or $_.Kind -eq 'root' }) | Select-Object -First 1
        $out += [pscustomobject]@{ Path = $f.FullName; Owner = $f.Directory.Name; Attack = [string]$j.attack; Topology = [string]$j.topology
                                   Location = [string]$j.location; Scenario = $(if ($j.scenario) { [string]$j.scenario } else { 'stationary' })
                                   Boards = $(if ($j.expectedChildren) { 1 + [int]$j.expectedChildren } else { 0 })
                                   RootMac = $(if ($root -and $root.Mac) { [string]$root.Mac } else { '' })
                                   Saved = $(if ($j.savedAt) { [string]$j.savedAt } else { $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }) }
    }
    return @($out | Sort-Object Saved -Descending)
}

function Invoke-CollectRunCli {
    Write-Host ""
    Write-Host "  Reads each plugged-in child's SD card over USB, ONE board at a time, and files THIS run's" -ForegroundColor DarkGray
    Write-Host "  telemetry under the run's folder - also when a card's location.txt still named the last site." -ForegroundColor DarkGray
    Write-Host "  Close every idf.py monitor first. Do NOT unplug a board while it is read." -ForegroundColor Yellow
    $ps = @(Get-CliPresets | Select-Object -First 15)
    if (-not $ps.Count) { Write-Host "  No presets found - run tools\collect_run.py by hand (see its --help)." -ForegroundColor Yellow; return }
    Write-Host ""
    for ($i = 0; $i -lt $ps.Count; $i++) {
        Write-Host ("  [{0,2}] {1} / {2} / {3} / {4}   [{5}, saved {6}]" -f ($i + 1), $ps[$i].Attack, $ps[$i].Topology, $ps[$i].Location, $ps[$i].Scenario, $ps[$i].Owner, $ps[$i].Saved)
    }
    $k = Read-Host "  Which run (preset)? number, Enter = cancel"
    if (-not $k -or -not ($k -as [int]) -or [int]$k -lt 1 -or [int]$k -gt $ps.Count) { Write-Host "  Cancelled." -ForegroundColor DarkGray; return }
    $p = $ps[[int]$k - 1]
    $ports = @([IO.Ports.SerialPort]::GetPortNames() | Sort-Object { [int]($_ -replace '\D', '') } -Unique)
    Write-Host ("  Ports on this laptop: {0}" -f ($ports -join ', '))
    $pp = Read-Host "  Which ports (e.g. COM9,COM10)? Enter = all of them (the root is skipped by its MAC)"
    $use = if ($pp) { @($pp -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }) } else { $ports }
    $rep = Read-Host "  Repeat number? Enter = 1"; if (-not ($rep -as [int])) { $rep = 1 }
    $hrs = Read-Host "  Only files started in the last N hours? Enter = 6"; if (-not ($hrs -as [int])) { $hrs = 6 }
    $a = @((Join-Path $base 'tools\collect_run.py'), '--ports', ($use -join ','), '--attack', $p.Attack, '--topology', $p.Topology, '--location', $p.Location,
           '--scenario', $p.Scenario, '--repeat', "$rep", '--since', (Get-Date).AddHours(-[int]$hrs).ToString('yyyy-MM-dd HH:mm'), '--roster', $p.Path)
    if ($p.RootMac) { $a += @('--skip-mac', $p.RootMac) }
    $wl = Read-Host "  Could these cards have recorded the WRONG location (location.txt left on the last site)? [y/N]"
    if ($wl -eq 'y' -or $wl -eq 'Y') { $a += '--allow-other-location' }
    # safety net (oct. 18 2026): SCAN first - copies nothing - and copy only the files shown
    $go = Read-Host ("  Scan {0} port(s) now (reads the cards, copies nothing)? [y/N]" -f $use.Count)
    if ($go -ne 'y' -and $go -ne 'Y') { Write-Host "  Cancelled - nothing read." -ForegroundColor DarkGray; return }
    $plan = [IO.Path]::GetTempFileName()
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # PS 5.1: a native stderr line must not abort this
    try { & python @a --dry-run --plan-json $plan | Where-Object { $_ -match '^COLLECT' } | ForEach-Object { Write-Host "  $_" } } finally { $ErrorActionPreference = $prev }
    $rows = @(); try { $rows = @(Get-Content $plan -Raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
    Remove-Item $plan -ErrorAction SilentlyContinue
    $okRows = @($rows | Where-Object { $_.state -eq 'OK' })
    Write-Host ""
    foreach ($r in $rows) {
        $c = switch ([string]$r.state) { 'OK' { 'Green' } 'SKIP' { 'DarkGray' } default { 'Yellow' } }
        Write-Host ("  {0,-6} {1,-13} {2,-5} {3}" -f $r.port, $r.mac, $r.state, $(if ($r.name) { "$($r.name)  ran $($r.started)  ($($r.cell))" } else { $r.why })) -ForegroundColor $c
        if ($r.name -and $r.why) { Write-Host ("                            {0}" -f $r.why) -ForegroundColor DarkGray }
    }
    if (-not $okRows.Count) { Write-Host "  Nothing to collect - the reasons are above (nothing was copied)." -ForegroundColor Yellow; return }
    $go = Read-Host ("  Copy EXACTLY these {0} file(s) (the OK rows above)? [y/N]" -f $okRows.Count)
    if ($go -ne 'y' -and $go -ne 'Y') { Write-Host "  Nothing copied." -ForegroundColor DarkGray; return }
    $pick = ($okRows | ForEach-Object { '{0}={1}' -f $_.port, ($_.rel -replace '\\', '/') }) -join ';'
    $a2 = @($a); $a2[2] = (@($okRows | ForEach-Object { $_.port }) -join ',')
    $before = @(Get-ExportCsvSet -Base $base); $t0 = Get-UnixNow
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & python @a2 --pick $pick } finally { $ErrorActionPreference = $prev }
    Save-ImportBatch -Base $base -Before $before -Started $t0
}

function Invoke-RunSummaryCli {
    $root = Join-Path $base 'datasets\exports'
    $cells = @(Get-ChildItem $root -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName.Substring($root.Length).Trim('\').Split('\').Count -eq 4 -and $_.Name -ne 'trimmed' -and @(Get-ChildItem $_.FullName -Filter '*_telem.csv' -File).Count } |
        Sort-Object { (Get-ChildItem $_.FullName -Filter '*_telem.csv' -File | Measure-Object LastWriteTime -Maximum).Maximum } -Descending | Select-Object -First 20)
    if (-not $cells.Count) { Write-Host "  No exported run found." -ForegroundColor Yellow; return }
    Write-Host ""
    for ($i = 0; $i -lt $cells.Count; $i++) { Write-Host ("  [{0,2}] {1}" -f ($i + 1), ($cells[$i].FullName.Substring($root.Length).Trim('\') -replace '\\', ' / ')) }
    $k = Read-Host "  Which run (newest first)? number, Enter = cancel"
    if (-not $k -or -not ($k -as [int]) -or [int]$k -lt 1 -or [int]$k -gt $cells.Count) { return }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & python (Join-Path $base 'tools\run_summary.py') $cells[[int]$k - 1].FullName } finally { $ErrorActionPreference = $prev }
}

function Invoke-UndoImportCli {
    $rec = Get-ImportBatch -Base $base
    if (-not $rec -or -not @($rec.files).Count) { Write-Host "  No import is recorded on this laptop (or it was undone already)." -ForegroundColor DarkGray; return }
    Write-Host ""
    Write-Host ("  Newest import: {0} file(s):" -f @($rec.files).Count) -ForegroundColor Cyan
    foreach ($f in @($rec.files) | Select-Object -First 15) { Write-Host ("    {0}" -f ($f -replace '^datasets/exports/', '')) }
    $tracked = @(Get-TrackedImportFiles -Base $base -Files @($rec.files))
    if ($tracked.Count) { Write-Host ("  (!) {0} of them are already committed / on GitHub - undo moves only THIS laptop's copy; a later pull brings them back. Delete them on GitHub too if they are wrong there." -f $tracked.Count) -ForegroundColor Yellow }
    $go = Read-Host "  MOVE them to archive\_undone_imports\ (nothing is deleted)? [y/N]"
    if ($go -ne 'y' -and $go -ne 'Y') { Write-Host "  Nothing moved." -ForegroundColor DarkGray; return }
    $r = Undo-ImportBatch -Base $base
    Write-Host ("  Moved {0} file(s) to {1}{2}" -f $r.Moved, $r.Dir, $(if ($r.Missing) { " ($($r.Missing) were already gone)" } else { '' })) -ForegroundColor Green
}
