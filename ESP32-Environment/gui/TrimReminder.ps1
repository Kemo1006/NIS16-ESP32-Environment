# gui\TrimReminder.ps1 - "this run is not trimmed yet" reminders (oct. 20 2026, user:
# "add a reminder to trim the files that have not been trimmed yet"). The sidebar's Data
# badge ("N to trim", Update-NavBadges) is the standing reminder; this adds a toast after a
# Collect and one at start-up, both opening the Trim tab on the run(s) concerned.
# Dot-sourced by run_gui.ps1 (functions only). ASCII only.

function Open-TrimFor([string]$Dir = '') {
    Show-Page 5
    try {
        $tab = @($ui.DataTabs.Items | Where-Object { [string]$_.Header -match 'Trim' }) | Select-Object -First 1
        if ($tab) { $ui.DataTabs.SelectedItem = $tab }
    } catch { }
    Update-TrimCells
    if ($Dir) {
        $hit = @($script:TrimCells | Where-Object { $_.Dir -eq $Dir }) | Select-Object -First 1
        if ($hit) { $ui.TrimFAll.IsChecked = $true; $ui.TrimList.SelectedItem = $hit; $ui.TrimList.ScrollIntoView($hit) }
    } else {
        $ui.TrimFTodo.IsChecked = $true     # 'Not trimmed' first; 'Needs re-trim' is one click away
    }
}

function Show-TrimReminder([string]$Dir) {
    # after new files land in one run folder (Collect): remind if its trimmed\ copy is behind
    if (-not $Dir) { return }
    $c = @(Get-ExportCells | Where-Object { $_.Dir -eq $Dir }) | Select-Object -First 1
    if (-not $c -or $c.Look -eq 'done') { return }
    $script:TrimRemindDir = $Dir
    $why = if ($c.Look -eq 'todo') { 'it has no trimmed copy yet' }
           elseif ($c.Missing) { "$($c.Missing) new file(s) have no trimmed copy yet" }
           else { 'its trimmed copy is older than the data' }
    Show-Toast 'Trim this run' ("{0}: {1}. Analyse trims it for you, or trim it now." -f $c.Text, $why) ([string][char]0xE8C6) 'GradMain' { Open-TrimFor $script:TrimRemindDir } 'Open Trim'
    $script:TrimCountAt = $null              # the sidebar badge recounts on its next tick
}

function Initialize-GuiTrimReminder {
    # once at start-up: say how many runs wait for a trim (the badge keeps saying it)
    try {
        $n = @(Get-ExportCells | Where-Object { $_.Look -ne 'done' }).Count
        $script:TrimTodoCount = $n
        if ($n -gt 0 -and -not $script:AutoConfirm) {
            Show-Toast ("{0} run(s) not trimmed yet" -f $n) 'New or changed captures have no up-to-date trimmed copy. Trim them before analysing (Analyse also trims).' ([string][char]0xE8C6) 'GradMain' { Open-TrimFor '' } 'Show them'
        }
    } catch { }
}
