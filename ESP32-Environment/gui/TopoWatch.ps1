# gui\TopoWatch.ps1 - layout watch during the capture (oct. 18 2026).
# User: "what should I do if it suddenly changes position / parent during the
# baseline or attack phase?" The firmware cannot pin a parent, so the GUI:
#   PREVENTS what it can - a pre-START check for WEAK links (a child below
#     -80 dBm to its parent is the one that re-parents mid-run): move it closer
#     BEFORE START (gui\PreStart.ps1 reads Get-WeakLinks).
#   DETECTS the rest - the root prints its tree ("[H02] CHILD aa:bb..",
#     indented under its parent). The tree at Phase 0 is the run's layout; each
#     later tree in BASELINE or ATTACK is compared with it. A board that moved,
#     left or came back raises an alert (+ a line in the run log, so the
#     verification sees it). Going back to its Phase 0 parent clears it.
#   ADVISES - see Get-TopoAdvice: let the run finish, then recapture.
# Fed from Read-PreStartLine (root lines only). Dot-sourced by run_gui.ps1. ASCII only.

function Reset-TopoWatch {
    $script:TopoRef = $null; $script:TopoCur = $null; $script:TopoLast = @{}; $script:TopoState = @{}; $script:TopoChanges = 0
}

function Get-TopoAdvice {
    $t = ''; try { $t = [string]$script:Run.Plan.Topology } catch { }
    if ($t -in @('tree', 'partial', 'partial_mesh')) { return 'Let the run finish (stopping saves no time), then RECAPTURE it - a tree run whose layout changed during the capture fails the re-routing check.' }
    if ($t -eq 'linear') { return 'A chain that re-links skips or adds a hop: let it finish, then recapture.' }
    return 'Let the run finish; if the board left the mesh, recapture it.'
}

function Get-TopoName([string]$Mac) {
    # the run's label for a MAC (node4), else the short MAC
    $k = ($Mac -replace '[^0-9A-Fa-f]', '').ToLower()
    try { foreach ($b in @($script:Run.Plan.Full)) { if ((([string]$b.Mac) -replace '[^0-9A-Fa-f]', '').ToLower() -eq $k -and $b.Label) { return [string]$b.Label } } } catch { }
    return $(if ($k.Length -eq 12) { ($k.Substring(0, 2) + ':' + $k.Substring(10, 2)).ToUpper() } else { $Mac })
}

function Read-TopoWatchLine([string]$Line) {
    if (-not $script:TopoLast) { Reset-TopoWatch }
    $m = [regex]::Match($Line, '\[H(?<h>\d+)\]\s+(?<role>[A-Z_]+)\s+(?<mac>(?:[0-9A-F]{2}:){5}[0-9A-F]{2})')
    if ($m.Success) {
        $h = [int]$m.Groups['h'].Value; $mac = $m.Groups['mac'].Value
        if ($h -eq 0) { Complete-TopoTree; $script:TopoCur = @{}; $script:TopoLast = @{ 0 = $mac }; return }
        if ($null -eq $script:TopoCur) { return }
        $script:TopoCur[$mac] = @{ Hop = $h; Parent = [string]$script:TopoLast[$h - 1]; Role = $m.Groups['role'].Value }
        $script:TopoLast[$h] = $mac
        return
    }
    if ($null -ne $script:TopoCur -and $script:TopoCur.Count) { Complete-TopoTree }
}

