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
    return (ConvertFrom-ReportText $t)
}

function ConvertFrom-ReportText([string]$Text) {
    # one parser for a verify report (attack or benign) - the Campaign panel and the Verify page
    $t = $Text -replace "\x1b\[[0-9;]*m", ''
    $lines = $t -split "`r?`n"
    $o = @{ Grade = ''; Say = ''; Notes = @(); ReportAs = ''; Glance = @(); Sketch = @(); Verdict = ''; Old = $false; Fails = @(); Nodes = @(); Proof = ''; Sig = @(); Benign = $false; Facts = @{} }
    $sk = $false; $inConf = $false; $lastKind = ''; $sec = ''   # which item a wrapped line continues
    foreach ($ln in $lines) {
        $tr = $ln.Trim()
        if ($ln -match '^\s*\[(\d)\]\s') { $sec = $Matches[1]; continue }
        if ($tr -match '^BENIGN VERIFICATION') { $o.Benign = $true; continue }
        if ($sec -eq '1') {
            # [1] ATTACK SIGNATURE / NO-ATTACK TEST rows: result, feature, normal, attack, z, role, [study]
            $parts = @($tr -split '\s{2,}'); $an = ''
            if ($parts.Count -ge 2 -and $parts[0] -in @('blackhole', 'wormhole')) { $an = $parts[0]; $parts = @($parts | Select-Object -Skip 1) }
            if ($parts.Count -ge 6 -and $parts[0] -match '^(PASS|FAIL|EXCLUDED|NO DATA|INVALID-BASE|N/A|INCONCL\S*|INFEASIBLE|SKIP|WARN|NOT TESTED)$') {
                $o.Sig += , @{ Res = $parts[0]; Feat = $parts[1]; Norm = $parts[2]; Atk = $parts[3]; Z = $parts[4]; Role = $parts[5]; Tag = $(if ($parts.Count -ge 7) { $parts[6] } else { '' }); For = $an }
            }
            continue
        }
        if ($sec -eq '3' -and $tr -match '^(OK|WARN|FAIL)\s+(.+)$') {
            # the numbers the plain-words card quotes
            $ft = $Matches[2]
            if ($ft -match 'attacker (\w{4}) received (\d+), forwarded (\d+) \((\d+)%\)') { $o.Facts.AtkId = $Matches[1]; $o.Facts.AtkRecv = $Matches[2]; $o.Facts.AtkFwd = $Matches[3]; $o.Facts.AtkPct = $Matches[4] }
            elseif ($ft -match '(\d+) victim\(s\) alive but cut off: attack PDR ([\d.]+) \(baseline ([\d.]+)\)') { $o.Facts.VicN = $Matches[1]; $o.Facts.VicPdr = $Matches[2]; $o.Facts.VicBase = $Matches[3] }
            elseif ($ft -match '(\d+) node\(s\) not behind the attacker kept delivering') { $o.Facts.ByN = $Matches[1] }
            elseif ($ft -match 'B sent ~(\d+) tunnel frames, A received ~(\d+)') { $o.Facts.TunSent = $Matches[1]; $o.Facts.TunGot = $Matches[2] }
            elseif ($ft -match 'duplicate arrivals in (\d+) attack window') { $o.Facts.DupWin = $Matches[1] }
            elseif ($ft -match '^ROBUST:') { $o.Facts.Robust = $true }
        }
        if ($sk) { if (-not $tr) { $sk = $false } else { $o.Sketch += $(if ($ln.Length -gt 7) { $ln.Substring(7) } else { $tr }) }; continue }
        if ($tr -match '^VERDICT\s*:\s*(.+)$') { $o.Verdict = $Matches[1]; continue }
        if ($tr -match '^CONFIDENCE\s*:\s*(STRONG|GOOD|MINOR GAPS|MAJOR GAPS|FAILED|NOT CONFIRMED)\s*-?\s*(.*)$') { $o.Grade = $(if ($Matches[1] -eq 'NOT CONFIRMED') { 'FAILED' } else { $Matches[1] }); $o.Say = $Matches[2]; $inConf = $true; continue }
        # a report from before the final grades (oct. 19 2026) - shown as an OLD report
        if ($tr -match '^CONFIDENCE\s*:\s*(SOUND|WITH NOTES|QUALIFIED|-)\s*-?\s*(.*)$') { $o.Grade = $Matches[1]; $o.Say = $Matches[2]; $o.Old = $true; $inConf = $true; continue }
        if ($inConf) {
            if ($tr -match '^-{20,}' -or -not $tr) { $inConf = $false; continue }
            if ($tr -match '^~\s+(.+)$') { $o.Notes += $Matches[1]; $lastKind = 'n' }
            elseif ($tr -match '^x\s+(.+)$') { $o.Fails += $Matches[1]; $lastKind = 'f' }
            elseif ($tr -match '^=\s+REPORT AS:\s*(.+)$') { $o.ReportAs = $Matches[1]; $lastKind = 'r' }
            elseif ($tr -match '^\+\s+impact check:\s*(.+)$') { $o.Proof = $Matches[1]; $lastKind = 'p' }
            elseif ($tr -match '^\+\s') { $lastKind = '' }
            elseif ($ln -match '^\s{7,}\S') {
                switch ($lastKind) { 'n' { $o.Notes[-1] += ' ' + $tr } 'f' { $o.Fails[-1] += ' ' + $tr } 'r' { $o.ReportAs += ' ' + $tr } 'p' { $o.Proof += ' ' + $tr } }
            }
            continue
        }
        if ($tr -match '^AT A GLANCE:\s+(.+)$') { $o.Glance = @([regex]::Matches($Matches[1], '([A-Z][A-Z-]+) \[\s*(OK|WARN|FAIL|--)\s*\]') | ForEach-Object { , @($_.Groups[1].Value, $_.Groups[2].Value) }); continue }
        if ($tr -match '^LAYOUT AT THE START') { $sk = $true; continue }
        if ($tr -match '^(NODE_[0-9A-Fa-f]{12})\s+(\S+)\s+(.+?)\s{2,}(\S+)\s+(\S+)\s+(\S+)\s+(\d+)$') {
            $o.Nodes += @{ Node = $Matches[1]; Exp = $Matches[3]; Hop = $Matches[4]; Base = $Matches[5]; Atk = $Matches[6] }
        }
    }
    $o.Old = [bool]($o.Old -or ($o.Verdict -and -not $o.Grade))
    return $o
}

function New-CampPill([string]$Text, [string]$Fg, [string]$Bg, [double]$Size = 11.5) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 9; $b.Padding = '9,3'; $b.Margin = '0,0,6,5'; $b.Background = Get-Brush $Bg
    $t = New-Text $Text $Size $Fg 'SemiBold'; $b.Child = $t
    return $b
}

function Add-CampJourney($Body, $Steps) {
    # $Steps: @( @(label, state, detail) ) - state ok | warn | major | bad | todo | na
    # one column per step; each column draws the left / right half of the line that
    # joins its dot to its neighbours, so the line runs dot to dot at any width
    $g = New-Object Windows.Controls.Grid; $g.Margin = '0,2,0,12'
    for ($i = 0; $i -lt $Steps.Count; $i++) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength 1, 'Star'; [void]$g.ColumnDefinitions.Add($cd) }
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $st = $Steps[$i]
        $hex = switch ($st[1]) { 'ok' { $Pal.Green } 'warn' { $Pal.Amber } 'major' { $Pal.Orange } 'bad' { $Pal.Red } default { '#4B5075' } }
        $glyph = switch ($st[1]) { 'ok' { [string][char]0x2714 } { $_ -in 'warn', 'major' } { '!' } 'bad' { [string][char]0x2716 } 'na' { '-' } default { [string]($i + 1) } }
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

