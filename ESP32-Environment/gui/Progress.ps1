# gui\Progress.ps1 - one progress bar for everything that makes you wait (oct. 19 2026,
# user: "a loading / progress bar when exporting, in analysis and anything that
# requires waiting"). It sits in the status bar at the bottom of the window, so it is
# visible on every page, and reads only the output the task already prints:
#   PROGRESS: <pct> <bytes> <total> <rows>   export_logs.py / import_sdcard.py (a real %
#                                             of the file, with time left) - these lines
#                                             are hidden from the activity pane
#   -- COM9: reading the card ...             collect_run.py: board k of N
#   COPY <file>                               import_sdcard.py: file k of N
#   === a/b/c/d === , APPLYING, Running M6,   analyze.ps1 stages -> a % per run
#   [features], Running EDA, Gate 1/3 ...
#   checking i/N cells                        redo_list.py
#   anything else                             a moving bar + elapsed time
# Queues (Analyse everything new, Verify all) show run k of N on top. No timers of its
# own: the activity pane's 300 ms reader drives it. Dot-sourced by run_gui.ps1. ASCII only.

$script:ProgStages = @(
    @('APPLYING', 8, 'trimming'), @('Running M6', 15, 'preprocessing'), @('Windows per segment', 25, 'preprocessing'),
    @('[features]', 45, 'features'), @('Running EDA', 55, 'charts (EDA)'), @('EDA Summary', 70, 'charts (EDA)'),
    @('Gate 1/3', 75, 'gate 1: integrity'), @('Gate 2/3', 82, 'gate 2: topology'), @('Gate 3/3', 90, 'gate 3: attack signature'),
    @('VERDICT:', 99, 'verdict'))

function Initialize-GuiProgress {
    $env:NIS16_PROGRESS = '1'          # child tools print PROGRESS: lines (export_logs.py)
    $dock = $ui.StatusDot.Parent; if (-not ($dock -is [Windows.Controls.DockPanel])) { return }
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.Margin = '0,0,14,0'; $sp.Visibility = 'Collapsed'
    [Windows.Controls.DockPanel]::SetDock($sp, 'Right')
    $bar = New-Object Windows.Controls.ProgressBar; $bar.Width = 240; $bar.Height = 8; $bar.Minimum = 0; $bar.Maximum = 100; $bar.VerticalAlignment = 'Center'
    $bar.BorderThickness = 0; $bar.Background = Get-Brush '#2A2E48'; $bar.Foreground = Get-Brush $Pal.Cyan
    $txt = New-Object Windows.Controls.TextBlock; $txt.FontSize = 11.5; $txt.Margin = '10,0,0,0'; $txt.VerticalAlignment = 'Center'; $txt.Foreground = Get-Brush $Pal.Cyan
    [void]$sp.Children.Add($bar); [void]$sp.Children.Add($txt)
    $dock.Children.Insert(1, $sp)      # left of the "Show activity" button
    $script:Prog = @{ Panel = $sp; Bar = $bar; Text = $txt; On = $false; Start = $null; Kind = ''; N = 0; K = 0; Item = -1.0; Pct = -1.0; Stage = ''; Title = ''; Last = [datetime]::MinValue; Hide = $null }
}

function Format-Span([double]$Sec) {
    $s = [int][Math]::Max(0, $Sec); if ($s -ge 3600) { return '{0}:{1:00}:{2:00}' -f [int][Math]::Floor($s / 3600), ([int][Math]::Floor($s / 60) % 60), ($s % 60) }
    return '{0}:{1:00}' -f [int][Math]::Floor($s / 60), ($s % 60)
}

