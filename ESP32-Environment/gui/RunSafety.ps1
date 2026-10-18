# gui\RunSafety.ps1 - run safety nets (oct. 18 2026, "do 1 to 9"):
#   1. CRASH WATCH THAT SURVIVES - a stop no longer ends the children's watches
#      (they keep running), a new Live run takes over the old run's watches, and
#      right before the ROOT is flashed (always the last board) every other
#      plugged-in board that is not watched gets a watch. Oct. 18: a victim
#      crashed at ~7:37 PM unwatched - its watch had ended at 6:35 PM with the
#      first attempt, and the root-only re-runs never started one.
#      Any task that opens a port first takes it back from a watch (one owner).
#   4. CLEAN START BETWEEN ATTEMPTS - when the last attempt was stopped AFTER the
#      baseline began and this run re-flashes only the root, the children still
#      hold that old session in their open file (oct. 18: 742 rows of an older
#      attempt at the top of the attacker's file). Offer to restart them right
#      before the root: each watch toggles its board's reset line (no esptool,
#      ~0.1 s) and keeps listening, so the next attempt starts fresh files.
#   5. "THE GUI WAS UPDATED" - once the GUI's own files change on disk after it
#      opened, say so (restart to load them).
#   +  the page switch refreshes Analyse / Campaign only when their data changed
#      (it was hooked onto F5 by mistake).
# Dot-sourced by run_gui.ps1. ASCII only.

function Get-AliveWatches {
    $R = $script:Run; if (-not $R -or -not $R.Bg) { return @() }
    return @($R.Bg | Where-Object { $_.Proc -and -not $_.Proc.HasExited })
}

function Release-WatchedPorts($ToolArgs) {
    # the ports a task is about to open (--port X / --ports A,B) - stop their watches first
    $a = @($ToolArgs); $ports = @()
    for ($i = 0; $i -lt $a.Count - 1; $i++) {
        if ($a[$i] -eq '--port') { $ports += [string]$a[$i + 1] }
        elseif ($a[$i] -eq '--ports') { $ports += @(([string]$a[$i + 1]) -split ',' | Where-Object { $_ }) }
    }
    $alive = @(Get-AliveWatches)
    foreach ($p in ($ports | Select-Object -Unique)) {
        if (@($alive | Where-Object { ([string]$_.Port).ToUpper() -eq $p.ToUpper() }).Count) { Stop-CrashWatchOn $p }
    }
}

function Get-BoardLabelFor([string]$Port, [string]$Mac, $Plan) {
    try { $b = @($Plan.Local | Where-Object { [string]$_.Port -eq $Port }) | Select-Object -First 1; if ($b) { return [string]$b.Label } } catch { }
    $k = ($Mac -replace '[^0-9A-Fa-f]', '').ToLower()
    if ($k.Length -eq 12) {
        try { $m = (Get-MemberInfo)[($k.Substring(0, 2) + ':' + $k.Substring(10, 2))]; if ($m -and $m.Nick) { return [string]$m.Nick } } catch { }
        return ($k.Substring(0, 2) + ':' + $k.Substring(10, 2)).ToUpper()
    }
    return $Port
}

function Ensure-ChildWatches([string]$SkipPort, $Plan) {
    # a crash watch on every plugged-in board except $SkipPort (the root about to be
    # flashed), a recording sniffer and boards already watched. Returns how many started.
    if ($SelfTest) { return 0 }
    $R = $script:Run; if (-not $R) { return 0 }
    if (-not $R.Bg) { $R | Add-Member -NotePropertyName Bg -NotePropertyValue (New-Object System.Collections.ArrayList) -Force }
    $sn = @{}; try { $sn = Get-SnifferPorts } catch { }
    $watched = @(Get-AliveWatches | ForEach-Object { ([string]$_.Port).ToUpper() })
    $n = 0
    foreach ($lp in @($script:Live.Values | Where-Object { $_.Kind -eq 'BRIDGE' })) {
        $port = ([string]$lp.Port).ToUpper()
        if ($port -eq $SkipPort.ToUpper() -or $sn.ContainsKey($port) -or $watched -contains $port) { continue }
        $st = [pscustomobject]@{ Board = [pscustomobject]@{ Label = (Get-BoardLabelFor $port ([string]$lp.Mac) $Plan); Port = $port; Role = 'child' }; Plan = $Plan }
        Start-CrashWatch $st
        $n++
    }
    return $n
}

