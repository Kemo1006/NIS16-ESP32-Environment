# gui\StopBoards.ps1 - Boards page: "Stop selected board" / "Stop all boards".
# oct. 19 2026 (user): "sometimes I can't find where a board is running" - a
# monitor / flash / capture console left open somewhere keeps the COM port busy
# ("COM3 is currently running"). These buttons find EVERY process that has the
# port on its command line (this window's crash watches included), say what each
# one is, and stop them after one confirmation. Export / SD reads get a second,
# louder warning: killing those mid-read is the BSOD 0xB8 case (STATUS.md).
# Dot-sourced by run_gui.ps1 (functions only). ASCII only.

function Get-PortProcesses([string]$Port) {
    # @( @{ Pid; What; Danger } ) - other processes whose command line names $Port
    $P = $Port.ToUpper(); $out = @()
    # COM3 must not match COM30: the port has to be a whole token
    $rx = '(?i)(^|[\s"=,])' + [regex]::Escape($P) + '([\s",]|$)'
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='py.exe' OR Name='powershell.exe' OR Name='pwsh.exe' OR Name='esptool.exe'" -ErrorAction Stop |
                   Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $rx })
    } catch { return @() }
    $ids = @($procs | ForEach-Object { $_.ProcessId })
    foreach ($h in $procs) {
        # a python child of a matched console dies with it (taskkill /T) - list the console only
        if ($ids -contains $h.ParentProcessId) { continue }
        # started by THIS window (Live run step, crash watch): stopped the GUI's own way, not here
        if ($h.ParentProcessId -eq $PID) { continue }
        # an export / SD read running INSIDE a console makes the console dangerous too
        $kids = @($procs | Where-Object { $_.ParentProcessId -eq $h.ProcessId })
        $c = [string]$h.CommandLine + ' ' + (($kids | ForEach-Object { [string]$_.CommandLine }) -join ' ')
        $what = switch -Regex ($c) {
            '(?i)export_logs\.py'             { 'an EXPORT (export_logs.py)'; break }
            '(?i)import_sdcard\.py'           { 'an SD card read (import_sdcard.py)'; break }
            '(?i)gui_monitor\.py'             { 'a GUI board monitor / crash watch (gui_monitor.py)'; break }
            '(?i)idf\.py.*monitor|idf_monitor' { 'idf.py monitor'; break }
            '(?i)esptool|idf\.py.*flash'      { 'a flash / MAC read (esptool)'; break }
            '(?i)sniff\.py'                   { 'the sniffer'; break }
            '(?i)run_wizard|menu\.ps1'        { 'the CLI wizard'; break }
            '(?i)run\.ps1'                    { 'a capture console (run.ps1)'; break }
            default                           { [string]$h.Name }
        }
        $out += @{ Pid = [int]$h.ProcessId; What = $what; Danger = ($c -match '(?i)export_logs\.py|import_sdcard\.py') }
    }
    return $out
}

