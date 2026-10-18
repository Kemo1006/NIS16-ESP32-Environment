# gui\TodayStrip.ps1 - the Home page's "last 24 hours" strip (oct. 19 2026, user):
#   CAPTURED   runs that got new export files (by the import time in the FILE NAME -
#              a sync rewrites modified times), with board counts and the time
#   ANALYSED   runs verified (verdicts.json), coloured by verdict, with the grade
#   NEXT UP    the next run in campaign order + a "Capture it" button
# Cost: the exports index Get-LastImports already keeps (re-read only for changed
# files), verdicts in memory, one small report read per analysed run (max 6).
# Called when the campaign data arrives (Update-Home). Dot-sourced. ASCII only.

function New-TodayCol([string]$Title, [string]$Hex) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '14,10'; $b.Margin = '0,0,10,0'
    $b.Background = Get-Brush $Pal.Card2; $b.BorderBrush = Get-Brush $Hex; $b.BorderThickness = '0,3,0,0'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text $Title 10.5 $Hex 'Bold'))
    $b.Child = $sp
    return @{ Border = $b; Panel = $sp }
}

function Add-TodayLine($Panel, [string]$Dot, [string]$Text, [string]$Sub) {
    $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = '0,6,0,0'
    $d = New-Object Windows.Shapes.Ellipse; $d.Width = 8; $d.Height = 8; $d.Fill = Get-Brush $Dot; $d.Margin = '0,5,8,0'; $d.VerticalAlignment = 'Top'
    [Windows.Controls.DockPanel]::SetDock($d, 'Left'); [void]$dp.Children.Add($d)
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Text $Text 12.5 $Pal.Text 'SemiBold'; $t.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t)
    if ($Sub) { $s = New-Text $Sub 11 $Pal.Dim; $s.TextWrapping = 'Wrap'; [void]$sp.Children.Add($s) }
    [void]$dp.Children.Add($sp)
    [void]$Panel.Children.Add($dp)
}

