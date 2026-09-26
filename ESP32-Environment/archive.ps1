<#
.SYNOPSIS
  Archive the current capture + analysis output, then reset the working tree to a
  clean empty scaffold ready for the next run.

.DESCRIPTION
  MOVES (never copies, never deletes) everything under datasets/exports/,
  datasets/analysis/, datasets/PCAP/ (sniffer .pcap + .json) and
  datasets/run_logs/ (console .log) into datasets/archive/<date>_<label>/,
  preserving the <attack>/<topology>/[<location>/][<scenario>/] layout, then puts
  the working tree back to the bare .gitkeep scaffold with a header-only
  run_ledger.csv. run_logs/_archive/ stays put: it is the wizard's own log
  archive ("Archive it" in the log viewer), not live data.

  Code is never touched: analysis/*.py, *.md, *.txt and every .gitkeep stay put.
  Only captured data and generated output move.

  Writes a README.md into the archive folder recording what was archived, when,
  and why, so a folder is never a mystery later.

  Uses Move-Item rather than a shell mv: Git-Bash mv hits "Permission denied" on
  these directories on this machine.

.EXAMPLE
  # see exactly what would move, change nothing:
  .\archive.ps1 -WhatIf

.EXAMPLE
  # normal use -- prompts for a label and a reason:
  .\archive.ps1

.EXAMPLE
  # fully scripted, no prompts:
  .\archive.ps1 -Label "bad-attacker-mac" -Reason "stale BLACKHOLE_ATTACKER_MAC voided the run" -Force
#>

[CmdletBinding()]
param(
    # Short kebab-case tag appended to the date, e.g. 2026-09-16_bad-attacker-mac
    [string]$Label,

    # One line recorded in the archive's README explaining why it was superseded.
    [string]$Reason,

    # Skip the confirmation prompt.
    [switch]$Force,

    # Show what would move and exit without changing anything.
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$root         = $PSScriptRoot
$exportsRoot  = Join-Path $root 'datasets\exports'
$analysisRoot = Join-Path $root 'datasets\analysis'
$archiveRoot  = Join-Path $root 'datasets\archive'
$pcapRoot     = Join-Path $root 'datasets\PCAP'
$logsRoot     = Join-Path $root 'datasets\run_logs'

$ATTACKS    = @('baseline', 'blackhole', 'wormhole')
$TOPOLOGIES = @('linear', 'star', 'tree', 'partial_mesh')

# Files that live in analysis/ but are CODE or DOCS, never run output.
$KEEP_EXT = @('.py', '.md', '.txt', '.gitkeep')

function Test-IsKeeper {
    param([System.IO.FileInfo]$File)
    if ($File.Name -eq '.gitkeep') { return $true }
    return $KEEP_EXT -contains $File.Extension.ToLower()
}

# ---------------------------------------------------------------- discovery ---
# Everything that would move, as @{ From; To; Kind }.
function Get-ArchivePlan {
    param([string]$Dest)

    $plan = @()

    # 1. Captured data: any non-.gitkeep file under tools/exports/
    if (Test-Path $exportsRoot) {
        foreach ($f in Get-ChildItem $exportsRoot -Recurse -File -ErrorAction SilentlyContinue) {
            if ($f.Name -eq '.gitkeep') { continue }
            $rel = $f.FullName.Substring($exportsRoot.Length).TrimStart('\')
            $plan += [PSCustomObject]@{
                From = $f.FullName
                To   = Join-Path $Dest "exports\$rel"
                Kind = 'export'
            }
        }
    }

    # 2. Generated analysis output: everything except code/docs/scaffold
    if (Test-Path $analysisRoot) {
        foreach ($f in Get-ChildItem $analysisRoot -Recurse -File -ErrorAction SilentlyContinue) {
            if ($f.FullName -like '*__pycache__*') { continue }
            if (Test-IsKeeper $f) { continue }
            $rel = $f.FullName.Substring($analysisRoot.Length).TrimStart('\')
            $plan += [PSCustomObject]@{
                From = $f.FullName
                To   = Join-Path $Dest "analysis\$rel"
                Kind = 'analysis'
            }
        }
    }

    # 3. Sniffer captures: every file under datasets/PCAP/ - the .pcap, its .json
    #    sidecar (pauses/loss) and any check_pcap _fixed copy, standalone/ included.
    if (Test-Path $pcapRoot) {
        foreach ($f in Get-ChildItem $pcapRoot -Recurse -File -ErrorAction SilentlyContinue) {
            if ($f.Name -eq '.gitkeep') { continue }
            $rel = $f.FullName.Substring($pcapRoot.Length).TrimStart('\')
            $plan += [PSCustomObject]@{
                From = $f.FullName
                To   = Join-Path $Dest "PCAP\$rel"
                Kind = 'pcap'
            }
        }
    }

    # 4. Run console logs: everything under datasets/run_logs/ EXCEPT _archive/,
    #    which the wizard's log viewer owns (Get-RunLogEntries -Archived).
    if (Test-Path $logsRoot) {
        foreach ($f in Get-ChildItem $logsRoot -Recurse -File -ErrorAction SilentlyContinue) {
            if ($f.Name -eq '.gitkeep') { continue }
            $rel = $f.FullName.Substring($logsRoot.Length).TrimStart('\')
            if ($rel -like '_archive\*') { continue }
            $plan += [PSCustomObject]@{
                From = $f.FullName
                To   = Join-Path $Dest "run_logs\$rel"
                Kind = 'log'
            }
        }
    }

    return $plan
}

# Reset tools/exports + analysis to the bare scaffold the next run expects.
function Reset-Scaffold {
    foreach ($a in $ATTACKS) {
        foreach ($t in $TOPOLOGIES) {
            foreach ($base in @($exportsRoot, $analysisRoot)) {
                $d = Join-Path $base "$a\$t"
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                $gk = Join-Path $d '.gitkeep'
                if (-not (Test-Path $gk)) { New-Item -ItemType File -Path $gk | Out-Null }
            }
        }
    }

    # Drop now-empty <location>/<scenario> dirs left behind by the move, deepest
    # first so parents empty out before they are tested.
    foreach ($base in @($exportsRoot, $analysisRoot)) {
        Get-ChildItem $base -Recurse -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
                    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
    }

    # PCAP/ and run_logs/ have no scaffold - sniff.py and the wizard create the
    # <attack>/<topology>/... folders on demand - so just drop the emptied ones.
    # The two roots themselves stay.
    foreach ($base in @($pcapRoot, $logsRoot)) {
        Get-ChildItem $base -Recurse -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
    }

    # Re-create the scaffold in case the empty-dir sweep removed a .gitkeep-only dir.
    foreach ($a in $ATTACKS) {
        foreach ($t in $TOPOLOGIES) {
            foreach ($base in @($exportsRoot, $analysisRoot)) {
                $d = Join-Path $base "$a\$t"
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                $gk = Join-Path $d '.gitkeep'
                if (-not (Test-Path $gk)) { New-Item -ItemType File -Path $gk | Out-Null }
            }
        }
    }

    # NOT Out-File -Encoding utf8: PowerShell 5.1 writes a BOM, and run_matrix.py
    # reads the ledger with plain encoding="utf-8" + csv.DictReader, which does
    # NOT strip it -- the first field name becomes "﻿topology" and every
    # row["topology"] lookup fails. Write ASCII (the header is pure ASCII) so no
    # BOM is emitted.
    'topology,attack,location,repeat,status,recorded_at,files' |
        Out-File (Join-Path $exportsRoot 'run_ledger.csv') -Encoding ascii
}

# -------------------------------------------------------------------- main ---
$plan = Get-ArchivePlan -Dest '<dest>'

# run_ledger.csv always exists, so it alone does not count as "there is data
# here" -- otherwise archiving an already-empty tree would create a folder
# holding nothing but a header row.
$substantive = @($plan | Where-Object { $_.To -notlike '*run_ledger.csv' })
if (-not $substantive) {
    Write-Host "Nothing to archive - datasets\exports\, analysis\, PCAP\ and run_logs\ hold no captured data or output." -ForegroundColor Yellow
    exit 0
}

$nExport   = @($plan | Where-Object { $_.Kind -eq 'export' }).Count
$nAnalysis = @($plan | Where-Object { $_.Kind -eq 'analysis' }).Count
$nPcap     = @($plan | Where-Object { $_.Kind -eq 'pcap' }).Count
$nLog      = @($plan | Where-Object { $_.Kind -eq 'log' }).Count

Write-Host ""
Write-Host "About to archive:" -ForegroundColor Cyan
Write-Host ("   {0,4} captured file(s) from datasets\exports\" -f $nExport)
Write-Host ("   {0,4} generated file(s) from datasets\analysis\" -f $nAnalysis)
Write-Host ("   {0,4} sniffer file(s) from datasets\PCAP\ (.pcap + .json)" -f $nPcap)
Write-Host ("   {0,4} run log(s) from datasets\run_logs\ (not _archive\)" -f $nLog)
Write-Host ""
Write-Host "Cells:" -ForegroundColor Cyan
$plan | Where-Object { $_.Kind -eq 'export' } | ForEach-Object {
    ((Split-Path $_.To -Parent) -replace '^<dest>\\exports\\?', '')
} | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object {
    Write-Host ("   {0}" -f $_)
}
if (@($plan | Where-Object { $_.To -like '*run_ledger.csv' }).Count) {
    Write-Host "   (+ run_ledger.csv)"
}
foreach ($k in @(@{ Kind = 'pcap'; Title = 'Captures (PCAP\):' }, @{ Kind = 'log'; Title = 'Run logs (run_logs\):' })) {
    $files = @($plan | Where-Object { $_.Kind -eq $k.Kind })
    if (-not $files.Count) { continue }
    Write-Host ""
    Write-Host $k.Title -ForegroundColor Cyan
    foreach ($p in $files) {
        Write-Host ("   {0}" -f ($p.To -replace '^<dest>\\(PCAP|run_logs)\\', ''))
    }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "-WhatIf: nothing was changed." -ForegroundColor Yellow
    exit 0
}

if (-not $Label) {
    Write-Host ""
    $Label = (Read-Host "Short label for this archive (e.g. bad-attacker-mac, r1-complete)").Trim()
}
if (-not $Label) { $Label = 'run' }
$Label = ($Label -replace '[^A-Za-z0-9._-]', '-')

if (-not $Reason) {
    $Reason = (Read-Host "One line: why is this data being superseded? (blank = none given)").Trim()
}
if (-not $Reason) { $Reason = '(no reason recorded)' }

# Never overwrite an existing archive; suffix until the name is free.
$stamp = Get-Date -Format 'yyyy-MM-dd'
$dest = Join-Path $archiveRoot "${stamp}_${Label}"
$n = 2
while (Test-Path $dest) {
    $dest = Join-Path $archiveRoot "${stamp}_${Label}-$n"
    $n++
}

if (-not $Force) {
    Write-Host ""
    Write-Host ("Destination: {0}" -f $dest) -ForegroundColor Cyan
    $ans = Read-Host "Proceed? Files are MOVED, never deleted. [y/N]"
    if ($ans.Trim().ToLower() -notlike 'y*') {
        Write-Host "Cancelled - nothing changed." -ForegroundColor Yellow
        exit 0
    }
}

# Re-plan against the real destination now that it is known.
$plan = Get-ArchivePlan -Dest $dest

$moved = 0
foreach ($item in $plan) {
    $parent = Split-Path $item.To -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Move-Item -LiteralPath $item.From -Destination $item.To -Force
    $moved++
}

Reset-Scaffold

$readme = @"
# Archive - $Label ($stamp)

$Reason

Moved here by ``archive.ps1`` on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Nothing was
deleted or copied: this is the working tree's captured data and generated output,
moved out whole so the next run starts from an empty scaffold.

- ``exports/``  - raw device CSVs, in their original
  ``<attack>/<topology>/[<location>/][<scenario>/]`` layout, plus ``run_ledger.csv``
- ``analysis/`` - ``windowed_dataset.csv``, ``feature_table.csv`` and ``eda_output/``
  for the same cells
- ``PCAP/``     - ESP32 sniffer captures (``.pcap`` + ``.json`` sidecar with pauses/loss),
  same cell layout plus ``standalone/``. Git-ignored: they exist only on the laptop
  that archived them.
- ``run_logs/`` - the wizard's console transcripts (``.log``) for the same runs

$moved file(s): $nExport captured, $nAnalysis generated, $nPcap sniffer, $nLog run log(s).

Everything here is reproducible from the raw CSVs with:

``````powershell
.\analyze.ps1
``````

(point it at this folder's ``exports/`` tree, or copy a cell back into
``datasets/exports/`` first).
"@

New-Item -ItemType Directory -Force -Path $dest | Out-Null
# BOM-less UTF-8: the reason text may contain non-ASCII so -Encoding ascii would
# mangle it, but Out-File -Encoding utf8 on PS 5.1 prepends a BOM.
[System.IO.File]::WriteAllText(
    (Join-Path $dest 'README.md'),
    $readme,
    (New-Object System.Text.UTF8Encoding $false)
)

Write-Host ""
Write-Host ("Archived {0} file(s) -> {1}" -f $moved, $dest) -ForegroundColor Green
Write-Host "Working tree reset: empty scaffold + header-only run_ledger.csv." -ForegroundColor Green
Write-Host "Check it with:  .\analyze.ps1 -List" -ForegroundColor DarkGray