function Stop-BoardPorts([string[]]$Ports) {
    $Ports = @($Ports | Where-Object { $_ -match '^(?i)COM\d+$' } | ForEach-Object { $_.ToUpper() } | Select-Object -Unique)
    if (-not $Ports.Count) { [void][Windows.MessageBox]::Show('No board port to stop.', 'Stop boards'); return }

    # this window's own users of the ports
    $R = $script:Run; $liveStep = $null
    if ($R -and $R.Active -and $R.Current -and $R.Current.Board -and ([string]$R.Current.Board.Port).ToUpper() -in $Ports) { $liveStep = $R.Current.Board }
    $watches = @(); try { $watches = @(Get-AliveWatches | Where-Object { ([string]$_.Port).ToUpper() -in $Ports }) } catch { }

    $found = @()
    foreach ($p in $Ports) { foreach ($x in @(Get-PortProcesses $p)) { $x.Port = $p; $found += $x } }
    $found = @($found | Sort-Object { $_.Pid } -Unique)

    if (-not $found.Count -and -not $watches.Count -and -not $liveStep) {
        Set-Status ("Nothing is using {0} - free." -f ($Ports -join ', ')) $Pal.Green
        Write-Activity ("Stop boards: nothing is using {0}." -f ($Ports -join ', ')) $Pal.Green
        return
    }

    $lines = @()
    foreach ($w in $watches) { $lines += ("  {0}: this window's crash watch on {1}" -f $w.Port, $w.Label) }
    foreach ($x in $found)   { $lines += ("  {0}: {1}  (PID {2})" -f $x.Port, $x.What, $x.Pid) }
    if ($liveStep) { $lines += ("  {0}: the Live run's current step ({1}) - NOT stopped here, press Stop on the Live run page" -f $liveStep.Port, $liveStep.Label) }

    $msg = "Stop everything using {0}?`n`n{1}`n`nA monitor or flash that is stopped just ends; flash the board again if a flash was cut." -f ($Ports -join ', '), ($lines -join "`n")
    if (-not (Confirm-Action $msg 'Stop boards')) { Set-Status 'Stop boards: cancelled.'; return }

    $danger = @($found | Where-Object { $_.Danger })
    if ($danger.Count) {
        $d = "!! {0} is reading a board's SD card / exporting right now.`n`nKilling it mid-read can crash Windows (BSOD 0xB8) and can leave the card half-read.`n`nSafer: let it finish. Kill it anyway?" -f (($danger | ForEach-Object { "$($_.What) on $($_.Port)" }) -join ', ')
        if (-not (Confirm-Action $d 'Export / SD read in progress')) {
            $found = @($found | Where-Object { -not $_.Danger })
            Write-Activity 'Stop boards: export / SD read left running (your choice).' $Pal.Amber
        }
    }

    foreach ($w in $watches) { try { Stop-CrashWatchOn ([string]$w.Port); Write-Activity ("Stopped the crash watch on {0} ({1})." -f $w.Port, $w.Label) $Pal.Cyan } catch { } }
    foreach ($x in $found) {
        # /T: the console's python / idf_monitor children go with it
        $o = & taskkill.exe /PID $x.Pid /T /F 2>&1
        $ok = ($LASTEXITCODE -eq 0)
        Write-Activity ("{0} {1} on {2} (PID {3}){4}" -f $(if ($ok) { 'Stopped' } else { 'Could not stop' }), $x.What, $x.Port, $x.Pid, $(if ($ok) { '' } else { ': ' + (($o | Out-String).Trim()) })) $(if ($ok) { $Pal.Cyan } else { $Pal.Red })
    }

    # what is left (a GUI watch can come back if a run is still active)
    Start-Sleep -Milliseconds 600
    $left = @(); foreach ($p in $Ports) { if (@(Get-PortProcesses $p).Count) { $left += $p } }
    if ($left.Count) { Set-Status ("Still in use: {0} - see the activity pane." -f ($left -join ', ')) $Pal.Amber }
    elseif ($liveStep) { Set-Status ("Stopped. {0} is still used by the Live run - press Stop there." -f $liveStep.Port) $Pal.Amber }
    else { Set-Status ("{0} free now." -f ($Ports -join ', ')) $Pal.Green }
    try { Update-Ports } catch { }
}

# ---- HALT a board's firmware (oct. 20 2026, user: "a button that stops the board itself -
# everything it runs - until it is flashed or started again") -------------------------
# 1. END_RUN over USB: the firmware closes its run file cleanly (SD card + flash), so the
#    halt never leaves a cut, ABORTED file (a board with no run open just answers ALREADY)
# 2. esptool read_mac --after no_reset (twice, the Live run's 'park'): the chip is held in
#    its ROM bootloader - firmware stopped: no mesh, no probes, no SD writes
# It stays halted while it is powered from this USB port, until it is FLASHED, power-
# cycled, or 'Start board again' (a hard reset = its firmware boots as after a plug-in).
# A board on a powerbank cannot be reached over USB - plug it in first.
$script:HaltQueue = New-Object System.Collections.Queue
$script:HaltedPorts = @{}