function Update-TodayStrip {
    if (-not $script:TodayHost) {
        $par = $ui.HomeCards.Parent; if (-not ($par -is [Windows.Controls.Panel])) { return }
        $script:TodayHost = New-Object Windows.Controls.Border; $script:TodayHost.Margin = '0,4,0,14'
        $par.Children.Insert($par.Children.IndexOf($ui.HomeCards) + 1, $script:TodayHost)
    }
    $since = (Get-Date).AddHours(-24)
    $outer = New-Object Windows.Controls.StackPanel
    $hd = New-Object Windows.Controls.DockPanel; $hd.Margin = '2,0,0,8'
    [void]$hd.Children.Add((New-Text ('LAST 24 HOURS   -   since {0}' -f $since.ToString('ddd h:mm tt')) 11 $Pal.Faint 'Bold'))
    [void]$outer.Children.Add($hd)
    $grid = New-Object Windows.Controls.Primitives.UniformGrid; $grid.Columns = 3

    # CAPTURED (the exports index; Get-LastImports fills it)
    $cap = New-TodayCol 'CAPTURED' $Pal.Pink
    try { [void](Get-LastImports) } catch { }
    $runs = @{}
    foreach ($e in @($script:ImportIdx.GetEnumerator())) {
        $v = $e.Value; if (-not $v -or $v.When -lt $since) { continue }
        $k = '{0}  r{1}' -f $v.Cell, $v.Rep
        if (-not $runs[$k]) { $runs[$k] = @{ N = 0; Last = $v.When; Cell = $v.Cell } }
        $runs[$k].N++; if ($v.When -gt $runs[$k].Last) { $runs[$k].Last = $v.When }
    }
    if ($runs.Count) {
        foreach ($k in @($runs.Keys | Sort-Object { $runs[$_].Last } -Descending | Select-Object -First 5)) {
            $atk = ($runs[$k].Cell -split ' / ')[0]
            $dot = if ($atk -eq 'blackhole') { $Pal.Red } elseif ($atk -eq 'wormhole') { $Pal.Purple } else { $Pal.Green }
            Add-TodayLine $cap.Panel $dot $k ('{0} board file(s)   -   last at {1}' -f $runs[$k].N, $runs[$k].Last.ToString('h:mm tt'))
        }
    } else { $n = New-Text 'nothing imported yet' 12 $Pal.Faint; $n.Margin = '0,6,0,0'; [void]$cap.Panel.Children.Add($n) }
    [void]$grid.Children.Add($cap.Border)

    # ANALYSED (verdicts.json, newest first)
    $ana = New-TodayCol 'ANALYSED' $Pal.Cyan
    $done = @()
    foreach ($k in @($script:Verdicts.Keys)) {
        $v = $script:Verdicts[$k]; $w = [datetime]::MinValue
        if ($v -and [datetime]::TryParseExact([string]$v.When, 'yyyy-MM-dd HH:mm', $null, 'None', [ref]$w) -and $w -ge $since) { $done += @{ Key = $k; When = $w; Code = [int]$v.Code } }
    }
    if ($done.Count) {
        foreach ($d in @($done | Sort-Object { $_.When } -Descending | Select-Object -First 6)) {
            $grade = ''; try { $b = Get-CampReportBits $d.Key; if ($b -and $b.Grade) { $grade = $(if ($b.Old) { ' - old report' } elseif ($b.Grade -eq 'NOT CONFIRMED') { '' } else { ' - ' + $b.Grade }) } } catch { }
            $word = switch ($d.Code) { 0 { 'CONFIRMED' } 3 { 'SETUP INVALID' } 2 { 'INCONCLUSIVE' } default { 'NOT CONFIRMED' } }
            $dot = switch ($d.Code) { 0 { $Pal.Green } 1 { $Pal.Red } default { $Pal.Amber } }
            Add-TodayLine $ana.Panel $dot ($d.Key -replace '/', ' / ') ('{0}{1}   -   {2}' -f $word, $grade, $d.When.ToString('h:mm tt'))
        }
        if ($done.Count -gt 6) { $m = New-Text ("+ {0} more" -f ($done.Count - 6)) 11 $Pal.Faint; $m.Margin = '16,4,0,0'; [void]$ana.Panel.Children.Add($m) }
    } else { $n = New-Text 'nothing verified yet' 12 $Pal.Faint; $n.Margin = '0,6,0,0'; [void]$ana.Panel.Children.Add($n) }
    [void]$grid.Children.Add($ana.Border)

    # NEXT UP (campaign order)
    $nx = New-TodayCol 'NEXT UP' $Pal.Green
    $st = $script:Campaign
    if ($st -and $st.next) {
        Add-TodayLine $nx.Panel $Pal.Green (Get-SlotText $st.next) ("session {0}   -   {1} run(s) left, ~{2} h of capturing" -f $st.next.session, $st.remaining, [math]::Round($st.hours_left))
        $bt = New-Object Windows.Controls.Button; $bt.Content = ([string][char]0x25B6) + '  Capture it'; $bt.Padding = '12,5'; $bt.Margin = '16,10,0,0'; $bt.HorizontalAlignment = 'Left'
        try { $bt.Style = $win.FindResource('Primary') } catch { }
        $bt.Tag = $st.next; $bt.Add_Click({ param($x) Start-CellCapture $x.Tag })
        [void]$nx.Panel.Children.Add($bt)
    } elseif ($st) { Add-TodayLine $nx.Panel $Pal.Green 'Everything planned is captured!' '' }
    else { $n = New-Text 'loading the campaign...' 12 $Pal.Faint; $n.Margin = '0,6,0,0'; [void]$nx.Panel.Children.Add($n) }
    $nx.Border.Margin = '0'
    [void]$grid.Children.Add($nx.Border)
    [void]$outer.Children.Add($grid)
    $script:TodayHost.Child = $outer
}
