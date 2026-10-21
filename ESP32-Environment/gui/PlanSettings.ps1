# gui\PlanSettings.ps1 - Campaign "Plan settings" (user, oct. 21 2026): tick / untick
# scenarios, locations, topologies and attacks to change the PLAN itself - not a view
# filter. Unticked items leave the checklist, the counts and the redo list (their
# captures become off-plan); nothing is deleted and ticking again restores the same
# slots. Saved in tools\campaign_plan.json "skip" via inventory_cells.py --set-skip
# (code area: reaches teammates with a git push, not Smart sync). Dot-sourced by
# run_gui.ps1. ASCII only.

function Show-PlanSettings {
    $py = $script:Py; if (-not $py) { return }
    $f = Join-Path $base 'tools\campaign_plan.json'
    $skip = @{}
    try { $j = Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json; if ($j.skip) { foreach ($p in $j.skip.PSObject.Properties) { $skip[$p.Name] = @($p.Value) } } } catch { }
    $groups = [ordered]@{
        scenarios  = @('stationary', 'highload', 'burst', 'jitter')
        locations  = @('G402', 'DLSU_Library', 'Yuchengco')
        topologies = @('linear', 'star', 'tree', 'partial_mesh')
        attacks    = @('blackhole', 'wormhole', 'baseline')
    }
    $title = @{ scenarios = 'Scenarios'; locations = 'Locations'; topologies = 'Topologies'; attacks = 'Attacks  (baseline = the matched benign runs)' }
    $dlg = New-Object Windows.Window
    $dlg.Title = 'Plan settings'; $dlg.Width = 560; $dlg.SizeToContent = 'Height'; $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Background = Get-Brush $Pal.Card2; $dlg.ResizeMode = 'NoResize'
    try { $dlg.Owner = $win } catch { }
    $root = New-Object Windows.Controls.StackPanel; $root.Margin = '20,16,20,16'
    $head = New-Object Windows.Controls.TextBlock; $head.Text = 'What the campaign plans to capture'; $head.FontSize = 18; $head.FontWeight = 'Bold'; $head.Foreground = Get-Brush $Pal.Text
    $sub = New-Object Windows.Controls.TextBlock; $sub.TextWrapping = 'Wrap'; $sub.Foreground = Get-Brush $Pal.Dim; $sub.Margin = '0,4,0,12'
    $sub.Text = "Untick to take it OUT of the plan (checklist, Campaign tiles, counts, redo list). This is the plan itself, not a filter. Nothing is deleted - captures already made stay on disk as off-plan, and ticking again brings back the same slots.`nShared with the team when tools\campaign_plan.json is pushed (git), like code."
    [void]$root.Children.Add($head); [void]$root.Children.Add($sub)
    $boxes = @{}
    foreach ($g in $groups.Keys) {
        $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text = $title[$g]; $lbl.FontWeight = 'SemiBold'; $lbl.Foreground = Get-Brush $Pal.Text; $lbl.Margin = '0,6,0,4'
        [void]$root.Children.Add($lbl)
        $row = New-Object Windows.Controls.WrapPanel; $row.Margin = '0,0,0,6'
        foreach ($v in $groups[$g]) {
            $cb = New-Object Windows.Controls.CheckBox; $cb.Content = $v; $cb.Foreground = Get-Brush $Pal.Text; $cb.Margin = '0,0,18,4'
            $cb.IsChecked = -not (@($skip[$g]) -contains $v)
            [void]$row.Children.Add($cb); $boxes["$g|$v"] = $cb
        }
        [void]$root.Children.Add($row)
    }
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'; $btns.Margin = '0,12,0,0'
    $ok = New-Object Windows.Controls.Button; $ok.Content = 'Save plan'; $ok.Padding = '16,6'; $ok.Margin = '0,0,8,0'; $ok.IsDefault = $true
    $no = New-Object Windows.Controls.Button; $no.Content = 'Cancel'; $no.Padding = '16,6'; $no.IsCancel = $true
    [void]$btns.Children.Add($ok); [void]$btns.Children.Add($no); [void]$root.Children.Add($btns)
    $dlg.Content = $root
    $ok.Add_Click({ $dlg.DialogResult = $true })
    if (-not $dlg.ShowDialog()) { return }
    $new = [ordered]@{}
    foreach ($g in $groups.Keys) { $new[$g] = @($groups[$g] | Where-Object { -not $boxes["$g|$_"].IsChecked }) }
    # PowerShell 5.1 strips bare double quotes from native-exe arguments - escape them
    $arg = ($new | ConvertTo-Json -Compress -Depth 3) -replace '"', '\"'
    $out = & $py (Join-Path $base 'tools\inventory_cells.py') --set-skip $arg 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Show-Toast 'Plan not saved' (($out -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)) ([string][char]0xE783) 'GradMain'; return }
    Write-Activity ("Plan settings: " + $out.Trim()) $Pal.Cyan
    Show-Toast 'Plan saved' ($out.Trim() + ' - push tools\campaign_plan.json to share it') ([string][char]0xE73E) 'GradGood'
    Update-Home
}
