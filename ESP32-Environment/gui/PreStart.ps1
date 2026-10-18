# gui\PreStart.ps1 - a pre-START checklist on the Live run's START gate card
# (oct. 18 2026). Everything is read from what the boards already print - no
# extra serial traffic:
#   children in            root: "[CTRL] READY: 7/7 children" / "WAITING: 5/7"
#   location               each board's boot report "Recorded location: X"
#   real clock             "SD_STATUS: clock: set from the card's host anchor"
#   firmware built         "Firmware built: <stamp>" (information - every board here was flashed by this run)
#   attacker MAC           blackhole victims: "Attacker MAC from NVS|compiled default: <mac>"
#   wormhole set up        root: "OK: A (exit) at H.., B (entry) at H.."
#   time in stabilise      from "[CTRL] Waiting N s for mesh to stabilise" until Phase 0 -
#                          the stabilise phase lasts until START, so its length
#                          differs per run (thesis checklist A25); logged to the run log.
# START asks before sending when a check FAILED (not when it is just unknown -
# a board flashed on another laptop is never seen here). The root's own gates
# still apply. Dot-sourced by run_gui.ps1. ASCII only.

function Reset-PreStart {
    $script:Pre = @{ Boards = @{}; Kids = ''; KidsOk = $null; Wh = $null; WhText = ''; StabAt = $null; Phase0At = $null; ClockText = '' }
    try { Reset-TopoWatch } catch { }     # gui\TopoWatch.ps1
    if ($script:PrePanel) { $script:PrePanel.Visibility = 'Visible'; Update-PreStartPanel }
}

function Get-PreBoard([string]$Label) {
    if (-not $script:Pre) { Reset-PreStart }
    $b = $script:Pre.Boards[$Label]
    if (-not $b) { $b = @{ Loc = $null; Clock = $null; Built = $null; AttMac = $null }; $script:Pre.Boards[$Label] = $b }
    return $b
}