function Complete-TopoTree {
    $cur = $script:TopoCur; $script:TopoCur = $null
    if (-not $cur -or -not $cur.Count) { return }
    $script:TopoLatest = $cur                                      # the newest tree, any phase (placement helper)
    $seg = if ($script:Dash) { [int]$script:Dash.Seg } else { -1 }
    if ($seg -lt 1) { return }                                     # stabilise: mesh FORMATION, not re-routing
    if (-not $script:TopoRef) {
        $script:TopoRef = $cur
        foreach ($k in $cur.Keys) { $script:TopoState[$k] = $cur[$k].Parent }
        Write-RunConsole ("Layout at Phase 0 recorded ({0} children) - any move during baseline / attack is reported." -f $cur.Count) $Pal.Faint
        return
    }
    if ($seg -gt 2) { return }                                     # cooldown / end: no longer the capture
    $phase = if ($seg -eq 1) { 'BASELINE' } else { 'ATTACK' }
    foreach ($k in @($script:TopoRef.Keys)) {
        $ref = $script:TopoRef[$k]; $now = $cur[$k]
        $was = $script:TopoState[$k]
        $is = if ($now) { $now.Parent } else { '(gone)' }
        if ($is -eq $was) { continue }
        $script:TopoState[$k] = $is
        $who = Get-TopoName $k
        if ($is -eq $ref.Parent) {
            Add-RunAlert ("{0}: back under its Phase 0 parent {1} (H{2:00})" -f $who, (Get-TopoName $ref.Parent), $ref.Hop) $Pal.Green
            Write-RunConsole ("[layout] {0} back under {1} during {2}" -f $who, (Get-TopoName $ref.Parent), $phase.ToLower()) $Pal.Green
            continue
        }
        $script:TopoChanges++
        $txt = if (-not $now) { "{0}: LEFT the mesh during {1} (was H{2:00} under {3}). {4}" -f $who, $phase, $ref.Hop, (Get-TopoName $ref.Parent), (Get-TopoAdvice) }
               else { "{0}: parent changed during {1}: {2} (H{3:00}) -> {4} (H{5:00}). {6}" -f $who, $phase, (Get-TopoName $ref.Parent), $ref.Hop, (Get-TopoName $now.Parent), $now.Hop, (Get-TopoAdvice) }
        Add-RunAlert $txt $Pal.Red
        Write-RunConsole ("[layout] " + $txt) $Pal.Red
    }
    foreach ($k in @($cur.Keys | Where-Object { -not $script:TopoRef.ContainsKey($_) -and -not $script:TopoState.ContainsKey($_) })) {
        $script:TopoState[$k] = $cur[$k].Parent
        Add-RunAlert ("{0}: JOINED during {1} under {2} (H{3:00}) - it was not in the Phase 0 layout" -f (Get-TopoName $k), $phase, (Get-TopoName $cur[$k].Parent), $cur[$k].Hop) $Pal.Amber
    }
}

function Get-WeakLinks {
    # children whose link to their parent is weak right now (root's table, RSSI < -80 dBm)
    $D = $script:Dash; if (-not $D -or -not $D.Rows) { return @() }
    return @($D.Rows | Where-Object { $_.Rssi -match '^-?\d+$' -and [int]$_.Rssi -lt -80 -and [string]$_.Role -notmatch 'ROOT' } |
             ForEach-Object { '{0} ({1} dBm)' -f (Get-TopoName ([string]$_.Mac)), $_.Rssi })
}

# -- placement helper (oct. 18 2026, item 7) ------------------------------------
# Tree + blackhole needs a child UNDER the attacker, or the attack drops nothing
# and the root's gate holds Phase 0 ("ATTACKER has 0 children"). Say WHICH board
# to move: the child sitting directly on the root with the weakest link to it
# (the easiest one to pull under the attacker).

function Get-AttackerChildState {
    # $null = no tree seen yet; else @{ Attacker; Hop; Kids }
    $t = $script:TopoLatest; if (-not $t) { return $null }
    $atk = @($t.Keys | Where-Object { $t[$_].Role -eq 'BLACKHOLE' }) | Select-Object -First 1
    if (-not $atk) { return $null }
    $kids = @($t.Keys | Where-Object { $t[$_].Parent -eq $atk })
    return @{ Attacker = $atk; Hop = $t[$atk].Hop; Kids = $kids.Count }
}

function Get-PlacementAdvice {
    $st = Get-AttackerChildState; if (-not $st -or $st.Kids) { return '' }
    $t = $script:TopoLatest
    $rssi = @{}; try { foreach ($r in @($script:Dash.Rows)) { $rssi[([string]$r.Mac).ToUpper()] = $r.Rssi } } catch { }
    $cand = @($t.Keys | Where-Object { $_ -ne $st.Attacker -and $t[$_].Role -ne 'ROOT' -and $t[$_].Hop -le $st.Hop } |
              Sort-Object @{ E = { $v = $rssi[$_]; if ("$v" -match '^-?\d+$') { [int]$v } else { 0 } } })
    $who = Get-TopoName $st.Attacker
    if (-not $cand.Count) { return "the attacker $who has no child - move it CLOSER to the root and power-cycle one child placed beyond it" }
    $c = $cand[0]; $r = $rssi[$c]
    return ("the attacker {0} (H{1:00}) has no child. Move {2} (H{3:00}{4}) next to the attacker, a bit FARTHER from the root than the attacker, then power-cycle {2} so it re-joins UNDER the attacker. Or move the attacker closer to the root." -f
            $who, $st.Hop, (Get-TopoName $c), $t[$c].Hop, $(if ("$r" -match '^-?\d+$') { ", $r dBm to its parent - the weakest" } else { '' }))
}

function Read-PlacementLine([string]$Line) {
    if ($Line -notmatch 'ATTACKER has 0 children') { return }
    if ($script:PlacementSaidAt -and ((Get-Date) - $script:PlacementSaidAt).TotalSeconds -lt 60) { return }
    $script:PlacementSaidAt = Get-Date
    $adv = Get-PlacementAdvice
    Add-RunAlert ('Placement: ' + $(if ($adv) { $adv } else { 'the attacker has no child yet - power-cycle ONE child near it (not the attacker) so it re-joins under it' })) $Pal.Amber
}
