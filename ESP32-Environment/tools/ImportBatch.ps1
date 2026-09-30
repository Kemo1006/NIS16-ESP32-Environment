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