function New-CampNoteRow([string]$Kind, [string]$Fg, [string]$Bg, [string]$Text) {
    # one note: a fixed-width chip on the left, the sentence wrapping beside it (aligned rows)
    $g = New-Object Windows.Controls.Grid; $g.Margin = '0,3,0,3'
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = '52'; [void]$g.ColumnDefinitions.Add($c0)
    [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $chip = New-Object Windows.Controls.Border; $chip.CornerRadius = 4; $chip.Padding = '0,1'; $chip.Margin = '0,1,8,0'; $chip.VerticalAlignment = 'Top'
    $chip.Background = Get-Brush $Bg; $chip.BorderBrush = Get-Brush $Fg; $chip.BorderThickness = 1
    $ct = New-Text $Kind 9.5 $Fg 'Bold'; $ct.HorizontalAlignment = 'Center'; $chip.Child = $ct
    [void]$g.Children.Add($chip)
    $col = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($col, 1)
    # "1C38 (attacker): only ..." -> the board name bold, the rest plain
    $t = New-Object Windows.Controls.TextBlock; $t.TextWrapping = 'Wrap'; $t.LineHeight = 17; $t.FontSize = 12; $t.FontFamily = 'Segoe UI'
    $t.Foreground = Get-Brush $(if ($Kind -in 'NOTE', 'PROOF') { $Pal.Dim } else { $Pal.Text })
    if ($Text -match '^([0-9A-F]{4}(?: \([a-z]+\))?):\s*(.+)$') {
        $r1 = New-Object Windows.Documents.Run ($Matches[1] + '  '); $r1.FontWeight = 'Bold'; $r1.Foreground = Get-Brush $Fg; [void]$t.Inlines.Add($r1)
        $Text = $Matches[2]
    }
    $Text = $Text.Substring(0, 1).ToUpper() + $Text.Substring(1)
    [void]$t.Inlines.Add((New-Object Windows.Documents.Run $Text))
    [void]$col.Children.Add($t)
    if ($Kind -in 'MINOR', 'MAJOR' -and $Text -match '(\d+) of (\d+) (s|victim-seconds)') {
        $have = [double]$Matches[1]; $all = [double]$Matches[2]; $u = $(if ($Matches[3] -eq 's') { ' s' } else { '' })
        if ($all -gt 0) {
            $bar = New-Object Windows.Controls.Grid; $bar.Height = 6; $bar.Margin = '0,5,0,1'
            $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = New-Object Windows.GridLength ([math]::Max($have, 0.0001)), 'Star'
            $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = New-Object Windows.GridLength ([math]::Max($all - $have, 0.0001)), 'Star'
            [void]$bar.ColumnDefinitions.Add($ca); [void]$bar.ColumnDefinitions.Add($cb)
            $b1 = New-Object Windows.Controls.Border; $b1.Background = Get-Brush $Pal.Green; $b1.CornerRadius = '3,0,0,3'; [void]$bar.Children.Add($b1)
            $b2 = New-Object Windows.Controls.Border; $b2.Background = Get-Brush $Bg; $b2.BorderBrush = Get-Brush $Fg; $b2.BorderThickness = 1; $b2.CornerRadius = '0,3,3,0'
            [Windows.Controls.Grid]::SetColumn($b2, 1); [void]$bar.Children.Add($b2)
            [void]$col.Children.Add($bar)
            $cap = New-Text ('{0:0}{2} recorded   {3}   {1:0}{2} missing' -f $have, ($all - $have), $u, [char]0x00B7) 10 $Pal.Faint
            [void]$col.Children.Add($cap)
        }
    }
    [void]$g.Children.Add($col)
    return $g
}

function New-ValidityStrip($Rep, [int]$Columns = 2) {
    # four questions, one light each - the run's VALIDITY at a glance (oct. 19 2026):
    #   ATTACK     did the attack happen (the verdict)?   SIGNATURE  how many primary features moved?
    #   SETUP      did it run as designed (topology, roles, start)?   DATASET  is the data complete?
    $v = [string]$Rep.Verdict
    $atk = if ($Rep.Benign) {
               if ($v -match 'BENIGN CONFIRMED') { @('ok', 'none - benign') } elseif ($v -match 'INCONCLUSIVE') { @('warn', 'untestable') } else { @('bad', 'not clean') }
           } elseif ($v -match 'SETUP INVALID') { @('bad', 'not as designed') } elseif ($v -match 'NOT CONFIRMED|INCONCLUSIVE') { @('bad', 'not seen') } elseif ($v -match 'CONFIRMED') { @('ok', 'seen') } else { @('todo', '-') }
    $prim = @($Rep.Sig | Where-Object { $_.Role -match 'primary' })
    $pass = @($prim | Where-Object { $_.Res -eq 'PASS' }).Count
    $sig = if (-not $prim.Count) { @('todo', '-') }
           elseif ($Rep.Benign) { if ($pass) { @('bad', "$pass moved") } else { @('ok', 'all still') } }
           elseif ($pass) { @('ok', "$pass/$($prim.Count) primary") } else { @('bad', "0/$($prim.Count) primary") }
    $fails = @($Rep.Glance | Where-Object { $_[1] -eq 'FAIL' }).Count
    $topoW = @($Rep.Glance | Where-Object { $_[0] -eq 'TOPOLOGY' -and $_[1] -eq 'WARN' }).Count
    $warnS = @($Rep.Glance | Where-Object { $_[1] -eq 'WARN' -and $_[0] -notin @('BOARDS', 'OTHER', 'RE-TEST', 'TOPOLOGY') }).Count
    $set = if ($Rep.Benign -or -not $Rep.Glance.Count) { @('na', '-') } elseif ($fails) { @('bad', "$fails check(s) failed") } elseif ($topoW) { @('ok', 'moves allowed') } elseif ($warnS) { @('ok', 'as designed, notes') } else { @('ok', 'as designed') }
    $data = switch ($Rep.Grade) { { $_ -in 'STRONG', 'GOOD' } { @('ok', 'complete') } 'MINOR GAPS' { @('warn', 'minor gaps') } 'MAJOR GAPS' { @('major', 'major gaps') } default { @('na', '-') } }
    $ug = New-Object Windows.Controls.Primitives.UniformGrid; $ug.Columns = $Columns; $ug.Margin = '0,0,0,8'   # 2 x 2 in the narrow run panel, 4 in a row on Verify
    foreach ($c in @(@('ATTACK', $atk), @('SIGNATURE', $sig), @('SETUP', $set), @('DATASET', $data))) {
        $st = $c[1][0]
        $hex = switch ($st) { 'ok' { $Pal.Green } 'warn' { $Pal.Amber } 'major' { $Pal.Orange } 'bad' { $Pal.Red } default { $Pal.Faint } }
        $g = switch ($st) { 'ok' { [char]0x2714 } 'bad' { [char]0x2716 } { $_ -in 'warn', 'major' } { [char]0x26A0 } default { [char]0x2013 } }
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 8; $b.Padding = '8,5'; $b.Margin = '0,0,6,6'; $b.Background = Get-Brush '#1A1D30'
        $b.BorderBrush = Get-Brush $hex; $b.BorderThickness = '0,0,0,2'
        $sp = New-Object Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-Text $c[0] 9.5 $Pal.Faint 'SemiBold'))
        $w = New-Text ([string]$g + ' ' + $c[1][1]) 11.5 $hex 'Bold'; $w.TextTrimming = 'CharacterEllipsis'; $w.ToolTip = $c[1][1]; [void]$sp.Children.Add($w)
        $b.Child = $sp; [void]$ug.Children.Add($b)
    }
    return $ug
}

