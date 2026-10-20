# gui\RunStatusCard.ps1 - the Verify page's "run status" card (oct. 20 2026, user: "the
# Campaign says REDO while Verify says STRONG - which is it?", "make the Verify page also
# show what the Campaign status says").
#
# Two different questions, shown side by side so they can no longer read as a contradiction:
#   CAMPAIGN STATUS   must this capture be redone?   redo_list.py - EVERY source: capture
#                     completeness, structure, verifier, verification log, checklist rows
#   ATTACK EVIDENCE   does this data prove the attack?   verify_attack.py OUTCOME
#                     PASS / FAIL / INCONCLUSIVE (signature, setup, dataset)
# plus the five dimensions and THIS run's own reasons (never another run's: the redo entry
# is looked up by this cell's key, and redo_list.py no longer moves reasons between cells).
# Also says when the saved report is OLDER than the analysis, or disagrees with the live
# re-check - the stale-report case that made the two pages disagree.
# Dot-sourced by run_gui.ps1. ASCII only.

function Get-ReportOutcome([string]$Text) {
    # the verifier's OUTCOME line of a saved report, or '' (reports before oct. 20 2026)
    $t = $Text -replace "\x1b\[[0-9;]*m", ''
    $m = [regex]::Match($t, '(?m)^\s*OUTCOME:\s*(PASS|FAIL|INCONCLUSIVE)\b\s*-?\s*(.*)$')
    if ($m.Success) { return @{ Word = $m.Groups[1].Value; Why = $m.Groups[2].Value.Trim() } }
    return $null
}