function Read-PreStartLine($Board, [string]$Line) {
    if (-not $Board -or -not $Line) { return }
    if (-not $script:Pre) { Reset-PreStart }
    $P = $script:Pre; $lab = [string]$Board.Label; $changed = $false
    if ($Line -match 'Recorded location: (\S+)') { $v = $Matches[1]; (Get-PreBoard $lab).Loc = $v; $changed = $true; if ($Board.Mac) { Set-CardLoc ([string]$Board.Mac) $v 'its boot report' } }
    elseif ($Line -match 'SD_STATUS: clock: set from') { (Get-PreBoard $lab).Clock = 'host'; $changed = $true }
    elseif ($Line -match '\(clock: (\w+)\)') { (Get-PreBoard $lab).Clock = $Matches[1]; $changed = $true }
    elseif ($Line -match 'SD_STATUS: clock: .*(build-stamp|BUILD-TIME|ESTIMATE)') { $pb = Get-PreBoard $lab; if ($pb.Clock -ne 'host') { $pb.Clock = 'build' }; $changed = $true }
    elseif ($Line -match 'Firmware built: (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { try { (Get-PreBoard $lab).Built = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { }; $changed = $true }
    elseif ($Line -match 'Attacker MAC from (?:NVS|compiled default): ([0-9A-Fa-f:]{17})') { (Get-PreBoard $lab).AttMac = $Matches[1].ToLower(); $changed = $true }
    if ($Line -match '^ARCHIVED: (.+)$') {
        # run.ps1 archived the OLD capture of this run (same repeat) after the root's new export
        Add-RunAlert ('Re-capture: the older capture of this run was archived ({0}) - this run replaces it' -f $Matches[1]) $Pal.Cyan
        # its verdict went to the archive too - forget it here, or the next Verify writes it back
        try {
            $pl = $script:Run.Plan
            $k = '{0}/{1}/{2}/{3}' -f $(if ($pl.Attack -in @('none', 'baseline')) { 'baseline' } else { $pl.Attack }), ($pl.Topology -replace '^partial$', 'partial_mesh'), $pl.Location, $pl.Scenario
            if ($script:Verdicts -and $script:Verdicts.ContainsKey($k)) { [void]$script:Verdicts.Remove($k) }
        } catch { }
    }
    if ($Board.Role -eq 'root') {
        try { Read-TopoWatchLine $Line } catch { }     # layout watch during baseline / attack
        try { Read-PlacementLine $Line } catch { }     # tree + blackhole: who to move under the attacker
        if ($Line -match 'TOPOLOGY TREE|n/a = no parent') { $changed = $true }   # the root's table just ended: weak links may have changed
        if ($Line -match '\[CTRL\] Waiting \d+ s for mesh to stabilise') { $P.StabAt = Get-Date; $P.Phase0At = $null; $changed = $true }
        elseif ($Line -match '\[CTRL\] (?:READY|WAITING): (\d+)/(\d+) children') { $P.Kids = "$($Matches[1])/$($Matches[2])"; $P.KidsOk = ([int]$Matches[1] -ge [int]$Matches[2]); $changed = $true }
        elseif ($Line -match 'OK: A \(exit\) at (H\d+), B \(entry\) at (H\d+)') { $P.Wh = $true; $P.WhText = "A at $($Matches[1]), B at $($Matches[2])"; $changed = $true }
        elseif ($Line -match 'WORMHOLE is not set up: (.+?)\. Phase 0 waits') { $P.Wh = $false; $P.WhText = $Matches[1]; $changed = $true }
        elseif ($Line -match '\u2550{4,}\s*PHASE 0 \u2014' -and $P.StabAt -and -not $P.Phase0At) {
            $P.Phase0At = Get-Date
            $s = [int]($P.Phase0At - $P.StabAt).TotalSeconds
            Write-RunConsole ("Stabilise (phase 255) lasted {0}:{1:00} - from the root's first PREPARE to START (60 s fixed + the wait for you)." -f [int][Math]::Floor($s / 60), ($s % 60)) $Pal.Cyan
            if ($script:PrePanel) { $script:PrePanel.Visibility = 'Collapsed' }
            $changed = $false
        }
    }
    if ($changed) { Update-PreStartPanel }
}

function Get-PreStartChecks {
    # @( @{ Name; State = ok|bad|wait|na; Text } )
    $P = $script:Pre; $R = $script:Run
    if (-not $P -or -not $R -or -not $R.Plan) { return @() }
    $out = @()
    $out += @{ Name = 'Children in'; State = $(if ($null -eq $P.KidsOk) { 'wait' } elseif ($P.KidsOk) { 'ok' } else { 'bad' }); Text = $(if ($P.Kids) { $P.Kids + ' (root)' } else { 'waiting for the root' }) }
    $want = [string]$R.Plan.Location
    $seen = @($P.Boards.Keys | Where-Object { $P.Boards[$_].Loc })
    $badLoc = @($seen | Where-Object { $P.Boards[$_].Loc -ne $want } | ForEach-Object { "$_ ($($P.Boards[$_].Loc))" })
    $out += @{ Name = 'Location = ' + $want; State = $(if (-not $seen.Count) { 'wait' } elseif ($badLoc.Count) { 'bad' } else { 'ok' })
               Text = $(if ($badLoc.Count) { 'WRONG on ' + ($badLoc -join ', ') + ' - power-cycle after the fix' } elseif ($seen.Count) { "$($seen.Count) board(s) read" } else { 'no boot report seen yet' }) }
    $ck = @($P.Boards.Keys | Where-Object { $P.Boards[$_].Clock })
    $est = @($ck | Where-Object { $P.Boards[$_].Clock -ne 'host' })
    $out += @{ Name = 'Real clock'; State = $(if (-not $ck.Count) { 'wait' } elseif ($est.Count) { 'bad' } else { 'ok' })
               Text = $(if ($est.Count) { 'build-time ESTIMATE on ' + ($est -join ', ') } elseif ($ck.Count) { "$($ck.Count) board(s) on the laptop's clock" } else { '-' }) }
    # information only (no START prompt): every board seen here was flashed by THIS
    # run, and a variant that did not need recompiling keeps its older build time
    $bt = @($P.Boards.Keys | Where-Object { $P.Boards[$_].Built })
    if ($bt.Count) {
        $times = @($bt | ForEach-Object { $P.Boards[$_].Built } | Sort-Object)
        $span = if ($times.Count -gt 1 -and ($times[-1] - $times[0]).TotalMinutes -ge 1) { '{0} to {1}' -f $times[0].ToString('MMM dd HH:mm'), $times[-1].ToString('MMM dd HH:mm') } else { $times[-1].ToString('MMM dd HH:mm') }
        $out += @{ Name = 'Firmware built'; State = 'ok'; Text = "$($bt.Count) board(s), $span" }
    } else { $out += @{ Name = 'Firmware built'; State = 'wait'; Text = '-' } }
    # a weak link is the one that re-parents mid-run - move it BEFORE START
    $weak = @(); try { $weak = @(Get-WeakLinks) } catch { }
    $hasTable = $script:Dash -and $script:Dash.Rows -and $script:Dash.Rows.Count
    $out += @{ Name = 'Links strong enough'; State = $(if (-not $hasTable) { 'wait' } elseif ($weak.Count) { 'bad' } else { 'ok' })
               Text = $(if ($weak.Count) { 'weak: ' + ($weak -join ', ') + ' - may change parent mid-run: move it closer BEFORE START' } elseif ($hasTable) { 'every child above -80 dBm to its parent' } else { 'waiting for the root''s table' }) }
    if ($R.Plan.Attack -eq 'blackhole' -and ($R.Plan.Topology -in @('tree', 'partial', 'partial_mesh'))) {
        $ac = $null; try { $ac = Get-AttackerChildState } catch { }
        $out += @{ Name = 'Attacker has a child'; State = $(if (-not $ac) { 'wait' } elseif ($ac.Kids) { 'ok' } else { 'bad' })
                   Text = $(if (-not $ac) { 'waiting for the root''s tree' } elseif ($ac.Kids) { "$($ac.Kids) board(s) under the attacker" } else { 'NONE - the attack would drop nothing. ' + (Get-PlacementAdvice) }) }
    }
    if ($R.Plan.Attack -eq 'blackhole') {
        $am = ([string]$R.Plan.AttackerMac).ToLower()
        $vs = @($P.Boards.Keys | Where-Object { $P.Boards[$_].AttMac })
        $wrong = @($vs | Where-Object { $am -and $P.Boards[$_].AttMac -ne $am })
        $out += @{ Name = 'Attacker MAC on victims'; State = $(if (-not $vs.Count -or -not $am) { 'wait' } elseif ($wrong.Count) { 'bad' } else { 'ok' })
                   Text = $(if ($wrong.Count) { 'other target on ' + ($wrong -join ', ') + " (want $am)" } elseif ($vs.Count) { "$($vs.Count) victim(s) target $am" } else { 'no victim boot seen yet' }) }
    }
    if ($R.Plan.Attack -eq 'wormhole') {
        $out += @{ Name = 'Wormhole set up'; State = $(if ($null -eq $P.Wh) { 'wait' } elseif ($P.Wh) { 'ok' } else { 'bad' }); Text = $(if ($P.WhText) { $P.WhText } else { 'waiting for the root' }) }
    }
    return $out
}

function Update-PreStartPanel {
    $sp = $script:PreRows; if (-not $sp) { return }
    $sp.Children.Clear()
    foreach ($c in @(Get-PreStartChecks)) {
        $hex = switch ($c.State) { 'ok' { $Pal.Green } 'bad' { $Pal.Red } default { $Pal.Faint } }
        $g = switch ($c.State) { 'ok' { [string][char]0x2714 } 'bad' { [string][char]0x2716 } default { [string][char]0x2026 } }
        $tb = New-Object Windows.Controls.TextBlock; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,1,0,1'; $tb.FontSize = 12
        $r1 = New-Object Windows.Documents.Run ($g + '  '); $r1.Foreground = Get-Brush $hex; $r1.FontWeight = 'Bold'; [void]$tb.Inlines.Add($r1)
        $r2 = New-Object Windows.Documents.Run ($c.Name + '   '); $r2.Foreground = Get-Brush $Pal.Text; [void]$tb.Inlines.Add($r2)
        $r3 = New-Object Windows.Documents.Run ([string]$c.Text); $r3.Foreground = Get-Brush $(if ($c.State -eq 'bad') { $Pal.Red } else { $Pal.Dim }); [void]$tb.Inlines.Add($r3)
        [void]$sp.Children.Add($tb)
    }
}

function Update-PreStartClock {
    # from the Live run's 250 ms heartbeat: only a text change, once a second at most
    $P = $script:Pre; $t = $script:PreClock
    if (-not $P -or -not $t -or -not $P.StabAt -or $P.Phase0At) { return }
    $s = [int]((Get-Date) - $P.StabAt).TotalSeconds
    $txt = 'in stabilise (phase 255) for {0}:{1:00} - it lasts until START' -f [int][Math]::Floor($s / 60), ($s % 60)
    if ($t.Text -ne $txt) { $t.Text = $txt }
}

function Confirm-PreStart {
    # $true = send START. Asks only when a check FAILED.
    $bad = @(Get-PreStartChecks | Where-Object { $_.State -eq 'bad' })
    if (-not $bad.Count) { return $true }
    $list = ($bad | ForEach-Object { '    x  ' + $_.Name + ':  ' + $_.Text }) -join "`n"
    return (Confirm-Action ("These pre-START checks did NOT pass:`n`n$list`n`nFix them first (the data of this run would carry it), or send START anyway?") 'Start with a failed check?')
}

function Initialize-GuiPreStart {
    # the checklist goes into the START gate card, above the START button
    $card = $ui.RunGateCard; if (-not $card -or -not ($card.Child -is [Windows.Controls.Panel])) { return }
    $box = New-Object Windows.Controls.Border; $box.CornerRadius = 10; $box.Padding = '12,8'; $box.Margin = '0,10,0,0'
    $box.Background = Get-Brush $Pal.Card2
    $sp = New-Object Windows.Controls.StackPanel
    $h = New-Object Windows.Controls.TextBlock; $h.Text = 'PRE-START CHECKS  (from what the boards printed)'; $h.FontSize = 10; $h.FontWeight = 'SemiBold'; $h.Foreground = Get-Brush $Pal.Faint
    [void]$sp.Children.Add($h)
    $clock = New-Object Windows.Controls.TextBlock; $clock.FontSize = 11.5; $clock.Foreground = Get-Brush $Pal.Cyan; $clock.Margin = '0,3,0,3'
    [void]$sp.Children.Add($clock)
    $rows = New-Object Windows.Controls.StackPanel; [void]$sp.Children.Add($rows)
    $box.Child = $sp
    $card.Child.Children.Insert([Math]::Min(1, $card.Child.Children.Count), $box)
    $script:PrePanel = $box; $script:PreRows = $rows; $script:PreClock = $clock
    Reset-PreStart
}