function Get-PlainGap([string]$Note) {
    # one MINOR / MAJOR gap line -> a sentence a non-specialist can read
    $n = $Note -replace '^(MAJOR|MINOR) GAP \([^)]*\):\s*', ''
    if ($n -match '^(\w{4}) \(attacker\): ') { return "$($Matches[1]) is the attacker and its own record is incomplete. The attacker IS the attack, so this part cannot be left out - the run should be captured again." }
    if ($n -match '^(\w{4}) \(victim\): only (\d+) of (\d+) s of its attack') { return "$($Matches[1]) (a victim) stopped recording after $($Matches[2]) s of the $($Matches[3])-s attack. That is one witness fewer, not missing proof: the attacker's own record and the other victims cover the whole attack." }
    if ($n -match '^(\w{4})(?: \(\w+\))?: only \d+ of \d+ s of cooldown') { return "$($Matches[1]) did not record the cooldown, so only its recovery after the attack is unknown. The verdict compares 'before' with 'during' - it never uses the cooldown." }
    if ($n -match '^(\w{4}) \(bystander\): windows for only (\d+) of (\d+) s') { return "$($Matches[1]) is a control board (not behind the attacker) with a few gaps ($($Matches[2]) of $($Matches[3]) s recorded). It shows the network stayed healthy; the attack result does not depend on it." }
    if ($n -match '^(\w{4}) \((\w+)\): windows for only (\d+) of (\d+) s of its (\w+)') { return "$($Matches[1]) ($($Matches[2])) recorded $($Matches[3]) of $($Matches[4]) s of the $($Matches[5]) - some seconds are missing." }
    if ($n -match 'boards have gaps') { return "Too many boards have gaps ($($n -replace '^(\d+ of \d+).*', '$1')) to prove the gaps are harmless - the run should be captured again." }
    if ($n -match 'victim-seconds could be tested') { return "Most of the victims' attack time could not be used (their path to the root was broken), so the result rests on a small part of the attack - capture it again." }
    if ($n -match 'dropped out before the attack') { return ($n -replace ':.*', '') + " switched off before the attack started, so it was never measured during it - capture it again." }
    return $n
}

function New-PlainExplain($Rep) {
    # WHAT THIS MEANS - the report's numbers as plain sentences (Campaign + Verify)
    $F = $Rep.Facts
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 12; $card.Padding = '14,10'; $card.Margin = '0,0,0,10'
    $card.Background = Get-Brush '#1B2033'; $card.BorderBrush = Get-Brush $Pal.Cyan; $card.BorderThickness = '3,0,0,0'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text 'WHAT THIS MEANS   in plain words' 10.5 $Pal.Cyan 'SemiBold'))
    $add = {
        param([string]$Glyph, [string]$Hex, [string]$Head, [string]$Body)
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,7,0,0'
        $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = '24'; [void]$g.ColumnDefinitions.Add($c0)
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $ic = New-Text $Glyph 13 $Hex 'Bold'; $ic.VerticalAlignment = 'Top'; [void]$g.Children.Add($ic)
        $tb = New-Object Windows.Controls.TextBlock; $tb.TextWrapping = 'Wrap'; $tb.FontSize = 12.5; $tb.LineHeight = 18; $tb.FontFamily = 'Segoe UI'
        $r1 = New-Object Windows.Documents.Run ($Head + '  '); $r1.FontWeight = 'Bold'; $r1.Foreground = Get-Brush $Pal.Text; [void]$tb.Inlines.Add($r1)
        $r2 = New-Object Windows.Documents.Run $Body; $r2.Foreground = Get-Brush $Pal.Dim; [void]$tb.Inlines.Add($r2)
        [Windows.Controls.Grid]::SetColumn($tb, 1); [void]$g.Children.Add($tb)
        [void]$sp.Children.Add($g)
    }
    $bullet = {
        # one point under the heading above it - indented, one sentence each
        param([string]$Text)
        $tb = New-Object Windows.Controls.TextBlock; $tb.TextWrapping = 'Wrap'; $tb.FontSize = 12; $tb.LineHeight = 17; $tb.Margin = '24,4,0,0'
        $tb.Foreground = Get-Brush $Pal.Dim; $tb.Text = [string][char]0x2022 + '  ' + $Text
        [void]$sp.Children.Add($tb)
    }
    $ok = [string][char]0x2714; $warn = [string][char]0x26A0; $bad = [string][char]0x2716; $info = [string][char]0x2139
    $v = [string]$Rep.Verdict
    if ($Rep.Benign) {
        if ($v -match 'BENIGN CONFIRMED') {
            & $add $ok $Pal.Green 'This is clean, normal traffic.' 'Nothing in it behaves like an attack: every board passed on what it received and the root got the messages. It can be used as the "normal" reference the attack runs are compared with.'
        } else {
            & $add $bad $Pal.Red 'This is NOT a clean normal reference.' 'Even with no attacker, part of this run looks like an attack. Usually congestion or a weak link - capture it again before using it as the normal reference. What went wrong:'
            foreach ($f in @($Rep.Fails)) { & $bullet ($f.Substring(0, 1).ToUpper() + $f.Substring(1)) }
        }
    }
    elseif ($v -match 'NOT CONFIRMED|INCONCLUSIVE|SETUP INVALID') {
        $pp = @($Rep.Sig | Where-Object { $_.Role -match 'primary' -and $_.Res -eq 'PASS' }).Count
        $why = if ($pp -and $v -match 'SETUP INVALID') { "The attack signature DID move ($pp primary feature(s) passed), but it cannot be counted: the run did not go as designed, so the numbers may not show the attack you planned. Fix the reason below, then capture the run again:" } else { 'Fix the reason below, then capture the run again:' }
        & $add $bad $Pal.Red 'The attack could not be confirmed in this data.' $why
        foreach ($f in $(if ($Rep.Fails.Count) { @($Rep.Fails) } else { @('no attack signature moved far enough') })) { & $bullet ($f.Substring(0, 1).ToUpper() + $f.Substring(1)) }
    }
    elseif ($v -match 'WORMHOLE') {
        $t = if ($F.TunSent) { "Board B sent about $($F.TunSent) messages through the cable to board A, and A received about $($F.TunGot) - the shortcut worked." } else { 'The two wormhole boards passed messages through their cable - the shortcut worked.' }
        & $add $ok $Pal.Green 'The attack happened: the tunnel carried traffic.' $t
        if ($F.DupWin) { & $add $ok $Pal.Green 'The root saw its fingerprint.' "In $($F.DupWin) attack seconds the root received the SAME message twice - one copy came the normal way, one through the tunnel. That duplicate is the wormhole's signature, and the root counts it on its own, independently of the attacking boards." }
    }
    else {
        if ($F.AtkId) { & $add $ok $Pal.Green 'The attack happened.' "Board $($F.AtkId) was the blackhole: it received $($F.AtkRecv) messages from the boards behind it and passed on $($F.AtkFwd) ($($F.AtkPct)%). An honest board passes on about 100%." }
        if ($F.VicN) { & $add $ok $Pal.Green "Its victims' messages never arrived." ("$($F.VicN) victim board(s) kept sending as normal, but the root received {0:0}% of their messages during the attack (before it: {1:0}%). The victims could not tell - a blackhole accepts each message and silently throws it away." -f (100 * [double]$F.VicPdr), (100 * [double]$F.VicBase)) }
        if ($F.ByN) { & $add $ok $Pal.Green 'The rest of the network was fine.' "$($F.ByN) board(s) whose messages do not pass the attacker kept delivering normally - so the loss is the attacker's doing, not a broken network or a bad signal." }
        if ($F.Robust) { & $add $ok $Pal.Green 'Checked a second way.' 'The test was repeated on only the part of the attack before any board moved, and it gave the same answer.' }
    }
    # the data - what is missing and why it does (not) matter
    $gaps = @($Rep.Notes | Where-Object { $_ -match '^(MAJOR|MINOR) GAP' })
    $maj = @($gaps | Where-Object { $_ -match '^MAJOR' }); $min = @($gaps | Where-Object { $_ -match '^MINOR' })
    if ($Rep.Grade -in @('STRONG', 'GOOD')) {
        & $add $ok $Pal.Green 'The data is complete.' 'Every board recorded the whole run, so the dataset can be used as it is.'
    } elseif ($min.Count -and -not $maj.Count) {
        & $add $warn $Pal.Amber 'Some data is missing - but it does not change the result.' 'The test was repeated WITHOUT the boards below and gave the same answer, so the verdict can be trusted. Recapturing would only make the dataset more complete.'
        foreach ($m in $min) { & $bullet (Get-PlainGap $m) }
    } elseif ($maj.Count) {
        & $add $warn $Pal.Orange 'Important data is missing.' 'The attack is still visible, but the run should be captured again before its numbers are used:'
        foreach ($m in $maj) { & $bullet (Get-PlainGap $m) }
        if ($min.Count) { & $bullet ('Smaller gaps that do not change the result: ' + (@($min | ForEach-Object { ((Get-PlainGap $_) -split '\.')[0] }) -join '; ') + '.') }
    }
    if (-not $Rep.Benign) {
        & $add $info $Pal.Faint 'Missing data never makes an attack look stronger.' 'A missing second is left out - it is never counted as "0 delivered" - and a board that was switched off or disconnected produces no delivery figure at all.'
    }
    # how to read it - the postcard analogy, folded away
    $ex = New-Object Windows.Controls.Expander; $ex.Margin = '0,8,0,0'; $ex.IsExpanded = $false
    $ex.Header = (New-Text 'How to read this (a 1-minute analogy)' 11.5 $Pal.Cyan 'SemiBold')
    $at = New-Object Windows.Controls.TextBlock; $at.TextWrapping = 'Wrap'; $at.FontSize = 12; $at.LineHeight = 18; $at.Margin = '0,6,0,0'; $at.Foreground = Get-Brush $Pal.Dim
    $at.Text = ("Think of each board as a house and the root as the post office. Every second each house sends a numbered postcard (a probe). " +
                "Houses far away hand their cards to a closer neighbour (their parent), who passes them on.`n`n" +
                "A blackhole is a neighbour who takes your cards and throws them away. You handed them over fine, so you never find out - " +
                "only the post office notices the missing card numbers. Delivery (PDR) = cards that arrived / cards sent: 1.00 = all, 0.00 = none.`n`n" +
                "Each 1-second slice is a window. A board with missing windows is a witness who left early: the case still stands if " +
                "the culprit's own record and the other witnesses are complete - that is what the 'repeated without' check proves.")
    $ex.Content = $at
    [void]$sp.Children.Add($ex)
    $card.Child = $sp
    return $card
}

