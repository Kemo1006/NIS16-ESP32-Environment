# gui\Alerts.ps1 - the Live run's "ALERTS FROM THE BOARDS", smarter (oct. 18 2026).
# run_gui.ps1's Add-RunAlert still keeps its own list (the self-test reads it);
# at its end it hands every alert to Add-RunAlertSmart, which draws this panel:
#   * a KIND per alert (crash, power, port, location, tunnel, start, mesh, phase,
#     export, board) from its words + colour -> an icon and a short title
#   * the BOARD it is about as a chip ("node4: ..." / "node4 (COM33) ...")
#   * one "do this" line for every problem kind
#   * repeats fold into one card with a x N count instead of a growing list
#   * a good alert RESOLVES the matching open problems (a crash -> that board is
#     back up; a tunnel problem -> UART OK; a missing child -> all joined), so
#     the card dims and says "resolved 3:41 PM"
#   * a problem raised during BASELINE or ATTACK gets "during the capture" -
#     those are the ones that touch the dataset
#   * header: open problems / resolved / good, and All / Problems / Good filters
# Only the new card is built (with a short fade-in); nothing is re-rendered, so
# it costs nothing between alerts. Dot-sourced by run_gui.ps1. ASCII only.

$script:Dot = '  ' + [string][char]0x00B7 + '  '
$script:AlertKinds = @(
    @{ K = 'health';   Rx = '(?i)LOW HEAP|LOW STACK';                                   G = 0xE9D9; T = 'HEALTH' }
    @{ K = 'crash';    Rx = '(?i)crash|panic|watchdog|\bWDT\b|guru|abort';                 G = 0xE7BA; T = 'CRASH' }
    @{ K = 'power';    Rx = '(?i)brownout|power cut|POWERON|unplugged';                    G = 0xE945; T = 'POWER' }
    @{ K = 'port';     Rx = '(?i)could not open|held by|port .*busy|LOST|disappeared';                      G = 0xE88E; T = 'PORT' }
    @{ K = 'location'; Rx = '(?i)location';                                                G = 0xE707; T = 'LOCATION' }
    @{ K = 'tunnel';   Rx = '(?i)UART|tunnel|wormhole';                                    G = 0xE71B; T = 'TUNNEL' }
    @{ K = 'start';    Rx = '(?-i)\bSTART(_ANYWAY)?\b|\bREADY\b';                                           G = 0xE768; T = 'START' }
    @{ K = 'export';   Rx = '(?i)SAFE TO EXPORT|export';                                   G = 0xE896; T = 'EXPORT' }
    @{ K = 'phase';    Rx = '(?i)phase|cooldown|TERMINATE|run finished|scenario|move .* now'; G = 0xE916; T = 'PHASE' }
    @{ K = 'mesh';     Rx = '(?i)child|children|topology|mesh|parent|joined|hop';         G = 0xE716; T = 'MESH' }
    @{ K = 'boot';     Rx = '(?i)booted|back up|running';                                  G = 0xE7E8; T = 'BOARD' }
)
$script:AlertDo = @{
    health   = 'Memory or a task stack is running low on this board. If it crashes next, this is the likely cause - keep its crash-watch log (tools/health_report.py shows the trend).'
    crash    = 'Its backtrace is decoded into the run-log folder. The same board crashing twice = note it for this run (D9).'
    power    = 'Weak powerbank or a long / thin cable: give it a stronger supply, plug it straight in, then watch it rejoin.'
    port     = 'Close whatever holds the port (named above), then retry that step.'
    location = 'Power-cycle that board BEFORE START, so its SD card files this run under the right site.'
    tunnel   = 'Check the crossed TX->RX wires and GND between A and B. The root holds Phase 0 until UART is OK both ways.'
    start    = 'The root keeps your START and fires it once this is fixed - or START_ANYWAY, and report the run as such.'
    mesh     = 'A missing or moved child: is it powered, in range, not brownout-looping? Move boards only BEFORE START.'
    phase    = 'Do the human step now (it is timed from Phase 0).'
}

function Get-AlertKind([string]$Text, [bool]$Good = $false) {
    # good news about a board ("back up after the crash", "booted") is a BOARD
    # alert, not a crash - check that first so the words do not mislead
    if ($Good) { $b = @($script:AlertKinds | Where-Object { $_.K -eq 'boot' })[0]; if ($Text -match $b.Rx) { return $b } }
    foreach ($k in $script:AlertKinds) { if ($Text -match $k.Rx) { return $k } }
    return @{ K = 'other'; G = 0xE946; T = 'NOTE' }
}

