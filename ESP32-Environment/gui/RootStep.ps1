# gui\RootStep.ps1 - ONE LAPTOP, WHOLE PRESET: the root is compiled + flashed by hand,
# AFTER every child (oct. 20 2026, user: "if the user has only 1 laptop and a preset with
# all boards incl. the root ... the children must finish compiling + flashing first, then a
# button appears to compile the root and another to flash it, with clean rebuild too").
#
# When it applies: the loaded preset has the ROOT and at least one child on THIS laptop and
# no board on another laptop. Then a tick box on the Live run setup card is shown, ticked by
# default ("One laptop: compile + flash the ROOT by hand after every child"):
#   1 Compile        compiles the CHILDREN only (the root's firmware is not built yet)
#   2 Wipe + flash   parks the old root, flashes + starts every child as before, then STOPS
#                    at the root with the ROOT STEP buttons:
#        Compile the root         its firmware only (skipped in seconds if unchanged)
#        Clean rebuild the root   deletes ONLY the root's build folder, compiles it from scratch
#        Flash the root  ->       enabled once the root compiled: wakes the parked root, wipes,
#                                 flashes, opens its monitor - the run carries on as always
#        Open the compile log     the root's last build log, when one was written
# Nothing else changes: same run.ps1 calls, same order (children first, root last), same
# safety (park the old root, crash watch, START gate). Untick the box for the old automatic
# behaviour (root compiled with the children and flashed right after the last child).
# Dot-sourced by run_gui.ps1. ASCII only.

function Test-RootByHandPlan($Plan) {
    # the preset holds the root AND children on this laptop, nothing elsewhere
    if (-not $Plan) { return $false }
    $root = @($Plan.Local | Where-Object Role -eq 'root').Count
    $kids = @($Plan.Local | Where-Object Role -ne 'root').Count
    return ($root -eq 1 -and $kids -ge 1 -and -not @($Plan.Remote).Count)
}

function Test-RootByHand {
    $R = $script:Run
    return [bool]($R -and $script:RootByHandBox -and $script:RootByHandBox.Visibility -eq 'Visible' -and
                   $script:RootByHandBox.IsChecked -and (Test-RootByHandPlan $R.Plan))
}

function Initialize-RootStepUi {
    if ($script:RootByHandBox) { return }
    # the option, on the setup card right above the notes
    $box = New-Object Windows.Controls.CheckBox
    $box.Content = 'One laptop: compile + flash the ROOT by hand, after every child is flashed'
    $box.IsChecked = $true; $box.Margin = '0,0,18,8'; $box.Visibility = 'Collapsed'
    $box.ToolTip = ("This preset has the root and every child on this laptop. Ticked: '1 Compile' compiles only the children, " +
                    "'2 Wipe + flash + run' flashes and starts every child, then stops at the ROOT with its own buttons - " +
                    "Compile the root, Clean rebuild the root, Flash the root. Unticked: the root is compiled with the children " +
                    "and flashed right after the last child, as before.")
    $box.Add_Checked({ Update-RootStepLabels }); $box.Add_Unchecked({ Update-RootStepLabels })
    $sp = $ui.RunNotes.Parent
    [void]$sp.Children.Insert($sp.Children.IndexOf($ui.RunNotes), $box)
    $script:RootByHandBox = $box

    # the ROOT STEP buttons, inside the "what to do now" card
    $bar = New-Object Windows.Controls.WrapPanel; $bar.Margin = '0,10,0,0'; $bar.Visibility = 'Collapsed'
    $mk = {
        param([string]$Text, [string]$Style, [string]$Tip)
        $b = New-Object Windows.Controls.Button; $b.Content = $Text; $b.Padding = '16,8'; $b.Margin = '0,0,8,6'; $b.ToolTip = $Tip
        if ($Style) { try { $b.Style = $win.FindResource($Style) } catch { } }
        [void]$bar.Children.Add($b); return $b
    }
    $script:RootBtnBuild = & $mk 'R1   Compile the root' 'Cool' 'Compiles ONLY the root''s firmware (no board is touched). Unchanged firmware is skipped in seconds.'
    $script:RootBtnClean = & $mk 'Clean rebuild the root' '' 'Deletes ONLY the root''s build folder and compiles it from scratch (~2-4 min) - after an interrupted compile, an ESP-IDF update or a moved project folder. The children''s builds are kept.'
    $script:RootBtnFlash = & $mk ('R2   Flash the root  ' + [char]0x2192) 'Primary' 'Wakes the parked root, wipes it, flashes its new firmware and opens its monitor. The children are already running and waiting for it.'
    $script:RootBtnLog = & $mk 'Open the compile log' '' 'The root''s last build log.'
    $script:RootBtnBuild.Add_Click({ Start-RootCompile })
    $script:RootBtnClean.Add_Click({ Start-RootCompile -Clean })
    $script:RootBtnFlash.Add_Click({ Start-RootFlash })
    $script:RootBtnLog.Add_Click({
        $e = Get-RootBuildEntry
        if ($e -and $e.Log -and (Test-Path $e.Log)) { Start-Process notepad.exe $e.Log } else { Set-Status 'No compile log for the root yet.' $Pal.Amber }
    })
    $host_ = $ui.RunNowText.Parent
    [void]$host_.Children.Insert($host_.Children.IndexOf($ui.RunNowText) + 1, $bar)
    $script:RootStepBar = $bar
}

function Update-RootStepOption {
    # called by Open-RunPage: show the option only for a one-laptop, whole preset
    Initialize-RootStepUi
    $ok = Test-RootByHandPlan $script:Run.Plan
    $script:RootByHandBox.Visibility = $(if ($ok) { 'Visible' } else { 'Collapsed' })
    $script:RootStepBar.Visibility = 'Collapsed'
    Update-RootStepLabels
}