function New-SignatureCard($Rep) {
    # the attack signature, one row per feature: did it move, from what to what, how far
    # (z), is it a primary, which study it comes from. Shared by Campaign and Verify.
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 12; $card.Padding = '14,10'; $card.Margin = '0,0,0,10'
    $card.Background = Get-Brush $Pal.Card; $card.BorderBrush = Get-Brush $Pal.Line; $card.BorderThickness = 1
    $sp = New-Object Windows.Controls.StackPanel
    $title = if ($Rep.Benign) { 'NO-ATTACK TEST   both signatures must stay still' } else { 'ATTACK SIGNATURE   3-sigma test, normal phase vs attack phase' }
    [void]$sp.Children.Add((New-Text $title 10.5 $Pal.Faint 'SemiBold'))
    $rule = if ($Rep.Benign) { 'A benign run is clean when NO feature passes - a pass would mean normal traffic looks attacked.' }
            else { 'Confirmed when a PRIMARY feature moves past 3 sigma AND by at least 0.10; support features only add weight. [Z]' }
    $rt = New-Text $rule 11 $Pal.Dim; $rt.TextWrapping = 'Wrap'; $rt.Margin = '0,2,0,6'; [void]$sp.Children.Add($rt)
    foreach ($s in $Rep.Sig) {
        $prim = [string]$s.Role -match 'primary'
        $lk = switch -Regex ($s.Res) { '^PASS' { @($(if ($Rep.Benign) { $Pal.Red } else { $Pal.Green }), $(if ($Rep.Benign) { '#3A1E2C' } else { '#1F4D3E' })) }
                                      '^FAIL' { @($(if ($Rep.Benign) { $Pal.Green } else { $Pal.Dim }), '#262A45') }
                                      '^(EXCLUDED|INVALID)' { @($Pal.Amber, '#3A2E14') } default { @($Pal.Faint, '#232742') } }
        $g = New-Object Windows.Controls.Grid; $g.Margin = '0,3,0,3'
        $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = '78'; [void]$g.ColumnDefinitions.Add($c0)
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $chip = New-Object Windows.Controls.Border; $chip.CornerRadius = 4; $chip.Padding = '0,1'; $chip.Margin = '0,1,8,0'; $chip.VerticalAlignment = 'Top'
        $chip.Background = Get-Brush $lk[1]; $chip.BorderBrush = Get-Brush $lk[0]; $chip.BorderThickness = 1
        # benign: a pass means the feature MOVED on normal traffic (bad), a fail that it stayed STILL (good)
        $word = if ($Rep.Benign -and $s.Res -eq 'PASS') { 'MOVED' } elseif ($Rep.Benign -and $s.Res -eq 'FAIL') { 'STILL' } else { [string]$s.Res }
        $ct = New-Text $word 9.5 $lk[0] 'Bold'; $ct.HorizontalAlignment = 'Center'; $chip.Child = $ct; [void]$g.Children.Add($chip)
        $col = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($col, 1)
        $h = New-Object Windows.Controls.TextBlock; $h.TextWrapping = 'Wrap'; $h.FontSize = 12; $h.FontFamily = 'Segoe UI'
        $r1 = New-Object Windows.Documents.Run ([string]$s.Feat); $r1.FontWeight = $(if ($prim) { 'Bold' } else { 'Normal' }); $r1.Foreground = Get-Brush $Pal.Text; [void]$h.Inlines.Add($r1)
        $r2 = New-Object Windows.Documents.Run ('   ' + $(if ($prim) { 'PRIMARY' } else { 'support' }) + $(if ($s.For) { ' - ' + $s.For } else { '' }) + '  ' + $s.Tag)
        $r2.FontSize = 10.5; $r2.Foreground = Get-Brush $(if ($prim) { $Pal.Cyan } else { $Pal.Faint }); [void]$h.Inlines.Add($r2)
        [void]$col.Children.Add($h)
        $nv = ([string]$s.Norm -split '\s')[0]; $av = [string]$s.Atk
        $vt = New-Text ('normal {0}   ' -f $s.Norm + [char]0x2192 + '   {0} {1}      z {2}' -f $(if ($Rep.Benign) { 'later' } else { 'attack' }), $av, $s.Z) 11 $Pal.Dim
        [void]$col.Children.Add($vt)
        $dn = 0.0; $da = 0.0
        if ([double]::TryParse($nv, [ref]$dn) -and [double]::TryParse($av, [ref]$da) -and $dn -ge 0 -and $dn -le 1 -and $da -ge 0 -and $da -le 1) {
            # a ratio: two thin bars on one 0..1 scale - how far it moved, at a glance
            foreach ($pair in @(@($dn, $Pal.Green), @($da, $lk[0]))) {
                $bar = New-Object Windows.Controls.Grid; $bar.Height = 4; $bar.Margin = '0,2,0,0'
                $ca = New-Object Windows.Controls.ColumnDefinition; $ca.Width = New-Object Windows.GridLength ([math]::Max($pair[0], 0.0001)), 'Star'
                $cb = New-Object Windows.Controls.ColumnDefinition; $cb.Width = New-Object Windows.GridLength ([math]::Max(1 - $pair[0], 0.0001)), 'Star'
                [void]$bar.ColumnDefinitions.Add($ca); [void]$bar.ColumnDefinitions.Add($cb)
                $b1 = New-Object Windows.Controls.Border; $b1.Background = Get-Brush $pair[1]; $b1.CornerRadius = 2; [void]$bar.Children.Add($b1)
                $b2 = New-Object Windows.Controls.Border; $b2.Background = Get-Brush '#2A2E48'; $b2.CornerRadius = 2; [Windows.Controls.Grid]::SetColumn($b2, 1); [void]$bar.Children.Add($b2)
                [void]$col.Children.Add($bar)
            }
        }
        [void]$g.Children.Add($col)
        [void]$sp.Children.Add($g)
    }
    $card.Child = $sp
    return $card
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
    if ($isBase -and -not $rep) { $ver = @('todo', $(if ($hasAna) { 'press Verify' } else { '' })); $grd = @('todo', '') }
    else {
        $ver = if ($Look -in @('todo', 'partial')) { @('todo', '') }
               elseif (-not $rep -and -not $v) { @('todo', $(if ($hasAna) { 'press Verify' } else { '' })) }
               elseif ($rep -and $rep.Verdict -match 'SETUP INVALID') { @('bad', 'setup invalid') }
               elseif ($rep -and $rep.Verdict -match 'NOT CONFIRMED|INCONCLUSIVE') { @('bad', 'failed') }
               elseif ($rep -and $rep.Verdict -match 'CONFIRMED') { @('ok', 'confirmed') }
               elseif ($v -and $v.Code -eq 0) { @('ok', 'confirmed') } elseif ($v) { @('bad', 'failed') } else { @('todo', '') }
        $grd = if (-not $rep) { @('todo', '') }
               elseif ($rep.Old) { @('warn', 'old report - press Verify') }
               else { switch ($rep.Grade) { 'STRONG' { @('ok', 'strong') } 'GOOD' { @('ok', 'good') } 'MINOR GAPS' { @('warn', 'minor gaps') } 'MAJOR GAPS' { @('major', 'major gaps') } 'FAILED' { @('bad', 'failed') } default { @('todo', '') } } }
    }
    Add-CampJourney $Body @(@('Captured', $cap[0], $cap[1]), @('Analysed', $ana[0], $ana[1]), @('Verified', $ver[0], $ver[1]), @('Graded', $grd[0], $grd[1]))
    if (-not $rep) { return }

    # 2. VERDICT tile
    $tone = switch ($rep.Grade) { 'STRONG' { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A' } } 'GOOD' { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A' } } 'MINOR GAPS' { @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320' } } 'MAJOR GAPS' { @{ Fg = $Pal.Orange; Bg = '#35200F'; Bd = '#7C3F1A' } } default { @{ Fg = $Pal.Red; Bg = '#33192A'; Bd = '#6B2A3F' } } }
    if ($rep.Old) { $tone = @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320' } }
    $tile = New-Object Windows.Controls.Border; $tile.CornerRadius = 12; $tile.Padding = '14,10'; $tile.Margin = '0,0,8,10'
    $tile.Background = Get-Brush $tone.Bg; $tile.BorderBrush = Get-Brush $tone.Bd; $tile.BorderThickness = 1
    $tp = New-Object Windows.Controls.StackPanel
    if (-not $rep.Old) { [void]$tp.Children.Add((New-ValidityStrip $rep)) }
    $big = New-Text $(if ($rep.Old) { 'OLD REPORT' } else { [string]$rep.Grade }) 17 $tone.Fg 'Bold'
    $big.TextWrapping = 'Wrap'; [void]$tp.Children.Add($big)
    $sub = New-Text $(if ($rep.Old) { 'Made by an older verifier - press Verify to update it.' } else { [string]$rep.Say }) 11.5 $Pal.Dim
    $sub.TextWrapping = 'Wrap'; $sub.Margin = '0,2,0,6'; [void]$tp.Children.Add($sub)
    foreach ($n in @($rep.Notes | Select-Object -First 8)) {
        $kind = if ($n -match '^MAJOR GAP') { @('MAJOR', $Pal.Orange, '#35200F') } elseif ($n -match '^MINOR GAP') { @('MINOR', $Pal.Amber, '#2E2716') } else { @('NOTE', $Pal.Dim, '#262A45') }
        $say = ($n -replace '^(MAJOR|MINOR) GAP \([^)]*\):\s*', '' -replace '^note:\s*', '')
        [void]$tp.Children.Add((New-CampNoteRow $kind[0] $kind[1] $kind[2] $say))
    }
    foreach ($f in @($rep.Fails | Select-Object -First 3)) { [void]$tp.Children.Add((New-CampNoteRow 'FAIL' $Pal.Red '#3A1E2C' $f)) }
    if ($rep.Proof) { [void]$tp.Children.Add((New-CampNoteRow 'PROOF' $Pal.Green '#16352B' $rep.Proof)) }
    if (@($rep.Notes | Where-Object { $_ -match '^(MAJOR|MINOR) GAP' }).Count) {
        # the two words, explained once, right where they are used
        $key = New-Object Windows.Controls.Border; $key.CornerRadius = 8; $key.Padding = '10,6'; $key.Margin = '0,8,0,0'; $key.Background = Get-Brush '#1A1D30'
        $ks = New-Object Windows.Controls.StackPanel
        foreach ($kk in @(@('MINOR GAP', $Pal.Amber, 'data is missing, but the attack is still confirmed without it (proved by the impact check)'),
                          @('MAJOR GAP', $Pal.Orange, 'the result relies on the missing data - capture the run again'))) {
            $kt = New-Object Windows.Controls.TextBlock; $kt.TextWrapping = 'Wrap'; $kt.FontSize = 11; $kt.Margin = '0,1,0,1'
            $k1 = New-Object Windows.Documents.Run ($kk[0] + '  '); $k1.FontWeight = 'Bold'; $k1.Foreground = Get-Brush $kk[1]; [void]$kt.Inlines.Add($k1)
            $k2 = New-Object Windows.Documents.Run $kk[2]; $k2.Foreground = Get-Brush $Pal.Faint; [void]$kt.Inlines.Add($k2)
            [void]$ks.Children.Add($kt)
        }
        $key.Child = $ks; [void]$tp.Children.Add($key)
    }
    if ($rep.ReportAs) { $ra = New-Text ('Report as: ' + ($rep.ReportAs -replace '\s*\(copy them to the thesis checklist\)', '')) 12 $Pal.Cyan 'SemiBold'; $ra.TextWrapping = 'Wrap'; $ra.Margin = '0,8,0,0'; [void]$tp.Children.Add($ra) }
    if ($rep.Glance.Count) {
        $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,8,0,0'
        foreach ($gl in $rep.Glance) {
            $c = switch ($gl[1]) { 'FAIL' { @($Pal.Red, '#3A1E2C', [char]0x2716) } 'WARN' { @($Pal.Amber, '#3A2E14', [char]0x26A0) } 'OK' { @($Pal.Green, '#1F4D3E', [char]0x2714) } default { @($Pal.Dim, '#2A2E48', [char]0x2026) } }
            [void]$wp.Children.Add((New-CampPill ('{0} {1}' -f [string]$c[2], $gl[0]) $c[0] $c[1] 10.5))
        }
        [void]$tp.Children.Add($wp)
    }
    if ($rep.Notes.Count -or $rep.Fails.Count) {
        # one click: the run + its footnotes on the clipboard, for the thesis checklist
        $cb = New-Object Windows.Controls.Button; $cb.Content = 'Copy footnotes'; $cb.Padding = '10,3'; $cb.Margin = '0,8,0,0'; $cb.HorizontalAlignment = 'Left'
        $cb.ToolTip = 'Copies this run, its verdict and its footnotes as text - paste it into the thesis checklist'
        $cb.Tag = ("{0}: {1}`n{2}" -f (Get-SlotText $S), $(if ($rep.ReportAs) { $rep.ReportAs } else { $rep.Verdict }), ((@($rep.Notes) + @($rep.Fails) | ForEach-Object { '- ' + $_ }) -join "`n"))
        $cb.Add_Click({ param($x) try { [Windows.Clipboard]::SetText([string]$x.Tag); $x.Content = 'Copied' } catch { } })
        [void]$tp.Children.Add($cb)
    }
    $tile.Child = $tp
    # verdict tile + delivery chart: side by side in a wide panel, stacked in a narrow one
    # (both STRETCH - fixed widths left holes, oct. 19 2026)
    # (a Grid, not a UniformGrid: stacked, each keeps its own height - no empty block)
    $wrap = New-Object Windows.Controls.Grid; $wrap.Tag = 'resp'
    [void]$wrap.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    [void]$wrap.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    [void]$wrap.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)); [void]$wrap.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition))
    $wrap.RowDefinitions[0].Height = 'Auto'; $wrap.RowDefinitions[1].Height = 'Auto'
    Register-CampResponsive
    [void]$wrap.Children.Add($tile)
    if ($rep.Nodes.Count) { try { [void]$wrap.Children.Add((New-CampDeliveryChart $rep.Nodes)) } catch { } }
    Set-CampRespLayout $wrap ($ui.CampDetBody.ActualWidth -ge 700)
    [void]$Body.Children.Add($wrap)
    if (-not $rep.Old) { try { [void]$Body.Children.Add((New-PlainExplain $rep)) } catch { } }
    if ($rep.Sig.Count) { try { [void]$Body.Children.Add((New-SignatureCard $rep)) } catch { } }

    # 2b. PHASE TIMELINE per board (cached; background read the first time)
    try { Add-CampTimeline $Body $S } catch { }

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

