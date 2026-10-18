# gui\Collect.ps1 - "Collect all children": read every plugged-in board's SD card
# over USB (tools\collect_run.py, ONE port at a time) and file ONE run's telemetry.
#
# Safety net (user, oct. 18 2026: "it might get the whole data if there is no
# safety net"): nothing is copied without a look first.
#   1. a window where YOU set the run - attack, topology, location, scenario,
#      repeat - and the time window, before anything is read
#   2. "Scan the boards" reads each card and COPIES NOTHING: one row per board -
#      the file it would take, when it ran, rows, where the card recorded it, OK
#      or why not. collect_run.py refuses to guess: two runs of the same attack +
#      topology in the window (a card has no scenario folder) = no pick; a file
#      recorded at another location = no pick unless you tick that the cards
#      kept the wrong location.txt
#   3. "Collect the ticked boards" copies EXACTLY the ticked files (--pick);
#      changing any choice above clears the scan, so what you saw is what you get.
# Opened by the Live run's "Collect all N children" and the Data page's
# "Collect all plugged-in boards". Dot-sourced by run_gui.ps1. ASCII only.

function Get-CollectPorts {
    # the run's children that are plugged in right now (the root is exported over USB)
    $R = $script:Run; if (-not $R -or -not $R.Plan) { return @() }
    return @($R.Plan.Local | Where-Object { $_.Role -ne 'root' -and $_.Port -and $script:Live.Contains([string]$_.Port) } |
             ForEach-Object { [string]$_.Port } | Select-Object -Unique)
}

function Get-AllPluggedPorts([string]$RootMac) {
    # every plugged-in board except the root (by MAC) and a recording sniffer
    $sn = @{}; try { $sn = Get-SnifferPorts } catch { }
    $rk = ($RootMac -replace '[^0-9A-Fa-f]', '').ToLower()
    return @($script:Live.Values | Where-Object { $_.Kind -eq 'BRIDGE' -and -not $sn.ContainsKey(([string]$_.Port).ToUpper()) -and
                                                 -not ($rk -and $_.Mac -and ((([string]$_.Mac) -replace '[^0-9A-Fa-f]', '').ToLower() -eq $rk)) } |
             ForEach-Object { [string]$_.Port } | Sort-Object { [int]($_ -replace '\D', '') } -Unique)
}

function Get-PresetFor([string]$A, [string]$T, [string]$L, [string]$S) {
    # the naming preset of a run (yours first, newest) -> @{ Path; RootMac; Boards }
    if (-not $script:Presets) { try { $script:Presets = Get-Presets } catch { } }
    $na = if ($A -in @('none', 'baseline')) { 'baseline' } else { $A }
    $p = @($script:Presets | Where-Object { ($(if ($_.Attack -in @('none', 'baseline')) { 'baseline' } else { $_.Attack })) -eq $na -and
                                            ($_.Topology -replace '^partial$', 'partial_mesh') -eq ($T -replace '^partial$', 'partial_mesh') -and
                                            $_.Location -eq $L -and $_.Scenario -eq $S } |
           Sort-Object @{ E = { $_.Owner -ne $script:Me } }, @{ E = { $_.Saved }; Descending = $true }) | Select-Object -First 1
    if (-not $p) { return @{ Path = ''; RootMac = ''; Boards = 0 } }
    $rb = @($p.Cfg.boards | Where-Object { $_.Role -eq 'root' -or $_.Kind -eq 'root' }) | Select-Object -First 1
    $n = 0; try { if ($p.Cfg.expectedChildren) { $n = 1 + [int]$p.Cfg.expectedChildren } } catch { }
    return @{ Path = [string]$p.Path; RootMac = $(if ($rb -and $rb.Mac) { [string]$rb.Mac } else { '' }); Boards = $n }
}