function New-RunStatusCard($C, [string]$ReportText) {
    if (-not $C) { return $null }
    $ck = Get-CellKey $C.Attack $C.Topology $C.Location $C.Scenario
    $r = $null; try { $r = $script:Redo[$ck] } catch { }
    $card = New-Object Windows.Controls.Border; $card.CornerRadius = 12; $card.Padding = '14,10'; $card.Margin = '0,0,0,10'
    $card.Background = Get-Brush '#1B2033'; $card.BorderBrush = Get-Brush $Pal.Line; $card.BorderThickness = 1
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text 'RUN STATUS   two different questions about this run' 10.5 $Pal.Faint 'SemiBold'))

    $tone = @{ PASS = @($Pal.Green, '#16352B'); FAIL = @($Pal.Red, '#3A1E2C'); INCONCLUSIVE = @($Pal.Amber, '#3A2E14') }
    $live = if ($r -and $r.PSObject.Properties['outcome'] -and $r.outcome) { $r.outcome } else { $null }
    $saved = Get-ReportOutcome $ReportText
    $ow = if ($live -and [string]$live.outcome -ne '-') { [string]$live.outcome } elseif ($saved) { $saved.Word } else { '' }
    $oy = if ($live -and [string]$live.outcome -ne '-') { [string]$live.why } elseif ($saved) { $saved.Why } else { '' }

    $row = New-Object Windows.Controls.WrapPanel; $row.Margin = '0,6,0,2'
    $q1 = New-Object Windows.Controls.StackPanel; $q1.Margin = '0,0,24,4'
    [void]$q1.Children.Add((New-Text 'CAMPAIGN STATUS - must this capture be redone?' 9.5 $Pal.Faint 'SemiBold'))
    $cw = if ($C.Badge) { [string]$C.Badge } else { 'not checked yet' }
    [void]$q1.Children.Add((New-CampPill $cw $(if ($C.BadgeFg) { [string]$C.BadgeFg.Color } else { $Pal.Dim }) $(if ($C.BadgeBg) { [string]$C.BadgeBg.Color } else { '#262A45' }) 13))
    [void]$row.Children.Add($q1)
    $q2 = New-Object Windows.Controls.StackPanel; $q2.Margin = '0,0,0,4'
    [void]$q2.Children.Add((New-Text 'ATTACK EVIDENCE - does this data prove the attack?' 9.5 $Pal.Faint 'SemiBold'))
    if ($ow) { $t2 = $tone[$ow]; [void]$q2.Children.Add((New-CampPill $ow $t2[0] $t2[1] 13)) }
    else { [void]$q2.Children.Add((New-CampPill 'press Verify' $Pal.Dim '#262A45' 13)) }
    [void]$row.Children.Add($q2)
    [void]$sp.Children.Add($row)
    if ($oy) { $w = New-Text $oy 11.5 $Pal.Dim; $w.TextWrapping = 'Wrap'; $w.Margin = '0,0,0,4'; [void]$sp.Children.Add($w) }

    # the five dimensions (redo_list.run_dimensions) - one chip each
    if ($r -and $r.PSObject.Properties['dimensions'] -and $r.dimensions) {
        $d = $r.dimensions
        $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,2,0,4'
        foreach ($k in @(@('execution', 'EXECUTION', 'every board recorded'), @('topology', 'TOPOLOGY', 'intended structure'),
                         @('signature', 'SIGNATURE', 'attack signature moved'), @('setup', 'SETUP', 'ran as designed'),
                         @('dataset', 'DATASET', 'data complete enough'))) {
            $v = [string]$d.($k[0]); if (-not $v) { $v = '-' }
            $hex = switch ($v) { 'PASS' { $Pal.Green } 'FAIL' { $Pal.Red } { $_ -in 'WARN', 'MINOR', 'INCONCLUSIVE' } { $Pal.Amber } default { $Pal.Faint } }
            $b = New-Object Windows.Controls.Border; $b.CornerRadius = 7; $b.Padding = '8,3'; $b.Margin = '0,0,6,4'; $b.Background = Get-Brush '#232742'
            $b.BorderBrush = Get-Brush $hex; $b.BorderThickness = '0,0,0,2'; $b.ToolTip = $k[2]
            $b.Child = (New-Text ('{0}  {1}' -f $k[1], $v) 10.5 $hex 'SemiBold'); [void]$wp.Children.Add($b)
        }
        [void]$sp.Children.Add($wp)
    }

    # why the campaign says what it says - THIS run's reasons only, with their source
    if ($r) {
        $rs = @(@($r.reasons) | Sort-Object { @{ REDO = 0; CHECK = 1; OK = 2 }[[string]$_.severity] })
        $sev = [string]$r.severity
        if ($sev -ne 'OK' -and $ow -eq 'PASS') {
            $x = New-Text ('The attack evidence is fine; the campaign status comes from the reason(s) below, not from the verifier''s grade.') 11.5 $Pal.Cyan
            $x.TextWrapping = 'Wrap'; $x.Margin = '0,2,0,2'; [void]$sp.Children.Add($x)
        }
        foreach ($it in @($rs | Select-Object -First 6)) {
            $s = [string]$it.severity
            $kind = switch ($s) { 'REDO' { @('REDO', $Pal.Red, '#3A1E2C') } 'CHECK' { @('CHECK', $Pal.Amber, '#3A2E14') } default { @('NOTE', $Pal.Dim, '#262A45') } }
            [void]$sp.Children.Add((New-CampNoteRow $kind[0] $kind[1] $kind[2] ('{0}  [{1}]' -f [string]$it.text, [string]$it.evidence)))
        }
        if (-not $rs.Count) { $x = New-Text 'No reason to redo: complete, verified, nothing open in the log or checklist.' 11.5 $Pal.Dim; $x.Margin = '0,2,0,0'; [void]$sp.Children.Add($x) }
        # oct. 20 2026 (user: "how to tick it - is it possible in the GUI?"): a checklist row that
        # asked for a recapture which a NEWER capture already answered gets a one-click tick
        # (tools/tick_checklist.py) - only when that newer capture's evidence is PASS
        foreach ($it in @($rs | Where-Object { [string]$_.evidence -match '^[A-D]\d+$' -and [string]$_.text -match 'newer capture exists|is DONE' })) {
            $rid = [string]$it.evidence
            $b = New-Object Windows.Controls.Button; $b.Margin = '0,6,8,0'; $b.Padding = '12,4'; $b.HorizontalAlignment = 'Left'
            if ($ow -eq 'PASS') {
                $b.Content = "Tick $rid as done in the thesis checklist"
                $b.ToolTip = "Marks $rid done in docs\deviations-limitations\THESIS-UPDATE-CHECKLIST.md with the evidence you confirm. Commit / push it so the team sees it."
                $b.Tag = @{ Rid = $rid; Cell = $C }
                $b.Add_Click({
                    param($s_)
                    $t = $s_.Tag; $c = $t.Cell
                    $note = 're-verified in the GUI on {0}: {1} / {2} / {3} / {4} - OUTCOME PASS' -f (Get-Date).ToString('MMM d'), $c.Attack, $c.Topology, $c.Location, $c.Scenario
                    if (-not $script:AutoConfirm) {
                        try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop } catch { }
                        $note = [Microsoft.VisualBasic.Interaction]::InputBox(("Mark {0} DONE in the thesis checklist?`n`nWhy it is done (evidence - edit if needed):" -f $t.Rid), "Tick $($t.Rid)", $note)
                        if (-not $note) { return }   # cancelled
                    }
                    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\tick_checklist.py', $t.Rid, '--note', $note) -State @{ Rid = $t.Rid; Key = ('{0}/{1}/{2}/{3}' -f $c.Attack, $c.Topology, $c.Location, $c.Scenario) } -OnDone {
                        param($text, $code, $st)
                        if ($code -eq 0) {
                            Set-Status ("{0} ticked in THESIS-UPDATE-CHECKLIST.md - commit / push it so the team sees it. Re-checking this run..." -f $st.Rid) $Pal.Green
                            Start-RedoList @($st.Key)
                        } else { Set-Status ("{0} NOT ticked: {1}" -f $st.Rid, ($text -split "`r?`n" | Where-Object { $_ -match '^TICK:' } | Select-Object -First 1)) $Pal.Amber }
                    }
                })
            } else {
                $b.Content = "Tick $rid - first verify the newer capture (attack evidence must be PASS)"
                $b.IsEnabled = $false
            }
            [void]$sp.Children.Add($b)
        }
    } else {
        $x = New-Text 'Campaign status not checked yet - press "Re-check the redo list" (Campaign page).' 11.5 $Pal.Amber; $x.TextWrapping = 'Wrap'; [void]$sp.Children.Add($x)
    }

    # stale / disagreeing saved report - the case that showed STRONG next to REDO
    $warn = @()
    try {
        $rf = Join-Path $script:AnaDir ('reports\' + ((Get-AnaKey $C) -replace '/', '__') + '.txt')
        if ($ReportText -and (Test-Path $rf) -and $C.AnaTime -and (Get-Item $rf).LastWriteTime -lt $C.AnaTime.AddSeconds(-5)) {
            $warn += ('This saved result was made on {0}, BEFORE the current analysis ({1}) - it may describe the previous capture of this cell. Press Verify.' -f (Get-Item $rf).LastWriteTime.ToString('MMM d h:mm tt'), $C.AnaTime.ToString('MMM d h:mm tt'))
        }
    } catch { }
    if ($saved -and $live -and [string]$live.outcome -ne '-' -and $saved.Word -ne [string]$live.outcome) {
        $warn += ('The saved report says {0}, the live re-check says {1} (newer verifier or newer data). Press Verify to update the report.' -f $saved.Word, [string]$live.outcome)
    }
    foreach ($w in $warn) { [void]$sp.Children.Add((New-CampNoteRow 'STALE' $Pal.Amber '#3A2E14' $w)) }
    if ($warn.Count) { $card.BorderBrush = Get-Brush $Pal.Amber }
    $card.Child = $sp
    return $card
}