# ---- oct. 19 2026 (user: "expand the notes, more user friendly, graphs - no lag") -------

function Set-CampSelection {
    # move the white selection border between two EXISTING tiles - no grid rebuild.
    # $false = the grid has not been drawn yet (the caller then draws it once)
    $m = $script:CampTileMap; if (-not $m -or -not $m.Count) { return $false }
    $n = $m[$script:CampSel]; if (-not $n) { return $false }
    if ($script:CampSelPrev -and $script:CampSelPrev -ne $script:CampSel -and $m[$script:CampSelPrev]) {
        $o = $m[$script:CampSelPrev]; $o.T.BorderBrush = $o.Bd; $o.T.BorderThickness = $o.Th
    }
    $n.T.BorderBrush = Get-Brush '#FFFFFF'; $n.T.BorderThickness = 2.5
    $script:CampSelPrev = $script:CampSel
    return $true
}

$script:CampTipCache = @{}
function Set-CampTileTip($Tile) {
    # hover: add the run's verdict grade to the tile's tooltip - read once per report version
    $S = $Tile.Tag; if (-not $S) { return }
    if ([string]$Tile.ToolTip -match "`nverdict: ") { return }
    $key = Get-SlotKeyPath $S
    $f = Join-Path $script:AnaDir ('reports\' + ($key -replace '/', '__') + '.txt')
    if (-not (Test-Path $f)) { return }
    $stamp = (Get-Item $f).LastWriteTime.Ticks
    $c = $script:CampTipCache[$key]
    if (-not $c -or $c.T -ne $stamp) {
        $b = Get-CampReportBits $key
        $line = if (-not $b) { '' } elseif ($b.Old) { 'old report - press Verify' }
                elseif ($b.Grade -eq 'FAILED') { 'FAILED' }
                elseif ($b.Grade) { 'CONFIRMED - ' + $b.Grade } else { '' }
        $c = @{ T = $stamp; Line = $line }; $script:CampTipCache[$key] = $c
    }
    if ($c.Line) { $Tile.ToolTip = [string]$Tile.ToolTip + "`nverdict: " + $c.Line }
}

function New-CampRing([int]$Done, [int]$Total) {
    # the campaign's done share as a ring (one arc, drawn once per stats refresh)
    $f = if ($Total -gt 0) { [Math]::Min(1.0, $Done / [double]$Total) } else { 0.0 }
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '10,4'; $b.Margin = '0,0,10,6'; $b.Background = Get-Brush $Pal.Card
    $b.BorderBrush = Get-Brush $Pal.Line; $b.BorderThickness = 1; $b.ToolTip = "$Done of $Total planned runs are done (usable)"
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $g = New-Object Windows.Controls.Grid; $g.Width = 46; $g.Height = 46
    $bg = New-Object Windows.Shapes.Ellipse; $bg.Stroke = Get-Brush '#2F3352'; $bg.StrokeThickness = 6; [void]$g.Children.Add($bg)
    $hex = if ($f -ge 0.999) { $Pal.Green } elseif ($f -ge 0.5) { $Pal.Cyan } else { $Pal.Amber }
    if ($f -ge 0.999) {
        $full = New-Object Windows.Shapes.Ellipse; $full.Stroke = Get-Brush $hex; $full.StrokeThickness = 6; [void]$g.Children.Add($full)
    } elseif ($f -gt 0) {
        $r = 20.0; $cx = 23.0; $cy = 23.0; $a = 2 * [Math]::PI * $f
        $fig = New-Object Windows.Media.PathFigure; $fig.StartPoint = New-Object Windows.Point $cx, ($cy - $r)
        $arc = New-Object Windows.Media.ArcSegment; $arc.Point = New-Object Windows.Point ($cx + $r * [Math]::Sin($a)), ($cy - $r * [Math]::Cos($a))
        $arc.Size = New-Object Windows.Size $r, $r; $arc.SweepDirection = 'Clockwise'; $arc.IsLargeArc = ($f -gt 0.5)
        [void]$fig.Segments.Add($arc)
        $geo = New-Object Windows.Media.PathGeometry; [void]$geo.Figures.Add($fig)
        $path = New-Object Windows.Shapes.Path; $path.Data = $geo; $path.Stroke = Get-Brush $hex; $path.StrokeThickness = 6
        $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'
        [void]$g.Children.Add($path)
    }
    $pt = New-Text ('{0:0}%' -f (100 * $f)) 12 $hex 'Bold'; $pt.HorizontalAlignment = 'Center'; $pt.VerticalAlignment = 'Center'; [void]$g.Children.Add($pt)
    [void]$sp.Children.Add($g)
    $lt = New-Text 'of the campaign done' 12 $Pal.Dim; $lt.Margin = '8,14,0,0'; [void]$sp.Children.Add($lt)
    $b.Child = $sp
    return $b
}

function New-ShareBar([double]$Share, [string]$Hex, [double]$H) {
    # a track that fills its space, with a coloured share of it - no fixed pixel width
    $g = New-Object Windows.Controls.Grid; $g.Height = $H; $g.VerticalAlignment = 'Center'
    $tr = New-Object Windows.Controls.Border; $tr.CornerRadius = $H / 2; $tr.Background = Get-Brush '#2A2E48'
    [Windows.Controls.Grid]::SetColumnSpan($tr, 2); [void]$g.Children.Add($tr)
    foreach ($w in $Share, (1.0 - $Share)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength ([Math]::Max(0.0001, $w)), 'Star'; [void]$g.ColumnDefinitions.Add($cd) }
    if ($Share -gt 0) { $fl = New-Object Windows.Controls.Border; $fl.CornerRadius = $H / 2; $fl.Background = Get-Brush $Hex; [void]$g.Children.Add($fl) }
    return $g
}

function Register-CampResponsive {
    # once: a wide run panel shows tile + chart side by side, a narrow one stacks them
    if ($script:CampRespOn) { return }
    $script:CampRespOn = $true
    $ui.CampDetBody.Add_SizeChanged({
        param($s, $e)
        foreach ($c in $s.Children) { if ($c -is [Windows.Controls.Grid] -and [string]$c.Tag -eq 'resp') { Set-CampRespLayout $c ($e.NewSize.Width -ge 700) } }
    })
}
function Set-CampRespLayout($G, [bool]$Wide) {
    # wide: tile | chart side by side; narrow: tile over chart, full width
    $G.ColumnDefinitions[1].Width = $(if ($Wide) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength 0 })
    if ($G.Children.Count -gt 1) {
        $c = $G.Children[1]
        [Windows.Controls.Grid]::SetColumn($c, $(if ($Wide) { 1 } else { 0 })); [Windows.Controls.Grid]::SetRow($c, $(if ($Wide) { 0 } else { 1 }))
    }
    $G.Children[0].Margin = $(if ($Wide) { '0,0,8,10' } else { '0,0,0,10' })
}