function Start-TaskProgress([string]$Title, [string[]]$ToolArgs) {
    $P = $script:Prog; if (-not $P) { return }
    if ($P.Hide) { $P.Hide.Stop(); $P.Hide = $null }
    $a = ($ToolArgs -join ' ')
    $P.Kind = if ($a -match 'collect_run\.py') { 'collect' } elseif ($a -match 'import_sdcard\.py') { 'import' } elseif ($a -match 'analyze\.ps1') { 'analyze' }
              elseif ($a -match 'redo_list\.py') { 'redo' } elseif ($a -match 'export_logs\.py|run\.ps1.*-Export') { 'export' } else { 'other' }
    $P.N = 0; $P.K = 0; $P.Item = -1.0; $P.Pct = -1.0; $P.Stage = ''
    if ($P.Kind -eq 'collect') { $i = [array]::IndexOf($ToolArgs, '--ports'); if ($i -ge 0 -and $i + 1 -lt $ToolArgs.Count) { $P.N = @($ToolArgs[$i + 1] -split ',' | Where-Object { $_ }).Count } }
    if ($P.Kind -eq 'import') { $i = [array]::IndexOf($ToolArgs, '--files'); if ($i -ge 0 -and $i + 1 -lt $ToolArgs.Count) { $P.N = @($ToolArgs[$i + 1] -split '[,;]' | Where-Object { $_ }).Count } }
    $P.Title = $Title; $P.Start = Get-Date; $P.On = $true
    $P.Bar.IsIndeterminate = $true; $P.Bar.Foreground = Get-Brush $Pal.Cyan; $P.Text.Foreground = Get-Brush $Pal.Cyan
    $P.Panel.Visibility = 'Visible'
    Show-TaskProgress
}

function Update-TaskProgress([string]$Text) {
    # $Text: new output since the last tick ('' = just refresh the clock)
    $P = $script:Prog; if (-not $P -or -not $P.On) { return }
    if ($Text) {
        foreach ($m in [regex]::Matches($Text, '(?m)^\s*PROGRESS:\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s+(\d+)')) {
            $v = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
            $P.Item = $v; $rows = $m.Groups[4].Value
            $P.Stage = $(if ($v -ge 0) { 'reading the card - {0:N0} rows' -f [int]$rows } else { '{0:N0} rows so far' -f [int]$rows })
        }
        switch ($P.Kind) {
            'collect' {
                foreach ($m in [regex]::Matches($Text, '(?m)^-- (\S+): reading the card')) { $P.K++; $P.Item = 0; $P.Stage = "board $($P.K) of $($P.N): $($m.Groups[1].Value)" }
            }
            'import' {
                foreach ($m in [regex]::Matches($Text, '(?m)^\s*COPY\s+(\S+)')) { $P.K++; $P.Item = 0; $P.Stage = "file $($P.K)$(if ($P.N) { " of $($P.N)" }): $([IO.Path]::GetFileName($m.Groups[1].Value))" }
            }
            'analyze' {
                $hm = [regex]::Match($Text, '(?m)^=== ([^=]+?) ===\s*$')
                if ($hm.Success -and $hm.Groups[1].Value.Contains('/')) { $P.Pct = 2; $P.Stage = 'starting ' + $hm.Groups[1].Value.Trim() }
                foreach ($s in $script:ProgStages) { if ($Text.Contains([string]$s[0]) -and $s[1] -gt $P.Pct) { $P.Pct = [double]$s[1]; $P.Stage = [string]$s[2] } }
            }
            'redo' {
                $ms = [regex]::Matches($Text, 'checking (\d+)/(\d+) cells')
                if ($ms.Count) { $m = $ms[$ms.Count - 1]; $P.Pct = 100.0 * [int]$m.Groups[1].Value / [Math]::Max(1, [int]$m.Groups[2].Value); $P.Stage = "run $($m.Groups[1].Value) of $($m.Groups[2].Value)" }
            }
        }
    }
    if (((Get-Date) - $P.Last).TotalMilliseconds -ge 250) { Show-TaskProgress }
}

