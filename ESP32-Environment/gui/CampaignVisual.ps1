# gui\CampaignVisual.ps1 - the Campaign "selected run" panel, made visual (oct. 19 2026,
# user: "more interactive and user-friendly, graphics / illustration, without lag").
#   1. JOURNEY   captured -> analysed -> verified -> graded, four dots on a line, each
#                green (done) / amber (look at it) / red (failed) / grey (not yet)
#   2. VERDICT   the CONFIDENCE grade as a big badge, its footnotes as a checklist, the
#                "report as" line and the at-a-glance lights per area
#   3. LAYOUT    the drawing of who sat under whom - in a collapsed expander, built only
#                when opened
# Cost per click: ONE read of the run's saved report (a ~30 KB text file the Verify page
# already wrote) + ~40 small WPF elements. No Python, no data files, no timers.
# Dot-sourced by run_gui.ps1. ASCII only.

function Get-CampReportBits([string]$Key) {
    # what the panel needs from the saved verify report, or $null
    $t = ''; try { $t = Get-AnaReport $Key } catch { }
    if (-not $t) { return $null }
    $t = $t -replace "\x1b\[[0-9;]*m", ''
    $lines = $t -split "`r?`n"
    $o = @{ Grade = ''; Say = ''; Notes = @(); ReportAs = ''; Glance = @(); Sketch = @(); Verdict = ''; Old = $false; Fails = @() }
    $sk = $false; $inConf = $false; $lastKind = ''   # which item a wrapped line continues
    foreach ($ln in $lines) {
        $tr = $ln.Trim()
        if ($sk) { if (-not $tr) { $sk = $false } else { $o.Sketch += $(if ($ln.Length -gt 7) { $ln.Substring(7) } else { $tr }) }; continue }
        if ($tr -match '^VERDICT\s*:\s*(.+)$') { $o.Verdict = $Matches[1]; continue }
        if ($tr -match '^CONFIDENCE\s*:\s*(\S+)\s*-?\s*(.*)$') { $o.Grade = $Matches[1]; $o.Say = $Matches[2]; $inConf = $true; continue }
        if ($inConf) {
            if ($tr -match '^-{20,}' -or -not $tr) { $inConf = $false; continue }
            if ($tr -match '^~\s+(.+)$') { $o.Notes += $Matches[1]; $lastKind = 'n' }
            elseif ($tr -match '^x\s+(.+)$') { $o.Fails += $Matches[1]; $lastKind = 'f' }
            elseif ($tr -match '^=\s+REPORT AS:\s*(.+)$') { $o.ReportAs = $Matches[1]; $lastKind = 'r' }
            elseif ($tr -match '^\+\s') { $lastKind = '' }
            elseif ($ln -match '^\s{7,}\S') {
                switch ($lastKind) { 'n' { $o.Notes[-1] += ' ' + $tr } 'f' { $o.Fails[-1] += ' ' + $tr } 'r' { $o.ReportAs += ' ' + $tr } }
            }
            continue
        }
        if ($tr -match '^AT A GLANCE:\s+(.+)$') { $o.Glance = @([regex]::Matches($Matches[1], '([A-Z][A-Z-]+) \[\s*(OK|WARN|FAIL|--)\s*\]') | ForEach-Object { , @($_.Groups[1].Value, $_.Groups[2].Value) }); continue }
        if ($tr -match '^LAYOUT AT THE START') { $sk = $true; continue }
    }
    $o.Old = [bool]($o.Verdict -and -not $o.Grade)
    return $o
}

function New-CampPill([string]$Text, [string]$Fg, [string]$Bg, [double]$Size = 11.5) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 9; $b.Padding = '9,3'; $b.Margin = '0,0,6,5'; $b.Background = Get-Brush $Bg
    $t = New-Text $Text $Size $Fg 'SemiBold'; $b.Child = $t
    return $b
}

