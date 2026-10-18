# gui\Collect.ps1 - "Collect all children": after a Live run, read every
# plugged-in child's SD card over USB (tools\collect_run.py, one port at a time)
# and file THIS run's telemetry under the run's own folder - even when a card's
# location.txt still named the last site (oct. 18 2026: 7 boards by hand).
# Dot-sourced by run_gui.ps1. ASCII only.

function Get-CollectPorts {
    # the run's children that are plugged in right now (the root is exported over USB)
    $R = $script:Run; if (-not $R -or -not $R.Plan) { return @() }
    return @($R.Plan.Local | Where-Object { $_.Role -ne 'root' -and $_.Port -and $script:Live.Contains([string]$_.Port) } |
             ForEach-Object { [string]$_.Port } | Select-Object -Unique)
}

function Start-CollectChildren {
    # $true when the collect started; $false = nothing to collect here (caller falls back to Import)
    $R = $script:Run; if (-not $R -or -not $R.Plan) { return $false }
    $py = Get-Py; if (-not $py) { return $true }
    $ports = @(Get-CollectPorts)
    if (-not $ports.Count) { return $false }
    $root = @($R.Plan.Full | Where-Object Role -eq 'root') | Select-Object -First 1
    $rootMac = if ($root -and $root.Mac) { ([string]$root.Mac -replace '[^0-9A-Fa-f]', '') } else { '' }
    $dirs = Get-RunDirs -Attack $R.Plan.Attack -Topology $R.Plan.Topology -Location $R.Plan.Location -Scenario $R.Plan.Scenario
    $msg = ("Read the SD card of {0} child board(s) over USB, one after the other (about a minute each), and file THIS run's telemetry into`n    {1}`n`nPorts: {2}`n`nDo NOT unplug a board until it says done. A card that recorded another location is filed under {3} anyway (and the output says so)." -f
            $ports.Count, $dirs.Export, ($ports -join ', '), $R.Plan.Location)
    if (-not (Confirm-Action $msg 'Collect all children')) { return $true }
    $since = if ($R.Started) { $R.Started.AddMinutes(-15).ToString('yyyy-MM-dd HH:mm') } else { (Get-Date).AddHours(-6).ToString('yyyy-MM-dd HH:mm') }
    $a = @('tools\collect_run.py', '--ports', ($ports -join ','), '--attack', [string]$R.Plan.Attack, '--topology', [string]$R.Plan.Topology,
           '--location', [string]$R.Plan.Location, '--scenario', [string]$R.Plan.Scenario, '--repeat', [string]$R.Settings.Repeat, '--since', $since)
    if ($rootMac) { $a += @('--skip-mac', $rootMac) }
    if ($R.Plan.Preset -and $R.Plan.Preset.Path) { $a += @('--roster', [string]$R.Plan.Preset.Path) }
    $st = @{ Before = @(Get-ExportCsvSet -Base $base); Started = (Get-UnixNow); Export = $dirs.Export; Expect = @($R.Plan.Full).Count }
    $ok = Start-StreamJob -Exe $py -ToolArgs $a -Title ("Collect {0} child board(s)" -f $ports.Count) -NoStop -State $st -OnDone {
        param($text, $code, $st)
        try { Save-ImportBatch -Base $base -Before $st.Before -Started $st.Started } catch { }
        $m = [regex]::Match($text, 'COLLECT_SUMMARY: ok=(\d+) skip=(\d+) fail=(\d+)')
        $fails = @([regex]::Matches($text, '(?m)^COLLECT: (\S+) (\S+) FAIL (.+)$') | ForEach-Object { '{0}: {1}' -f $_.Groups[1].Value, $_.Groups[3].Value.Trim() })
        foreach ($f in $fails) {
            $port = ($f -split ':')[0]
            $hold = Get-PortHolderText $port
            Write-Activity ("  {0}{1}" -f $f, $(if ($hold) { "   ->  $hold" } else { '' })) $Pal.Amber
        }
        if ($m.Success) {
            $okN = [int]$m.Groups[1].Value; $failN = [int]$m.Groups[3].Value
            Show-Toast $(if ($failN) { "Collected $okN - $failN failed" } else { "Collected $okN board(s)" }) $(if ($failN) { 'The activity pane says why per board - import those from the Data page.' } else { 'The run summary opens next.' }) ([string][char]0xE73E) $(if ($failN) { 'GradMain' } else { 'GradGood' })
        }
        Show-RunSummary $st.Export $st.Expect 'COLLECTED - RUN SUMMARY'
        try { Update-Cells } catch { }
        $ui.RunContinue.IsEnabled = $true
    }
    if ($ok) { $ui.RunContinue.IsEnabled = $false }
    return $true
}