function Invoke-BeforeRootFlash($St) {
    # the root is always flashed LAST: every child is in place now
    $R = $script:Run
    $kidsFlashedHere = @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'ok' -and $_.Board.Role -ne 'root' }).Count
    $prev = [int]$(if ($null -ne $script:PrevAttemptSeg) { $script:PrevAttemptSeg } else { -1 })
    if ($ui.RunWatchKids.IsChecked) {
        $n = Ensure-ChildWatches ([string]$St.Board.Port) $St.Plan
        if ($n) { Write-RunConsole ("  crash watch: {0} more plugged-in board(s) are now listened to before the root starts" -f $n) $Pal.Faint }
    }
    # 4. the last attempt got past Phase 0 and was stopped; this run did not re-flash the children
    if ($prev -ge 1 -and -not $kidsFlashedHere -and -not $SelfTest) {
        $script:PrevAttemptSeg = -1
        $alive = @(Get-AliveWatches | Where-Object { ([string]$_.Port).ToUpper() -ne ([string]$St.Board.Port).ToUpper() })
        $phase = @('stabilise', 'baseline', 'attack', 'cooldown', 'end')[[Math]::Min(4, [Math]::Max(0, $prev))]
        if (-not $alive.Count) {
            # the usual setup: the children run on powerbanks / adapters, only the root is on USB
            [void][Windows.MessageBox]::Show(("The last attempt was stopped in its {0} phase. The children (on powerbanks / adapters) still have THAT session open in their files - this run would be appended to it.`n`nPower-cycle EVERY child now (unplug its power ~2 s, plug it back) BEFORE the root starts, so this run starts clean files.`n`nPress OK when they are back on." -f $phase), 'Clean start for the children', 'OK', 'Information')
            Write-RunConsole ("  asked to power-cycle the children by hand (the last attempt was stopped in its {0} phase)" -f $phase) $Pal.Cyan
        }
        elseif (Confirm-Action ("The last attempt was stopped in its {0} phase. The {1} children still have THAT session open in their files - the new run would be appended to it.`n`nRestart them now, right before the root, so this run starts clean files?`n`n(Recommended. Each board restarts in ~2 s and is still watched; its old, abandoned file closes as ABORTED.)" -f $phase, $alive.Count) 'Clean start for the children') {
            foreach ($w in $alive) { try { Set-Content -Path (Join-Path $w.Ctl 'reset') -Value 'reset' -ErrorAction Stop } catch { } }
            Write-RunConsole ("  restarted {0} child board(s) for a clean start: {1}" -f $alive.Count, ((@($alive | ForEach-Object Label)) -join ', ')) $Pal.Cyan
            Add-RunAlert ("{0} children restarted for a clean start (the last attempt was stopped in its {1} phase)" -f $alive.Count, $phase) $Pal.Cyan
        }
    }
}

# -- 5. the GUI's own files changed after it opened ---------------------------
function Get-GuiFilesStamp {
    $t = 0L
    $files = @((Join-Path $base 'run_gui.ps1'), (Join-Path $base 'tools\ImportBatch.ps1'), (Join-Path $base 'tools\Show-MemberBoards.ps1')) +
             @([IO.Directory]::GetFiles((Join-Path $base 'gui'), '*.ps1'))
    foreach ($f in $files) { if ([IO.File]::Exists($f)) { $w = [IO.File]::GetLastWriteTimeUtc($f).Ticks; if ($w -gt $t) { $t = $w } } }
    return $t
}

function Test-GuiUpdated {
    if ($script:GuiUpdateSaid -or -not $script:GuiStamp -or $SelfTest) { return }
    if ((Get-GuiFilesStamp) -le $script:GuiStamp) { return }
    $script:GuiUpdateSaid = $true
    try { $win.Title = $win.Title + '   (updated on disk - restart to load it)' } catch { }
    Set-Status 'The GUI was updated on disk after you opened it - close it and open it again to load the new version.' $Pal.Amber
    Show-Toast 'GUI updated' 'Close and reopen the GUI to load the new version (a run in progress is not affected).' ([string][char]0xE777) 'GradCool'
}

