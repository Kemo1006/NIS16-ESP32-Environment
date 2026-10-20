# gui\ParallelFlash.ps1 - FLASH THE CHILDREN N AT A TIME (oct. 20 2026, user: "make the capturing
# faster" + "a button so the user can choose that or the normal way").
#
# The setup card's "FLASH THE CHILDREN" chips: one at a time (the normal way) / 2 at a time /
# 3 at a time (faster, default). With 2 or 3, the first child step starts a PARALLEL FLASH of
# every plugged-in child: up to N run.ps1 -FlashOnly processes at once (clock / location /
# scenario -> full erase -> esptool write of the ALREADY compiled image -> exit). Each finished
# child gets its crash watch (it keeps listening, like a child done the normal way) and its
# step turns OK. A child that fails, is not plugged in or shares a port is left for the normal
# one-at-a-time step afterwards (retry / skip as always). Then the root, as always, last.
#
# Laptop safety (BSOD 0xB8 = the CP210x driver): at most 3 boards are written at once, starts
# are 4 s apart, nothing is ever killed mid-flash (Stop waits for the boards being written),
# and run.ps1 -FlashOnly never runs idf.py / ninja nor deletes a build dir, so boards sharing
# one compiled firmware read it side by side. 'Export over USB' for children keeps the normal
# way (that export needs the per-board monitor). Dot-sourced by run_gui.ps1. ASCII only.

$script:PFlashGap = 4    # seconds between two starts

function Get-PFlashN {
    if ($SelfTest) { return 1 }
    if ($ui.RunPFlash3 -and $ui.RunPFlash3.IsChecked) { return 3 }
    if ($ui.RunPFlash2 -and $ui.RunPFlash2.IsChecked) { return 2 }
    return 1
}

function Initialize-ParallelFlashUi {
    if ($script:PFlashUiDone) { return }
    $script:PFlashUiDone = $true
    $n = 3; try { if ($script:Settings.ContainsKey('PFlash')) { $n = [int]$script:Settings.PFlash } } catch { }
    $pick = @{ 1 = $ui.RunPFlash1; 2 = $ui.RunPFlash2; 3 = $ui.RunPFlash3 }
    if ($pick[$n]) { $pick[$n].IsChecked = $true }
    foreach ($k in 1, 2, 3) {
        $rb = $pick[$k]; if (-not $rb) { continue }
        $rb.Tag = $k
        $rb.Add_Checked({ try { $script:Settings.PFlash = [int]$this.Tag; Save-Settings } catch { } })
    }
}

function Start-ParallelChildFlash($St) {
    # $true = a parallel flash started (the caller returns); $false = carry on the normal way
    $R = $script:Run
    if ($R.PSObject.Properties['PFlashDone'] -and $R.PFlashDone) { return $false }
    $N = Get-PFlashN
    if ($N -le 1) { return $false }
    if ($ui.RunChildExport.IsChecked) {
        Write-RunConsole '  flash N at a time: off for this run - "export over USB" needs each child''s own monitor' $Pal.Faint
        $R | Add-Member -NotePropertyName PFlashDone -NotePropertyValue $true -Force; return $false
    }
    $seen = @{}; $todo = @()
    foreach ($s in @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'waiting' -and $_.Board.Role -ne 'root' })) {
        $p = ([string]$s.Board.Port).ToUpper()
        if (-not $p -or -not $script:Live.Contains([string]$s.Board.Port) -or $seen.ContainsKey($p) -or $R.Used.ContainsKey([string]$s.Board.Port) -or -not $s.Plan) { continue }
        $seen[$p] = $true; $todo += $s
    }
    $R | Add-Member -NotePropertyName PFlashDone -NotePropertyValue $true -Force
    if ($todo.Count -lt 2) { return $false }
    $q = New-Object System.Collections.Queue; foreach ($s in $todo) { $q.Enqueue($s) }
    $R | Add-Member -NotePropertyName PF -NotePropertyValue ([pscustomobject]@{
        N = $N; Queue = $q; Jobs = (New-Object System.Collections.ArrayList); NextAt = (Get-Date); T0 = (Get-Date); Ok = 0; Bad = 0; Total = $todo.Count }) -Force
    $R.Current = $St; $R.Phase = 'pflash'; $R.Wait = @{ Kind = 'pflash' }
    foreach ($s in $todo) { $s.State = 'waiting'; $s.Note = 'in the parallel flash queue' }
    Set-RunState ("FLASHING {0} AT A TIME" -f $N) $Pal.Cyan
    Set-RunNow ("Flashing {0} children, {1} at a time" -f $todo.Count, $N) ("Clock set -> full erase -> flash, up to {0} boards at once. Do not unplug any board. Each child starts and is listened to as soon as it is flashed; one that fails is flashed again alone afterwards." -f $N) $Pal.Cyan ([string][char]0xE896)
    Set-RunButtons -Abort $true
    Write-RunConsole ''
    Write-RunConsole ("> Parallel flash: {0} children, {1} at a time   ({2})" -f $todo.Count, $N, (Get-Date).ToString('hh:mm:ss tt')) $Pal.Blue
    Update-RunSteps
    return $true
}