function Start-HaltBoards([string[]]$Ports) {
    $Ports = @($Ports | Where-Object { $_ -match '^(?i)COM\d+$' } | ForEach-Object { $_.ToUpper() } | Select-Object -Unique)
    if (-not $Ports.Count) { return }
    $R = $script:Run
    if ($R -and $R.Active -and $R.Current -and $R.Current.Board -and ([string]$R.Current.Board.Port).ToUpper() -in $Ports) {
        [void][Windows.MessageBox]::Show("$($R.Current.Board.Port) is the Live run's current board - stop the run on the Live run page first.", 'Halt board'); return
    }
    $busy = @(); foreach ($p in $Ports) { foreach ($x in @(Get-PortProcesses $p)) { $busy += ("  {0}: {1}" -f $p, $x.What); if ($x.Danger) { [void][Windows.MessageBox]::Show("$p is being EXPORTED / its SD card read right now - wait for it to finish (cutting it can crash Windows).", 'Halt board'); return } } }
    $msg = ("HALT {0}?`n`nEach board first closes its run file cleanly (END_RUN), then its firmware is STOPPED - no mesh, no probes, no SD writes - until it is flashed, power-cycled or you press 'Start board again'.{1}`n`nThe firmware itself is not erased." -f ($Ports -join ', '), $(if ($busy.Count) { "`n`nThese programs on the laptop use the port and are stopped first:`n" + ($busy -join "`n") } else { '' }))
    if (-not (Confirm-Action $msg 'Halt board')) { return }
    foreach ($p in $Ports) {
        foreach ($x in @(Get-PortProcesses $p)) { & taskkill.exe /PID $x.Pid /T /F 2>&1 | Out-Null }
        try { Stop-CrashWatchOn $p } catch { }
        $script:HaltQueue.Enqueue($p)
    }
    Step-HaltBoards
}

function Step-HaltBoards {
    if (-not $script:HaltQueue.Count) { try { Update-Ports } catch { }; return }
    $p = $script:HaltQueue.Dequeue(); $py = Get-Py; $t = Get-EsptoolCommand
    # 1. close the run file cleanly
    $ok = Start-StreamJob -Exe $py -ToolArgs @('tools\export_logs.py', '--port', $p, '--end-run') -Title "Halt $p - 1/2 close its run file (END_RUN)" -NoStop -State @{ Port = $p; T = $t } -OnDone {
        param($text, $code, $st)
        $res = ([regex]::Match($text, '(?m)^END_RUN_RESULT:\s*(\S+)')).Groups[1].Value
        Write-Activity ("  {0}: run file {1}" -f $st.Port, $(switch ($res) { 'COMPLETE' { 'closed - capture complete' } 'CUT_SHORT' { 'closed - the run was cut short (stays ABORTED)' } 'ALREADY' { 'was already closed' } default { 'could not be confirmed (old firmware / no answer) - halting anyway' } })) $Pal.Cyan
        # 2. hold the chip in its ROM bootloader (the Live run's park, twice for a sure hold)
        $cmd = "& '{0}' {1} --chip esp32 --port {2} --after no_reset read_mac; if (`$LASTEXITCODE -eq 0) {{ & '{0}' {1} --chip esp32 --port {2} --before no_reset --after no_reset read_mac }}; exit `$LASTEXITCODE" -f $st.T.Exe, (@($st.T.Pre) -join ' '), $st.Port
        [void](Start-StreamJob -Exe 'powershell' -ToolArgs @('-NoProfile', '-Command', $cmd) -Title "Halt $($st.Port) - 2/2 stop its firmware" -NoStop -State $st -OnDone {
            param($text2, $code2, $st2)
            if ($code2 -eq 0) {
                $script:HaltedPorts[$st2.Port] = Get-Date
                Write-Activity ("HALTED {0}: its firmware is stopped until it is flashed, power-cycled or 'Start board again'." -f $st2.Port) $Pal.Green
                Show-Toast "$($st2.Port) halted" 'Firmware stopped (run file closed first). Start board again / flash / power-cycle to wake it.' ([string][char]0xE769)
            } else {
                Write-Activity ("Could NOT halt {0} (esptool exit {1}) - is it plugged in, is the port free?" -f $st2.Port, $code2) $Pal.Red
            }
            Step-HaltBoards
        })
    }
    if (-not $ok) { $script:HaltQueue.Clear() }
}

