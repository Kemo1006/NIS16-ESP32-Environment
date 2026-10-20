# gui\Perf.ps1 - GUI smoothness (oct. 20 2026, user: "make the GUI more smooth and faster").
#
# MEASURED on Angelo's laptop: one Windows process-list query (Get-CimInstance Win32_Process)
# takes ~210 ms and freezes the window while it runs. The board watcher (every 1.5 s) asked it
# up to TWICE per tick (Test-HandsOff + Get-SnifferPorts) whenever a board sat unidentified or
# 'paused' - which is every tick during a Live run (the crash watches count as 'busy'). That is
# the stutter. Now:
#   Get-ProcRows -MaxAgeS 4   one query for python / py / powershell / pwsh, reused for up to
#                             4 s by the PERIODIC checks only. A click (Read MACs, Stop + halt,
#                             the sniffer check, a hands-off check before a reset) still asks
#                             Windows fresh (-MaxAgeS 0, the default).
#   Measure-GuiTick           times the main timers; a tick over 150 ms is written to
#                             %LOCALAPPDATA%\NIS16\gui_slow_ticks.log, so the next stutter is
#                             found by name instead of guessed.
# Dot-sourced by run_gui.ps1. ASCII only.

$script:ProcCache = $null
$script:SlowTickLog = Join-Path $env:LOCALAPPDATA 'NIS16\gui_slow_ticks.log'
$script:SlowTickLast = @{}

function Get-ProcRows([int]$MaxAgeS = 0) {
    # rows of { ProcessId, Name, CommandLine } - throws like Get-CimInstance when Windows refuses
    $c = $script:ProcCache
    if ($MaxAgeS -gt 0 -and $c -and ((Get-Date) - $c.At).TotalSeconds -lt $MaxAgeS) { return $c.Rows }
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='py.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop |
              ForEach-Object { [pscustomobject]@{ ProcessId = $_.ProcessId; Name = [string]$_.Name; CommandLine = [string]$_.CommandLine } })
    $script:ProcCache = @{ At = (Get-Date); Rows = $rows }
    return $rows
}

function Measure-GuiTick([string]$Name, [scriptblock]$Body) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body } finally {
        $ms = $sw.ElapsedMilliseconds
        if ($ms -gt 150 -and -not $SelfTest) {
            # at most one line per timer every 10 s - the log must never become the stutter
            $last = $script:SlowTickLast[$Name]
            if (-not $last -or ((Get-Date) - $last).TotalSeconds -ge 10) {
                $script:SlowTickLast[$Name] = Get-Date
                try {
                    $page = try { [string]$nav[$ui.Pages.SelectedIndex] } catch { '?' }
                    $run = if ($script:Run) { [string]$script:Run.Phase } else { '-' }
                    Add-Content -Path $script:SlowTickLog -Value ("{0}  {1,-6} {2,5} ms  page={3} run={4}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Name, $ms, $page, $run) -Encoding ASCII
                } catch { }
            }
        }
    }
}
