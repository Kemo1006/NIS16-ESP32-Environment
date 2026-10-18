# gui\LastPreset.ps1 - "which preset did I use last?" (oct. 18 2026).
#  * Every Live run records its preset in .last_used_preset.json (this laptop only,
#    git-ignored): when flashing starts, when it finishes, when it is stopped.
#    No record yet = the newest run log in datasets\run_logs names it instead.
#  * Run a capture: a reminder card under "up next" - the run, its state, the next
#    step for it, and "Show it" (selects that preset card).
#  * New / copied preset: a note at the top of the editor - your last preset, and
#    whether this run already has a preset (yours: saving replaces it; a teammate's:
#    copy theirs instead, same boards = same naming), live as the run is picked.
# Dot-sourced by run_gui.ps1. ASCII only.

$script:LastUsedFile = '.last_used_preset.json'

function Save-LastUsedPreset([string]$State) {
    $R = $script:Run
    if (-not $R -or -not $R.Plan -or -not $R.Plan.Preset -or $SelfTest) { return }
    $P = $R.Plan.Preset
    $rep = 1; try { $rep = [int]$R.Settings.Repeat } catch { }
    $rec = [ordered]@{
        path = [string]$P.Path; file = [string]$P.File; owner = [string]$P.Owner
        attack = $(if ($R.Plan.Attack -eq 'none') { 'baseline' } else { [string]$R.Plan.Attack }); topology = [string]$R.Plan.Topology
        location = [string]$R.Plan.Location; scenario = [string]$R.Plan.Scenario; repeat = $rep
        state = $State; when = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); computer = [string]$env:COMPUTERNAME
    }
    try { [IO.File]::WriteAllText((Join-Path $base $script:LastUsedFile), (ConvertTo-Json -InputObject $rec), (New-Object Text.UTF8Encoding $false)) } catch { }
    $script:LastLogScanAt = $null
    Update-LastUsedCard
}

function Get-LastUsedPreset {
    # @{ Path; File; Owner; Attack; Topology; Location; Scenario; Repeat; State; When; Source } or $null
    $f = Join-Path $base $script:LastUsedFile
    if ([IO.File]::Exists($f)) {
        try {
            $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
            return @{ Path = [string]$j.path; File = [string]$j.file; Owner = [string]$j.owner; Attack = [string]$j.attack; Topology = [string]$j.topology
                      Location = [string]$j.location; Scenario = [string]$j.scenario; Repeat = [int]$j.repeat; State = [string]$j.state
                      When = [datetime]::ParseExact([string]$j.when, 'yyyy-MM-dd HH:mm:ss', $null); Source = 'record' }
        } catch { }
    }
    # fallback: the newest run log ("<preset>_r<n>_<stamp>.log"), cached 30 s
    if (-not $script:LastLogScanAt -or ((Get-Date) - $script:LastLogScanAt).TotalSeconds -gt 30) {
        $script:LastLogScanAt = Get-Date; $script:LastLog = $null
        $dir = Join-Path $base 'datasets\run_logs'
        if ([IO.Directory]::Exists($dir)) {
            $newest = $null
            foreach ($fp in [IO.Directory]::EnumerateFiles($dir, '*_r*_*.log', 'AllDirectories')) {
                $fi = New-Object IO.FileInfo $fp
                if ($fi.Name -notmatch '^(?<p>[a-z]+-[a-z_]+-[a-z0-9_]+-[a-z]+)_r(?<r>\d+)_') { continue }
                if (-not $newest -or $fi.LastWriteTime -gt $newest.LastWriteTime) { $newest = $fi; $script:LastLog = @{ Base = $Matches.p; Rep = [int]$Matches.r; When = $fi.LastWriteTime } }
            }
        }
    }
    $L = $script:LastLog; if (-not $L) { return $null }
    if (-not $script:Presets) { return $null }
    $hit = @($script:Presets | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.File).ToLower() -eq $L.Base } |
             Sort-Object @{ E = { $_.Owner -ne $script:Me } }, @{ E = { $_.Saved }; Descending = $true }) | Select-Object -First 1
    if (-not $hit) { return $null }
    return @{ Path = $hit.Path; File = $hit.File; Owner = $hit.Owner; Attack = $hit.Attack; Topology = $hit.Topology; Location = $hit.Location
              Scenario = $hit.Scenario; Repeat = $L.Rep; State = 'logged'; When = $L.When; Source = 'run log' }
}

