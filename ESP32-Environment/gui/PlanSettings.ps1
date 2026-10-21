# gui\PlanSettings.ps1 - Campaign "Plan settings" (user, oct. 21 2026): tick / untick
# scenarios, locations, topologies and attacks to change the PLAN itself - not a view
# filter. Unticked items leave the checklist, the counts and the redo list (their
# captures become off-plan); nothing is deleted and ticking again restores the same
# slots. Saved in tools\campaign_plan.json "skip" via inventory_cells.py --set-skip
# (code area: reaches teammates with a git push, not Smart sync). Dot-sourced by
# run_gui.ps1. ASCII only.
# Oct. 21 2026: the dialog also edits the BENIGN runs (no attacker): one per
# location x topology, picked per box; "Shuffle" asks inventory_cells.py
# --draw-benign for a new draw (per topology 3 different scenarios, D-35) and
# Save writes it with --set-benign. Benign runs already captured are locked.
# Oct. 21 2026 (later): mobility + powercycle are opt-in scenarios (off by
# default, "add_scenarios" in the plan file); redesigned with the app styles,
# a live run counter and a clash check on the benign grid.

$PlanScenarioInfo = [ordered]@{
    stationary = 'Boards stay put, normal traffic'
    highload   = 'Every child probes 4x faster for the whole run'
    burst      = 'One child fires a probe burst inside the attack window'
    jitter     = 'Root adds a random extra length to the phase windows'
    mobility   = 'Manual: move the target child from spot A to spot B'
    powercycle = 'Manual: unplug the target child, wait, plug it back'
}
$PlanScenarioColor = @{ stationary = 'Blue'; highload = 'Orange'; burst = 'Pink'; jitter = 'Purple'; mobility = 'Lime'; powercycle = 'Amber' }

