# gui\DataPage.ps1 - two Data-page fixes (oct. 18 2026). Dot-sourced by run_gui.ps1. ASCII only.
#
# 1) WHERE the ticked files really go. The line under the run picker used to say
#    "goes to datasets\exports\<your pick>", but an import files each card file
#    under the CARD's own attack/topology/location folder - that is how a
#    DLSU_Library run's file landed in G402 without anyone noticing. It now names
#    the real folder(s) and turns amber/red when they are not the pick.
# 2) "Undo last import": the newest import's files are MOVED to
#    archive\_undone_imports\<stamp>\ (tools\ImportBatch.ps1 Undo-ImportBatch,
#    the same code the CLI uses) - never deleted.

function Update-ImpDestReal {
    $pk = Get-ImpPick
    $scn = [string]$ui.ImpScenario.SelectedItem
    $rep = $ui.ImpRepeat.Text
    $dt = $script:ImpTable
    $ticked = if ($dt) { @($dt.Rows | Where-Object { $_.Import }) } else { @() }
    if (-not $ticked.Count) {
        $ui.ImpDest.Text = if ($pk) { 'goes to  datasets\exports\{0}\{1}\   (repeat {2})' -f ($pk -replace ' / ', '\'), $scn, $rep } else { 'pick the run - or press List and it is filled in from the card' }
        $ui.ImpDest.Foreground = Get-Brush $Pal.Cyan
        return
    }
    $cells = @($ticked | ForEach-Object { [string]$_.Cell } | Select-Object -Unique)
    $off = @($cells | Where-Object { $pk -and $_ -ne $pk })
    $locOnly = @($off | Where-Object { Test-ImpLocOnly $_ $pk })
    $lines = @($cells | ForEach-Object { 'datasets\exports\{0}\{1}\' -f ($_ -replace ' / ', '\'), $scn })
    $txt = ('the {0} ticked file(s) go to  {1}   (repeat {2})' -f $ticked.Count, ($lines -join '   +   '), $rep)
    if ($off.Count -and $locOnly.Count -eq $off.Count) {
        $txt += "`n(!) the card recorded another LOCATION than your pick ($pk) - Import asks to file them under your pick instead."
        $ui.ImpDest.Foreground = Get-Brush $Pal.Amber
    } elseif ($off.Count) {
        $txt += "`n(!) NOT your pick ($pk): these files are from another run and land in THEIR folder above."
        $ui.ImpDest.Foreground = Get-Brush $Pal.Red
    } else { $ui.ImpDest.Foreground = Get-Brush $Pal.Cyan }
    $ui.ImpDest.Text = $txt
}

function Initialize-GuiDataPage {
    # "Undo last import" next to Import (built here, so run_gui.ps1's XAML stays untouched)
    $host_ = $ui.ImpGo.Parent
    if (-not $host_ -or -not ($host_ -is [Windows.Controls.Panel])) { return }
    $b = New-Object Windows.Controls.Button
    $b.Content = 'Undo last import'; $b.Margin = '8,0,0,0'; $b.Padding = '12,7'
    $b.ToolTip = 'Moves the files of your newest import (or Collect) to archive\_undone_imports\ - nothing is deleted, they can be moved back.'
    $b.Add_Click({ Invoke-UndoLastImport })
    [void]$host_.Children.Add($b)
    $script:ImpUndoBtn = $b
}

function Invoke-UndoLastImport {
    $rec = Get-ImportBatch -Base $base
    if (-not $rec -or -not @($rec.files).Count) { [void][Windows.MessageBox]::Show('No import is recorded on this laptop (or it was undone already).', 'Undo last import'); return }
    $when = try { [DateTimeOffset]::FromUnixTimeSeconds([long]$rec.finished).LocalDateTime.ToString('MMM dd  hh:mm tt') } catch { '?' }
    $list = (@($rec.files) | Select-Object -First 10 | ForEach-Object { '    ' + ($_ -replace '^datasets/exports/', '') }) -join "`n"
    $more = if (@($rec.files).Count -gt 10) { "`n    ... and $(@($rec.files).Count - 10) more" } else { '' }
    $msg = "Undo the import of $when ($(@($rec.files).Count) file(s))?`n`n$list$more`n`nThey are MOVED to archive\_undone_imports\ (nothing is deleted). Their run's analysis then needs Analyse again."
    $tracked = @(Get-TrackedImportFiles -Base $base -Files @($rec.files))
    if ($tracked.Count) { $msg += "`n`n(!) $($tracked.Count) of them are already committed / on GitHub. Undo moves only THIS laptop's copy - a later pull or Smart sync brings them back. Delete them on GitHub too (GitHub sync page) if they are wrong there." }
    if (-not (Confirm-Action $msg 'Undo last import')) { return }
    try { $r = Undo-ImportBatch -Base $base } catch { [void][Windows.MessageBox]::Show("Undo failed: $($_.Exception.Message)", 'Undo last import'); return }
    $script:UndoDir = $r.Dir
    Write-Activity ("  undo: {0} file(s) moved to {1}{2}" -f $r.Moved, $r.Dir, $(if ($r.Missing) { " ($($r.Missing) were already gone)" } else { '' })) $Pal.Green
    Show-Toast 'Import undone' ("{0} file(s) moved to archive\_undone_imports" -f $r.Moved) ([string][char]0xE7A7) 'GradCool' { if ($script:UndoDir) { Start-Process explorer $script:UndoDir } } 'Open the folder'
    try { Update-TrimCells; Update-Cells } catch { }
    if ($script:ImpItems.Count) { try { Show-ImpList $script:ImpItems } catch { } }
}