function Format-Ago([datetime]$T) {
    $s = ((Get-Date) - $T).TotalMinutes
    if ($s -lt 1) { return 'just now' }
    if ($s -lt 60) { return ('{0} min ago' -f [int]$s) }
    if ($T.Date -eq (Get-Date).Date) { return ('today ' + $T.ToString('h:mm tt')) }
    if ($T.Date -eq (Get-Date).Date.AddDays(-1)) { return ('yesterday ' + $T.ToString('h:mm tt')) }
    return $T.ToString('MMM dd  h:mm tt')
}

function Update-LastUsedCard {
    $c = $script:LastCard; if (-not $c) { return }
    $L = $null; try { $L = Get-LastUsedPreset } catch { }
    if (-not $L -or $script:LastCardHidden) { $c.Visibility = 'Collapsed'; return }
    $exists = $L.Path -and [IO.File]::Exists($L.Path)
    $a = if ($L.Attack -in @('none', 'baseline')) { 'baseline' } else { $L.Attack }
    $script:LastCardTitle.Text = '{0}  {4}  {1}  {4}  {2}  {4}  {3}' -f $a, ($L.Topology -replace '_', ' '), ($L.Location -replace '_', ' '), $L.Scenario, [char]0x00B7
    $runNow = $script:Run -and $script:Run.Active
    $state = switch ($L.State) {
        'running'  { if ($runNow) { 'running right now on the Live run page' } else { 'started ' + (Format-Ago $L.When) + ' and never reached the end here - its boards may still hold the run' } }
        'finished' { 'finished ' + (Format-Ago $L.When) }
        'stopped'  { 'stopped by you ' + (Format-Ago $L.When) + ' - pick it to resume or start over' }
        default    { 'last run log ' + (Format-Ago $L.When) }
    }
    $next = ''
    try { $n = Get-NextStep $a $L.Topology $L.Location $L.Scenario; $next = $n.Text } catch { }
    $tip = if ($L.State -eq 'finished' -and $next -match '^(verify|done|check)') { "next capture of this run = repeat $($L.Repeat + 1)" } else { '' }
    $script:LastCardSub.Text = ('{0} [{1}]  {4}  repeat {2}  {4}  {3}' -f $L.File, $L.Owner, $L.Repeat, $state, [char]0x00B7)
    $script:LastCardNext.Text = $(if ($next) { 'next: ' + $next + $(if ($tip) { '   ' + [char]0x00B7 + '   ' + $tip } else { '' }) } else { $tip })
    $script:LastCardGo.IsEnabled = [bool]$exists
    $script:LastCardGo.Content = $(if ($exists) { 'Show it  ' + [char]0x2192 } else { 'preset deleted' })
    $script:LastCardPath = $L.Path
    $c.Visibility = 'Visible'
}

