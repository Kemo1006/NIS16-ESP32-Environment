<#
.SYNOPSIS
  Analysis + validation front door. Run it with no arguments for a menu
  (same style as menu.ps1); pass flags to script it non-interactively.

.DESCRIPTION
  Wraps the whole host-side pipeline on already-captured data in tools/exports/:
  tools/trim_run.py --apply -> analysis/preprocess.py (M6) -> features.py (M7)
  -> eda.py (M8), plus tools/verify_attack.py for paper-backed 3-sigma
  validation. Output goes to analysis/<attack>/<topology>/<...same subpath>.

  Capture folders are auto-detected at ANY depth under
  tools/exports/<attack>/<topology>/ -- no <location>, just <location>, or
  <location>/<scenario> all work. A folder counts as a capture if it directly
  holds *_telem.csv; trimmed/ and _archive/ are never treated as captures.

  No arguments  -> interactive menu (pick runs from a numbered list).
  -All          -> analyze every captured combo, no prompts.
  -List         -> show what's captured, with row counts, then exit.

.EXAMPLE
  # interactive menu -- easiest, no flags to remember:
  .\analyze.ps1

.EXAMPLE
  # what's captured so far + row counts:
  .\analyze.ps1 -List

.EXAMPLE
  # scripted: one combo, analyze + validate:
  .\analyze.ps1 -Attack blackhole -Topology linear -Location G402 -Scenario mobility -Verify

.EXAMPLE
  # scripted: everything captured, no prompts:
  .\analyze.ps1 -All
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('baseline', 'blackhole', 'wormhole')]
    [string]$Attack,

    [Parameter(Position = 1)]
    [ValidateSet('linear', 'star', 'tree', 'partial_mesh')]
    [string]$Topology,

    [Parameter(Position = 2)]
    [string]$Location,

    [ValidateSet('none', 'burst', 'highload', 'mobility', 'powercycle')]
    [string]$Scenario,

    [switch]$All,
    [switch]$List,
    [switch]$Verify,
    [switch]$SkipTrim,
    [switch]$Menu
)

$ErrorActionPreference = 'Stop'
$root         = $PSScriptRoot
$exportsRoot  = Join-Path $root 'tools\exports'
$analysisRoot = Join-Path $root 'analysis'
$ROW_TARGET   = 10000

# ---------------------------------------------------------------- helpers ---
# Read-Choice / Read-YesNo mirror menu.ps1's versions on purpose, so both
# front-ends prompt identically. Keep them in sync if menu.ps1's change.

function Read-Choice {
    param([string]$Title, [string[]]$Options, [int]$Default = 1)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("   [{0}] {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $ans = Read-Host ("Choice [default {0}]" -f $Default)
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $Options.Count) { return [int]$ans }
        Write-Host ("   Enter a number 1..{0}." -f $Options.Count) -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $true)
    if ($Default) { $hint = 'Y/n' } else { $hint = 'y/N' }
    while ($true) {
        $ans = Read-Host ("{0} [{1}]" -f $Question, $hint)
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        $a = $ans.Trim().ToLower()
        if ($a -like 'y*') { return $true }
        if ($a -like 'n*') { return $false }
        Write-Host "   Please answer y or n." -ForegroundColor Yellow
    }
}

function Get-RowCount {
    param([string]$Csv)
    if (-not (Test-Path $Csv)) { return 0 }
    $n = 0
    foreach ($line in [System.IO.File]::ReadLines($Csv)) { $n++ }
    return [Math]::Max(0, $n - 1)   # minus header
}

function Get-OutDir {
    param($Target)
    if ($Target.Sub) { return Join-Path $analysisRoot "$($Target.Attack)\$($Target.Topology)\$($Target.Sub)" }
    return Join-Path $analysisRoot "$($Target.Attack)\$($Target.Topology)"
}

function Get-TargetLabel {
    param($Target)
    if ($Target.Sub) { return "$($Target.Attack)/$($Target.Topology)/$($Target.Sub -replace '\\','/')" }
    return "$($Target.Attack)/$($Target.Topology)"
}

