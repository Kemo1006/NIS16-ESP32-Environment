# gui\SnifferGate.ps1 - SNIFFER CHECK before the root is flashed (oct. 20 2026, user: "a safety
# net like a warning that the sniffer hasn't started yet before starting the flash in root").
#
# The root is flashed LAST and its boot starts the run's phases, so a sniffer started after it
# misses Phase 0 / the baseline. Right before the root's turn (automatic or 'R2 Flash the root')
# the run checks for a RECORDING sniffer on this laptop (a running tools\sniff.py, not paused).
# None -> the run HOLDS at the root with three buttons:
#   Open the sniffer page          the 'Wireshark & sniffer' page (Start recording there)
#   Check again - flash the root   flashes once the sniffer records; otherwise says so
#   Flash WITHOUT the sniffer      for a run with no capture, or a sniffer on ANOTHER laptop
# A run asked once: after a choice it never asks again. The sniffer is optional for the data
# (only MacRetryRate / MacFramesHeard come from it, D-15) - this only stops a forgotten one.
# Dot-sourced by run_gui.ps1. ASCII only.

function Get-SnifferState {
    # 'recording' | 'paused' | 'off'
    if ($script:Stream -and (Test-IsSnifferStream)) {
        if ($script:SnPauseFile -and (Test-Path $script:SnPauseFile)) { return 'paused' }
        return 'recording'
    }
    $sn = @{}; try { $sn = Get-SnifferPorts } catch { }
    if ($sn.Count) { return 'recording' }   # sniff.py started outside the GUI (CLI / wizard)
    return 'off'
}

function Test-SnifferGateNeeded {
    $R = $script:Run
    if ($script:AutoConfirm -or $SelfTest) { return $false }
    if ($R.PSObject.Properties['SniffOk'] -and $R.SniffOk) { return $false }
    return ((Get-SnifferState) -ne 'recording')
}

function Initialize-SnifferGateUi {
    if ($script:SnGateBar) { return }
    $bar = New-Object Windows.Controls.WrapPanel; $bar.Margin = '0,10,0,0'; $bar.Visibility = 'Collapsed'
    $mk = {
        param([string]$Text, [string]$Style, [string]$Tip)
        $b = New-Object Windows.Controls.Button; $b.Content = $Text; $b.Padding = '16,8'; $b.Margin = '0,0,8,6'; $b.ToolTip = $Tip
        if ($Style) { try { $b.Style = $win.FindResource($Style) } catch { } }
        [void]$bar.Children.Add($b); return $b
    }
    $open = & $mk 'Open the sniffer page' 'Cool' "The 'Wireshark & sniffer' page: pick the sniffer's port, press Start recording, then come back here."
    $again = & $mk ('Check again - flash the root  ' + [char]0x2192) 'Primary' 'Flashes the root once the sniffer is recording (not paused).'
    $skip = & $mk 'Flash WITHOUT the sniffer' '' 'This run has no capture on this laptop (no sniffer, or it records on another laptop). The data is complete without it; only the MAC-retry columns stay NaN.'
    $open.Add_Click({ Show-Page 6 })
    $again.Add_Click({
        $s = Get-SnifferState
        if ($s -eq 'recording') { Write-RunConsole '  sniffer check: recording - flashing the root' $Pal.Green; Resume-AfterSnifferGate }
        elseif ($s -eq 'paused') { Set-Status 'The sniffer is PAUSED - press Resume on the sniffer page first.' $Pal.Amber }
        else { Set-Status 'Still no sniffer recording on this laptop.' $Pal.Amber }
    })
    $skip.Add_Click({
        if (-not (Confirm-Action "Flash the root with NO sniffer recording on this laptop?`n`nThe run will have no .pcap from here (the MAC-retry columns stay NaN). Say Yes only if this run has no sniffer, or it records on another laptop." 'No sniffer')) { return }
        Write-RunConsole '  sniffer check: flashing the root WITHOUT a sniffer on this laptop (operator''s choice)' $Pal.Amber
        Add-RunAlert 'root flashed with no sniffer recording on this laptop' $Pal.Amber
        Resume-AfterSnifferGate
    })
    $host_ = $ui.RunNowText.Parent
    [void]$host_.Children.Insert($host_.Children.IndexOf($ui.RunNowText) + 1, $bar)
    $script:SnGateBar = $bar
}

function Show-SnifferGate($St) {
    $R = $script:Run
    Initialize-SnifferGateUi
    $R.Current = $St; $R.Phase = 'sniffgate'; $R.Active = $true
    $R.Wait = @{ Kind = 'sniffgate'; Step = $St }
    $state = Get-SnifferState
    $St.State = 'attention'; $St.Note = $(if ($state -eq 'paused') { 'sniffer PAUSED' } else { 'sniffer not recording' })
    Set-RunState 'SNIFFER?' $Pal.Amber
    $text = $(if ($state -eq 'paused') {
        "The sniffer is PAUSED - it would save nothing of this run. Press Resume on the sniffer page, then 'Check again'."
    } else {
        "No sniffer is recording on this laptop. The root starts the run's phases, so a sniffer started later misses the start of the run.`n`n" +
        "Start it now: 'Open the sniffer page' -> pick its port -> Start recording -> come back -> 'Check again'. " +
        "No sniffer for this run (or it records on another laptop)? Press 'Flash WITHOUT the sniffer'."
    })
    Set-RunNow 'Sniffer check before the root' $text $Pal.Amber ([string][char]0xE968)
    Set-RunButtons -Abort $true
    $script:SnGateBar.Visibility = 'Visible'
    Write-RunConsole ("  sniffer check: {0} - the root waits" -f $(if ($state -eq 'paused') { 'PAUSED' } else { 'nothing recording' })) $Pal.Amber
    Update-RunSteps
    Show-Toast 'Sniffer not recording' 'Start the sniffer before the root is flashed' ([string][char]0xE968) 'GradCool' { Show-Page 6 } 'Open sniffer'
}

function Hide-SnifferGateBar { if ($script:SnGateBar) { $script:SnGateBar.Visibility = 'Collapsed' } }

function Resume-AfterSnifferGate {
    $R = $script:Run
    if (-not $R -or $R.Phase -ne 'sniffgate' -or -not $R.Wait) { return }
    $st = $R.Wait.Step
    Hide-SnifferGateBar
    $R | Add-Member -NotePropertyName SniffOk -NotePropertyValue $true -Force
    $R.Wait = $null; $R.Phase = 'boards'; $st.State = 'waiting'; $st.Note = ''
    Start-RunStep $st
}

function Stop-SnifferWithRun {
    # called when the root's monitor closes ("Finish + export root" / the run's end): a sniffer
    # recording from THIS GUI gets its stop file - sniff.py closes the .pcap cleanly (same as
    # its Stop button). One started from the CLI cannot be reached from here: say so.
    if ($SelfTest) { return }
    if ($script:Stream -and (Test-IsSnifferStream) -and $script:SnStop) {
        Set-Content -Path $script:SnStop -Value 'stop'
        Write-RunConsole '  sniffer: STOPPED with the root - its capture is closed and saved (Wireshark & sniffer page)' $Pal.Green
        Add-RunAlert 'sniffer stopped with the root - capture saved' $Pal.Green
        return
    }
    $sn = @{}; try { $sn = Get-SnifferPorts } catch { }
    if ($sn.Count) { Write-RunConsole ("  sniffer: still recording on {0} (started outside this GUI) - stop it in its own window (Enter) so its capture is saved" -f (@($sn.Keys) -join ', ')) $Pal.Amber }
}
