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
}
