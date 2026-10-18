# gui\PageDesign.ps1 - one design pass for every page (oct. 19 2026, user: "more design and
# aesthetic to all the other pages"). Done ONCE at start-up, nothing runs afterwards:
#   * each page title (the H1 style) gets a gradient icon tile on its left and a short
#     gradient accent bar under it, so every page reads like the Home page
#   * (the card edge gradient is in run_gui.ps1's Card style - every card on every page)
# Dot-sourced by run_gui.ps1. ASCII only.

$script:PageIcons = @{
    'Run a capture' = @(0xE722, 'GradMain'); 'Verify & analyse' = @(0xE9D9, 'GradCool'); 'Campaign' = @(0xE8F1, 'GradMain')
    'Boards' = @(0xE950, 'GradCool'); 'Data' = @(0xE8B7, 'GradGood'); 'Wireshark & sniffer' = @(0xE968, 'GradCool')
    'GitHub sync' = @(0xE895, 'GradGood'); 'Live run' = @(0xE768, 'GradMain')
}

function Get-LogicalTextBlocks($Root) {
    # every TextBlock below $Root in the logical tree (pages that are not shown yet included)
    $out = New-Object System.Collections.ArrayList
    $stack = New-Object System.Collections.Stack; $stack.Push($Root)
    while ($stack.Count) {
        $n = $stack.Pop()
        if ($n -is [Windows.Controls.TextBlock]) { [void]$out.Add($n); continue }
        if ($n -is [Windows.DependencyObject]) {
            foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($n)) { if ($c -is [Windows.DependencyObject]) { $stack.Push($c) } }
        }
    }
    return $out
}

function Initialize-GuiPageDesign {
    try { $h1 = $win.FindResource('H1') } catch { return }
    foreach ($tb in @(Get-LogicalTextBlocks $win)) {
        if ($tb.Style -ne $h1) { continue }
        $par = $tb.Parent; if (-not ($par -is [Windows.Controls.Panel])) { continue }
        $ic = $script:PageIcons[[string]$tb.Text]; if (-not $ic) { continue }
        $at = $par.Children.IndexOf($tb)
        $par.Children.RemoveAt($at)
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = '0,0,0,2'
        # icon tile
        $tile = New-Object Windows.Controls.Border; $tile.Width = 44; $tile.Height = 44; $tile.CornerRadius = 12; $tile.Margin = '0,0,14,0'; $tile.VerticalAlignment = 'Top'
        try { $tile.Background = $win.FindResource($ic[1]) } catch { $tile.Background = Get-Brush $Pal.Blue }
        $g = New-Object Windows.Controls.TextBlock; $g.Text = [string][char]$ic[0]; $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 20
        $g.Foreground = Get-Brush '#FFFFFF'; $g.HorizontalAlignment = 'Center'; $g.VerticalAlignment = 'Center'; $tile.Child = $g
        [Windows.Controls.DockPanel]::SetDock($tile, 'Left'); [void]$row.Children.Add($tile)
        # title + accent bar
        $col = New-Object Windows.Controls.StackPanel
        $tb.Margin = '0,0,0,0'; [void]$col.Children.Add($tb)
        $bar = New-Object Windows.Controls.Border; $bar.Height = 3; $bar.Width = 64; $bar.CornerRadius = 2; $bar.HorizontalAlignment = 'Left'; $bar.Margin = '1,5,0,0'
        try { $bar.Background = $win.FindResource($ic[1]) } catch { $bar.Background = Get-Brush $Pal.Blue }
        [void]$col.Children.Add($bar)
        [void]$row.Children.Add($col)
        $par.Children.Insert($at, $row)
    }
}