function Show-PlanSettings {
    $py = $script:Py; if (-not $py) { return }
    $f = Join-Path $base 'tools\campaign_plan.json'
    $j = $null; $skip = @{}
    try { $j = Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json; if ($j.skip) { foreach ($p in $j.skip.PSObject.Properties) { $skip[$p.Name] = @($p.Value) } } } catch { }
    $optional = @('mobility', 'powercycle')
    $added = @(); try { if ($j.add_scenarios) { $added = @($j.add_scenarios) } } catch { }
    $skip['scenarios'] = @($skip['scenarios']) + @($optional | Where-Object { $added -notcontains $_ })
    $groups = [ordered]@{
        scenarios  = @($PlanScenarioInfo.Keys)
        locations  = @('G402', 'DLSU_Library', 'Yuchengco')
        topologies = @('linear', 'star', 'tree', 'partial_mesh')
        attacks    = @('blackhole', 'wormhole', 'baseline')
    }
    $benign = @{}
    try { if ($j.benign) { foreach ($p in $j.benign.PSObject.Properties) { $benign[$p.Name] = [string]$p.Value } } } catch { }
    $captured = @{}
    try {
        $dj = (& $py (Join-Path $base 'tools\inventory_cells.py') --draw-benign 2>$null | Out-String) | ConvertFrom-Json
        if ($dj.captured) { foreach ($p in $dj.captured.PSObject.Properties) { $captured[$p.Name] = [string]$p.Value } }
    } catch { }

    [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Plan settings" Width="900" SizeToContent="Height" MaxHeight="900" Background="$($Pal.Bg)" Foreground="$($Pal.Text)"
        FontFamily="Segoe UI" FontSize="13" WindowStartupLocation="CenterOwner" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
$StyleXaml
    <Style x:Key="SecHead" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Text)"/><Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="SecSub" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Faint)"/><Setter Property="FontSize" Value="12"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="0,2,0,10"/></Style>
  </Window.Resources>
  <DockPanel Margin="26,22,26,18">
    <Grid DockPanel.Dock="Top" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border Width="42" Height="42" CornerRadius="12" Background="{StaticResource GradMain}" VerticalAlignment="Top">
        <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="19" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel Grid.Column="1" Margin="14,0,0,0">
        <TextBlock Text="Plan settings" FontSize="22" FontWeight="Bold" Foreground="$($Pal.Text)"/>
        <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,2,0,0"
                   Text="Choose what the campaign captures. Switching something off takes it out of the plan (checklist, tiles, counts). Nothing is deleted - switch it back on and the same runs return."/>
      </StackPanel>
      <Border Grid.Column="2" CornerRadius="12" Background="$($Pal.Card)" BorderBrush="$($Pal.Line)" BorderThickness="1" Padding="16,8" Margin="16,0,0,0" VerticalAlignment="Top">
        <StackPanel HorizontalAlignment="Center">
          <TextBlock x:Name="PsTotal" FontSize="26" FontWeight="Bold" Foreground="$($Pal.Cyan)" HorizontalAlignment="Center"/>
          <TextBlock x:Name="PsSplit" FontSize="11" Foreground="$($Pal.Dim)" HorizontalAlignment="Center"/>
          <TextBlock x:Name="PsDelta" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Center"/>
        </StackPanel>
      </Border>
    </Grid>
    <Grid DockPanel.Dock="Bottom" Margin="0,14,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBlock Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center" TextWrapping="Wrap"
                 Text="Saved in tools\campaign_plan.json - push it with git so teammates get the same plan."/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="PsCancel" Content="Cancel" IsCancel="True" Margin="0,0,8,0"/>
        <Button x:Name="PsSave" Content="Save plan" Style="{StaticResource Primary}" IsDefault="True" Margin="0"/>
      </StackPanel>
    </Grid>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <Border Style="{StaticResource Card}" Padding="18,14" Margin="0,0,0,12">
          <StackPanel>
            <TextBlock Text="Scenarios" Style="{StaticResource SecHead}"/>
            <TextBlock Style="{StaticResource SecSub}" Text="Each one switched on is run once per location, topology and attack. Mobility and powercycle are manual (a person does it during the run), so they start switched off."/>
            <UniformGrid x:Name="PsScen" Columns="2"/>
          </StackPanel>
        </Border>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}" Padding="18,14">
            <StackPanel><TextBlock Text="Locations" Style="{StaticResource SecHead}"/><TextBlock Style="{StaticResource SecSub}" Text="Where the boards are placed"/><StackPanel x:Name="PsLoc"/></StackPanel>
          </Border>
          <Border Grid.Column="2" Style="{StaticResource Card}" Padding="18,14">
            <StackPanel><TextBlock Text="Topologies" Style="{StaticResource SecHead}"/><TextBlock Style="{StaticResource SecSub}" Text="Shape of the mesh"/><StackPanel x:Name="PsTopo"/></StackPanel>
          </Border>
          <Border Grid.Column="4" Style="{StaticResource Card}" Padding="18,14">
            <StackPanel><TextBlock Text="Attacks" Style="{StaticResource SecHead}"/><TextBlock Style="{StaticResource SecSub}" Text="Benign = the runs with no attacker"/><StackPanel x:Name="PsAtk"/></StackPanel>
          </Border>
        </Grid>
        <Border Style="{StaticResource Card}" Padding="18,14">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="Benign runs (no attacker)" Style="{StaticResource SecHead}"/>
                <TextBlock Style="{StaticResource SecSub}" Text="One run per location and topology. Rule: inside one topology the 3 locations use 3 different scenarios. Runs already captured are locked."/>
              </StackPanel>
              <Button x:Name="PsShuffle" Grid.Column="1" Content="&#x21BB;  Shuffle" Style="{StaticResource Cool}" VerticalAlignment="Top" Margin="12,0,0,0" ToolTip="Draw a new random set (only changes the boxes; nothing is saved until Save plan)"/>
            </Grid>
            <Grid x:Name="PsBenign"/>
          </StackPanel>
        </Border>
      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $px))
    try { $dlg.Owner = $win } catch { }
    $dlg.MaxHeight = [Math]::Max(500, [Windows.SystemParameters]::WorkArea.Height - 40)   # fits laptop screens; the body scrolls
    $c = @{}; foreach ($n in 'PsTotal', 'PsSplit', 'PsDelta', 'PsScen', 'PsLoc', 'PsTopo', 'PsAtk', 'PsBenign', 'PsShuffle', 'PsSave') { $c[$n] = $dlg.FindName($n) }

    $boxes = @{}
    $label = @{ baseline = 'benign (no attacker)'; DLSU_Library = 'DLSU Library'; partial_mesh = 'partial mesh' }
    # scenario tiles: switch + name + colour dot + one-line description
    foreach ($v in $groups.scenarios) {
        $tile = New-Object Windows.Controls.Border; $tile.CornerRadius = '10'; $tile.Padding = '12,9'; $tile.Margin = '0,0,8,8'
        $tile.Background = Get-Brush $Pal.Card2; $tile.BorderBrush = Get-Brush $Pal.Line; $tile.BorderThickness = '1'
        $g = New-Object Windows.Controls.Grid
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'; [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $cb = New-Object Windows.Controls.CheckBox; $cb.VerticalAlignment = 'Center'; $cb.IsChecked = -not (@($skip['scenarios']) -contains $v)
        $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '12,0,0,0'; [Windows.Controls.Grid]::SetColumn($sp, 1)
        $nm = New-Object Windows.Controls.StackPanel; $nm.Orientation = 'Horizontal'
        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 9; $dot.Height = 9; $dot.Fill = Get-Brush $Pal[$PlanScenarioColor[$v]]; $dot.Margin = '0,0,7,0'; $dot.VerticalAlignment = 'Center'
        $t = New-Object Windows.Controls.TextBlock; $t.Text = $v; $t.FontWeight = 'SemiBold'; $t.Foreground = Get-Brush $Pal.Text
        [void]$nm.Children.Add($dot); [void]$nm.Children.Add($t)
        if ($optional -contains $v) {
            $tag = New-Object Windows.Controls.Border; $tag.CornerRadius = '6'; $tag.Padding = '6,0'; $tag.Margin = '8,0,0,0'; $tag.Background = Get-Brush $Pal.Line
            $tt = New-Object Windows.Controls.TextBlock; $tt.Text = 'manual'; $tt.FontSize = 10; $tt.Foreground = Get-Brush $Pal.Amber; $tag.Child = $tt
            [void]$nm.Children.Add($tag)
        }
        $d = New-Object Windows.Controls.TextBlock; $d.Text = $PlanScenarioInfo[$v]; $d.FontSize = 11; $d.Foreground = Get-Brush $Pal.Faint; $d.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($nm); [void]$sp.Children.Add($d)
        [void]$g.Children.Add($cb); [void]$g.Children.Add($sp); $tile.Child = $g
        [void]$c['PsScen'].Children.Add($tile); $boxes["scenarios|$v"] = $cb
    }
    foreach ($pair in @(@('locations', 'PsLoc'), @('topologies', 'PsTopo'), @('attacks', 'PsAtk'))) {
        foreach ($v in $groups[$pair[0]]) {
            $cb = New-Object Windows.Controls.CheckBox; $cb.Margin = '0,4,0,6'
            $t = New-Object Windows.Controls.TextBlock; $t.Text = $(if ($label[$v]) { $label[$v] } else { $v }); $cb.Content = $t
            $cb.IsChecked = -not (@($skip[$pair[0]]) -contains $v)
            [void]$c[$pair[1]].Children.Add($cb); $boxes["$($pair[0])|$v"] = $cb
        }
    }

    # benign grid: header row + one row per topology + a status column
    $locs = $groups.locations; $topos = $groups.topologies; $grid = $c['PsBenign']
    $cw = New-Object Windows.Controls.ColumnDefinition; $cw.Width = '120'; [void]$grid.ColumnDefinitions.Add($cw)
    foreach ($l in $locs) { [void]$grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
    $cs = New-Object Windows.Controls.ColumnDefinition; $cs.Width = '150'; [void]$grid.ColumnDefinitions.Add($cs)
    for ($r = 0; $r -le $topos.Count; $r++) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = 'Auto'; [void]$grid.RowDefinitions.Add($rd) }
    for ($i = 0; $i -lt $locs.Count; $i++) {
        $h = New-Object Windows.Controls.TextBlock; $h.Text = $(if ($label[$locs[$i]]) { $label[$locs[$i]] } else { $locs[$i] }).ToUpper()
        $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Foreground = Get-Brush $Pal.Faint; $h.Margin = '6,0,6,4'
        [Windows.Controls.Grid]::SetColumn($h, $i + 1); [void]$grid.Children.Add($h)
    }
    $combos = @{}; $status = @{}
    for ($r = 0; $r -lt $topos.Count; $r++) {
        $t = New-Object Windows.Controls.TextBlock; $t.Text = $(if ($label[$topos[$r]]) { $label[$topos[$r]] } else { $topos[$r] }); $t.Foreground = Get-Brush $Pal.Text; $t.FontWeight = 'SemiBold'; $t.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetRow($t, $r + 1); [void]$grid.Children.Add($t)
        for ($i = 0; $i -lt $locs.Count; $i++) {
            $k = "$($locs[$i])/$($topos[$r])"
            $cb = New-Object Windows.Controls.ComboBox; $cb.Margin = '6,3,6,3'
            foreach ($v in $groups.scenarios) { [void]$cb.Items.Add($v) }
            $cb.SelectedItem = $benign[$k]
            if ($captured.ContainsKey($k)) { $cb.SelectedItem = $captured[$k]; $cb.IsEnabled = $false; $cb.ToolTip = 'Already captured - locked' }
            [Windows.Controls.Grid]::SetColumn($cb, $i + 1); [Windows.Controls.Grid]::SetRow($cb, $r + 1); [void]$grid.Children.Add($cb)
            $combos[$k] = $cb
        }
        $st = New-Object Windows.Controls.TextBlock; $st.VerticalAlignment = 'Center'; $st.FontSize = 12; $st.Margin = '8,0,0,0'
        [Windows.Controls.Grid]::SetColumn($st, $locs.Count + 1); [Windows.Controls.Grid]::SetRow($st, $r + 1); [void]$grid.Children.Add($st)
        $status[$topos[$r]] = $st
    }

    # live counter + benign clash check
    $refresh = {
        $on = @{}
        foreach ($g in $groups.Keys) { $on[$g] = @($groups[$g] | Where-Object { $boxes["$g|$_"].IsChecked }) }
        $atkOn = @($on.attacks | Where-Object { $_ -ne 'baseline' })
        $attack = $on.locations.Count * $on.topologies.Count * $atkOn.Count * $on.scenarios.Count
        $ben = 0
        if ($on.attacks -contains 'baseline') {
            foreach ($l in $on.locations) { foreach ($tp in $on.topologies) { $s = $combos["$l/$tp"].SelectedItem; if ($s -and $on.scenarios -contains $s) { $ben++ } } }
        }
        $tot = $attack + $ben
        $c['PsTotal'].Text = "$tot runs"
        $c['PsSplit'].Text = "$attack attack  +  $ben benign"
        if ($null -eq $script:PsBefore) { $script:PsBefore = $tot }
        $dd = $tot - $script:PsBefore
        $c['PsDelta'].Text = $(if ($dd -gt 0) { "+$dd vs saved" } elseif ($dd -lt 0) { "$dd vs saved" } else { 'same as saved' })
        $c['PsDelta'].Foreground = Get-Brush $(if ($dd -gt 0) { $Pal.Amber } elseif ($dd -lt 0) { $Pal.Green } else { $Pal.Faint })
        foreach ($tp in $topos) {
            $v = @($locs | ForEach-Object { $combos["$_/$tp"].SelectedItem } | Where-Object { $_ })
            $off = @($v | Where-Object { $on.scenarios -notcontains $_ })
            $st = $status[$tp]
            if (@($v | Select-Object -Unique).Count -lt $v.Count) { $st.Text = [char]0x26A0 + ' same scenario twice'; $st.Foreground = Get-Brush $Pal.Amber }
            elseif ($off) { $st.Text = [char]0x26A0 + " $($off[0]) is off"; $st.Foreground = Get-Brush $Pal.Faint }
            else { $st.Text = [char]0x2713 + ' all different'; $st.Foreground = Get-Brush $Pal.Green }
        }
    }
    $script:PsBefore = $null
    & $refresh
    foreach ($b in $boxes.Values) { $b.Add_Click({ & $refresh }) }
    foreach ($b in $combos.Values) { $b.Add_SelectionChanged({ & $refresh }) }
    $c['PsShuffle'].Add_Click({
        try {
            $d = (& $py (Join-Path $base 'tools\inventory_cells.py') --draw-benign 2>$null | Out-String) | ConvertFrom-Json
            foreach ($p in $d.benign.PSObject.Properties) { if ($combos[$p.Name] -and $combos[$p.Name].IsEnabled) { $combos[$p.Name].SelectedItem = [string]$p.Value } }
        } catch { Show-Toast 'Shuffle failed' $_.Exception.Message ([string][char]0xE783) 'GradMain' }
    })
    $c['PsSave'].Add_Click({
        foreach ($g in $groups.Keys) {
            if ($g -ne 'attacks' -and -not @($groups[$g] | Where-Object { $boxes["$g|$_"].IsChecked }).Count) {
                Show-Toast 'Not saved' "Keep at least one of the $g switched on" ([string][char]0xE783) 'GradMain'; return
            }
        }
        $dlg.DialogResult = $true
    })
    if (-not $dlg.ShowDialog()) { return }

    $new = [ordered]@{}
    foreach ($g in $groups.Keys) { $new[$g] = @($groups[$g] | Where-Object { -not $boxes["$g|$_"].IsChecked }) }
    # PowerShell 5.1 strips bare double quotes from native-exe arguments - escape them
    $arg = ($new | ConvertTo-Json -Compress -Depth 3) -replace '"', '\"'
    $out = & $py (Join-Path $base 'tools\inventory_cells.py') --set-skip $arg 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Show-Toast 'Plan not saved' (($out -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)) ([string][char]0xE783) 'GradMain'; return }
    # benign: only send the boxes that changed, so an untouched plan stays byte-identical
    $bmap = [ordered]@{}
    foreach ($k in $combos.Keys) { $s = [string]$combos[$k].SelectedItem; if ($s -and $s -ne $benign[$k]) { $bmap[$k] = $s } }
    if ($bmap.Count) {
        $barg = ($bmap | ConvertTo-Json -Compress) -replace '"', '\"'
        $bout = & $py (Join-Path $base 'tools\inventory_cells.py') --set-benign $barg 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Show-Toast 'Benign runs not saved' (($bout -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)) ([string][char]0xE783) 'GradMain'; return }
        $out = $out.Trim() + "; benign: $($bmap.Count) changed"
    }
    Write-Activity ("Plan settings: " + $out.Trim()) $Pal.Cyan
    Show-Toast 'Plan saved' ($out.Trim() + ' - push tools\campaign_plan.json to share it') ([string][char]0xE73E) 'GradGood'
    Update-Home
}