function New-CampDeliveryChart($Nodes) {
    # delivery per board, baseline vs attack, from the report's [4] table (no data read)
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 12; $card.Padding = '14,10'; $card.Margin = '0,0,8,10'
    $card.Background = Get-Brush $Pal.Card; $card.BorderBrush = Get-Brush $Pal.Line; $card.BorderThickness = 1
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text 'DELIVERY PER BOARD   baseline -> attack' 10.5 $Pal.Faint 'SemiBold'))
    $mem = @{}; try { $mem = Get-MemberInfo } catch { }
    foreach ($n in $Nodes) {
        $mac = [string]$n.Node -replace '^NODE_', ''
        $vic = [string]$n.Exp -match 'VICTIM'
        $nick = ''; if ($mac.Length -ge 12) { $k = $mem[($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToLower()]; if ($k) { $nick = ' ' + $k.Nick } }
        $row = New-Object Windows.Controls.Grid; $row.Margin = '0,5,0,0'
        foreach ($w in 86, 1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq 1) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength $w }); [void]$row.ColumnDefinitions.Add($cd) }
        # the same 4-character ID the notes use (D7B4), then the Boards-page label (28:B4)
        $nm = New-Object Windows.Controls.TextBlock; $nm.FontSize = 11; $nm.FontFamily = 'Segoe UI'
        $q1 = New-Object Windows.Documents.Run ($(if ($mac.Length -ge 4) { $mac.Substring($mac.Length - 4) } else { $mac })); $q1.FontWeight = 'SemiBold'; $q1.Foreground = Get-Brush $(if ($vic) { '#FCA5A5' } else { $Pal.Cyan }); [void]$nm.Inlines.Add($q1)
        $q2 = New-Object Windows.Documents.Run ($(if ($mac.Length -ge 12) { '  ' + $mac.Substring(0, 2) + ':' + $mac.Substring(10, 2) } else { '' }) + $nick); $q2.Foreground = Get-Brush $Pal.Faint; [void]$nm.Inlines.Add($q2)
        $nm.ToolTip = "$($n.Node)  -  $($n.Exp.Trim())  -  hop $($n.Hop)"; $nm.TextTrimming = 'CharacterEllipsis'
        [Windows.Controls.Grid]::SetColumn($nm, 0); [void]$row.Children.Add($nm)
        $bars = New-Object Windows.Controls.StackPanel
        foreach ($pair in @(@('baseline', $n.Base, $Pal.Green), @('attack', $n.Atk, $(if ($vic) { $Pal.Red } else { $Pal.Cyan })))) {
            $v = 0.0; $ok = [double]::TryParse([string]$pair[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)
            $line = New-Object Windows.Controls.DockPanel; $line.Margin = '0,1,0,1'
            $val = New-Text $(if ($ok) { '{0:0.00}' -f $v } else { '-' }) 10 $Pal.Dim; $val.Width = 32; $val.TextAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($val, 'Right'); [void]$line.Children.Add($val)
            $f = if ($ok) { [Math]::Max(0.0, [Math]::Min(1.0, $v)) } else { 0.0 }
            [void]$line.Children.Add((New-ShareBar $f $pair[2] 7))
            [void]$bars.Children.Add($line)
        }
        [Windows.Controls.Grid]::SetColumn($bars, 1); [void]$row.Children.Add($bars)
        [void]$sp.Children.Add($row)
    }
    $lg = New-Text 'red = behind the attacker (victim)   -   blue = not behind it' 10 $Pal.Faint; $lg.Margin = '0,8,0,0'; [void]$sp.Children.Add($lg)
    $card.Child = $sp
    return $card
}