function Start-PFlashJob($St) {
    $R = $script:Run; $b = $St.Board
    Stop-CrashWatchOn ([string]$b.Port)
    $dir = Join-Path $script:RunCtlRoot ("pflash_{0}_{1}" -f ($b.Label -replace '[^\w-]', ''), (Get-Date).ToString('HHmmss'))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $h = [ordered]@{}; foreach ($k in $St.Plan.Keys) { $h[$k] = $St.Plan[$k] }
    $h.Port = [string]$b.Port; $h.FlashOnly = $true
    if ($h.Contains('GuiMonitor')) { $h.Remove('GuiMonitor') }
    $cmd = Get-RunScriptCommand $h (Join-Path $dir 'params.json')
    $full = "`$ErrorActionPreference = 'Continue'; `$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [Text.Encoding]::UTF8; Set-Location '$base'; . '$base\tools\idf_shims.ps1'; " + $cmd
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $out = Join-Path (Get-RunLogFolder) ("{0}_{1}_flash_{2}.log" -f ($b.Label -replace '[^\w-]', ''), $b.Port, (Get-Date).ToString('MMMdd_hhmmtt').ToLower())
    $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUNBUFFERED = '1'
    $p = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) -WorkingDirectory $base `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
    $null = $p.Handle
    $St.State = 'running'; $St.Note = 'erasing + flashing...'
    $R.Used[[string]$b.Port] = $b.Label
    [void]$R.PF.Jobs.Add([pscustomobject]@{ Step = $St; Proc = $p; Out = $out; Pos = [long]0; Buf = ''; T0 = (Get-Date) })
    Write-RunConsole ("  {0} on {1}: flashing  (log {2})" -f $b.Label, $b.Port, $out) $Pal.Faint
}

function Step-ParallelFlash {
    # called on every run tick while $R.Phase -eq 'pflash'
    $R = $script:Run; $pf = $R.PF; if (-not $pf) { return }
    foreach ($j in @($pf.Jobs)) {
        # the few lines worth showing: the outcome, location / scenario checks, errors
        $pos = $j.Pos; $t = Read-NewText $j.Out ([ref]$pos); $j.Pos = $pos
        if ($j.Proc.HasExited) { $t = [string]$t + "`n" }   # flush the last line
        if ($t) {
            $parts = ($j.Buf + $t) -split "`r?`n"; $j.Buf = $parts[-1]
            foreach ($ln in $(if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] } else { @() })) {
                $ln = $ln -replace "\x1b\[[0-9;]*m", ''
                if ($ln -match 'FLASH_ONLY_DONE|NOT COMPILED|FAILED|LOCATION_CHECK|SCENARIO_CHECK|Hash of data verified|A fatal error|ERROR:') { Write-RunConsole ("  {0}: {1}" -f $j.Step.Board.Label, $ln.Trim()) $(if ($ln -match 'FAIL|fatal|ERROR|NOT COMPILED') { $Pal.Amber } else { $Pal.Faint }) }
            }
        }
        if (-not $j.Proc.HasExited) { continue }
        $pf.Jobs.Remove($j)
        $st = $j.Step; $b = $st.Board; $code = $j.Proc.ExitCode
        $secs = [int]((Get-Date) - $j.T0).TotalSeconds
        if ($code -eq 0) {
            $pf.Ok++
            $st.State = 'ok'; $st.Note = "flashed in $(Format-Duration $secs) (parallel)"
            if ($ui.RunWatchKids.IsChecked) { Start-CrashWatch $st; $st.Note += ' - listening' }
            Write-RunConsole ("  {0} on {1}: flashed + started in {2}" -f $b.Label, $b.Port, (Format-Duration $secs)) $Pal.Green
        } else {
            $pf.Bad++
            $R.Used.Remove([string]$b.Port)
            $st.State = 'waiting'; $st.Note = "parallel flash failed (exit $code) - flashed alone next"
            Write-RunConsole ("  {0} on {1}: FAILED (exit {2}) - it is flashed again on its own after the others. Log: {3}" -f $b.Label, $b.Port, $code, $j.Out) $Pal.Amber
            Add-RunAlert ("{0}: parallel flash failed (exit {1}) - retried alone" -f $b.Label, $code) $Pal.Amber
        }
        Update-RunSteps
    }
    $stopping = $R.StopAfterFlash
    while (-not $stopping -and $pf.Queue.Count -and $pf.Jobs.Count -lt $pf.N -and (Get-Date) -ge $pf.NextAt) {
        Start-PFlashJob ($pf.Queue.Dequeue())
        $pf.NextAt = (Get-Date).AddSeconds($script:PFlashGap)
        Update-RunSteps
    }
    if ($pf.Jobs.Count) {
        $ui.RunNowText.Text = ("{0} of {1} flashed, {2} being written now, {3} waiting. Do not unplug any board." -f $pf.Ok, $pf.Total, $pf.Jobs.Count, $pf.Queue.Count)
        return
    }
    if ($pf.Queue.Count -and -not $stopping) { return }
    # all done (or Stop pressed and the boards being written are finished)
    $R.PF = $null; $R.Wait = $null
    $mins = Format-Duration ([int]((Get-Date) - $pf.T0).TotalSeconds)
    Write-RunConsole ("  parallel flash: {0} of {1} children flashed in {2}{3}" -f $pf.Ok, $pf.Total, $mins, $(if ($pf.Bad) { " - $($pf.Bad) failed, flashed alone next" } else { '' })) $(if ($pf.Bad) { $Pal.Amber } else { $Pal.Green })
    if ($stopping) {
        $R.StopAfterFlash = $false
        foreach ($s in @($pf.Queue)) { $s.Note = '' }
        Finish-RunStopped; return
    }
    $R.Phase = 'boards'; $R.Current = $null
    Start-RunStep ($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'waiting' } | Select-Object -First 1)
}