function Reset-SmartAlerts {
    $script:AlertItems = New-Object System.Collections.ArrayList
    $script:AlertDash = $script:Dash
    if ($script:AlertList) { $script:AlertList.Children.Clear() }
    Update-AlertHeader
}

function Update-AlertHeader {
    $h = $script:AlertHead; if (-not $h) { return }
    $open = @($script:AlertItems | Where-Object { -not $_.Good -and -not $_.Resolved }).Count
    $res = @($script:AlertItems | Where-Object { -not $_.Good -and $_.Resolved }).Count
    $good = @($script:AlertItems | Where-Object { $_.Good }).Count
    $h.Inlines.Clear()
    foreach ($p in @(@($open, 'open problem', $Pal.Red), @($res, 'resolved', $Pal.Faint), @($good, 'good news', $Pal.Green))) {
        $d = New-Object Windows.Documents.Run ([string][char]0x25CF + ' '); $d.Foreground = Get-Brush $p[2]; [void]$h.Inlines.Add($d)
        $r = New-Object Windows.Documents.Run ('{0} {1}{2}     ' -f $p[0], $p[1], $(if ($p[0] -ne 1 -and $p[1] -eq 'open problem') { 's' } else { '' }))
        $r.Foreground = Get-Brush $(if ($p[0]) { $Pal.Text } else { $Pal.Faint }); [void]$h.Inlines.Add($r)
    }
    if ($script:AlertPanel) { $script:AlertPanel.Visibility = $(if ($script:AlertItems.Count) { 'Visible' } else { 'Collapsed' }) }
}

function Set-AlertFilter([string]$F) {
    $script:AlertFilter = $F
    foreach ($it in @($script:AlertItems)) { Set-AlertVisible $it }
    foreach ($b in @($script:AlertChips)) { $on = ([string]$b.Tag -eq $F); $b.Background = Get-Brush $(if ($on) { $Pal.Card2 } else { $Pal.Card }); $b.Foreground = Get-Brush $(if ($on) { $Pal.Text } else { $Pal.Faint }) }
}

function Set-AlertVisible($It) {
    $show = switch ($script:AlertFilter) { 'problems' { -not $It.Good } 'good' { $It.Good } default { $true } }
    $It.Border.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' })
}

function Set-AlertResolved($It) {
    if ($It.Resolved -or $It.Good) { return }
    $It.Resolved = $true
    $It.Border.Opacity = 0.55
    $It.WhenTb.Text = $It.WhenTb.Text + $script:Dot + 'resolved ' + (Get-Date).ToString('h:mm tt')
    if ($It.DoTb) { $It.DoTb.Visibility = 'Collapsed' }
}

