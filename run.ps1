<#
.SYNOPSIS
  Run an ESP32 node, and OPTIONALLY export its CSVs when you exit the monitor.

.DESCRIPTION
  Opens "idf.py monitor" on the board. By default it JUST runs — nothing is
  exported. Add -Export to have the script run export_logs.py for that board the
  moment you press Ctrl+] to leave the monitor, so you don't type the export
  command by hand. This way not every run auto-exports; you choose per run.

  Run this from the "ESP-IDF 5.3 PowerShell" window (idf.py + python + pyserial
  must be on PATH).

.EXAMPLE
  # RUN ONLY — watch the run, Ctrl+] to quit, NO export:
  .\run.ps1 -Port COM8 -Role root -Flash

.EXAMPLE
  # RUN THEN EXPORT — Ctrl+] at 'terminate' auto-exports the CSVs:
  .\run.ps1 -Port COM8 -Role root -Flash -Export

.EXAMPLE
  # GUARANTEED FRESH RUN + export: wipe old data, flash, run, then export:
  .\run.ps1 -Port COM8 -Role root -Wipe -Flash -Export

.EXAMPLE
  # BLACKHOLE run: -Attack blackhole flashes the attack firmware (-DACTIVE_ATTACK=1).
  # Run BOTH boards with -Attack blackhole -Flash for the attack to trigger.
  .\run.ps1 -Port COM8 -Role root   -Attack blackhole -Wipe -Flash -Export
  .\run.ps1 -Port COM3 -Role victim -Attack blackhole -Wipe -Flash -Export

.EXAMPLE
  # M3: STAR topology (caps depth at 2, everyone a direct child of root).
  # Run EVERY board in the run with the SAME -Topology -Flash, or nodes disagree
  # on shaping. Physical placement still matters most (see verify_topology.py).
  .\run.ps1 -Port COM8 -Role root   -Topology star -Wipe -Flash -Export
  .\run.ps1 -Port COM3 -Role victim -Topology star -Wipe -Flash -Export
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][ValidateSet('root', 'victim')][string]$Role,
    # -Topology also picks the BUILD flag when -Flash is set (M3): star => cap
    # depth at 2, linear => force a chain, tree/partial => default self-organising
    # (unchanged M1 behaviour; "partial" comes from physical placement, not a
    # firmware knob). Build EVERY board in a run with the SAME -Topology.
    [ValidateSet('tree', 'star', 'linear', 'partial')][string]$Topology = 'tree',
    # -Attack also picks the BUILD flag when -Flash is set: blackhole => -DACTIVE_ATTACK=1,
    # none => -DACTIVE_ATTACK=255 (baseline; also clears a cached blackhole build).
    [ValidateSet('none', 'blackhole')][string]$Attack = 'none',
    [int]$Repeat      = 1,
    [switch]$Flash,    # also (re)flash before monitoring — restarts the experiment
    [switch]$Export,   # after Ctrl+], pull the CSVs with export_logs.py. WITHOUT
                       # this the script just runs and exports NOTHING.
    [switch]$Clean,    # after a successful export, wipe the board's logs so the
                       # NEXT run starts empty (implies -Export)
    [switch]$Wipe      # BEFORE flashing, erase the board's logs so THIS run starts
                       # empty — use for a guaranteed fresh, unstacked run
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$proj = if ($Role -eq 'root') { 'root_node' } else { 'victim_node' }

# -Clean only makes sense if we actually export first, so it implies -Export.
$doExport = $Export.IsPresent -or $Clean.IsPresent

# 0) Optional pre-run wipe so this run's CSV is a single clean run (no stacking).
#    The on-device command listener runs from boot, so DELETE_LOGS is accepted now.
if ($Wipe) {
    Write-Host "Wiping old logs on $Port before this run ..." -ForegroundColor Yellow
    Push-Location (Join-Path $base 'tools')
    try { python export_logs.py --port $Port --wipe } finally { Pop-Location }
}

# Map -Attack to the ACTIVE_ATTACK build flag (only meaningful when flashing).
# Always pass an explicit value so a plain run also CLEARS a cached blackhole
# build: none => 255 (ATTACK_NONE / baseline), blackhole => 1.
$attackFlag = if ($Attack -eq 'blackhole') { '-DACTIVE_ATTACK=1' } else { '-DACTIVE_ATTACK=255' }

# Map -Topology to the MESH_TOPOLOGY build flag (only meaningful when flashing).
# Always pass an explicit value so a plain run also CLEARS a cached star/linear
# build: star=0, tree=1 (default/M1 behaviour), linear=2, partial=3.
$topologyNum = switch ($Topology) {
    'star'    { 0 }
    'tree'    { 1 }
    'linear'  { 2 }
    'partial' { 3 }
}
$topologyFlag = "-DMESH_TOPOLOGY=$topologyNum"

# What happens after Ctrl+], for the on-screen hint.
$exitHint = if ($doExport) { "to auto-export" } else { "to quit (no export)" }

# 1) Monitor (optionally flash first). Ctrl+] exits the monitor and returns here.
Push-Location (Join-Path $base $proj)
try {
    if ($Flash) {
        Write-Host "Flashing + monitoring $Role on $Port (topology=$Topology, attack=$Attack). Ctrl+] when it reaches 'terminate' $exitHint." -ForegroundColor Cyan
        idf.py $attackFlag $topologyFlag -p $Port flash monitor
    } else {
        if ($Attack -eq 'blackhole' -or $Topology -ne 'tree') {
            Write-Host "NOTE: -Attack/-Topology have no effect without -Flash; monitoring the CURRENTLY flashed firmware." -ForegroundColor Yellow
        }
        Write-Host "Monitoring $Role on $Port. Ctrl+] when it reaches 'terminate' $exitHint." -ForegroundColor Cyan
        idf.py -p $Port monitor
    }
} finally {
    Pop-Location
}

# 2) Monitor closed. Export only if asked. (export_logs.py deasserts DTR/RTS so
#    opening the port does NOT reset the board / kill its export task.)
if (-not $doExport) {
    Write-Host "`nMonitor closed - run only (no export). Data is safe on the board's SPIFFS." -ForegroundColor Green
    Write-Host "To export later:  python tools\export_logs.py --port $Port --role $Role --topology $Topology --attack $Attack --repeat $Repeat" -ForegroundColor DarkGray
    return
}

Write-Host "`nMonitor closed - exporting $Role CSVs from $Port ..." -ForegroundColor Green
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