function Start-ResumeBoard([string]$Port) {
    if (-not $Port) { return }
    $t = Get-EsptoolCommand
    [void](Start-StreamJob -Exe $t.Exe -ToolArgs (@($t.Pre) + @('--chip', 'esp32', '--port', $Port, '--before', 'no_reset', '--after', 'hard_reset', 'read_mac')) -Title "Start $Port again (hard reset)" -NoStop -State $Port -OnDone {
        param($text, $code, $p)
        if ($code -eq 0) { [void]$script:HaltedPorts.Remove($p); Write-Activity ("{0} started again - its firmware boots as after a plug-in." -f $p) $Pal.Green }
        else { Write-Activity ("Could not reset {0} (exit {1}) - press its EN / RST button or unplug + replug it." -f $p, $code) $Pal.Red }
        try { Update-Ports } catch { }
    })
}

function Initialize-GuiStopBoards {
    $bar = $ui.IdentifyAll.Parent; if (-not ($bar -is [Windows.Controls.Panel])) { return }
    $one = New-Object Windows.Controls.Button; $one.Content = 'Stop selected board'
    $one.ToolTip = "Find and stop whatever is using the selected board's port (monitor, flash, capture console, crash watch) - shows the list first."
    $all = New-Object Windows.Controls.Button; $all.Content = 'Stop all boards'
    $all.ToolTip = 'Same, for every COM port in the list.'
    $one.Margin = '6,0,0,0'; $all.Margin = '6,0,0,0'
    $i = $bar.Children.IndexOf($ui.IdentifyAll) + 1
    $bar.Children.Insert($i, $all); $bar.Children.Insert($i, $one)
    $one.Add_Click({ $r = Get-SelectedPort; if ($r) { Stop-BoardPorts @([string]$r.Port) } })
    $all.Add_Click({ Stop-BoardPorts @($script:PortRows | ForEach-Object { [string]$_.Port }) })
    # oct. 20 2026: stop the BOARD itself (its firmware), not only the laptop's programs
    $halt = New-Object Windows.Controls.Button; $halt.Content = 'Halt board (stop its firmware)'; $halt.Margin = '6,0,0,0'
    $halt.ToolTip = 'Closes the board''s run file cleanly (END_RUN), then holds the chip in its bootloader: no mesh, no probes, no SD writes - until it is flashed, power-cycled or started again. Firmware is not erased.'
    try { $halt.Style = $win.FindResource('Danger') } catch { }
    $wake = New-Object Windows.Controls.Button; $wake.Content = 'Start board again'; $wake.Margin = '6,0,0,0'
    $wake.ToolTip = 'Hard-resets the selected board: its firmware boots as after a plug-in.'
    $j = $bar.Children.IndexOf($all) + 1
    $bar.Children.Insert($j, $wake); $bar.Children.Insert($j, $halt)
    $halt.Add_Click({ $r = Get-SelectedPort; if ($r) { Start-HaltBoards @([string]$r.Port) } else { [void][Windows.MessageBox]::Show('Pick a board in the list first.', 'Halt board') } })
    $wake.Add_Click({ $r = Get-SelectedPort; if ($r) { Start-ResumeBoard ([string]$r.Port) } })
}