# --------------------------------------------------------------- discovery ---
# Every folder under tools/exports/<attack>/<topology>/ (any depth, including the
# topology folder itself) that DIRECTLY holds *_telem.csv. trimmed/ and _archive/
# are excluded whether they are the folder itself or an ancestor.
function Get-DataTargets {
    param([string]$Attack, [string]$Topology)

    $topoDir = Join-Path $exportsRoot "$Attack\$Topology"
    if (-not (Test-Path $topoDir)) { return @() }

    $candidates = @([System.IO.DirectoryInfo]::new($topoDir))
    $candidates += Get-ChildItem $topoDir -Directory -Recurse -ErrorAction SilentlyContinue

    $results = @()
    foreach ($c in $candidates) {
        if ($c.FullName -match '(^|\\)(trimmed|_archive)(\\|$)') { continue }
        $telem = Get-ChildItem $c.FullName -Filter '*_telem.csv' -File -ErrorAction SilentlyContinue
        if (-not $telem) { continue }

        $sub = $c.FullName.Substring($topoDir.Length).Trim('\')
        $parts = @()
        if ($sub) { $parts = $sub -split '\\' }
        $loc = $null
        $scn = $null
        if ($parts.Count -ge 1) { $loc = $parts[0] }
        if ($parts.Count -ge 2) { $scn = $parts[1] }

        $results += [PSCustomObject]@{
            Attack     = $Attack
            Topology   = $Topology
            Location   = $loc
            Scenario   = $scn
            Sub        = $sub
            Dir        = $c.FullName
            TelemCount = $telem.Count
        }
    }
    return $results
}

function Get-AllTargets {
    $all = @()
    foreach ($a in 'baseline', 'blackhole', 'wormhole') {
        foreach ($t in 'linear', 'star', 'tree', 'partial_mesh') {
            $all += Get-DataTargets -Attack $a -Topology $t
        }
    }
    return $all
}

function Get-TotalRows {
    param([array]$Targets)
    $total = 0
    foreach ($t in $Targets) { $total += Get-RowCount (Join-Path (Get-OutDir $t) 'feature_table.csv') }
    return $total
}

function Show-Targets {
    param([array]$Targets)

    if (-not $Targets) {
        Write-Host "No captured data found under tools\exports\." -ForegroundColor Yellow
        Write-Host "Run a capture first (menu.ps1 / run.ps1 -Export), then come back." -ForegroundColor DarkGray
        return
    }

    $rows = foreach ($t in $Targets) {
        $features = Join-Path (Get-OutDir $t) 'feature_table.csv'
        $loc = '-'; if ($t.Location) { $loc = $t.Location }
        $scn = '-'; if ($t.Scenario) { $scn = $t.Scenario }
        [PSCustomObject]@{
            Attack       = $t.Attack
            Topology     = $t.Topology
            Location     = $loc
            Scenario     = $scn
            TelemFiles   = $t.TelemCount
            AnalyzedRows = Get-RowCount $features
        }
    }
    $rows | Format-Table -AutoSize

    $total = ($rows | Measure-Object -Property AnalyzedRows -Sum).Sum
    Write-Host ("Total analyzed rows: {0:N0} / {1:N0} target" -f $total, $ROW_TARGET) -ForegroundColor Cyan
    if ($total -lt $ROW_TARGET) {
        $need = $ROW_TARGET - $total
        Write-Host ("  {0:N0} more needed. At ~500 rows/run that's about {1} more run(s)." -f $need, [Math]::Ceiling($need / 500)) -ForegroundColor DarkGray
    } else {
        Write-Host "  Row target reached." -ForegroundColor Green
    }
}

# Numbered picker over discovered captures.
function Select-Target {
    param([array]$Targets, [string]$Title = "Which run?")
    if (-not $Targets) { return $null }
    $opts = foreach ($t in $Targets) {
        $rows = Get-RowCount (Join-Path (Get-OutDir $t) 'feature_table.csv')
        "{0}  ({1} telem file(s), {2} row(s) analyzed)" -f (Get-TargetLabel $t), $t.TelemCount, $rows
    }
    $opts = @($opts) + @('Back')
    $idx = Read-Choice -Title $Title -Options $opts -Default 1
    if ($idx -eq $opts.Count) { return $null }
    return $Targets[$idx - 1]
}

# ----------------------------------------------------------------- actions ---
function Invoke-Analyze {
    param($Target, [bool]$DoVerify = $false, [bool]$NoTrim = $false, [bool]$FreshTrim = $false)

    Write-Host ""
    Write-Host ("=== {0} ===" -f (Get-TargetLabel $Target)) -ForegroundColor Cyan

    $srcDir = $Target.Dir
    if (-not $NoTrim) {
        $trimmedDir = Join-Path $srcDir 'trimmed'
        # Stale files in trimmed/ from an earlier partial run get silently loaded by
        # every analysis tool; clearing first is the only way to be sure.
        if ($FreshTrim -and (Test-Path $trimmedDir)) { Remove-Item $trimmedDir -Recurse -Force }
        python (Join-Path $root 'tools\trim_run.py') $srcDir --apply
        if (Test-Path $trimmedDir) { $srcDir = $trimmedDir }
    }

    $outDir = Get-OutDir $Target
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $windowed = Join-Path $outDir 'windowed_dataset.csv'
    $features = Join-Path $outDir 'feature_table.csv'
    $edaOut   = Join-Path $outDir 'eda_output'

    python (Join-Path $analysisRoot 'preprocess.py') $srcDir -o $windowed
    python (Join-Path $analysisRoot 'features.py')   $srcDir -o $features
    python (Join-Path $analysisRoot 'eda.py')        $features -o $edaOut

    if ($DoVerify) { Invoke-Validate -Target $Target }

    return (Get-RowCount $features)
}

function Invoke-Validate {
    param($Target)

    $features = Join-Path (Get-OutDir $Target) 'feature_table.csv'
    if (-not (Test-Path $features)) {
        Write-Host ("No feature_table.csv for {0} yet -- analyze it first." -f (Get-TargetLabel $Target)) -ForegroundColor Yellow
        return
    }
    if ($Target.Attack -eq 'baseline') {
        Write-Host "Baseline runs have no attack to verify (that's the point) -- skipping." -ForegroundColor DarkGray
        return
    }
    Write-Host ""
    python (Join-Path $root 'tools\verify_attack.py') $features --attack $Target.Attack
}

# -------------------------------------------------------------------- menu ---
function Show-MainMenu {
    while ($true) {
        $targets = Get-AllTargets
        $total = Get-TotalRows -Targets $targets

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "  ANALYSIS + VALIDATION  (M6 -> M7 -> M8, 3-sigma verify)" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ("  Captured runs: {0}     Analyzed rows: {1:N0} / {2:N0}" -f $targets.Count, $total, $ROW_TARGET)

        $choice = Read-Choice -Title "What do you want to do?" -Options @(
            'Analyze ALL captured runs',
            'Analyze ONE run (pick from list)',
            'Validate ONE run (3-sigma attack check)',
            'Analyze + validate ONE run',
            'Show what is captured (row counts)',
            'Re-analyze ALL from scratch (clears trimmed/ first)',
            'Quit'
        ) -Default 5

        switch ($choice) {
            1 {
                if (-not $targets) { Show-Targets -Targets $targets; break }
                $doV = Read-YesNo -Question "Also run validation on each attack run?" -Default $false
                $sum = 0
                foreach ($t in $targets) { $sum += Invoke-Analyze -Target $t -DoVerify $doV }
                Write-Host ""
                Write-Host ("Done: {0} run(s), {1:N0} row(s) in this batch." -f $targets.Count, $sum) -ForegroundColor Green
            }
            2 {
                $t = Select-Target -Targets $targets -Title "Analyze which run?"
                if ($t) { $n = Invoke-Analyze -Target $t; Write-Host ("Done: {0:N0} row(s)." -f $n) -ForegroundColor Green }
            }
            3 {
                $t = Select-Target -Targets $targets -Title "Validate which run?"
                if ($t) { Invoke-Validate -Target $t }
            }
            4 {
                $t = Select-Target -Targets $targets -Title "Analyze + validate which run?"
                if ($t) { $n = Invoke-Analyze -Target $t -DoVerify $true; Write-Host ("Done: {0:N0} row(s)." -f $n) -ForegroundColor Green }
            }
            5 { Show-Targets -Targets $targets }
            6 {
                if (-not $targets) { Show-Targets -Targets $targets; break }
                if (Read-YesNo -Question ("Re-trim and re-analyze all {0} run(s)? (raw exports are never touched)" -f $targets.Count) -Default $false) {
                    $doV = Read-YesNo -Question "Also run validation on each attack run?" -Default $false
                    $sum = 0
                    foreach ($t in $targets) { $sum += Invoke-Analyze -Target $t -DoVerify $doV -FreshTrim $true }
                    Write-Host ""
                    Write-Host ("Done: {0} run(s), {1:N0} row(s)." -f $targets.Count, $sum) -ForegroundColor Green
                }
            }
            7 { return }
        }
    }
}

# -------------------------------------------------------------------- main ---
if ($List) {
    if ($Attack -and $Topology) { Show-Targets -Targets (Get-DataTargets -Attack $Attack -Topology $Topology) }
    else { Show-Targets -Targets (Get-AllTargets) }
    exit 0
}

# No filters and no -All -> the menu. -Menu forces it.
if ($Menu -or (-not $All -and -not $Attack -and -not $Topology)) {
    Show-MainMenu
    exit 0
}

$targets = @()
if ($Attack -and $Topology) {
    if ($Location -or $Scenario) {
        $segs = @($Attack, $Topology)
        if ($Location) { $segs += $Location }
        if ($Scenario) { $segs += $Scenario }
        $dir = Join-Path $exportsRoot ($segs -join '\')
        if (-not (Test-Path $dir) -or -not (Get-ChildItem $dir -Filter '*_telem.csv' -File -ErrorAction SilentlyContinue)) {
            Write-Host ("No captured data at tools\exports\{0}. Here is what IS there for {1}/{2}:" -f ($segs -join '\'), $Attack, $Topology) -ForegroundColor Yellow
            Show-Targets -Targets (Get-DataTargets -Attack $Attack -Topology $Topology)
            exit 1
        }
        $sub = ($segs[2..($segs.Count - 1)]) -join '\'
        $targets += [PSCustomObject]@{ Attack = $Attack; Topology = $Topology; Location = $Location; Scenario = $Scenario; Sub = $sub; Dir = $dir; TelemCount = 0 }
    } else {
        $targets += Get-DataTargets -Attack $Attack -Topology $Topology
        if (-not $targets) {
            Write-Host ("No captured data under tools\exports\{0}\{1}." -f $Attack, $Topology) -ForegroundColor Yellow
            exit 0
        }
    }
} elseif ($Attack -or $Topology) {
    throw "Give both -Attack and -Topology (or neither, for the menu). Try -List to see what's captured."
} else {
    $targets += Get-AllTargets
}

if (-not $targets) {
    Write-Host "No captured data found under tools\exports\. Nothing to analyze." -ForegroundColor Yellow
    exit 0
}

$batch = 0
foreach ($tgt in $targets) {
    $batch += Invoke-Analyze -Target $tgt -DoVerify $Verify.IsPresent -NoTrim $SkipTrim.IsPresent
}

Write-Host ""
Write-Host ("Done: {0} run(s) analyzed, {1:N0} row(s) in this batch." -f $targets.Count, $batch) -ForegroundColor Green
Write-Host "Run '.\analyze.ps1 -List' for the running total across everything captured." -ForegroundColor DarkGray
