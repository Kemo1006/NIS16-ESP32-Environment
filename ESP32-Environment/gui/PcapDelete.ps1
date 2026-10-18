# gui\PcapDelete.ps1 - "Delete" on Wireshark > Captures & views (oct. 18 2026).
# A capture is several files: <name>.pcap + <name>.json (loss counts) +
# <name>_retry.csv / _retry.json (MAC retry report) + <name>_fixed.pcap (repair).
# Delete takes the selected capture(s) WITH those companions to the Windows
# Recycle Bin - restorable - never a permanent delete. Refused while the sniffer
# is still recording it, or while another task runs. datasets\PCAP is
# git-ignored: this only touches THIS laptop. Dot-sourced by run_gui.ps1. ASCII only.

function Get-PcapCompanions([string]$Path) {
    $dir = [IO.Path]::GetDirectoryName($Path); $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    $out = @($Path)
    foreach ($suf in '.json', '_retry.csv', '_retry.json', '_fixed.pcap', '_fixed.pcapng') {
        $c = Join-Path $dir ($stem + $suf); if ([IO.File]::Exists($c)) { $out += $c }
    }
    return $out
}

function Invoke-DeletePcaps {
    if (Test-TaskBusy 'Delete') { return }
    $sel = @($ui.PcapGrid.SelectedItems)
    if (-not $sel.Count) { [void][Windows.MessageBox]::Show('Select the capture(s) to delete first (Ctrl / Shift + click selects several).', 'Delete capture'); return }
    # a capture the sniffer is still writing is never touched
    $rec = @()
    try { $rec = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='py.exe'" -ErrorAction Stop | Where-Object { $_.CommandLine -match '(?i)sniff\.py' } | ForEach-Object { [string]$_.CommandLine }) } catch { }
    $busy = @($sel | Where-Object { $n = [IO.Path]::GetFileNameWithoutExtension($_.Path); @($rec | Where-Object { $_ -like "*$n*" }).Count })
    if ($busy.Count) { [void][Windows.MessageBox]::Show(("Still being recorded - stop the sniffer first:`n`n    " + (($busy | ForEach-Object Name) -join "`n    ")), 'Delete capture'); return }
    $files = @($sel | ForEach-Object { Get-PcapCompanions $_.Path })
    $mb = [math]::Round((($files | ForEach-Object { (New-Object IO.FileInfo $_).Length }) | Measure-Object -Sum).Sum / 1MB, 1)
    $list = (@($sel | ForEach-Object { '    {0}   ({1} MB, {2})' -f $_.Name, $_.MB, $_.WhenText }) | Select-Object -First 12) -join "`n"
    $msg = "Move {0} capture(s) - {1} file(s), {2} MB with their .json / retry reports - to the Recycle Bin?`n`n{3}`n`nRestorable from the Recycle Bin. This laptop only (datasets\PCAP is not on GitHub)." -f $sel.Count, $files.Count, $mb, $list
    if (-not (Confirm-Action $msg 'Delete capture')) { return }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0; $bad = @()
    foreach ($f in $files) {
        try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($f, 'OnlyErrorDialogs', 'SendToRecycleBin'); $ok++ }
        catch { $bad += ('{0}: {1}' -f [IO.Path]::GetFileName($f), $_.Exception.Message) }
    }
    Write-Activity ("  deleted {0} file(s) to the Recycle Bin{1}" -f $ok, $(if ($bad.Count) { " - $($bad.Count) failed: " + ($bad -join '; ') } else { '' })) $(if ($bad.Count) { $Pal.Amber } else { $Pal.Green })
    Show-Toast $(if ($bad.Count) { 'Some files were not deleted' } else { 'Capture(s) deleted' }) ("{0} file(s) are in the Recycle Bin" -f $ok) ([string][char]0xE74D) $(if ($bad.Count) { 'GradMain' } else { 'GradCool' })
    Update-Pcaps
    $ui.PcapBoards.Text = 'Select a capture, then read its boards.'
}

function Initialize-GuiPcapDelete {
    $host_ = $ui.PcapRetry.Parent; if (-not ($host_ -is [Windows.Controls.Panel])) { return }
    $b = New-Object Windows.Controls.Button
    $b.Content = 'Delete'; $b.Margin = '8,0,0,0'
    try { $b.Style = $win.FindResource('Danger') } catch { }
    $b.ToolTip = 'Moves the selected capture(s) and their .json / retry reports to the Recycle Bin (restorable). Ctrl / Shift + click selects several.'
    $b.Add_Click({ Invoke-DeletePcaps })
    [void]$host_.Children.Add($b)
    try { $ui.PcapGrid.SelectionMode = 'Extended' } catch { }
}
