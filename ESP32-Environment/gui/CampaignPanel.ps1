# gui\CampaignPanel.ps1 - the Campaign side panel ("selected run" notes) stays
# current (user, oct. 18 2026: "it is either delayed or showing old notes").
# Two causes, both fixed here:
#   1. the panel kept the run object it was opened with: when the campaign data
#      (inventory_cells.py) or the redo check (redo_list.py) came back in the
#      background, it was redrawn from that OLD object -> Update-CampPanelFresh
#      looks the run up again in the NEW data and redraws.
#   2. nothing said the notes were older than the run's files: clicking a run whose
#      files changed after its last check now re-checks THAT run at once (seconds)
#      and shows "re-checking - the notes below are from <time>"; otherwise a quiet
#      "checked <time>" line. When the check returns, the panel redraws by itself.
# Dot-sourced by run_gui.ps1. ASCII only.

$script:RedoAtCell = @{}; $script:RedoAtAll = $null

function Get-SlotKeyPath($S) {
    $a = if ($S.kind -eq 'benign' -or $S.attack -in @('none', 'baseline')) { 'baseline' } else { [string]$S.attack }
    return ('{0}/{1}/{2}/{3}' -f $a, ([string]$S.topology -replace '^partial$', 'partial_mesh'), $S.location, $S.scenario)
}

function Get-FreshSlot($S) {
    # the same run in the CURRENT campaign data (the panel may hold an older copy)
    if (-not $S -or -not $script:Campaign) { return $S }
    foreach ($x in @($script:Campaign.slots)) {
        if ($x.attack -eq $S.attack -and $x.topology -eq $S.topology -and $x.location -eq $S.location -and $x.scenario -eq $S.scenario -and $x.kind -eq $S.kind) { return $x }
    }
    return $S
}

function Update-CampPanelFresh {
    if (-not $script:CampSlot) { return }
    try { Show-CampaignCell (Get-FreshSlot $script:CampSlot) } catch { }
}

function Set-RedoCheckedTimes([string[]]$Only, [bool]$Part) {
    $now = Get-Date
    if ($Part) { foreach ($o in @($Only)) { if ($o) { $script:RedoAtCell[$o] = $now } } }
    else { $script:RedoAtAll = $now; $script:RedoAtCell = @{} }
}

function Add-CampFreshness($Body, $S) {
    $k = Get-SlotKeyPath $S
    $busy = -not $ui.LoadRedo.IsEnabled
    $checked = if ($script:RedoAtCell[$k]) { $script:RedoAtCell[$k] } else { $script:RedoAtAll }
    $changed = $false
    if ($script:RedoCells) {
        $o = $script:RedoCells[$k]; $n = Get-OneCellStamp $k      # this run's folders only - no lag on a click
        $changed = [bool](($o -and -not $n) -or ($n -and -not $o) -or ($o -and $n -and ($o[0] -ne $n[0] -or $o[1] -ne $n[1])))
        if ($changed -and -not $busy) { Start-RedoList -Only @($k); $busy = $true }
    }
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 8; $b.Padding = '10,6'; $b.Margin = '0,0,0,8'
    if ($busy -or $changed) {
        $b.Background = Get-Brush '#2E2716'; $b.BorderThickness = '3,0,0,0'; $b.BorderBrush = Get-Brush $Pal.Amber
        $t = New-Text ('Re-checking this run now' + $(if ($checked) { ' - the notes below are from ' + $checked.ToString('h:mm tt') + ', before its latest change' } else { '' }) + '. They update by themselves in a few seconds.') 11.5 $Pal.Amber
    } else {
        $t = New-Text $(if ($checked) { 'notes checked ' + $checked.ToString('h:mm tt') + ' - matches the run''s current files' } else { 'notes from the start-up check' }) 10.5 $Pal.Faint
        $b.Padding = '2,0'
    }
    $t.TextWrapping = 'Wrap'; $b.Child = $t
    $Body.Children.Insert(0, $b)
}