function Get-TaskPct {
    # overall 0-100, or -1 when unknown
    $P = $script:Prog
    $item = if ($P.Item -ge 0) { $P.Item / 100.0 } else { -1 }
    switch ($P.Kind) {
        { $_ -in 'collect', 'import' } { if ($P.N -gt 0 -and $P.K -gt 0) { return 100.0 * (($P.K - 1) + [Math]::Max(0.0, [double]$item)) / $P.N }; if ($item -ge 0) { return 100 * $item }; return -1 }
        'analyze' { $pc = $P.Pct } 'redo' { $pc = $P.Pct }
        default { $pc = $(if ($item -ge 0) { 100.0 * $item } else { -1.0 }) }
    }
    # a queue (Analyse everything new): run k of N on top of this run's %
    if ($P.Kind -eq 'analyze' -and $script:AnaQueueTotal -gt 1 -and $pc -ge 0) {
        $done = $script:AnaQueueTotal - $script:AnaQueue.Count - 1
        return 100.0 * ($done + $pc / 100.0) / $script:AnaQueueTotal
    }
    return $pc
}

function Show-TaskProgress {
    $P = $script:Prog; if (-not $P -or -not $P.On) { return }
    $P.Last = Get-Date
    $el = ((Get-Date) - $P.Start).TotalSeconds
    $pct = Get-TaskPct
    $q = if ($P.Kind -eq 'analyze' -and $script:AnaQueueTotal -gt 1) { '  [run {0} of {1}]' -f ($script:AnaQueueTotal - $script:AnaQueue.Count), $script:AnaQueueTotal } else { '' }
    if ($pct -ge 0) {
        $P.Bar.IsIndeterminate = $false; $P.Bar.Value = [Math]::Min(100, $pct)
        $left = if ($pct -ge 3 -and $el -ge 4) { '  -  ~' + (Format-Span ($el * (100 - $pct) / $pct)) + ' left' } else { '' }
        $P.Text.Text = '{0:0}%  {1}{2}{3}  -  {4}' -f $pct, $(if ($P.Stage) { '- ' + $P.Stage } else { $P.Title }), $q, $left, (Format-Span $el)
    } else {
        $P.Bar.IsIndeterminate = $true
        $P.Text.Text = '{0}{1}  -  {2} elapsed' -f $(if ($P.Stage) { $P.Stage } else { $P.Title }), $q, (Format-Span $el)
    }
}

function Stop-TaskProgress([int]$Code) {
    $P = $script:Prog; if (-not $P -or -not $P.On) { return }
    $P.On = $false
    $el = ((Get-Date) - $P.Start).TotalSeconds
    $P.Bar.IsIndeterminate = $false; $P.Bar.Value = 100
    $hex = if ($Code -eq 0) { $Pal.Green } else { $Pal.Amber }
    $P.Bar.Foreground = Get-Brush $hex; $P.Text.Foreground = Get-Brush $hex
    $P.Text.Text = '{0}  {1} in {2}' -f $(if ($Code -eq 0) { [string][char]0x2714 } else { '!' }), $(if ($Code -eq 0) { 'done' } else { "ended (exit $Code)" }), (Format-Span $el)
    # fade out after 5 s unless the next task (a queue) starts first
    $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(5)
    $t.Add_Tick({ param($s, $e) $s.Stop(); if ($script:Prog -and -not $script:Prog.On) { $script:Prog.Panel.Visibility = 'Collapsed' } })
    $P.Hide = $t; $t.Start()
}

function Update-LiveExportProgress([string]$Line) {
    # the Live run's own export (run.ps1 -> export_logs.py): PROGRESS lines from the
    # run console; the bar starts on the first one and ends at 100 %
    $P = $script:Prog; if (-not $P) { return }
    if (-not $P.On) { Start-TaskProgress 'Exporting (Live run)' @('export_logs.py') }
    Update-TaskProgress $Line
    if ($Line -match 'PROGRESS:\s+100(\.0)?\s') { Show-TaskProgress; Stop-TaskProgress 0 }
}