# ---- phase timeline per board (oct. 19 2026, user) -----------------------------------
# tools\phase_summary.py reads the run's CSVs (~1 s) - so it runs in the BACKGROUND the
# first time a run is opened and its result is cached in %LOCALAPPDATA%\NIS16\phase_cache
# with a signature of the run's files (names + sizes). Later opens draw from the cache
# at once; a re-import / re-trim changes the signature and the timeline is re-read.
$script:PhaseHex = @{ '255' = '#4B5075'; '254' = '#4B5075'; '0' = '#3DDC97'; '1' = '#FF5C9A'; '2' = '#FF5C9A'; '3' = '#3FD0FF'; '4' = '#A78BFA' }
$script:PhaseWord = @{ '255' = 'stabilise'; '254' = 'prepare'; '0' = 'baseline'; '1' = 'attack'; '2' = 'attack'; '3' = 'cooldown'; '4' = 'terminate' }

function Get-RunFilesSig([string]$Dir) {
    $fs = @(Get-ChildItem $Dir -Filter '*_telem.csv' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    return (@($fs | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Length }) -join '|')
}

function Add-CampTimeline($Body, $S) {
    $key = Get-SlotKeyPath $S
    $exp = Join-Path $base ('datasets\exports\' + ($key -replace '/', '\'))
    if (-not (Test-Path $exp)) { return }
    $trim = Join-Path $exp 'trimmed'
    $src = if (@(Get-ChildItem $trim -Filter '*_telem.csv' -File -ErrorAction SilentlyContinue).Count) { $trim } else { $exp }
    $sig = Get-RunFilesSig $src
    if (-not $sig) { return }
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 12; $card.Padding = '14,10'; $card.Margin = '0,0,10,10'
    $card.Background = Get-Brush $Pal.Card; $card.BorderBrush = Get-Brush $Pal.Line; $card.BorderThickness = 1
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text ('PHASE TIMELINE PER BOARD   ({0} data)' -f $(if ($src -eq $trim) { 'trimmed' } else { 'raw' })) 10.5 $Pal.Faint 'SemiBold'))
    $wait = New-Text 'reading the boards'' files in the background...' 11.5 $Pal.Dim; $wait.Margin = '0,6,0,0'; [void]$sp.Children.Add($wait)
    $card.Child = $sp
    [void]$Body.Children.Add($card)
    $dir = Join-Path $script:AnaDir 'phase_cache'
    $cf = Join-Path $dir (($key -replace '/', '__') + '.json')
    if (Test-Path $cf) {
        try { $c = Get-Content $cf -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c.sig -eq $sig) { Show-CampTimeline $card @($c.items); return } } catch { }
    }
    if (-not $script:Py) { $wait.Text = 'Python not found - no timeline'; return }
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\phase_summary.py', $src) -State @{ Card = $card; Key = $key; Sig = $sig; Cf = $cf; Dir = $dir } -OnDone {
        param($text, $code, $st)
        $line = @($text -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('[') } | Select-Object -Last 1)
        if (-not $line) { try { $st.Card.Child.Children[1].Text = 'could not read the files (see the activity pane)' } catch { }; return }
        $items = @([string]$line | ConvertFrom-Json | ForEach-Object { $_ })
        try { New-Item -ItemType Directory -Force -Path $st.Dir | Out-Null; (@{ sig = $st.Sig; items = $items } | ConvertTo-Json -Depth 6) | Set-Content -Path $st.Cf -Encoding UTF8 } catch { }
        # draw only if the user is still looking at this run
        if ($script:CampSlot -and (Get-SlotKeyPath $script:CampSlot) -eq $st.Key) { Show-CampTimeline $st.Card $items }
    }
}