function Add-RunAlertSmart([string]$Text, [string]$Hex) {
    if (-not $script:AlertList -or -not $Text) { return }
    if (-not [object]::ReferenceEquals($script:AlertDash, $script:Dash)) { Reset-SmartAlerts }
    $ui.RunAlerts.Visibility = 'Collapsed'
    $good = $Hex -in @($Pal.Green, $Pal.Cyan)
    $kind = Get-AlertKind $Text $good
    # the board: a label of this run's preset as the first word, or "x: ..." / "x (COM9) ..."
    $board = ''
    $labels = @(); try { $labels = @($script:Run.Plan.Full | ForEach-Object { [string]$_.Label }) } catch { }
    if ($Text -match '^(?<b>[A-Za-z][\w-]{0,20})(?<rest>(?: \(COM\d+\))?:? )') {
        $w = $Matches.b
        if ($labels -contains $w -or $Matches.rest -match 'COM' -or ($Matches.rest -match ':' -and $w -match '(?i)^(node|child|root|victim|attacker|board)[\w-]*$' -and $w -cnotmatch '^[A-Z_]+$')) { $board = $w }
    }
    $body = $Text
    if ($board) { $body = ($Text -replace ('^' + [regex]::Escape($board) + '(?: \(COM\d+\))?:?\s*'), '') }
    # a good alert closes the matching open problems
    if ($good) {
        foreach ($it in @($script:AlertItems | Where-Object { -not $_.Good -and -not $_.Resolved })) {
            $sameBoard = $board -and $it.Board -eq $board
            $hit = ($sameBoard -and ($it.Kind -eq $kind.K -or ($kind.K -eq 'boot' -and $it.Kind -in @('crash', 'power', 'port')))) -or
                   (-not $board -and $it.Kind -eq $kind.K -and $kind.K -in @('tunnel', 'mesh', 'start')) -or
                   ($kind.K -eq 'mesh' -and $Text -match '(?i)^All \d+ children' -and $it.Kind -eq 'mesh')
            if ($hit) { Set-AlertResolved $it }
        }
    }
    # a repeat folds into its card (numbers ignored: "5/7" and "6/7" are one story)
    $key = '{0}|{1}|{2}|{3}' -f $kind.K, $board, $good, ($body -replace '\d+', '#' -replace '\s+', ' ')
    $same = @($script:AlertItems | Where-Object { $_.Key -eq $key }) | Select-Object -First 1
    $when = (Get-Date).ToString('h:mm:ss tt')
    $seg = if ($script:Dash) { [int]$script:Dash.Seg } else { -1 }
    $phase = switch ($seg) { 0 { 'stabilise' } 1 { 'baseline' } 2 { 'attack' } 3 { 'cooldown' } 4 { 'end' } default { '' } }
    if ($same) {
        $same.Count++
        $same.TextTb.Text = $body
        $same.CountTb.Text = 'x ' + $same.Count; $same.CountBox.Visibility = 'Visible'
        $same.WhenTb.Text = $when + $(if ($phase) { $script:Dot + $phase } else { '' }) + '   .   first ' + $same.First
        if ($same.Resolved -and -not $good) { $same.Resolved = $false; $same.Border.Opacity = 1; if ($same.DoTb) { $same.DoTb.Visibility = 'Visible' } }
        [void]$script:AlertList.Children.Remove($same.Border); $script:AlertList.Children.Insert(0, $same.Border)
        [void]$script:AlertItems.Remove($same); [void]$script:AlertItems.Insert(0, $same)
        Update-AlertHeader; return
    }
    $tone = if ($good) { $Hex } elseif ($Hex -eq $Pal.Red) { $Pal.Red } else { $Pal.Amber }
    $bg = switch ($tone) { $Pal.Red { '#2E1A28' } $Pal.Green { '#12302B' } $Pal.Cyan { '#0F2E3A' } default { '#2E2716' } }
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 10; $card.Padding = '10,8'; $card.Margin = '0,6,0,0'
    $card.Background = Get-Brush $bg; $card.BorderBrush = Get-Brush $tone; $card.BorderThickness = '3,0,0,0'
    $grid = New-Object Windows.Controls.Grid
    foreach ($w in 34, 0) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w) { New-Object Windows.GridLength $w } else { New-Object Windows.GridLength 1, 'Star' }); [void]$grid.ColumnDefinitions.Add($cd) }
    $ic = New-Object Windows.Controls.Border; $ic.Width = 26; $ic.Height = 26; $ic.CornerRadius = 13; $ic.VerticalAlignment = 'Top'; $ic.Background = Get-Brush '#22FFFFFF'
    $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char]$kind.G; $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 12; $g.Foreground = Get-Brush $tone
    $g.HorizontalAlignment = 'Center'; $g.VerticalAlignment = 'Center'; $ic.Child = $g
    [void]$grid.Children.Add($ic)
    $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1)
    $top = New-Object Windows.Controls.WrapPanel
    $k = New-Object Windows.Controls.TextBlock; $k.Text = $kind.T; $k.FontSize = 10; $k.FontWeight = 'Bold'; $k.Foreground = Get-Brush $tone; $k.Margin = '0,1,8,0'; [void]$top.Children.Add($k)
    if ($board) {
        $chip = New-Object Windows.Controls.Border; $chip.CornerRadius = 6; $chip.Padding = '6,0'; $chip.Margin = '0,0,6,0'; $chip.Background = Get-Brush $Pal.Card2
        $ct = New-Object Windows.Controls.TextBlock; $ct.Text = $board; $ct.FontSize = 10.5; $ct.FontWeight = 'SemiBold'; $ct.Foreground = Get-Brush $Pal.Blue; $chip.Child = $ct
        [void]$top.Children.Add($chip)
    }
    if (-not $good -and $seg -in @(1, 2)) {
        $cap = New-Object Windows.Controls.Border; $cap.CornerRadius = 6; $cap.Padding = '6,0'; $cap.Margin = '0,0,6,0'; $cap.Background = Get-Brush '#4A1D2C'
        $cpt = New-Object Windows.Controls.TextBlock; $cpt.Text = 'during the capture'; $cpt.FontSize = 10; $cpt.Foreground = Get-Brush $Pal.Red; $cap.Child = $cpt
        $cap.ToolTip = "Raised in the $phase phase - it can affect this run's data. Mention it when the run is verified."
        [void]$top.Children.Add($cap)
    }
    $cb = New-Object Windows.Controls.Border; $cb.CornerRadius = 6; $cb.Padding = '6,0'; $cb.Background = Get-Brush $tone; $cb.Visibility = 'Collapsed'
    $cnt = New-Object Windows.Controls.TextBlock; $cnt.FontSize = 10; $cnt.FontWeight = 'Bold'; $cnt.Foreground = Get-Brush '#0B1020'; $cb.Child = $cnt
    [void]$top.Children.Add($cb)
    [void]$sp.Children.Add($top)
    $tt = New-Object Windows.Controls.TextBlock; $tt.Text = $body; $tt.TextWrapping = 'Wrap'; $tt.FontSize = 12; $tt.Foreground = Get-Brush $Pal.Text; $tt.Margin = '0,2,0,0'
    [void]$sp.Children.Add($tt)
    $do = $null
    if (-not $good -and $script:AlertDo[$kind.K]) {
        $do = New-Object Windows.Controls.TextBlock; $do.Text = 'do: ' + $script:AlertDo[$kind.K]; $do.TextWrapping = 'Wrap'; $do.FontSize = 11; $do.Foreground = Get-Brush $Pal.Cyan; $do.Margin = '0,3,0,0'
        [void]$sp.Children.Add($do)
    }
    $wt = New-Object Windows.Controls.TextBlock; $wt.Text = $when + $(if ($phase) { $script:Dot + $phase } else { '' }); $wt.FontSize = 10; $wt.Foreground = Get-Brush $Pal.Faint; $wt.Margin = '0,3,0,0'
    [void]$sp.Children.Add($wt)
    [void]$grid.Children.Add($sp)
    $card.Child = $grid
    $it = [pscustomobject]@{ Key = $key; Kind = $kind.K; Board = $board; Good = $good; Resolved = $false; Count = 1; First = (Get-Date).ToString('h:mm tt')
                             Border = $card; TextTb = $tt; WhenTb = $wt; CountTb = $cnt; CountBox = $cb; DoTb = $do }
    $script:AlertList.Children.Insert(0, $card); [void]$script:AlertItems.Insert(0, $it)
    Set-AlertVisible $it
    try { $card.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation 0, 1, ([TimeSpan]::FromMilliseconds(260)))) } catch { }
    # full: good news and resolved ones go first - an open problem is never pushed out
    while ($script:AlertItems.Count -gt 14) {
        $drop = @($script:AlertItems | Where-Object { $_.Good -or $_.Resolved }) | Select-Object -Last 1
        if (-not $drop) { $drop = $script:AlertItems[$script:AlertItems.Count - 1] }
        [void]$script:AlertList.Children.Remove($drop.Border); [void]$script:AlertItems.Remove($drop)
    }
    Update-AlertHeader
}

