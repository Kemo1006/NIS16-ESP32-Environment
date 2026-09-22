<#
.SYNOPSIS
  Read an ESP32's MAC address over USB serial — no flashing, no monitor.

.DESCRIPTION
  Wraps `esptool read_mac`, which reads the base MAC straight from the chip's
  eFuse. On ESP32 the base MAC IS the Wi-Fi STA MAC, which is exactly the
  firmware's Node ID (boot log: "NODE_XXXXXXXXXXXX"). Use it to identify which
  physical board is on which COM port BEFORE flashing (match a board to its
  Node ID so you assign root/victim/attacker roles to the right ports).
  Works on a blank / factory-reset board (it reads eFuse, not flash).

  (Note: WORMHOLE_NODE_A_MAC is no longer used — the wormhole tunnel is a wired
  UART cable now, not a MAC-addressed message — so this tool is purely for board
  identification, not wormhole setup.)

  Each result object has four fields:
    Port   - the COM port queried
    MAC    - colon form, e.g. f4:2d:c9:73:e6:18
    NodeId - NODE_F42DC973E618        (matches the boot-log Node ID)
    CArray - {0xF4, 0x2D, ...}        (C-array form, if ever needed)

.PARAMETER Port
  A single COM port to read, e.g. COM21.

.PARAMETER All
  Ignore -Port and scan EVERY connected Silicon Labs CP210x board, one row each.
  WARNING: opens + resets every board it finds, so only use it BETWEEN runs /
  on idle boards, never mid-experiment.

.EXAMPLE
  # One board:
  .\tools\Get-EspMac.ps1 -Port COM21

.EXAMPLE
  # Inventory every connected board at once:
  .\tools\Get-EspMac.ps1 -All

.EXAMPLE
  # Load the function for repeated interactive use, then call it directly:
  . .\tools\Get-EspMac.ps1
  Get-EspMac COM21
  (Get-EspMac COM21).CArray     # just the mesh_config.h array

.NOTES
  Close `idf.py monitor` / any export first — the port must be free or you get
  "port busy". read_mac briefly resets the board (DTR/RTS); harmless.
  Run from the "ESP-IDF 5.3 PowerShell" window, or a plain shell — the function
  falls back to the pinned esptool path when esptool.py isn't on PATH.
#>
param(
    [string]$Port,
    [switch]$All
)

function Get-EspMac {
    param([Parameter(Mandatory)][string]$Port)

    # Prefer esptool.py on PATH (an ESP-IDF PowerShell); otherwise DISCOVER an
    # install rather than pinning one.
    #
    # This used to hardcode esp-idf-v5.3.5 + idf5.3_py3.11_env. CLAUDE.md records
    # that the team runs BOTH 5.3.5 and 5.5.4, so on any laptop that had moved on
    # the fallback pointed at a directory that does not exist and this function
    # simply stopped working -- silently, because the only symptom is "no MAC".
    # Verified 2026-09-23: this machine has 5.5.4 / idf5.5_py3.11_env only.
    $esptool = Get-Command esptool.py -ErrorAction SilentlyContinue
    if ($esptool) {
        $raw = & esptool.py -p $Port read_mac 2>$null
    } else {
        $toolsRoot = if ($env:IDF_TOOLS_PATH) { $env:IDF_TOOLS_PATH }
                     else { Join-Path $(if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }) 'Espressif' }
        # Newest version first, so a laptop with several installs uses the latest.
        $idfRoots = @()
        if ($env:IDF_PATH) { $idfRoots += $env:IDF_PATH }
        $idfRoots += (Get-ChildItem (Join-Path $toolsRoot 'frameworks') -Directory -Filter 'esp-idf-*' -ErrorAction SilentlyContinue |
                      Sort-Object Name -Descending | Select-Object -ExpandProperty FullName)
        $et = $idfRoots |
              ForEach-Object { Join-Path $_ 'components\esptool_py\esptool\esptool.py' } |
              Where-Object { Test-Path $_ } | Select-Object -First 1
        $py = Get-ChildItem (Join-Path $toolsRoot 'python_env') -Directory -ErrorAction SilentlyContinue |
              Sort-Object Name -Descending |
              ForEach-Object { Join-Path $_.FullName 'Scripts\python.exe' } |
              Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue).Source }
        if (-not $et -or -not $py) {
            Write-Warning "esptool.py not on PATH and no ESP-IDF install found under $toolsRoot. Run this from an ESP-IDF PowerShell window."
            return
        }
        $raw = & $py $et -p $Port read_mac 2>$null
    }

    # esptool prints "MAC: xx:xx:..." (twice — before and after the stub); take
    # the last one, which is the stub-confirmed read.
    $line = $raw | Select-String -Pattern '^MAC:' | Select-Object -Last 1
    if (-not $line) {
        Write-Warning "No MAC from $Port (port busy? idf.py monitor open? wrong COM? no board?)"
        return
    }

    $mac   = ($line.Line -split '\s+')[1]
    $bytes = $mac -split ':'
    [pscustomobject]@{
        Port   = $Port
        MAC    = $mac
        NodeId = 'NODE_' + (($bytes -join '').ToUpper())
        CArray = '{' + (($bytes | ForEach-Object { '0x' + $_.ToUpper() }) -join ', ') + '}'
    }
}

# Return every connected CP210x COM port (sorted), parsed from Device Manager.
function Get-Cp210xPorts {
    Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.Name -match 'CP210x.*\(COM\d+\)' } |
        ForEach-Object { if ($_.Name -match '\((COM\d+)\)') { $Matches[1] } } |
        Sort-Object
}

# ── Auto-run when invoked directly with arguments. When DOT-SOURCED (". .\Get-EspMac.ps1")
#    the functions above just load into the session and the block below is skipped. ──
$dotSourced = $MyInvocation.InvocationName -eq '.'

if ($All) {
    $ports = Get-Cp210xPorts
    if (-not $ports) { Write-Warning "No CP210x boards found."; return }
    Write-Host ("Scanning CP210x ports: " + ($ports -join ', ')) -ForegroundColor Cyan
    $ports | ForEach-Object { Get-EspMac $_ } | Format-Table -AutoSize
}
elseif ($Port) {
    Get-EspMac $Port | Format-Table -AutoSize
}
elseif (-not $dotSourced) {
    Write-Host "Usage:  .\tools\Get-EspMac.ps1 -Port COM21        # one board" -ForegroundColor Yellow
    Write-Host "        .\tools\Get-EspMac.ps1 -All               # every connected CP210x board" -ForegroundColor Yellow
    Write-Host "        . .\tools\Get-EspMac.ps1 ; Get-EspMac COM21   # load function, call directly" -ForegroundColor Yellow
}