function Initialize-GuiRunSafety {
    $script:GuiStamp = Get-GuiFilesStamp
    # page switch: refresh only what changed (Analyse = data stamps, Campaign = changed runs), and the update check
    $ui.Pages.Add_SelectionChanged({
        param($s, $e)
        if ($e.OriginalSource -ne $ui.Pages) { return }
        Test-GuiUpdated
        switch ($ui.Pages.SelectedIndex) {
            2 { if (Test-PageStale 'analyse') { try { Update-Cells } catch { } } }
            3 { try { Update-RedoIfChanged } catch { } }
        }
    })
    # a button for boards flashed earlier / elsewhere: watch them now
    $chk = $ui.RunWatchKids
    if ($chk -and ($chk.Parent -is [Windows.Controls.Panel])) {
        $b = New-Object Windows.Controls.Button; $b.Content = 'Watch every plugged-in board now'; $b.Margin = '8,0,0,0'; $b.Padding = '10,4'
        $b.ToolTip = 'Starts a crash watch on every plugged-in board that has none (not the sniffer). Use it when boards were flashed in an earlier run or by the CLI.'
        $b.Add_Click({
            if (-not $script:Run) { [void][Windows.MessageBox]::Show('Open a run on the Live run page first (its log folder keeps the watch logs).', 'Crash watch'); return }
            # the board the Live run is flashing / monitoring / exporting right now keeps its port
            $busy = if ($script:Run.Current -and $script:Run.Current.Board -and $script:Run.Phase -in @('flash', 'monitor', 'export')) { [string]$script:Run.Current.Board.Port } else { '' }
            $n = Ensure-ChildWatches $busy $script:Run.Plan
            Set-Status ("Crash watch: {0} board(s) added ({1} watched in all)." -f $n, @(Get-AliveWatches).Count) $Pal.Green
        })
        $chk.Parent.Children.Insert($chk.Parent.Children.IndexOf($chk) + 1, $b)
    }
}

# -- [HEALTH] LOW lines (components/mesh_common/src/health_log.c) -> one alert per board per 5 min
function Read-HealthLine([string]$Label, [string]$Line) {
    if ($Line -notmatch '\[HEALTH\] (LOW (?:HEAP|STACK).+)$') { return }
    $what = $Matches[1].Trim()
    if (-not $script:HealthSaid) { $script:HealthSaid = @{} }
    $last = $script:HealthSaid[$Label]
    if ($last -and ((Get-Date) - $last).TotalMinutes -lt 5) { return }
    $script:HealthSaid[$Label] = Get-Date
    Add-RunAlert ("{0}: {1}" -f $Label, $what) $Pal.Amber
    Write-RunConsole ("  [HEALTH] {0}: {1}" -f $Label, $what) $Pal.Amber
}

# -- the root is not in this preset (oct. 18 2026) ------------------------------
function Get-RootElsewhereNote($P, [string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario, [int]$NKids) {
    # The usual setup: children flashed from one preset, the ROOT from its own preset
    # on THIS laptop, LAST. Name that preset when it exists; else the root's laptop.
    $na = if ($Attack -in @('none', 'baseline')) { 'baseline' } else { $Attack }
    $t = $Topology -replace '^partial$', 'partial_mesh'
    $live = @{}; foreach ($l in @($script:Live.Values)) { if ($l.Mac) { $live[(([string]$l.Mac) -replace '[^0-9A-Fa-f]', '').ToLower()] = [string]$l.Port } }
    $cands = @($script:Presets | Where-Object {
            $_.Path -ne $P.Path -and ($(if ($_.Attack -in @('none', 'baseline')) { 'baseline' } else { $_.Attack })) -eq $na -and
            ($_.Topology -replace '^partial$', 'partial_mesh') -eq $t -and $_.Location -eq $Location -and $_.Scenario -eq $Scenario -and
            @($_.Cfg.boards | Where-Object { $_.Role -eq 'root' -or $_.Kind -eq 'root' }).Count } |
        Sort-Object @{ E = { $_.Owner -ne $script:Me } }, @{ E = { $_.Saved }; Descending = $true })
    foreach ($c in $cands) {
        $rb = @($c.Cfg.boards | Where-Object { $_.Role -eq 'root' -or $_.Kind -eq 'root' }) | Select-Object -First 1
        $port = $live[(([string]$rb.Mac) -replace '[^0-9A-Fa-f]', '').ToLower()]
        $here = if ($port) { " - the root is plugged in here on $port" } else { '' }
        return ("The ROOT is not in this preset: it is in {0} [{1}]{2}. Order: flash these {3} children FIRST, then run that root preset LAST - the root waits for every child, and START is pressed on the root's dashboard." -f $c.File, $c.Owner, $here, $NKids)
    }
    return ("The ROOT is not in this preset (no root preset for this run on this laptop). Flash these {0} children FIRST; the root goes LAST - from its own preset here, or on the root's laptop with your {0} children counted under 'children on other laptops'. START is pressed where the root runs." -f $NKids)
}