function Update-RootStepLabels {
    if (-not $script:RootByHandBox) { return }
    $byHand = $script:RootByHandBox.IsChecked -and $script:RootByHandBox.Visibility -eq 'Visible'
    $ui.RunBuild.Content = $(if ($byHand) { '1   Compile the children  (the root comes later)' } else { '1   Compile every board  (touches no board)' })
    $ui.RunGo.Content = $(if ($byHand) { ('2   Wipe + flash + run the children  ' + [char]0x2192) } else { ('2   Wipe + flash + run  ' + [char]0x2192) })
}

function Get-RootStep { @($script:Run.Steps | Where-Object { $_.Kind -eq 'board' -and $_.Board.Role -eq 'root' })[0] }

function Get-RootBuildEntry {
    $R = $script:Run; $st = Get-RootStep
    if (-not $R -or -not $st -or -not $st.Plan -or -not $R.Builds) { return $null }
    $key = Get-RunBuildKey $st.Plan
    return @($R.Builds | Where-Object Key -eq $key)[0]
}

function Show-RootGate([string]$Why = '') {
    # the children are flashed and running; the root waits for the operator
    $R = $script:Run; $st = Get-RootStep; if (-not $st) { return }
    Initialize-RootStepUi
    $R.Current = $st; $R.Phase = 'rootgate'; $R.Active = $true
    $R.Wait = @{ Kind = 'rootgate'; Step = $st }
    $e = Get-RootBuildEntry
    $built = [bool]($R.PSObject.Properties['RootBuilt'] -and $R.RootBuilt -and $e -and $e.State -eq 'ok')
    $st.State = 'attention'; $st.Note = $(if ($built) { 'compiled - press Flash the root' } else { 'press Compile the root' })
    $kids = @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.Board.Role -ne 'root' -and $_.State -eq 'ok' }).Count
    Set-RunState 'ROOT STEP' $Pal.Amber
    $text = ("{0} child board(s) are flashed and running, waiting for the root. Now: {1}{2}" -f $kids,
             $(if ($built) { "the root's firmware is ready - press 'R2 Flash the root'. (Compile it again first if you changed anything.)" }
               else { "press 'R1 Compile the root' (or 'Clean rebuild the root'), then 'R2 Flash the root'." }),
             $(if ($Why) { "`n`n$Why" } else { '' }))
    Set-RunNow 'Root step - compile, then flash the root' $text $Pal.Amber ([string][char]0xE734)
    Set-RunButtons -Abort $true
    $script:RootStepBar.Visibility = 'Visible'
    $script:RootBtnBuild.IsEnabled = $true; $script:RootBtnClean.IsEnabled = $true
    $script:RootBtnFlash.IsEnabled = $built
    $script:RootBtnLog.Visibility = $(if ($e -and $e.Log) { 'Visible' } else { 'Collapsed' })
    Update-RunSteps
    Show-Toast 'Root step' $(if ($built) { 'Root firmware ready - press Flash the root' } else { 'Every child is running - compile the root now' }) ([string][char]0xE734)
    if ($script:AutoConfirm) {
        # -SelfTest drives the feature end to end: compile, then flash
        [Console]::Out.WriteLine(("root step: gate shown, built={0}, kids running={1}, flash button enabled={2}" -f $built, $kids, $script:RootBtnFlash.IsEnabled))
        if ($built) { Start-RootFlash } else { Start-RootCompile }
    }
}

function Hide-RootStepBar { if ($script:RootStepBar) { $script:RootStepBar.Visibility = 'Collapsed' } }

function Start-RootCompile([switch]$Clean) {
    $R = $script:Run; $st = Get-RootStep
    if (-not $R -or -not $st -or $R.Phase -ne 'rootgate') { return }
    if ($R.Proc -and -not $R.Proc.HasExited) { Set-Status 'Something is still running - wait for it.' $Pal.Amber; return }
    Hide-RootStepBar
    if ($Clean) {
        if (-not $st.Plan) { Build-RunParams }
        $dir = Get-RunBuildKey $st.Plan
        if ($dir -and (Test-Path $dir) -and (Split-Path $dir -Leaf) -like 'build_*') {
            Write-RunConsole ("  clean rebuild of the root: removing {0}" -f $dir) $Pal.Amber
            Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        }
    }
    $R | Add-Member -NotePropertyName RootBuilding -NotePropertyValue $true -Force
    $R | Add-Member -NotePropertyName RootBuilt -NotePropertyValue $false -Force
    Start-RunBuild -Only @($st.Board.Label)
}

function Complete-RootCompile {
    # called by Step-RunBuild when the root-only compile is done (ok)
    $R = $script:Run
    $R.RootBuilding = $false; $R.RootBuilt = $true
    Write-RunConsole 'Root firmware ready - press "R2 Flash the root".' $Pal.Green
    Show-RootGate
}

function Start-RootFlash {
    $R = $script:Run; $st = Get-RootStep
    if (-not $R -or -not $st -or $R.Phase -ne 'rootgate') { return }
    if (-not ($R.PSObject.Properties['RootBuilt'] -and $R.RootBuilt)) { Set-Status 'Compile the root first.' $Pal.Amber; return }
    Hide-RootStepBar
    $R | Add-Member -NotePropertyName RootGo -NotePropertyValue $true -Force
    $R.Wait = $null; $R.Phase = 'boards'; $st.State = 'waiting'; $st.Note = ''
    Start-RunStep $st
}
