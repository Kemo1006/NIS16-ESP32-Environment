# Remembers which capture CSVs the LATEST SD-card import wrote, so the Data sync
# push/pull lists (tools\push_data.py) can show them green and everything older
# yellow. Dot-sourced by run_wizard.ps1 and menu.ps1.
#
# One batch = one trip through "Import SD card": every card copied until the
# operator answers N to "Import another card for this same run?". The NEXT import
# that copies at least one file replaces the record, which is what turns the
# previous batch yellow. An import that copies nothing leaves the record alone.
#
# How the files are known: the set of tools\exports\ CSVs is snapshotted when the
# import starts and diffed after each card, so only files THIS import created
# count - not teammates' pulled files, not a ledger it appended rows to.
#
# Record: .last_import_batch.json next to run_wizard.ps1 - git-ignored, this
# laptop only (read by push_data.py's load_batch()).
# ASCII-only on purpose (Windows PowerShell 5.1 misreads non-ASCII in .ps1).

$script:ImportBatchFile = '.last_import_batch.json'

function Get-ExportCsvSet {
    # Live capture CSVs under tools\exports\, as push_data.py names them
    # ("tools/exports/<attack>/.../<file>.csv"). Superseded (archive, _archive)
    # and derived (trimmed) folders are skipped, and so are the ledgers - an
    # import appends rows to run_ledger.csv, it is not a new capture.
    param([string]$Base)
    $root = Join-Path $Base 'datasets\exports'
    if (-not (Test-Path $root)) { return @() }
    $skipDirs = @('archive', '_archive', 'trimmed')
    $skipNames = @('run_ledger.csv', 'test_ledger.csv')
    $cut = $Base.TrimEnd('\').Length + 1
    return @(Get-ChildItem -Path $root -Filter '*.csv' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $rel = $_.FullName.Substring($cut)
            $dirs = @($rel.Split('\') | Select-Object -SkipLast 1)
            ($skipNames -notcontains $_.Name) -and -not @($dirs | Where-Object { $skipDirs -contains $_ }).Count
        } |
        ForEach-Object { $_.FullName.Substring($cut).Replace('\', '/') })
}

function Get-UnixNow { [DateTimeOffset]::Now.ToUnixTimeSeconds() }

function Save-ImportBatch {
    # Writes every CSV that appeared since -Before as the newest batch. Called
    # after EACH card, so the record is right even if the session is abandoned
    # mid-way; a later call in the same session just grows the same batch.
    # Never throws - a failed record costs colour in a listing, not an import.
    param([string]$Base, [string[]]$Before, [long]$Started)
    try {
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($p in @($Before)) { if ($p) { [void]$seen.Add($p) } }
        $new = @(Get-ExportCsvSet -Base $Base | Where-Object { -not $seen.Contains($_) } | Sort-Object)
        if ($new.Count -eq 0) { return }

        $record = [ordered]@{
            _help    = 'Written by run_wizard.ps1 / menu.ps1 after an SD-card import (tools\ImportBatch.ps1). These files show GREEN in Data sync push/pull; the next import replaces this list. Safe to delete - listings then colour by the last 30 min.'
            started  = $Started
            finished = (Get-UnixNow)
            computer = [string]$env:COMPUTERNAME
            files    = [object[]]$new
        }
        $json = ConvertTo-Json -InputObject $record -Depth 3
        [System.IO.File]::WriteAllText((Join-Path $Base $script:ImportBatchFile), $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host ("  {0} file(s) marked as your newest import - GREEN in Data sync push/pull; earlier imports now show yellow." -f $new.Count) -ForegroundColor DarkGray
    }
    catch {
        Write-Host ("  (Could not record this import batch: {0} - push/pull colours fall back to the last 30 min.)" -f $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Get-ImportBatch {
    # the newest import's record, or $null (no import recorded on this laptop yet)
    param([string]$Base)
    $f = Join-Path $Base $script:ImportBatchFile
    if (-not (Test-Path $f)) { return $null }
    try { return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Undo-ImportBatch {
    # Undo the newest import (oct. 18 2026): its CSVs are MOVED - never deleted -
    # to archive\_undone_imports\<stamp>\ with the same folder layout, so a file
    # filed into the wrong run is one step to take back, and one move to restore.
    # The record is renamed, so the same import cannot be undone twice.
    # Returns @{ Moved; Missing; Dir } (Dir = where the files went).
    param([string]$Base)
    $rec = Get-ImportBatch -Base $Base
    if (-not $rec -or -not @($rec.files).Count) { return @{ Moved = 0; Missing = 0; Dir = '' } }
    $dir = Join-Path $Base ('archive\_undone_imports\' + (Get-Date).ToString('yyyyMMdd_HHmmss'))
    $moved = 0; $missing = 0
    foreach ($rel in @($rec.files)) {
        $src = Join-Path $Base ($rel -replace '/', '\')
        if (-not (Test-Path $src)) { $missing++; continue }
        $dst = Join-Path $dir ($rel -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
        Move-Item -LiteralPath $src -Destination $dst
        $moved++
    }
    if ($moved) {
        $note = [ordered]@{ undone = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); computer = [string]$env:COMPUTERNAME
                            restore = 'move the datasets\ folder in here back into the project folder (same paths)'; files = [object[]]@($rec.files) }
        [System.IO.File]::WriteAllText((Join-Path $dir 'UNDONE_IMPORT.json'), (ConvertTo-Json -InputObject $note -Depth 3), [System.Text.UTF8Encoding]::new($false))
    }
    Move-Item -LiteralPath (Join-Path $Base $script:ImportBatchFile) -Destination (Join-Path $Base ($script:ImportBatchFile + '.undone')) -Force
    return @{ Moved = $moved; Missing = $missing; Dir = $dir }
}
function Get-TrackedImportFiles {
    # the batch files git already tracks (committed / pushed): undo moves only THIS
    # laptop's copy - GitHub keeps them, and a later pull / sync brings them back
    param([string]$Base, [string[]]$Files)
    if (-not @($Files).Count -or -not (Get-Command git -ErrorAction SilentlyContinue)) { return @() }
    try { return @(& git -C $Base ls-files -- @($Files) 2>$null | Where-Object { $_ }) } catch { return @() }
}
