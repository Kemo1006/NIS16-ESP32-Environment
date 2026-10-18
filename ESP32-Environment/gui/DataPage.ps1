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
    $c = New-Object Windows.Controls.Button
    $c.Content = 'Collect all plugged-in boards'; $c.Margin = '8,0,0,0'; $c.Padding = '12,7'
    $c.ToolTip = 'Reads every plugged-in board''s SD card (one at a time, the root left out) and files the run picked above - also when a card recorded the wrong location. Same as the Live run''s Collect.'
    $c.Add_Click({ Start-CollectFromDataPage })
    [void]$host_.Children.Add($c)
    $script:ImpCollectBtn = $c
    Add-DataRefreshButton
}

function Add-DataRefreshButton {
    # oct. 19 2026 (user): a Refresh button on the Data page "in case it lags or
    # freezes". Top right of the page, next to the title - works on every Data tab.
    $tabs = $ui.DataTabs; if (-not $tabs) { return }
    $dock = $tabs.Parent; if (-not ($dock -is [Windows.Controls.Panel]) -or $dock.Children.Count -lt 1) { return }
    $hdr = $dock.Children[0]; if (-not ($hdr -is [Windows.Controls.StackPanel]) -or $hdr.Children.Count -lt 1) { return }
    $title = $hdr.Children[0]
    $row = New-Object Windows.Controls.DockPanel; $row.LastChildFill = $true
    $b = New-Object Windows.Controls.Button
    $b.Content = ([string][char]0x21BB) + '  Refresh'; $b.Padding = '14,6'; $b.Margin = '12,0,0,0'; $b.VerticalAlignment = 'Center'
    $b.ToolTip = "Re-reads this page: plugged-in boards, cards, the run folders and what is already imported, the trim/archive list, logs.`nIt never stops a card read or an import that is running - that can blue-screen the laptop - it redraws around it.`n(Same as F5.)"
    try { $b.Style = $win.FindResource('Cool') } catch { }
    $b.Add_Click({ Invoke-DataRefresh })
    [Windows.Controls.DockPanel]::SetDock($b, 'Right')
    $hdr.Children.RemoveAt(0)
    [void]$row.Children.Add($b); [void]$row.Children.Add($title)
    $hdr.Children.Insert(0, $row)
    $script:DataRefreshBtn = $b
}

function Invoke-DataRefresh {
    # Light and safe: caches cleared, every list rebuilt from disk / the port watcher.
    # A running card read or import is NEVER stopped (CP210x blue-screen history) -
    # the page is redrawn around it and the status says what is still running.
    $b = $script:DataRefreshBtn
    if ($b) { $b.IsEnabled = $false }
    $sw = [Diagnostics.Stopwatch]::StartNew(); $done = @(); $bad = @()
    $steps = [ordered]@{
        'boards'         = { [void](Update-LivePorts -Force) }
        'import list'    = { $script:ImportIdx = @{}; Update-ImpPorts; Update-ImpDest }
        'card drives'    = { Update-Cards }
        'files on screen' = { if ($script:ImpItems.Count -and -not $script:Stream) { Show-ImpList $script:ImpItems } }
        'trim & archive' = { Update-TrimCells }
        'run logs'       = { Update-Logs }
    }
    foreach ($k in $steps.Keys) {
        try { & $steps[$k]; $done += $k } catch { $bad += "$k ($($_.Exception.Message))" }
    }
    $sw.Stop()
    if ($b) { $b.IsEnabled = $true }
    $msg = 'Data page refreshed in {0:0.0} s' -f $sw.Elapsed.TotalSeconds
    if ($script:Stream) { $msg += " - '$($script:Stream.Title)' is still running (not stopped on purpose; its progress is in the activity pane)" }
    if ($bad.Count) { $msg += ' - could not refresh: ' + ($bad -join '; ') }
    Set-Status $msg $(if ($bad.Count) { $Pal.Amber } elseif ($script:Stream) { $Pal.Cyan } else { $Pal.Green })
    try { Write-Activity ('  ' + $msg) $(if ($bad.Count) { $Pal.Amber } else { $Pal.Faint }) } catch { }
}

function Invoke-UndoLastImport {
    if (Test-TaskBusy 'Undo') { return }
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

# -- one task at a time: the buttons say so (oct. 18 2026: Import clicked again while
#    an import was running opened a second confirm box over the first copy)
function Update-BusyButtons([bool]$Busy) {
    $title = if ($Busy -and $script:Stream) { [string]$script:Stream.Title } else { '' }
    foreach ($n in 'ImpGo', 'ImpPreview', 'ImpDel', 'ImpList', 'LocRead', 'LocWrite', 'SdDelete') {
        $b = $ui[$n]; if (-not $b) { continue }
        if ($Busy) { $b.IsEnabled = $false; $b.ToolTip = "Wait - '$title' is still running (one task at a time)." } else { $b.ClearValue([Windows.FrameworkElement]::ToolTipProperty) }
    }
    foreach ($b in @($script:ImpUndoBtn, $script:ImpCollectBtn)) { if ($b) { $b.IsEnabled = -not $Busy } }
    if ($Busy) {
        if ($title -match '(?i)^import') { $ui.ImpGo.Content = 'Importing... wait' }
    } else {
        foreach ($n in 'ImpList', 'LocRead', 'LocWrite', 'SdDelete') { if ($ui[$n]) { $ui[$n].IsEnabled = $true } }
        try { Update-ImpSummary } catch { }        # Import / Preview / Delete follow the ticked rows again
        if (-not $script:ImpTable) { $ui.ImpGo.Content = 'Import' }
    }
}

function Test-TaskBusy([string]$What) {
    # $true (and says so) while another task runs - checked BEFORE any confirm box opens
    if (-not $script:Stream) { return $false }
    [void][Windows.MessageBox]::Show("$What is not started: '$($script:Stream.Title)' is still running.`n`nWait for it to finish - its progress is in the activity pane.", 'Busy')
    return $true
}

function Get-PieceSize($F) {
    # one card file's size for comparing the pieces of one run: bytes, else rows x ~80 B
    if ($null -ne $F.bytes -and [long]$F.bytes -ge 0) { return [long]$F.bytes }
    if ($null -ne $F.rows) { return [long]$F.rows * 80 }
    return 0L
}