function Start-CollectChildren {
    # Live run, after Finish. $true when handled; $false = no child plugged in here (caller opens Import)
    $R = $script:Run; if (-not $R -or -not $R.Plan) { return $false }
    $ports = @(Get-CollectPorts)
    if (-not $ports.Count) { return $false }
    Show-CollectDialog -Attack ([string]$R.Plan.Attack) -Topology ([string]$R.Plan.Topology) -Location ([string]$R.Plan.Location) `
        -Scenario ([string]$R.Plan.Scenario) -Repeat ([int]$R.Settings.Repeat) -Ports $ports -RunStart $R.Started
    return $true
}

function Start-CollectFromDataPage {
    # Data page: starts from the run picked at the top (or the last used preset)
    $pk = Get-ImpPick
    $a = ''; $t = ''; $l = ''; $s = [string]$ui.ImpScenario.SelectedItem
    if ($pk) { $p = $pk -split ' / '; $a = $p[0]; $t = $p[1]; $l = $p[2] }
    else { try { $L0 = Get-LastUsedPreset; if ($L0) { $a = $L0.Attack; $t = $L0.Topology; $l = $L0.Location; $s = $L0.Scenario } } catch { } }
    $rep = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$rep)
    Show-CollectDialog -Attack $a -Topology $t -Location $l -Scenario $s -Repeat $rep -Ports @() -RunStart $null
}

function Show-CollectDialog {
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario, [int]$Repeat, [string[]]$Ports, $RunStart)
    if ($script:CollectWin -and $script:CollectWin.IsVisible) { $script:CollectWin.Activate(); return }
    $w = New-Object Windows.Window
    $w.Title = 'Collect a run from the plugged-in boards'; $w.Width = 980; $w.Height = 720; $w.WindowStartupLocation = 'CenterOwner'
    $w.Background = Get-Brush $Pal.Bg; $w.Foreground = Get-Brush $Pal.Text
    try { $w.Owner = $win } catch { }
    try { if ($win) { [void]$w.Resources.MergedDictionaries.Add($win.Resources) } } catch { }   # the GUI's dark styles
    $root = New-Object Windows.Controls.DockPanel; $root.Margin = '22,18'
    $head = New-Object Windows.Controls.StackPanel; [Windows.Controls.DockPanel]::SetDock($head, 'Top')
    [void]$head.Children.Add((New-Text 'COLLECT A RUN' 11 $Pal.Cyan 'Bold'))
    $hint = New-Text 'Pick the run, scan (copies nothing), check the rows, then collect the ticked boards. A card has no scenario folder - two runs of the same attack + topology in the time window are never guessed.' 12 $Pal.Dim
    $hint.TextWrapping = 'Wrap'; $hint.Margin = '0,4,0,12'; [void]$head.Children.Add($hint)
    # the run
    $g = New-Object Windows.Controls.WrapPanel
    $mk = { param($label, $items, $sel, $width)
        $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,0,12,8'
        [void]$sp.Children.Add((New-Text $label 10.5 $Pal.Faint 'SemiBold'))
        $cb = New-Object Windows.Controls.ComboBox; $cb.Width = $width; $cb.ItemsSource = $items; if ($sel -and $items -contains $sel) { $cb.SelectedItem = $sel }
        [void]$sp.Children.Add($cb); [void]$g.Children.Add($sp); return $cb }
    $cA = & $mk 'ATTACK' @('blackhole', 'wormhole', 'baseline') $(if ($Attack -eq 'none') { 'baseline' } else { $Attack }) 120
    $cT = & $mk 'TOPOLOGY' @('linear', 'tree', 'star', 'partial_mesh') ($Topology -replace '^partial$', 'partial_mesh') 130
    $cL = & $mk 'LOCATION' @('G402', 'DLSU_Library', 'Yuchengco', 'home') $Location 140
    $cS = & $mk 'SCENARIO' @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle') $Scenario 130
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '0,0,12,8'
    [void]$sp.Children.Add((New-Text 'REPEAT' 10.5 $Pal.Faint 'SemiBold'))
    $cR = New-Object Windows.Controls.TextBox; $cR.Width = 50; $cR.Text = [string][Math]::Max(1, $Repeat); [void]$sp.Children.Add($cR); [void]$g.Children.Add($sp)
    $winItems = @(); if ($RunStart) { $winItems += 'since this Live run started' }
    $winItems += @('in the last 3 hours', 'in the last 12 hours', 'today', 'in the last 24 hours', 'in the last 7 days')
    $cW = & $mk 'ONLY FILES THAT RAN' $winItems $(if ($RunStart) { 'since this Live run started' } else { 'in the last 12 hours' }) 200
    [void]$head.Children.Add($g)
    $other = New-Object Windows.Controls.CheckBox
    $other.Content = 'These cards may have recorded the WRONG location (location.txt left on the last site) - file such a file under the location above'
    $other.Foreground = Get-Brush $Pal.Text; $other.Margin = '0,2,0,8'; [void]$head.Children.Add($other)
    $portLine = New-Text '' 12 $Pal.Dim; $portLine.TextWrapping = 'Wrap'; [void]$head.Children.Add($portLine)
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = '0,10,0,10'
    $bScan = New-Object Windows.Controls.Button; $bScan.Content = '1   Scan the boards  (copies nothing)'; $bScan.Padding = '16,8'
    try { $bScan.Style = $win.FindResource('Cool') } catch { }
    $bGo = New-Object Windows.Controls.Button; $bGo.Content = '2   Collect the ticked boards'; $bGo.Padding = '16,8'; $bGo.Margin = '10,0,0,0'; $bGo.IsEnabled = $false
    try { $bGo.Style = $win.FindResource('Primary') } catch { }
    [void]$btns.Children.Add($bScan); [void]$btns.Children.Add($bGo)
    $status = New-Text 'Not scanned yet.' 12 $Pal.Faint; $status.Margin = '14,0,0,0'; $status.VerticalAlignment = 'Center'; [void]$btns.Children.Add($status)
    [void]$head.Children.Add($btns)
    [void]$root.Children.Add($head)
    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
    $rows = New-Object Windows.Controls.StackPanel; $sv.Content = $rows
    [void]$root.Children.Add($sv)
    $w.Content = $root
    $script:CollectWin = $w
    $script:Col = @{ A = $cA; T = $cT; L = $cL; S = $cS; R = $cR; W = $cW; Other = $other; Rows = $rows; Scan = $bScan; Go = $bGo; Status = $status
                     PortLine = $portLine; FixedPorts = @($Ports); RunStart = $RunStart; Plan = $null; Checks = @{} }
    foreach ($c in @($cA, $cT, $cL, $cS, $cW)) { $c.Add_SelectionChanged({ Clear-CollectScan }) }
    $cR.Add_TextChanged({ Clear-CollectScan }); $other.Add_Click({ Clear-CollectScan })
    $bScan.Add_Click({ Start-CollectScan })
    $bGo.Add_Click({ Start-CollectTicked })
    Clear-CollectScan
    $w.Show()
}

function Get-CollectChoice {
    # the run + ports + window as chosen in the dialog, or $null (says why)
    $C = $script:Col
    $a = [string]$C.A.SelectedItem; $t = [string]$C.T.SelectedItem; $l = [string]$C.L.SelectedItem; $s = [string]$C.S.SelectedItem
    $rep = 0; [void][int]::TryParse($C.R.Text, [ref]$rep)
    if (-not $a -or -not $t -or -not $l -or -not $s -or $rep -lt 1) { return $null }
    $pre = Get-PresetFor $a $t $l $s
    $ports = if ($C.FixedPorts.Count) { $C.FixedPorts } else { @(Get-AllPluggedPorts $pre.RootMac) }
    $since = switch ([string]$C.W.SelectedItem) {
        'since this Live run started' { $C.RunStart.AddMinutes(-15) }
        'in the last 3 hours'  { (Get-Date).AddHours(-3) }
        'in the last 12 hours' { (Get-Date).AddHours(-12) }
        'today'                { (Get-Date).Date }
        'in the last 24 hours' { (Get-Date).AddHours(-24) }
        default                { (Get-Date).AddDays(-7) }
    }
    return @{ A = $a; T = $t; L = $l; S = $s; Rep = $rep; Pre = $pre; Ports = @($ports); Since = $since.ToString('yyyy-MM-dd HH:mm'); Other = [bool]$C.Other.IsChecked }
}

function Clear-CollectScan {
    $C = $script:Col; if (-not $C) { return }
    $C.Plan = $null; $C.Checks = @{}; $C.Rows.Children.Clear(); $C.Go.IsEnabled = $false
    $ch = Get-CollectChoice
    if (-not $ch) { $C.PortLine.Text = 'Pick attack, topology, location, scenario and repeat.'; $C.Status.Text = ''; $C.Scan.IsEnabled = $false; return }
    $C.Scan.IsEnabled = [bool]$ch.Ports.Count
    $C.PortLine.Text = $(if ($ch.Ports.Count) { 'Boards to read: {0}   (one at a time; {1})' -f ($ch.Ports -join ', '), $(if ($C.FixedPorts.Count) { "this Live run's children" } else { 'every plugged-in board - root and sniffer left out' }) } else { 'No board is plugged in (root and sniffer are left out).' }) +
                         $(if ($ch.Pre.Path) { "`nNaming from preset " + (Split-Path $ch.Pre.Path -Leaf) } else { "`nNo preset for this run - files keep the card's own names" })
    $C.Status.Text = 'Not scanned yet - choices changed.'; $C.Status.Foreground = Get-Brush $Pal.Faint
}

function Get-CollectArgs($Ch) {
    $a = @('tools\collect_run.py', '--ports', ($Ch.Ports -join ','), '--attack', $(if ($Ch.A -eq 'baseline') { 'none' } else { $Ch.A }), '--topology', $Ch.T,
           '--location', $Ch.L, '--scenario', $Ch.S, '--repeat', "$($Ch.Rep)", '--since', $Ch.Since)
    if ($Ch.Other) { $a += '--allow-other-location' }
    if ($Ch.Pre.RootMac) { $a += @('--skip-mac', $Ch.Pre.RootMac) }
    if ($Ch.Pre.Path) { $a += @('--roster', $Ch.Pre.Path) }
    return $a
}

function Start-CollectScan {
    $C = $script:Col; $ch = Get-CollectChoice; if (-not $ch -or -not $ch.Ports.Count) { return }
    $py = Get-Py; if (-not $py) { return }
    if (Test-TaskBusy 'The scan') { return }
    $json = [IO.Path]::GetTempFileName()
    $a = (Get-CollectArgs $ch) + @('--dry-run', '--plan-json', $json)
    $C.Status.Text = ('Scanning {0} board(s), one at a time - do not unplug them...' -f $ch.Ports.Count); $C.Status.Foreground = Get-Brush $Pal.Amber
    $C.Scan.IsEnabled = $false
    [void](Start-StreamJob -Exe $py -ToolArgs $a -Title ("Collect - scan {0} board(s)" -f $ch.Ports.Count) -NoStop -State @{ Json = $json; Ch = $ch } -OnDone {
        param($text, $code, $st)
        $C = $script:Col; if (-not $C) { return }
        $plan = @(); try { $plan = @(Get-Content $st.Json -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ }) } catch { }
        Remove-Item $st.Json -ErrorAction SilentlyContinue
        $C.Scan.IsEnabled = $true
        Show-CollectPlan $plan $st.Ch
    })
}

function Show-CollectPlan($Plan, $Ch) {
    $C = $script:Col; $C.Plan = @{ Rows = $Plan; Ch = $Ch }; $C.Checks = @{}; $C.Rows.Children.Clear()
    $mem = @{}; try { $mem = Get-MemberInfo } catch { }
    foreach ($r in $Plan) {
        $ok = [string]$r.state -eq 'OK'
        $hex = switch ([string]$r.state) { 'OK' { $Pal.Green } 'SKIP' { $Pal.Faint } default { $Pal.Amber } }
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 10; $b.Padding = '12,8'; $b.Margin = '0,0,0,6'
        $b.Background = Get-Brush $Pal.Card; $b.BorderThickness = '3,0,0,0'; $b.BorderBrush = Get-Brush $hex
        $dp = New-Object Windows.Controls.DockPanel
        $cb = New-Object Windows.Controls.CheckBox; $cb.IsChecked = $ok; $cb.IsEnabled = $ok; $cb.VerticalAlignment = 'Top'; $cb.Margin = '0,2,10,0'
        [Windows.Controls.DockPanel]::SetDock($cb, 'Left'); [void]$dp.Children.Add($cb)
        $sp = New-Object Windows.Controls.StackPanel
        $mac = [string]$r.mac; $short = if ($mac.Length -ge 12) { ($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToUpper() } else { $mac }
        $nick = ''; if ($mac.Length -ge 12) { $k = $mem[($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToLower()]; if ($k) { $nick = '  ' + $k.Nick } }
        [void]$sp.Children.Add((New-Text ('{0}   {1}{2}   -   {3}' -f $r.port, $short, $nick, [string]$r.state) 12.5 $hex 'SemiBold'))
        if ($r.name) {
            $t = New-Text ('{0}   .   ran {1}   .   {2} rows   .   card recorded {3}' -f $r.name, $(if ($r.started) { $r.started } else { '?' }), $(if ($null -ne $r.rows) { '{0:N0}' -f [int]$r.rows } else { '?' }), $r.cell) 11.5 $Pal.Text
            $t.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t)
        }
        if ($r.why) { $t = New-Text ([string]$r.why) 11.5 $(if ($ok) { $Pal.Cyan } else { $Pal.Dim }); $t.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t) }
        [void]$dp.Children.Add($sp); $b.Child = $dp
        [void]$C.Rows.Children.Add($b)
        if ($ok) { $C.Checks[[string]$r.port] = @{ Box = $cb; Rel = [string]$r.rel } }
    }
    $n = @($Plan | Where-Object { $_.state -eq 'OK' }).Count
    $C.Go.IsEnabled = [bool]$n
    $C.Status.Text = ('{0} board(s) ready to collect, {1} not - nothing copied yet.' -f $n, (@($Plan).Count - $n)); $C.Status.Foreground = Get-Brush $(if ($n) { $Pal.Green } else { $Pal.Amber })
}

function Start-CollectTicked {
    $C = $script:Col; if (-not $C -or -not $C.Plan) { return }
    $py = Get-Py; if (-not $py) { return }
    if (Test-TaskBusy 'Collect') { return }
    $ticked = @($C.Checks.Keys | Where-Object { $C.Checks[$_].Box.IsChecked })
    if (-not $ticked.Count) { [void][Windows.MessageBox]::Show('Tick at least one board.', 'Collect'); return }
    $ch = $C.Plan.Ch
    $pick = ($ticked | ForEach-Object { '{0}={1}' -f $_, ($C.Checks[$_].Rel -replace '\\', '/') }) -join ';'
    $dirs = Get-RunDirs -Attack $(if ($ch.A -eq 'baseline') { 'none' } else { $ch.A }) -Topology ($ch.T -replace '^partial_mesh$', 'partial') -Location $ch.L -Scenario $ch.S
    $msg = "Copy {0} file(s) - exactly the ticked ones - into`n    {1}`n`nfrom: {2}`n`nDo NOT unplug a board until it says done." -f $ticked.Count, $dirs.Export, ($ticked -join ', ')
    if (-not (Confirm-Action $msg 'Collect')) { return }
    $ch2 = $ch.Clone(); $ch2.Ports = @($ticked)
    $a = (Get-CollectArgs $ch2) + @('--pick', $pick)
    $st = @{ Before = @(Get-ExportCsvSet -Base $base); Started = (Get-UnixNow); Export = $dirs.Export; Expect = $ch.Pre.Boards
             Then = @{ A = $ch.A; T = $ch.T; L = $ch.L; S = $ch.S; Text = ('{0} / {1} / {2} / {3}' -f $ch.A, $ch.T, $ch.L, $ch.S) } }
    $C.Go.IsEnabled = $false; $C.Scan.IsEnabled = $false
    $C.Status.Text = 'Collecting - do not unplug the boards...'; $C.Status.Foreground = Get-Brush $Pal.Amber
    [void](Start-StreamJob -Exe $py -ToolArgs $a -Title ("Collect {0} board(s)" -f $ticked.Count) -NoStop -State $st -OnDone {
        param($text, $code, $st)
        try { Save-ImportBatch -Base $base -Before $st.Before -Started $st.Started } catch { }
        $m = [regex]::Match($text, 'COLLECT_SUMMARY: ok=(\d+) skip=(\d+) fail=(\d+)')
        foreach ($f in @([regex]::Matches($text, '(?m)^COLLECT: (\S+) (\S+) FAIL (.+)$'))) {
            $hold = Get-PortHolderText $f.Groups[1].Value
            Write-Activity ("  {0}: {1}{2}" -f $f.Groups[1].Value, $f.Groups[3].Value.Trim(), $(if ($hold) { "   ->  $hold" } else { '' })) $Pal.Amber
        }
        # crash records fetched off the cards (tools/fetch_crashes.py via collect_run.py)
        foreach ($cm in @([regex]::Matches($text, '(?m)^\s*CRASHES: (NODE_[0-9A-Fa-f]{12}) (\d+) record\(s\) -> (.+)$'))) {
            $dec = ($cm.Groups[3].Value.Trim() -replace '\.csv$', '.decoded.txt')
            Write-Activity ("  CRASH RECORD of {0}: {1} crash(es), decoded -> {2}" -f $cm.Groups[1].Value, $cm.Groups[2].Value, $dec) $Pal.Red
            Show-Toast ("{0} crashed during this run" -f $cm.Groups[1].Value) 'Its crash record (where it crashed + memory before it) was fetched and decoded - open it.' ([string][char]0xE783) 'GradMain' { if ($script:LastCrashFile -and (Test-Path $script:LastCrashFile)) { Start-Process notepad $script:LastCrashFile } } 'Open it'
            $script:LastCrashFile = $dec
        }
        $C = $script:Col
        if ($m.Success) {
            $okN = [int]$m.Groups[1].Value; $failN = [int]$m.Groups[3].Value
            if ($C) { $C.Status.Text = "Collected $okN board(s)" + $(if ($failN) { " - $failN failed (see the activity pane)" } else { ' - the run summary opens next.' }); $C.Status.Foreground = Get-Brush $(if ($failN) { $Pal.Amber } else { $Pal.Green }) }
            Show-Toast $(if ($failN) { "Collected $okN - $failN failed" } else { "Collected $okN board(s)" }) 'The run summary opens next.' ([string][char]0xE73E) $(if ($failN) { 'GradMain' } else { 'GradGood' })
        }
        if ($C) { $C.Scan.IsEnabled = $true }
        Show-RunSummary $st.Export $st.Expect 'COLLECTED - RUN SUMMARY' $(if ($m.Success -and [int]$m.Groups[1].Value -gt 0) { $st.Then } else { $null })
        try { Update-Cells } catch { }
        try { if ($script:ImpItems.Count) { Start-ImpList -Again } } catch { }
    })
}