function Initialize-GuiLastPreset {
    $hero = $ui.CapHero; if (-not $hero -or -not ($hero.Parent -is [Windows.Controls.Panel])) { return }
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 14; $card.Padding = '16,10'; $card.Margin = '0,0,0,12'
    $card.Background = Get-Brush $Pal.Card; $card.BorderBrush = Get-Brush $Pal.Line; $card.BorderThickness = 1; $card.Visibility = 'Collapsed'
    [Windows.Controls.DockPanel]::SetDock($card, 'Top')
    $dp = New-Object Windows.Controls.DockPanel
    $go = New-Object Windows.Controls.Button; $go.Content = 'Show it'; $go.Padding = '14,6'; $go.Margin = '12,0,0,0'; $go.VerticalAlignment = 'Center'
    [Windows.Controls.DockPanel]::SetDock($go, 'Right')
    $go.Add_Click({ if ($script:LastCardPath) { try { $ui.PresetFClear.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) } catch { }; Select-Preset $script:LastCardPath } })
    $x = New-Object Windows.Controls.Button; $x.Content = [string][char]0x2715; $x.Padding = '8,4'; $x.Margin = '6,0,0,0'; $x.VerticalAlignment = 'Center'; $x.ToolTip = 'Hide until the GUI restarts'
    [Windows.Controls.DockPanel]::SetDock($x, 'Right')
    $x.Add_Click({ $script:LastCardHidden = $true; $script:LastCard.Visibility = 'Collapsed' })
    [void]$dp.Children.Add($x); [void]$dp.Children.Add($go)
    $ic = New-Object Windows.Controls.Border; $ic.Width = 36; $ic.Height = 36; $ic.CornerRadius = 18; $ic.Background = Get-Brush $Pal.Card2; $ic.Margin = '0,0,12,0'; $ic.VerticalAlignment = 'Center'
    $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char]0xE81C; $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 15; $g.Foreground = Get-Brush $Pal.Cyan
    $g.HorizontalAlignment = 'Center'; $g.VerticalAlignment = 'Center'; $ic.Child = $g
    [Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$dp.Children.Add($ic)
    $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
    [void]$sp.Children.Add((New-Text 'LAST USED PRESET' 10 $Pal.Cyan 'Bold'))
    $t = New-Text '' 15 $Pal.Text 'Bold'; $t.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t)
    $s = New-Text '' 12 $Pal.Dim; $s.TextWrapping = 'Wrap'; [void]$sp.Children.Add($s)
    $n = New-Text '' 12 $Pal.Amber 'SemiBold'; $n.TextWrapping = 'Wrap'; [void]$sp.Children.Add($n)
    [void]$dp.Children.Add($sp)
    $card.Child = $dp
    $panel = $hero.Parent
    $panel.Children.Insert($panel.Children.IndexOf($hero) + 1, $card)
    $script:LastCard = $card; $script:LastCardTitle = $t; $script:LastCardSub = $s; $script:LastCardNext = $n; $script:LastCardGo = $go
    Update-LastUsedCard
}

# -- the preset editor note --
function Initialize-PresetEditorNote($Ed, $F, $From) {
    # called by Show-PresetEditor right before it opens; $From = the preset being edited (none = new)
    $root = $Ed.Content; if (-not ($root -is [Windows.Controls.Panel])) { return }
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 10; $b.Padding = '12,8'; $b.Margin = '0,0,0,12'
    $b.Background = Get-Brush $Pal.Card2; $b.BorderThickness = '3,0,0,0'; $b.BorderBrush = Get-Brush $Pal.Cyan
    [Windows.Controls.DockPanel]::SetDock($b, 'Top')
    $tb = New-Object Windows.Controls.TextBlock; $tb.TextWrapping = 'Wrap'; $tb.FontSize = 12.5; $b.Child = $tb
    $root.Children.Insert([Math]::Min(1, $root.Children.Count), $b)
    $script:EdF = $F; $script:EdNote = $b; $script:EdNoteText = $tb
    $script:EdFromPath = $(if ($From -and $From.Path) { [string]$From.Path } else { '' })
    foreach ($n in 'EdAttack', 'EdTopology', 'EdLocation', 'EdScenario', 'EdOwner') { $F[$n].Add_SelectionChanged({ Update-PresetEditorNote }) }
    $F.EdOwner.Add_LostFocus({ Update-PresetEditorNote })
    Update-PresetEditorNote
}

