<#
.SYNOPSIS
  Run an ESP32 node and AUTO-EXPORT its CSVs the moment you exit the monitor.

.DESCRIPTION
  Opens "idf.py monitor" on the board. When you press Ctrl+] to leave the
  monitor, this script immediately runs export_logs.py for that board — so you
  never have to type the export command by hand.

  Run this from the "ESP-IDF 5.3 PowerShell" window (idf.py + python + pyserial
  must be on PATH).

.EXAMPLE
  # Just watch the run, then Ctrl+] to auto-export (board already flashed/running):
  .\run.ps1 -Port COM9 -Role victim

.EXAMPLE
  # Flash first, watch the full run, then Ctrl+] to auto-export:
  .\run.ps1 -Port COM3 -Role root -Flash -Repeat 2
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][ValidateSet('root', 'victim')][string]$Role,
    [string]$Topology = 'star',
    [string]$Attack   = 'none',
    [int]$Repeat      = 1,
    [switch]$Flash,    # also (re)flash before monitoring — restarts the experiment
    [switch]$Clean     # after a successful export, wipe the board's logs so the
                       # NEXT run starts empty (prevents stacked multi-run files)
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$proj = if ($Role -eq 'root') { 'root_node' } else { 'victim_node' }

# 1) Monitor (optionally flash first). Ctrl+] exits the monitor and returns here.
Push-Location (Join-Path $base $proj)
try {
    if ($Flash) {
        Write-Host "Flashing + monitoring $Role on $Port. Ctrl+] when it reaches 'terminate' to auto-export." -ForegroundColor Cyan
        idf.py -p $Port flash monitor
    } else {
        Write-Host "Monitoring $Role on $Port. Ctrl+] when it reaches 'terminate' to auto-export." -ForegroundColor Cyan
        idf.py -p $Port monitor
    }
} finally {
    Pop-Location
}

# 2) Monitor closed -> auto-export. (export_logs.py deasserts DTR/RTS so opening
#    the port does NOT reset the board / kill its export task.)
Write-Host "`nMonitor closed - auto-exporting $Role CSVs from $Port ..." -ForegroundColor Green
Push-Location (Join-Path $base 'tools')
try {
    $exportArgs = @('export_logs.py', '--port', $Port, '--role', $Role,
                    '--topology', $Topology, '--attack', $Attack, '--repeat', $Repeat)
    if ($Clean) { $exportArgs += '--delete' }   # wipe board AFTER a good download
    python @exportArgs
} finally {
    Pop-Location
}
Write-Host "Done. Files are in tools\exports\." -ForegroundColor Green
if ($Clean) { Write-Host "Board logs wiped (--delete) - next run starts empty." -ForegroundColor Green }