function Show-CampTimeline($Card, $Items) {
    # the colours live HERE: this also runs from a background job's callback, where a
    # script-level table was not visible (an empty colour -> an error, oct. 19 2026)
    $PhaseHex = @{ '255' = '#4B5075'; '254' = '#4B5075'; '0' = '#3DDC97'; '1' = '#FF5C9A'; '2' = '#FF5C9A'; '3' = '#3FD0FF'; '4' = '#A78BFA' }
    $PhaseWord = @{ '255' = 'stabilise'; '254' = 'prepare'; '0' = 'baseline'; '1' = 'attack'; '2' = 'attack'; '3' = 'cooldown'; '4' = 'terminate' }
    $sp = $Card.Child
    while ($sp.Children.Count -gt 1) { $sp.Children.RemoveAt(1) }
    $Items = @($Items | Sort-Object { if ($_.role -eq 'root') { 0 } else { 1 } }, { [string]$_.node })
    $maxRows = [Math]::Max(1, ($Items | ForEach-Object { [int]$_.rows } | Measure-Object -Maximum).Maximum)
    $W = 380.0
    $mem = @{}; try { $mem = Get-MemberInfo } catch { }
    foreach ($it in $Items) {
        $mac = [string]$it.node -replace '^NODE_', ''
        $short = if ($mac.Length -ge 12) { $mac.Substring(0, 2) + ':' + $mac.Substring(10, 2) } else { $mac }
        $nick = ''; if ($mac.Length -ge 12) { $k = $mem[$short.ToLower()]; if ($k) { $nick = ' ' + $k.Nick } }
        $row = New-Object Windows.Controls.Grid; $row.Margin = '0,6,0,0'
        foreach ($w in 120, 1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq 1) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength $w }); [void]$row.ColumnDefinitions.Add($cd) }
        $role = [string]$it.role
        $nm = New-Text ($short + $nick) 11.5 $(if ($role -eq 'root') { $Pal.Amber } elseif ($role -match 'blackhole|wormhole') { $Pal.Pink } else { $Pal.Text }) 'SemiBold'
        $nm.ToolTip = "$($it.node)  -  $role  -  $($it.file)"; $nm.TextTrimming = 'CharacterEllipsis'
        [Windows.Controls.Grid]::SetColumn($nm, 0); [void]$row.Children.Add($nm)
        $right = New-Object Windows.Controls.StackPanel
        $bar = New-Object Windows.Controls.Grid; $bar.Height = 12
        $ph = @{}; foreach ($pp in $it.phases.PSObject.Properties) { $ph[$pp.Name] = [int]$pp.Value }
        $seen = @{}
        foreach ($id in @($it.seq)) {
            $id = [string]$id; if ($seen[$id]) { continue }; $seen[$id] = $true
            $n = [int]$ph[$id]; if ($n -le 0) { continue }
            $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength ([double]$n), 'Star'; [void]$bar.ColumnDefinitions.Add($cd)
            $seg = New-Object Windows.Controls.Border; $seg.Height = 12; $seg.Margin = '0,0,1,0'
            $seg.Background = Get-Brush $(if ($PhaseHex[$id]) { $PhaseHex[$id] } else { '#6B7393' })
            $seg.ToolTip = '{0}: {1:N0} rows (~{2:N0} s)' -f $(if ($PhaseWord[$id]) { $PhaseWord[$id] } else { "phase $id" }), $n, ($n / 10)
            [Windows.Controls.Grid]::SetColumn($seg, $bar.ColumnDefinitions.Count - 1); [void]$bar.Children.Add($seg)
        }
        # the rest of the row stays empty, so a shorter file is a shorter bar
        $rest = [double]$maxRows - [double]$it.rows
        if ($rest -gt 0) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength $rest, 'Star'; [void]$bar.ColumnDefinitions.Add($cd) }
        [void]$right.Children.Add($bar)
        $miss = @(); if (-not $ph['0']) { $miss += 'no baseline' }; if (-not ($ph['1'] -or $ph['2'])) { $miss += 'no attack' }; if (-not $ph['3']) { $miss += 'no cooldown' }
        $info = '{0:N0} s' -f [double]$it.seconds
        # a board that kept running across a root restart holds two sessions in one file;
        # the counts above are both added up - the analysis uses only the LAST one
        $sessions = @($it.seq | Where-Object { [string]$_ -eq '0' }).Count
        if ($sessions -gt 1) { $info += "   -   holds $sessions root sessions (the analysis uses the last)" }
        $lt = New-Text ($info + $(if ($miss.Count) { '   -   ' + ($miss -join ', ') } else { '' })) 10 $(if ($miss.Count) { $Pal.Amber } elseif ($sessions -gt 1) { $Pal.Cyan } else { $Pal.Faint }); $lt.Margin = '0,2,0,0'
        [void]$right.Children.Add($lt)
        [Windows.Controls.Grid]::SetColumn($right, 1); [void]$row.Children.Add($right)
        [void]$sp.Children.Add($row)
    }
    $lg = New-Object Windows.Controls.WrapPanel; $lg.Margin = '0,8,0,0'
    foreach ($id in '255', '0', '1', '3') {
        $d = New-Object Windows.Controls.Border; $d.Width = 10; $d.Height = 10; $d.CornerRadius = 2; $d.Margin = '0,2,4,0'; $d.Background = Get-Brush $PhaseHex[$id]
        [void]$lg.Children.Add($d); $l = New-Text ($PhaseWord[$id] + '    ') 10.5 $Pal.Faint; [void]$lg.Children.Add($l)
    }
    [void]$sp.Children.Add($lg)
}