function Initialize-GuiAlerts {
    $old = $ui.RunAlerts; if (-not $old -or -not ($old.Parent -is [Windows.Controls.Panel])) { return }
    $host_ = $old.Parent
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '0,4,0,0'; $panel.Visibility = 'Collapsed'
    $head = New-Object Windows.Controls.DockPanel
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($chips, 'Right')
    $script:AlertChips = @()
    foreach ($f in @(@('all', 'All'), @('problems', 'Problems'), @('good', 'Good'))) {
        $b = New-Object Windows.Controls.Button; $b.Content = $f[1]; $b.Tag = $f[0]; $b.Padding = '8,2'; $b.Margin = '4,0,0,0'; $b.FontSize = 10.5
        $b.BorderThickness = 0; $b.Background = Get-Brush $Pal.Card; $b.Foreground = Get-Brush $Pal.Faint
        $b.Add_Click({ param($s, $e) Set-AlertFilter ([string]$s.Tag) })
        [void]$chips.Children.Add($b); $script:AlertChips += $b
    }
    [void]$head.Children.Add($chips)
    $ht = New-Object Windows.Controls.TextBlock; $ht.FontSize = 11; $ht.VerticalAlignment = 'Center'; [void]$head.Children.Add($ht)
    [void]$panel.Children.Add($head)
    $list = New-Object Windows.Controls.StackPanel; [void]$panel.Children.Add($list)
    $host_.Children.Insert($host_.Children.IndexOf($old) + 1, $panel)
    $script:AlertPanel = $panel; $script:AlertHead = $ht; $script:AlertList = $list
    $script:AlertFilter = 'all'
    Reset-SmartAlerts
    Set-AlertFilter 'all'
}