function Add-CampJourney($Body, $Steps) {
    # $Steps: @( @(label, state, detail) ) - state ok | warn | bad | todo | na
    # one column per step; each column draws the left / right half of the line that
    # joins its dot to its neighbours, so the line runs dot to dot at any width
    $g = New-Object Windows.Controls.Grid; $g.Margin = '0,2,0,12'
    for ($i = 0; $i -lt $Steps.Count; $i++) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength 1, 'Star'; [void]$g.ColumnDefinitions.Add($cd) }
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $st = $Steps[$i]
        $hex = switch ($st[1]) { 'ok' { $Pal.Green } 'warn' { $Pal.Amber } 'bad' { $Pal.Red } default { '#4B5075' } }
        $glyph = switch ($st[1]) { 'ok' { [string][char]0x2714 } 'warn' { '!' } 'bad' { [string][char]0x2716 } 'na' { '-' } default { [string]($i + 1) } }
        $cell = New-Object Windows.Controls.Grid
        $halves = New-Object Windows.Controls.Grid; $halves.VerticalAlignment = 'Top'; $halves.Margin = '0,12,0,0'
        foreach ($k in 0, 1) { [void]$halves.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)) }
        if ($i -gt 0) {
            $l = New-Object Windows.Controls.Border; $l.Height = 3
            $l.Background = Get-Brush $(if ($Steps[$i - 1][1] -eq 'ok' -and $st[1] -in @('ok', 'warn', 'bad')) { $Pal.Green } else { '#2F3352' })
            [Windows.Controls.Grid]::SetColumn($l, 0); [void]$halves.Children.Add($l)
        }
        if ($i -lt $Steps.Count - 1) {
            $r = New-Object Windows.Controls.Border; $r.Height = 3
            $r.Background = Get-Brush $(if ($st[1] -eq 'ok' -and $Steps[$i + 1][1] -in @('ok', 'warn', 'bad')) { $Pal.Green } else { '#2F3352' })
            [Windows.Controls.Grid]::SetColumn($r, 1); [void]$halves.Children.Add($r)
        }
        [void]$cell.Children.Add($halves)
        $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
        $dot = New-Object Windows.Controls.Border; $dot.Width = 26; $dot.Height = 26; $dot.CornerRadius = 13; $dot.HorizontalAlignment = 'Center'
        $dot.Background = Get-Brush $(if ($st[1] -in @('todo', 'na')) { $Pal.Card } else { $hex }); $dot.BorderBrush = Get-Brush $hex; $dot.BorderThickness = 2
        $dt = New-Text $glyph 12 $(if ($st[1] -in @('todo', 'na')) { $hex } else { '#0B1020' }) 'Bold'; $dt.HorizontalAlignment = 'Center'; $dt.VerticalAlignment = 'Center'; $dot.Child = $dt
        [void]$sp.Children.Add($dot)
        $lb = New-Text $st[0] 11 $(if ($st[1] -in @('todo', 'na')) { $Pal.Faint } else { $Pal.Text }) 'SemiBold'; $lb.HorizontalAlignment = 'Center'; $lb.Margin = '0,4,0,0'; [void]$sp.Children.Add($lb)
        if ($st[2]) { $dl = New-Text $st[2] 10 $hex; $dl.HorizontalAlignment = 'Center'; $dl.TextAlignment = 'Center'; $dl.TextWrapping = 'Wrap'; $dl.MaxWidth = 120; [void]$sp.Children.Add($dl) }
        [void]$cell.Children.Add($sp)
        [Windows.Controls.Grid]::SetColumn($cell, $i); [void]$g.Children.Add($cell)
    }
    [void]$Body.Children.Add($g)
}

