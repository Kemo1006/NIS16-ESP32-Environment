# gui\PortHolder.ps1 - "COM31 is held by ...": who has a serial port open, so a
# failed read says what to close instead of a generic "could not read the card"
# (oct. 18 2026: the root's card could not be listed - its port was busy).
# Only runs on a failure path, never on a timer. Dot-sourced by run_gui.ps1. ASCII only.

function Get-PortHolderText([string]$Port) {
    if (-not $Port -or $Port -notmatch '^COM\d+$') { return '' }
    $P = $Port.ToUpper()
    # 1) this window's own users of the port
    $R = $script:Run
    if ($R -and $R.Current -and $R.Current.Board -and ([string]$R.Current.Board.Port).ToUpper() -eq $P -and $R.Phase -in @('monitor', 'flash', 'export')) {
        return "held by this window's Live run ($($R.Current.Board.Label), $($R.Phase)) - finish that step first"
    }
    if ($R -and $R.Bg) {
        $bg = @($R.Bg | Where-Object { ([string]$_.Port).ToUpper() -eq $P -and $_.Proc -and -not $_.Proc.HasExited }) | Select-Object -First 1
        if ($bg) { return "held by this window's crash watch on $($bg.Label) - it stops when the run is finished (or stop the run)" }
    }
    # 2) any other process whose command line names the port (idf.py monitor, esptool, a second GUI, a wizard)
    try {
        $rx = '(?i)(^|[\s"=])' + [regex]::Escape($P) + '([\s"]|$)'
        $hits = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='py.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop |
                  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $rx })
        foreach ($h in $hits) {
            $c = [string]$h.CommandLine
            $what = switch -Regex ($c) {
                'idf\.py.*monitor|idf_monitor' { 'idf.py monitor'; break }
                'esptool' { 'esptool (a flash or MAC read)'; break }
                'gui_monitor\.py' { 'a GUI board monitor (Live run / crash watch)'; break }
                'sniff\.py' { 'the sniffer'; break }
                'export_logs\.py' { 'an export (export_logs.py) - let it finish'; break }
                'import_sdcard\.py' { 'an SD read (import_sdcard.py) - let it finish'; break }
                'run_wizard|menu\.ps1|run\.ps1' { 'a capture console (wizard / run.ps1)'; break }
                default { $h.Name }
            }
            return "held by $what (PID $($h.ProcessId)) - close it, then try again"
        }
    } catch { }
    return ''
}
