# gui\RunSummary.ps1 - the per-run health card (tools\run_summary.py) in a
# small window: rows per phase per board, roles, one schedule, missing boards.
# Shown by itself after an Import (Data page) and after Collect all children.
# Dot-sourced by run_gui.ps1. ASCII only.

function Show-RunSummary([string]$Folder, [int]$Expect = 0, [string]$Title = '') {
    if (-not $script:Py -or -not $Folder -or -not (Test-Path $Folder)) { return }
    $json = [IO.Path]::GetTempFileName()
    $a = @('tools\run_summary.py', $Folder, '--json', $json)
    if ($Expect -gt 0) { $a += @('--expect', "$Expect") }
    Start-ToolJob -Exe $script:Py -ToolArgs $a -State @{ Json = $json; Title = $Title; Folder = $Folder } -OnDone {
        param($text, $code, $st)
        $s = $null
        try { $s = Get-Content $st.Json -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        Remove-Item $st.Json -ErrorAction SilentlyContinue
        if (-not $s) { Set-Status ('Run summary failed: ' + (($text -split "`n" | Where-Object { $_ } | Select-Object -Last 1))) $Pal.Red; return }
        Show-RunSummaryWindow $s $st.Title
    }
}

function Get-RunSummaryRows($S) {
    $atk = @{ blackhole = '1'; wormhole = '2' }[[string]$S.attack]
    foreach ($b in @($S.boards)) {
        $ph = $b.phases
        $roles = $b.roles
        $role = @(@($roles.'0') + @($roles.$atk) + @($roles.'255') | Where-Object { $_ })[0]
        $attack = if ($atk) { [int]$ph.$atk } else { [int]$ph.'1' + [int]$ph.'2' }
        $mac = ([string]$b.node -replace '[^0-9A-Fa-f]', '')
        [pscustomobject]@{
            Board = $(if ($mac.Length -ge 12) { ($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToUpper() } else { $b.node })
            Role = [string]$role; Rows = [int]$b.rows; Stab = [int]$ph.'255'; Base = [int]$ph.'0'; Attack = $attack; Cool = [int]$ph.'3'
            Secs = [int]$b.seconds; Missing = @($b.missing) -join ', '
        }
    }
}

function Show-RunSummaryWindow($S, [string]$Title = '') {
    $w = New-Object Windows.Window
    $w.Title = 'Run summary'
    $w.Width = 820; $w.SizeToContent = 'Height'; $w.MaxHeight = 720
    $w.Background = Get-Brush $Pal.Bg; $w.WindowStartupLocation = 'CenterOwner'
    try { $w.Owner = $win } catch { }
    $sv = New-Object Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = '20,16,20,18'
    $parts = ([string]$S.folder -replace '/', '\') -split '\\'
    $cell = ($parts | Select-Object -Last 4) -join '  /  '
    [void]$sp.Children.Add((New-Text $(if ($Title) { $Title } else { 'RUN SUMMARY' }) 11 $Pal.Faint 'SemiBold'))
    [void]$sp.Children.Add((New-Text $cell 18 $Pal.Text 'Bold'))
    $ok = [bool]$S.complete
    $n = @($S.boards).Count
    $res = if ($ok) { "COMPLETE - all $n board(s) hold the whole run (baseline, attack, cooldown, one schedule)" }
           elseif (-not $n) { 'NO DATA - no telemetry file with rows in this folder' }
           else { "LOOK - $(@($S.issues).Count) thing(s) to check before analysing" }
    $r = New-Text $res 13 $(if ($ok) { $Pal.Green } else { $Pal.Amber }) 'SemiBold'; $r.Margin = '0,6,0,12'; $r.TextWrapping = 'Wrap'
    [void]$sp.Children.Add($r)
    # the table: a Grid, one row per board (no DataGrid - the window has no theme styles)
    $g = New-Object Windows.Controls.Grid
    $cols = @(@('Board', 70), @('Role', 110), @('Rows', 70), @('Stabilise', 70), @('Baseline', 70), @('Attack', 70), @('Cooldown', 70), @('Secs', 50), @('Status', 180))
    foreach ($c in $cols) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength $c[1]; [void]$g.ColumnDefinitions.Add($cd) }
    $rows = @(Get-RunSummaryRows $S)
    for ($i = 0; $i -le $rows.Count; $i++) {
        $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = 'Auto'; [void]$g.RowDefinitions.Add($rd)
        for ($j = 0; $j -lt $cols.Count; $j++) {
            if ($i -eq 0) { $t = New-Text $cols[$j][0] 10.5 $Pal.Faint 'SemiBold' }
            else {
                $x = $rows[$i - 1]
                $flag = @($S.issues | Where-Object { ([string]$_).StartsWith($x.Board + ':') }).Count
                $v = switch ($j) { 0 { $x.Board } 1 { $x.Role } 2 { '{0:N0}' -f $x.Rows } 3 { '{0:N0}' -f $x.Stab } 4 { '{0:N0}' -f $x.Base }
                                   5 { '{0:N0}' -f $x.Attack } 6 { '{0:N0}' -f $x.Cool } 7 { $x.Secs } 8 { if ($x.Missing) { 'missing ' + $x.Missing } elseif ($flag) { 'look (see below)' } else { 'OK' } } }
                $hex = if ($j -eq 8) { if ($x.Missing -or $flag) { $Pal.Amber } else { $Pal.Green } } elseif ($j -eq 0) { $Pal.Blue } else { $Pal.Text }
                $t = New-Text ([string]$v) 12 $hex $(if ($j -eq 0) { 'Bold' } else { 'Normal' })
            }
            $t.Margin = '0,3,8,3'; $t.TextWrapping = 'Wrap'
            [Windows.Controls.Grid]::SetRow($t, $i); [Windows.Controls.Grid]::SetColumn($t, $j); [void]$g.Children.Add($t)
        }
    }
    $card = New-Object Windows.Controls.Border; $card.Background = Get-Brush $Pal.Card; $card.CornerRadius = 10; $card.Padding = '14,10'; $card.Child = $g
    [void]$sp.Children.Add($card)
    if (@($S.issues).Count) {
        $h = New-Text 'TO CHECK' 10.5 $Pal.Faint 'SemiBold'; $h.Margin = '0,14,0,4'; [void]$sp.Children.Add($h)
        foreach ($is in @($S.issues)) { $t = New-Text ('-  ' + $is) 12 $Pal.Amber; $t.TextWrapping = 'Wrap'; $t.Margin = '0,2,0,2'; [void]$sp.Children.Add($t) }
    }
    $note = New-Text 'Rows at 10 Hz: 1,800 attack rows = 180 s. Stabilise (phase 255) differs per board - each logs it from the root''s PREPARE until START.' 11 $Pal.Faint
    $note.TextWrapping = 'Wrap'; $note.Margin = '0,12,0,0'; [void]$sp.Children.Add($note)
    $sv.Content = $sp; $w.Content = $sv
    $w.Show()
}