function Add-CampVisual($Body, $S, [string]$Look) {
    $isBase = ($S.kind -eq 'benign' -or $S.attack -in @('none', 'baseline'))
    $key = Get-SlotKeyPath $S                                    # gui\CampaignPanel.ps1
    $rep = if ($Look -in @('todo', 'partial')) { $null } else { Get-CampReportBits $key }
    $v = $null; try { $v = $script:Verdicts[$key] } catch { }
    $hasAna = $false; try { $hasAna = [bool](Find-AnalysedCell $S) } catch { }

    # 1. JOURNEY
    $cap = switch ($Look) { 'todo' { @('todo', 'not yet') } 'partial' { @('warn', 'incomplete') } default { @('ok', $(if ($S.last) { (([string]$S.last -split ' ') | Select-Object -First 2) -join ' ' } else { '' })) } }
    $ana = if ($Look -eq 'todo') { @('todo', '') } elseif ($Look -eq 'analyse' -or -not $hasAna) { @('warn', 'press Analyse') } else { @('ok', '') }
    if ($isBase) { $ver = @('na', 'baseline run'); $grd = @('na', '') }
    else {
        $ver = if ($Look -in @('todo', 'partial')) { @('todo', '') }
               elseif (-not $rep -and -not $v) { @('todo', $(if ($hasAna) { 'press Verify' } else { '' })) }
               elseif ($rep -and $rep.Verdict -match 'SETUP INVALID') { @('bad', 'setup invalid') }
               elseif ($rep -and $rep.Verdict -match 'NOT CONFIRMED|INCONCLUSIVE') { @('bad', 'not confirmed') }
               elseif ($rep -and $rep.Verdict -match 'CONFIRMED') { @('ok', 'confirmed') }
               elseif ($v -and $v.Code -eq 0) { @('ok', 'confirmed') } elseif ($v) { @('bad', 'not confirmed') } else { @('todo', '') }
        $grd = if (-not $rep) { @('todo', '') }
               elseif ($rep.Old) { @('warn', 'old report - press Verify') }
               else { switch ($rep.Grade) { 'STRONG' { @('ok', 'strong') } 'SOUND' { @('ok', 'sound') } 'QUALIFIED' { @('warn', "$($rep.Notes.Count) footnote(s)") } '-' { @('bad', 'not confirmed') } default { @('todo', '') } } }
    }
    Add-CampJourney $Body @(@('Captured', $cap[0], $cap[1]), @('Analysed', $ana[0], $ana[1]), @('Verified', $ver[0], $ver[1]), @('Graded', $grd[0], $grd[1]))
    if ($isBase -or -not $rep) { return }

    # 2. VERDICT tile
    $tone = switch ($rep.Grade) { 'STRONG' { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A' } } 'SOUND' { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A' } } 'QUALIFIED' { @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320' } } default { @{ Fg = $Pal.Red; Bg = '#33192A'; Bd = '#6B2A3F' } } }
    if ($rep.Old) { $tone = @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320' } }
    $tile = New-Object Windows.Controls.Border; $tile.CornerRadius = 12; $tile.Padding = '14,10'; $tile.Margin = '0,0,0,10'
    $tile.Background = Get-Brush $tone.Bg; $tile.BorderBrush = Get-Brush $tone.Bd; $tile.BorderThickness = 1
    $tp = New-Object Windows.Controls.StackPanel
    $hd = New-Object Windows.Controls.DockPanel
    $big = New-Text $(if ($rep.Old) { 'OLD REPORT' } elseif ($rep.Grade -eq '-') { 'NOT CONFIRMED' } else { [string]$rep.Grade }) 20 $tone.Fg 'Bold'
    [Windows.Controls.DockPanel]::SetDock($big, 'Left'); [void]$hd.Children.Add($big)
    $sub = New-Text $(if ($rep.Old) { 'made by an older verifier - press Verify to update' } else { [string]$rep.Say }) 11.5 $Pal.Dim
    $sub.TextWrapping = 'Wrap'; $sub.Margin = '12,6,0,0'; [void]$hd.Children.Add($sub)
    [void]$tp.Children.Add($hd)
    foreach ($n in @($rep.Notes | Select-Object -First 6)) {
        $r = New-Text ([string][char]0x26A0 + '  ' + $n) 12 $Pal.Amber; $r.TextWrapping = 'Wrap'; $r.Margin = '0,4,0,0'; [void]$tp.Children.Add($r)
    }
    foreach ($f in @($rep.Fails | Select-Object -First 3)) {
        $r = New-Text ([string][char]0x2716 + '  ' + $f) 12 $Pal.Red; $r.TextWrapping = 'Wrap'; $r.Margin = '0,4,0,0'; [void]$tp.Children.Add($r)
    }
    if ($rep.ReportAs) { $ra = New-Text ('report as  ' + $rep.ReportAs) 12 $Pal.Cyan 'SemiBold'; $ra.TextWrapping = 'Wrap'; $ra.Margin = '0,8,0,0'; [void]$tp.Children.Add($ra) }
    if ($rep.Glance.Count) {
        $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,8,0,0'
        foreach ($gl in $rep.Glance) {
            $c = switch ($gl[1]) { 'FAIL' { @($Pal.Red, '#3A1E2C', [char]0x2716) } 'WARN' { @($Pal.Amber, '#3A2E14', [char]0x26A0) } 'OK' { @($Pal.Green, '#1F4D3E', [char]0x2714) } default { @($Pal.Dim, '#2A2E48', [char]0x2026) } }
            [void]$wp.Children.Add((New-CampPill ('{0} {1}' -f [string]$c[2], $gl[0]) $c[0] $c[1] 10.5))
        }
        [void]$tp.Children.Add($wp)
    }
    $tile.Child = $tp; [void]$Body.Children.Add($tile)

    # 3. LAYOUT - built only when the expander opens
    if ($rep.Sketch.Count) {
        $ex = New-Object Windows.Controls.Expander; $ex.Margin = '0,0,0,10'; $ex.IsExpanded = $false
        $ex.Header = (New-Text 'Show the layout during the attack (who sat under whom)' 11.5 $Pal.Cyan 'SemiBold')
        $ex.Tag = @($rep.Sketch)
        $ex.Add_Expanded({
            param($sender, $e)
            if ($sender.Content) { return }
            $box = New-Object Windows.Controls.Border; $box.CornerRadius = 8; $box.Padding = '10,8'; $box.Margin = '0,6,0,0'; $box.Background = Get-Brush $Pal.Bg
            $tb = New-Object Windows.Controls.TextBlock; $tb.FontFamily = 'Cascadia Mono, Consolas'; $tb.FontSize = 11.5
            foreach ($sl in @($sender.Tag)) {
                $sl = [string]$sl
                $hex = if ($sl -match 'NOT ALLOWED') { $Pal.Red } elseif ($sl -match 'ATTACKER|WORMHOLE') { $Pal.Pink } elseif ($sl -match 'VICTIM') { '#FCA5A5' } elseif ($sl -match 'ROOT') { $Pal.Amber } elseif ($sl -match '^[x?]') { $Pal.Faint } else { $Pal.Cyan }
                $parts = $sl -split '   \* ', 2
                $r1 = New-Object Windows.Documents.Run ($parts[0]); $r1.Foreground = Get-Brush $hex; [void]$tb.Inlines.Add($r1)
                if ($parts.Count -gt 1) { $r2 = New-Object Windows.Documents.Run ('   * ' + $parts[1]); $r2.Foreground = Get-Brush $Pal.Amber; [void]$tb.Inlines.Add($r2) }
                [void]$tb.Inlines.Add((New-Object Windows.Documents.LineBreak))
            }
            $sv = New-Object Windows.Controls.ScrollViewer; $sv.HorizontalScrollBarVisibility = 'Auto'; $sv.VerticalScrollBarVisibility = 'Disabled'; $sv.Content = $tb
            $box.Child = $sv; $sender.Content = $box
        })
        [void]$Body.Children.Add($ex)
    }
}