function Update-PresetEditorNote {
    $F = $script:EdF; $tb = $script:EdNoteText; if (-not $F -or -not $tb) { return }
    if (-not $script:Presets) { try { $script:Presets = Get-Presets } catch { } }
    $owner = ([string]$F.EdOwner.Text).Trim(); if (-not $owner) { $owner = [string]$script:Me }
    $a = [string]$F.EdAttack.SelectedItem; $t = [string]$F.EdTopology.SelectedItem; $l = [string]$F.EdLocation.SelectedItem; $s = [string]$F.EdScenario.SelectedItem
    $norm = { param($x) if ($x -in @('none', 'baseline')) { 'baseline' } else { [string]$x } }
    $topo = { param($x) ([string]$x) -replace '^partial$', 'partial_mesh' }
    $tb.Inlines.Clear()
    $add = { param($text, $hex, $bold) $r = New-Object Windows.Documents.Run $text; $r.Foreground = Get-Brush $hex; if ($bold) { $r.FontWeight = 'SemiBold' }; [void]$tb.Inlines.Add($r) }
    $tone = $Pal.Cyan
    # 1) this run already has preset(s)?
    if ($a -and $t -and $l -and $s) {
        $same = @($script:Presets | Where-Object { (& $norm $_.Attack) -eq (& $norm $a) -and (& $topo $_.Topology) -eq (& $topo $t) -and $_.Location -eq $l -and $_.Scenario -eq $s -and $_.Path -ne $script:EdFromPath } |
                  Sort-Object Saved -Descending)
        $mine = @($same | Where-Object { $_.Owner -eq $owner })
        $theirs = @($same | Where-Object { $_.Owner -ne $owner })
        if ($mine.Count) {
            & $add ("You already have a preset for this run: {0} (saved {1}). Saving REPLACES it." -f $mine[0].File, (Format-Ago $mine[0].Saved)) $Pal.Amber $true
            & $add "`n" $Pal.Dim $false; $tone = $Pal.Amber
        }
        if ($theirs.Count) {
            $who = (@($theirs | ForEach-Object { '{0} ({1})' -f $_.Owner, (Format-Ago $_.Saved) } | Select-Object -Unique) -join ', ')
            & $add ("Already made by {0} - Cancel and use Copy on theirs instead if it is the same boards (same naming, same run)." -f $who) $Pal.Amber $false
            & $add "`n" $Pal.Dim $false; if ($tone -eq $Pal.Cyan) { $tone = $Pal.Amber }
        }
        if (-not $same.Count) { & $add 'No preset exists for this run yet - this is the first one.' $Pal.Green $false; & $add "`n" $Pal.Dim $false }
    } else { & $add 'Pick the attack, topology, location and scenario - this note says if a preset for that run exists already.' $Pal.Dim $false; & $add "`n" $Pal.Dim $false }
    # 2) your previous preset + the last used one
    $prev = @($script:Presets | Where-Object { $_.Owner -eq $owner -and $_.Path -ne $script:EdFromPath } | Sort-Object Saved -Descending) | Select-Object -First 1
    if ($prev) { & $add ("Your last preset: {0}  -  saved {1}" -f $prev.File, (Format-Ago $prev.Saved)) $Pal.Dim $false }
    $L = $null; try { $L = Get-LastUsedPreset } catch { }
    if ($L) {
        $cur = (& $norm $a) -eq (& $norm $L.Attack) -and (& $topo $t) -eq (& $topo $L.Topology) -and $l -eq $L.Location -and $s -eq $L.Scenario
        & $add ("`nLast used on this laptop: {0} [{1}]  -  {2}{3}" -f $L.File, $L.Owner, (Format-Ago $L.When), $(if ($cur) { '   (this same run - a new capture of it is repeat ' + ($L.Repeat + 1) + ')' } else { '' })) $(if ($cur) { $Pal.Cyan } else { $Pal.Dim }) $cur
    }
    $script:EdNote.BorderBrush = Get-Brush $tone
}
