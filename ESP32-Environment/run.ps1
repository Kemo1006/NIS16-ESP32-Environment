<#
.SYNOPSIS
  Run an ESP32 node, and OPTIONALLY export its CSVs when you exit the monitor.

.DESCRIPTION
  Opens "idf.py monitor" on the board. By default it JUST runs — nothing is
  exported. Add -Export to have the script run export_logs.py for that board the
  moment you press Ctrl+] to leave the monitor, so you don't type the export
  command by hand. This way not every run auto-exports; you choose per run.

  Ctrl+] only quits idf.py monitor's own terminal UI -- it can't know you typed
  -Export by mistake. So after the monitor closes with -Export/-Clean/-Analyze
  set, the script pauses for a few seconds before actually exporting: press 'n'
  to skip (data stays safe on the board's SPIFFS either way), or press anything
  else / do nothing to proceed right away. For a hard abort at ANY point in this
  script (mid-monitor or mid-export) without closing this PowerShell window, use
  Ctrl+Break -- Windows' equivalent of a shell's Ctrl+\ (Windows consoles don't
  deliver Ctrl+\ as a signal, so Ctrl+Break is the real one here).

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
  .\run.ps1 -Port COM3 -Role child  -Attack blackhole -Wipe -Flash -Export

.EXAMPLE
  # WORMHOLE run: -Attack wormhole flashes the tunnel firmware (-DACTIVE_ATTACK=2).
  # Run ALL THREE boards with -Attack wormhole -Flash; the two victim boards pick
  # opposite ends with -WormholeEnd A (exit) / B (entry). The A<->B tunnel is now
  # a WIRED UART CABLE (Milestone 2): wire Node A GPIO17(TX)->Node B GPIO16(RX),
  # Node A GPIO16(RX)->Node B GPIO17(TX), shared GND, BEFORE powering them on.
  # No MAC to set anymore (WORMHOLE_NODE_A_MAC is obsolete). See WORMHOLE-SETUP.md.
  .\run.ps1 -Port COM11 -Role root   -Attack wormhole              -Wipe -Flash -Export
  .\run.ps1 -Port COM8  -Role child  -Attack wormhole -WormholeEnd A -Wipe -Flash -Export
  .\run.ps1 -Port COM3  -Role child  -Attack wormhole -WormholeEnd B -Wipe -Flash -Export

.EXAMPLE
  # M3: STAR topology (caps depth at 2, everyone a direct child of root).
  # Run EVERY board in the run with the SAME -Topology -Flash, or nodes disagree
  # on shaping. Physical placement still matters most (see verify_topology.py).
  .\run.ps1 -Port COM8 -Role root   -Topology star -Wipe -Flash -Export
  .\run.ps1 -Port COM3 -Role child  -Topology star -Wipe -Flash -Export

.EXAMPLE
  # AUTO-ANALYZE: export THEN run the full M6+M7+M8 pipeline in one step. Add
  # -Analyze on the LAST board you export (the root) so the whole run is present;
  # feature_table.csv AND eda_output\ land in analysis\<attack>\<topology>\.
  .\run.ps1 -Port COM3 -Role child  -Attack blackhole -Wipe -Flash -Export   # victims first
  .\run.ps1 -Port COM8 -Role root   -Attack blackhole -Wipe -Flash -Analyze  # root LAST -> analyzes

.EXAMPLE
  # SCENARIO: BURST — the panel's "user sends 100 packets to root" test. ONE
  # child fires 100 probes back-to-back 60s into the attack-length window; the
  # root ALSO needs -Scenario burst so it holds that window on a baseline run
  # (matched pair: legit burst vs burst-under-attack). Only the target child
  # gets -ScenarioTarget.
  .\run.ps1 -Port COM8 -Role root   -Scenario burst              -Wipe -Flash -Export  # baseline pair
  .\run.ps1 -Port COM3 -Role child  -Scenario burst -ScenarioTarget -Wipe -Flash -Export
  .\run.ps1 -Port COM8 -Role root   -Attack blackhole -Scenario burst                 -Wipe -Flash -Export  # attack pair
  .\run.ps1 -Port COM3 -Role child  -Attack blackhole -Scenario burst -ScenarioTarget -BlackholeRole victim -Wipe -Flash -Export

.EXAMPLE
  # SCENARIO: HIGHLOAD — every child probes 4x faster (250ms) for the whole
  # run, root unchanged. No -ScenarioTarget needed (applies to every child).
  .\run.ps1 -Port COM8 -Role root   -Scenario highload -Wipe -Flash -Export
  .\run.ps1 -Port COM3 -Role child  -Scenario highload -Wipe -Flash -Export

.EXAMPLE
  # SCENARIO: MOBILITY / POWERCYCLE — HUMAN scenarios, no firmware change.
  # -ScenarioTarget just labels which child you will move / unplug-replug;
  # this script prints the checklist for you right before the root boots.
  .\run.ps1 -Port COM8 -Role root   -Scenario mobility                  -Wipe -Flash -Export
  .\run.ps1 -Port COM3 -Role child  -Scenario mobility -ScenarioTarget  -Wipe -Flash -Export
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    # Which PHYSICAL board this is, e.g. node5. Purely an identifier: a COM number
    # names the USB SOCKET here, not the board (these CP210x bridges report
    # duplicate/blank serials, so Windows assigns COM per socket) — so every child
    # goes through the same -Port and only -Label distinguishes them.
    # It is echoed on start and passed to export_logs.py as --label, which puts it
    # in the CSV filename (child_node5_..._telem.csv) instead of the COM number.
    # Does NOT affect the firmware, the build, or what is captured.
    [string]$Label = '',
    # Mesh-position role. 'child' is the preferred name for a non-root board;
    # 'victim' is kept as a working alias (older commands/scripts still run). The
    # CSV `node_role` is written by the FIRMWARE (per thesis Table 4.12), NOT by
    # this flag, so naming a board 'child' here does not change the dataset's
    # security role — the attack role is set separately by -BlackholeRole.
    [Parameter(Mandatory = $true)][ValidateSet('root', 'child', 'victim')][string]$Role,
    # -Topology also picks the BUILD flag when -Flash is set (M3): star => cap
    # depth at 2, linear => force a chain, tree/partial => default self-organising
    # (unchanged M1 behaviour; "partial" comes from physical placement, not a
    # firmware knob). Build EVERY board in a run with the SAME -Topology.
    [ValidateSet('tree', 'star', 'linear', 'partial')][string]$Topology = 'tree',
    # Deployment site for export/analysis routing ONLY — the firmware itself
    # reads its site from /sdcard/location.txt (sd_status.c), not from a build
    # or run flag, so this does NOT affect -Flash. Required whenever -Export/
    # -Clean/-Analyze is set (see the hard-fail below); harmless to omit on a
    # plain flash-and-monitor run. Confirm location.txt on the card matches
    # this value before powering the board on — thesis panel P4 requires the
    # environment be RECORDED, not inferred, and a mismatch here would file
    # the export under a site the card never actually recorded.
    [ValidateSet('home', 'G402', 'DLSU_Library', 'Goks')][string]$Location = '',
    # -Attack also picks the BUILD flag when -Flash is set: blackhole => -DACTIVE_ATTACK=1,
    # wormhole => -DACTIVE_ATTACK=2 (attacker victims also take -WormholeEnd),
    # none => -DACTIVE_ATTACK=255 (baseline; also clears a cached attack build).
    [ValidateSet('none', 'blackhole', 'wormhole')][string]$Attack = 'none',
    # For -Attack wormhole on a victim board, which tunnel end this board is:
    # A = exit/root-side (re-injects to root), B = entry/leaf-side (captures +
    # tunnels). Ignored for the root and for non-wormhole attacks. Run one victim
    # board as A and the other as B.
    [ValidateSet('A', 'B')][string]$WormholeEnd = 'B',
    # For -Attack blackhole on a victim board, which blackhole role this board is:
    # attacker = the relay that forwards/drops victim probes; victim = a board
    # that addresses its probes to the attacker's MAC (BLACKHOLE_ATTACKER_MAC).
    # Ignored for the root and non-blackhole attacks. Run ONE board as attacker
    # and the others as victim.
    [ValidateSet('attacker', 'victim')][string]$BlackholeRole = 'attacker',
    # Export FOLDER override for a control victim in an attack run. The board is
    # flashed -Attack none (it's a plain victim) but its CSV belongs with the
    # run's data, so pass e.g. -DestAttack blackhole to file it under
    # exports/blackhole/<topology>/ instead of exports/baseline/.
    # Only affects where the export lands, not the firmware or the filename.
    [ValidateSet('none', 'blackhole', 'wormhole')][string]$DestAttack = 'none',
    [int]$Repeat      = 1,
    # Run-to-run variation the panel asked for (see THESIS3-PANEL-PLAN.md P2/P7).
    # CODE scenarios pick a BUILD flag when -Flash is set:
    #   burst    => -DTRAFFIC_PROFILE=1 on the root + the -ScenarioTarget child
    #               only. That child fires 100 probes back-to-back 60s into the
    #               attack-length window; the root's copy of the flag makes it
    #               hold that same window on a BASELINE run too (announced as
    #               PHASE_ID_BASELINE, gt_label unchanged) so the burst lands at
    #               the same offset in both -- a matched legit-burst/attack pair.
    #   jitter   => -DTRAFFIC_PROFILE=3 on the ROOT only: randomises (additively)
    #               the baseline and attack window lengths per boot, so elapsed
    #               run-clock time stops predicting the phase label.
    #   highload => -DTRAFFIC_PROFILE=2 on EVERY child (root untouched): probes
    #               at 250ms instead of 1000ms for the whole run.
    # HUMAN scenarios take NO build flag -- they only label the run and, with
    # -ScenarioTarget, print a checklist naming which child to move/power-cycle:
    #   mobility    => move the target child from spot A to spot B
    #   powercycle  => unplug the target child, wait, replug it
    # 'none' is byte-identical to pre-scenario firmware/behaviour.
    [ValidateSet('none', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')][string]$Scenario = 'none',
    # Marks THIS child as the scenario's subject: the burst sender, the node you
    # will move, or the node you will unplug/replug. Exactly one child per run.
    # Ignored (and warned on) for -Scenario none/highload; invalid on the root.
    [switch]$ScenarioTarget,
    [switch]$Flash,    # also (re)flash before monitoring — restarts the experiment
    [switch]$Export,   # after Ctrl+], pull the CSVs with export_logs.py. WITHOUT
                       # this the script just runs and exports NOTHING.
    [switch]$Clean,    # after a successful export, wipe the board's logs so the
                       # NEXT run starts empty (implies -Export)
    [switch]$Wipe,     # BEFORE flashing, clear the board so THIS run starts empty.
                       # WITH -Flash: FULL chip erase (esptool erase_flash) --
                       # bulletproof, auto-fixes a full/crash-looping SPIFFS with
                       # no manual erase-flash. WITHOUT -Flash: light serial
                       # DELETE_LOGS (keeps firmware). Use for a fresh, unstacked run.
    [switch]$Analyze,  # after a successful export, auto-run the full analysis
                       # pipeline over THIS run's exports subfolder: M6
                       # (analysis/preprocess.py -> windowed_dataset.csv), M7
                       # (analysis/features.py -> feature_table.csv), AND M8
                       # (analysis/eda.py -> eda_output/), all written into the
                       # matching analysis/<attack>/<topology>/ folder.
                       # Implies -Export. Use it on the LAST board you export (the
                       # root), so the whole run — every node's CSV + the root's
                       # arrivals.csv (needed for PDR) — is present when it runs.
                       # (M8/EDA needs matplotlib/seaborn/scipy/scikit-learn; if
                       # those aren't installed it runs M6+M7 and skips M8.)
    [switch]$BuildOnly # compile this board's exact variant into its build dir and
                       # stop: no wipe, no flash, no monitor, no export, no port
                       # touched. Exit code = idf.py's. Used by run_wizard.ps1's
                       # pre-build so its builds can never drift from this file's
                       # dir naming / -D flags.
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot

# Build output goes OUTSIDE OneDrive: this repo lives under OneDrive sync, and
# ninja writing ~1000 objects/build dir under a synced+Defender-scanned folder
# is a real, ongoing build-speed tax (not a one-time cost). Tag by parent-
# folder name + a short hash of the full repo path so this can't collide with
# a sibling workstation (CC / NIS16-ESP32-Environment) if someone builds those
# too. Safe to delete %LOCALAPPDATA%\esp32_builds\<tag> anytime for a full
# clean rebuild -- it holds only regenerable ninja/CMake output.
$repoTag   = (Split-Path (Split-Path $base -Parent) -Leaf) + '_' + ([math]::Abs($base.GetHashCode())).ToString('x8')
$buildRoot = Join-Path $env:LOCALAPPDATA "esp32_builds\$repoTag"

function Format-Elapsed {
    # Seconds -> "43s" / "2m 05s", for the export/M6/M7/M8 timing lines below.
    # Kept local rather than shared with run_wizard.ps1's own Format-Duration:
    # these two scripts have no shared function library, and this one only
    # ever needs to format durations of a few seconds to a couple of minutes.
    param([int]$Seconds)
    if ($Seconds -lt 60) { return "${Seconds}s" }
    return "{0}m {1:D2}s" -f ([math]::Floor($Seconds / 60)), ($Seconds % 60)
}

# ── Node -> COM map ──────────────────────────────────────────────────────────
# EDIT HERE if a board is replaced or Windows reassigns a COM number.
# Derived from the COM ports in ascending order, which matches the NODE numbers
# on the floor-plan diagrams (node 5 = COM26 = the red attacker node).
# Verify a board's identity any time with:  python tools\board_check.py --port COMxx
# NOTE: do NOT add a "-Node <n>" alias that maps a logical board number to a COM
# port. It was tried on 2026-07-25 and reverted: these CP210x bridges report
# duplicate/blank USB serial numbers, so Windows cannot tell the boards apart and
# assigns COM numbers per USB SOCKET, not per board (Device Manager shows the same
# COM claimed by several device instances). Moving a board to another socket
# changes its COM, so any fixed node->COM table would eventually flash the WRONG
# board. Identify a board by its MAC instead:  python tools\board_check.py --port COMxx
$proj = if ($Role -eq 'root') { 'root_node' } else { 'child_node' }

# ccache tuning (build-speed). ccache is already ON (idf.py passes CCACHE_ENABLE),
# but the per-variant build dirs above defeat its fast "direct" mode: the same
# source compiled under build_victim_none_tree vs build_victim_blackhole_tree has
# DIFFERENT absolute build paths, so ccache keeps missing across configs. Pointing
# CCACHE_BASEDIR at the project root makes ccache treat those paths as relative,
# so the none/blackhole/wormhole x topology builds SHARE cache entries. Sloppiness
# lets time/pch macros still hit. Measured direct-hit rate was only ~28% without
# this. Setting these in this process' env; idf.py -> ninja -> ccache inherit them.
$env:CCACHE_BASEDIR   = $base
$env:CCACHE_SLOPPINESS = 'pch_defines,time_macros,include_file_mtime'

# -Clean and -Analyze both need the export to have happened first, so both imply
# -Export (you can only wipe-after or analyze data you've actually pulled).
$doExport = $Export.IsPresent -or $Clean.IsPresent -or $Analyze.IsPresent

# -Location is required for anything that writes to exports/ or analysis/ —
# without it the CSVs would file under an unrecorded site. A plain flash-and-
# monitor run (no -Export/-Clean/-Analyze) doesn't need it.
if ($doExport -and -not $Location) {
    throw "-Location is required with -Export/-Clean/-Analyze (home | G402 | DLSU_Library | Goks)."
}

# -ScenarioTarget names the ONE child that is the scenario's subject; the root
# is never the target. Warn (don't fail) if it's set for a scenario that
# doesn't use it, since that's more likely a leftover flag than an error.
if ($ScenarioTarget -and $Role -eq 'root') {
    throw "-ScenarioTarget is for a child board (the burst sender / the node you move or power-cycle), not the root."
}
if ($ScenarioTarget -and $Scenario -in @('none', 'highload')) {
    Write-Host "NOTE: -ScenarioTarget has no effect with -Scenario $Scenario (highload applies to every child; none does nothing)." -ForegroundColor Yellow
}

# 0-pre) Auto-free THIS port. The #1 cause of "Could not open COMxx ... Access
#    is denied" on flash is a stale idf.py/idf_monitor from an earlier run still
#    holding the port (a monitor left open, not Ctrl+]-ed). Kill ONLY Espressif
#    python processes whose command line targets THIS exact port -- never another
#    board's monitor, never this script (it's powershell, not python), and never
#    the flash/monitor this run is about to start (that process doesn't exist yet).
$portEsc = [regex]::Escape($Port)
$stale = Get-CimInstance Win32_Process -Filter "name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -like '*Espressif*' -and
                   $_.CommandLine -match "\b$portEsc\b" -and
                   $_.CommandLine -match 'idf_monitor|esp_idf_monitor|idf\.py|esptool' }
if ($stale -and -not $BuildOnly) {
    foreach ($p in $stale) {
        Write-Host "Freeing ${Port}: stopping stale process $($p.ProcessId) still holding it." -ForegroundColor DarkYellow
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { }
    }
    Start-Sleep -Milliseconds 600   # let the CP210x driver release the handle
}

# 0) Optional pre-run wipe so this run's CSV is a single clean run (no stacking).
#    Two modes:
#    * -Wipe WITH -Flash  -> FULL CHIP ERASE (esptool erase_flash). This clears
#      the whole SPIFFS at the bootloader level, so it ALWAYS works even on a
#      board that's crash-looping on a full filesystem (root aborting with
#      "Failed to open arrivals file", or a child spamming "fprintf failed") --
#      the light serial DELETE_LOGS can't reach a crashing board, this can.
#      Safe because -Flash re-writes bootloader+partitions+app right after.
#      Falls back to the serial wipe if erase_flash can't run. This is what makes
#      "storage full" self-heal: every -Wipe -Flash run starts truly empty, no
#      manual `idf.py ... erase-flash` needed.
#    * -Wipe WITHOUT -Flash -> light serial DELETE_LOGS only (keeps the firmware;
#      the on-device command listener runs from boot, so DELETE_LOGS is accepted).
# ---------------------------------------------------------------------------
# GIVE THE BOARD A REAL CLOCK -- BEFORE the erase, BEFORE the flash.
# ---------------------------------------------------------------------------
# An ESP32 has no RTC and never reaches NTP, so on its own it dates every file,
# folder and manifest row from the firmware's BUILD timestamp. That value is
# baked in at link time and is IDENTICAL on every boot of one flash, which is
# why deleting a card's CSVs and re-running produced the SAME date: it never
# described the run. The board's clock can only come from a laptop.
#
# WHY HERE AND NOT LATER: the board keeps the anchor on its SD card and starts
# the next boot from it, but only if the anchor is NEWER than the incoming
# firmware's build stamp (sd_status_apply_clock_anchor() only ever moves the
# clock forward). A fresh build is minutes old, so an anchor from the last
# session would lose to it and the first run after a flash would fall back to a
# build-time estimate. Writing the anchor seconds before flashing beats the new
# build stamp, so even that first run is on a real clock.
#
# Ordering is load-bearing: this must precede -Wipe -Flash's esptool
# erase_flash, because an erased board has no firmware left to accept the
# command. Best-effort throughout -- a board that is unplugged, busy, or still
# running pre-SET_TIME firmware just keeps the old estimate, and nothing about
# a run depends on this succeeding.
if (-not $BuildOnly) {
    Write-Host "Setting $Port's clock from this laptop (so captures get real dates) ..." -ForegroundColor DarkGray
    Push-Location (Join-Path $base 'tools')
    try { python export_logs.py --port $Port --set-time } catch { } finally { Pop-Location }
}

if ($Wipe -and -not $BuildOnly) {
    if ($Flash) {
        Write-Host "Full-erasing $Port before this run (guaranteed-clean SPIFFS; auto-fixes 'storage full') ..." -ForegroundColor Yellow
        $erased = $false
        try {
            esptool.py --chip esp32 --port $Port erase_flash
            if ($LASTEXITCODE -eq 0) { $erased = $true }
        } catch { }
        if (-not $erased) {
            Write-Host "erase_flash didn't run (port busy? board unplugged?) -- falling back to serial DELETE_LOGS." -ForegroundColor Yellow
            Push-Location (Join-Path $base 'tools')
            try { python export_logs.py --port $Port --wipe } finally { Pop-Location }
        }
    } else {
        Write-Host "Wiping old logs on $Port before this run (serial DELETE_LOGS; firmware kept) ..." -ForegroundColor Yellow
        Push-Location (Join-Path $base 'tools')
        try { python export_logs.py --port $Port --wipe } finally { Pop-Location }
    }
}

# Map -Attack to the ACTIVE_ATTACK build flag(s) (only meaningful when flashing).
# Always pass an explicit value so a plain run also CLEARS a cached attack build:
# none => 255 (ATTACK_NONE / baseline), blackhole => 1, wormhole => 2. For a
# wormhole victim board we also pass -DWORMHOLE_END (A=0 exit, B=1 entry).
$attackFlags = @()
switch ($Attack) {
    'blackhole' {
        $attackFlags += '-DACTIVE_ATTACK=1'
        if ($Role -ne 'root') {
            # attacker relay = 0, victim-that-targets-attacker = 1
            $bhNum = if ($BlackholeRole -eq 'victim') { 1 } else { 0 }
            $attackFlags += "-DBLACKHOLE_ROLE=$bhNum"
        }
    }
    'wormhole'  {
        $attackFlags += '-DACTIVE_ATTACK=2'
        if ($Role -ne 'root') {
            $endNum = if ($WormholeEnd -eq 'A') { 0 } else { 1 }
            $attackFlags += "-DWORMHOLE_END=$endNum"
        }
    }
    default     { $attackFlags += '-DACTIVE_ATTACK=255' }
}

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

# Map -Scenario to the TRAFFIC_PROFILE build flag (only meaningful when
# flashing). Unlike -Attack/-Topology, 'none' passes NO flag at all -- the
# mesh_config.h #ifndef default already IS "none", so a plain run's compile
# command line (and build dir) stays byte-identical to before this feature
# existed. Only the boards that actually change firmware get a flag/tag:
#   burst    -> root (baseline-run window) + the -ScenarioTarget child (sender)
#   highload -> every child; root untouched
#   mobility / powercycle -> no flag anywhere (human, label-only)
$scenarioFlags = @()
$scenarioTag   = ''
switch ($Scenario) {
    'burst' {
        if ($Role -eq 'root' -or $ScenarioTarget) {
            $scenarioFlags += '-DTRAFFIC_PROFILE=1'
            $scenarioTag = 'burst'
        }
    }
    'highload' {
        if ($Role -ne 'root') {
            $scenarioFlags += '-DTRAFFIC_PROFILE=2'
            $scenarioTag = 'highload'
        }
    }
    'jitter' {
        # ROOT ONLY -- the root is the only board that schedules phases; every
        # child just follows the broadcasts, so a jitter child binary would be
        # byte-identical to a plain one and only cost an extra build dir.
        if ($Role -eq 'root') {
            $scenarioFlags += '-DTRAFFIC_PROFILE=3'
            $scenarioTag = 'jitter'
        }
    }
}

# Give each distinct firmware variant its OWN build directory. Without this,
# running multiple -Role child  boards at once (e.g. wormhole Node A + Node B +
# a normal victim, all three "child_node") race on the SAME build/ folder --
# concurrent CMake/ninja processes stomp on build.ninja and you get
# "ninja: error: failed recompaction: Permission denied". Root never collided
# (separate project dir), but the three victim variants share one otherwise.
$buildSuffix = "$Role`_$Attack`_$Topology"
if ($Attack -eq 'wormhole'  -and $Role -ne 'root') { $buildSuffix += "_$WormholeEnd" }
if ($Attack -eq 'blackhole' -and $Role -ne 'root') { $buildSuffix += "_$BlackholeRole" }
# SCENARIO TAG RULE (kept identical in menu.ps1 Get-BuildDirSpec and
# run_wizard.ps1 Get-BoardBuildDir): only a board that actually receives
# -DTRAFFIC_PROFILE gets a suffix, so a plain 'none'/'mobility'/'powercycle'
# board's build dir is untouched.
if ($scenarioTag) { $buildSuffix += "_$scenarioTag" }
# Per-COM-port build dir: append a sanitized port tag (COM25 -> COM25) so that
# multiple boards running the SAME firmware variant (e.g. two plain baseline
# victims, or two blackhole victims) each build in their OWN folder and can
# flash in PARALLEL from separate windows without racing build.ninja
# ("failed recompaction: Permission denied"). Trade-off: the first build per
# port is a full build (ccache CCACHE_BASEDIR above still shares most objects
# across ports). Root has its own project dir but is keyed by port too for
# consistency.
$portTag     = ($Port -replace '[^A-Za-z0-9]', '')
$buildDirName = "build_${buildSuffix}_$portTag"
# Absolute path under $buildRoot (see top of file) -- idf.py -B accepts an
# absolute path just as well as a relative one, and this is what actually
# moves compiled output off OneDrive; $proj (root_node/child_node) stays the
# CMake SOURCE dir, still under OneDrive, unchanged.
$buildDir = Join-Path $buildRoot "$proj\$buildDirName"

# Deliberately keyed by PORT, not by -Label: boards sharing a port also share
# identical firmware, so one build dir serves all of them (faster, less disk).
# Labelling per board would rebuild the same image five times.
if ($Label) { Write-Host "Board: $Label (on $Port)" -ForegroundColor Cyan }

# Self-heal a build dir cached against a DIFFERENT absolute project path. CMake
# bakes the absolute source path into CMakeCache.txt at configure time; if this
# repo folder ever gets moved/renamed/re-cloned elsewhere (e.g. reorganized into
# a different folder, or checked out fresh by another teammate at a different
# path) a leftover build_* dir from the old location makes idf.py hard-fail with
# "Build directory ... configured for project 'OLD\path' not 'NEW\path'. Run
# 'idf.py fullclean' to start again." build_* dirs are git-ignored disposable
# artifacts, so instead of failing we just wipe the stale one and let it
# reconfigure from scratch — no manual fullclean needed by anyone.
$cacheFile = Join-Path $buildDir "CMakeCache.txt"
if (($Flash -or $BuildOnly) -and (Test-Path $cacheFile)) {
    $expectedHome = (Join-Path $base $proj) -replace '\\', '/'
    $cachedHomeLine = Select-String -Path $cacheFile -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
    if ($cachedHomeLine) {
        $cachedHome = ($cachedHomeLine.Line -split '=', 2)[1]
        if ($cachedHome -and ($cachedHome.TrimEnd('/') -ne $expectedHome.TrimEnd('/'))) {
            Write-Host "Stale build dir '$buildDir' was configured for a different path ($cachedHome) -- wiping it so this run reconfigures cleanly." -ForegroundColor Yellow
            Remove-Item -Recurse -Force $buildDir
        }
    }
}

# Self-heal a build dir left half-configured by an interrupted build (Ctrl+Break,
# a killed idf.py, etc.). Symptom: CMakeCache.txt/build.ninja exist but the
# generated config\sdkconfig.h never got CONFIG_IDF_TARGET_ESP32 written into it,
# so esp-idf's soc_caps.h can't determine the ECO version and sha_hal.c fails with
# "SHA_TYPE"/"SHA1" undeclared -- a plain rebuild just reuses the same broken tree
# forever. Same remedy as the path-mismatch case above: wipe and let it reconfigure.
$sdkconfigH  = Join-Path $buildDir "config\sdkconfig.h"
$sdkconfigOk = (Test-Path $sdkconfigH) -and (Select-String -Path $sdkconfigH -Pattern '^#define CONFIG_IDF_TARGET_ESP32\b' -Quiet)
if (($Flash -or $BuildOnly) -and (Test-Path $cacheFile) -and -not $sdkconfigOk) {
    Write-Host "Stale build dir '$buildDir' has an incomplete sdkconfig.h (interrupted build?) -- wiping it so this run reconfigures cleanly." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $buildDir
}

if ($BuildOnly) {
    Write-Host "Building $Role for $Port (attack=$Attack, topology=$Topology, scenario=$Scenario, build=$buildDir) - no flash." -ForegroundColor Cyan
    Push-Location (Join-Path $base $proj)
    try { idf.py -B $buildDir @attackFlags $topologyFlag @scenarioFlags build } finally { Pop-Location }
    exit $LASTEXITCODE
}

# What happens after Ctrl+], for the on-screen hint.
$exitHint = if ($doExport) { "to auto-export (you'll get a few seconds to cancel with 'n')" } else { "to quit (no export)" }

# HUMAN scenarios (mobility/powercycle) have no firmware to flash -- this is
# the one place both front-ends and a bare run.ps1 call are guaranteed to pass
# through, so it's the single spot that prints the checklist. Shown once, right
# before the board boots, so it's on screen for the whole run rather than
# scrolled away by monitor output. Waits for Enter only when there's an actual
# human at the console (skip it under an unattended/-WhatIf-style invocation).
function Show-ScenarioChecklist {
    param([string]$Scenario, [bool]$IsTarget, [string]$Role)
    if ($Scenario -notin @('mobility', 'powercycle')) { return }

    $verb = if ($Scenario -eq 'mobility') {
        "MOVE the target child from its start spot to its second spot"
    } else {
        "UNPLUG the target child's USB/power, wait ~10s, then PLUG IT BACK IN"
    }
    Write-Host ""
    Write-Host "============ SCENARIO: $Scenario (HUMAN -- you do this, not the code) ============" -ForegroundColor Magenta
    Write-Host " $verb." -ForegroundColor Magenta
    Write-Host " WHEN: as soon as the ROOT console prints 'PHASE -- ATTACK'  (attack run)" -ForegroundColor Magenta
    Write-Host "       or about halfway through 'PHASE 0 -- BASELINE'        (baseline run)" -ForegroundColor Magenta
    Write-Host " Do it ONCE, in one motion; keep the board powered afterward -- it keeps" -ForegroundColor Magenta
    Write-Host " logging (CSV_EXPORT_ON_INIT, append mode). Note both spots / the exact time" -ForegroundColor Magenta
    Write-Host " in the ledger yourself -- this tooling does NOT time or beep this for you." -ForegroundColor Magenta
    if ($IsTarget) {
        Write-Host " THIS board ($Role on $Port) IS the $Scenario target." -ForegroundColor Magenta
    }
    Write-Host "====================================================================================" -ForegroundColor Magenta
    if ([Environment]::UserInteractive) {
        Write-Host " Press Enter once you've read this ..." -ForegroundColor DarkGray -NoNewline
        [void][Console]::ReadLine()
    }
}
Show-ScenarioChecklist -Scenario $Scenario -IsTarget $ScenarioTarget.IsPresent -Role $Role

# 1) Monitor (optionally flash first). Ctrl+] exits the monitor and returns here.
Push-Location (Join-Path $base $proj)
try {
    if ($Flash) {
        $attackLabel = if ($Attack -eq 'wormhole' -and $Role -ne 'root') { "wormhole/$WormholeEnd" } else { $Attack }
        $scenarioLabel = if ($Scenario -ne 'none') { $Scenario + $(if ($ScenarioTarget) { '+target' } else { '' }) } else { 'none' }
        Write-Host "Flashing + monitoring $Role on $Port (topology=$Topology, attack=$attackLabel, scenario=$scenarioLabel, build=$buildDir). Ctrl+] when it reaches 'terminate' $exitHint." -ForegroundColor Cyan
        idf.py -B $buildDir @attackFlags $topologyFlag @scenarioFlags -p $Port flash monitor
    } else {
        if ($Attack -ne 'none' -or $Topology -ne 'tree') {
            Write-Host "NOTE: -Attack/-Topology have no effect without -Flash; monitoring the CURRENTLY flashed firmware." -ForegroundColor Yellow
        }
        Write-Host "Monitoring $Role on $Port (build=$buildDir). Ctrl+] when it reaches 'terminate' $exitHint." -ForegroundColor Cyan
        idf.py -B $buildDir -p $Port monitor
    }
} finally {
    Pop-Location
}

# 2) Monitor closed. Export only if asked. (export_logs.py deasserts DTR/RTS so
#    opening the port does NOT reset the board / kill its export task.)
$laterHint = "To export later:  python tools\export_logs.py --port $Port --role $Role --topology $Topology --attack $Attack --repeat $Repeat --scenario $Scenario"
if ($Location) { $laterHint += " --location $Location" }
# Carry -Label through. Without it the hint would produce child_<COM>_..._telem.csv, and
# since every board is exported through the SAME port, all of them would collide on a name
# that differs only by timestamp. The label is what keeps the files identifiable.
if ($Label)                  { $laterHint += " --label $Label" }
if ($DestAttack -ne 'none') { $laterHint += " --attack-dir $DestAttack" }

if (-not $doExport) {
    Write-Host "`nMonitor closed - run only (no export). Data is safe on the board's SPIFFS." -ForegroundColor Green
    Write-Host $laterHint -ForegroundColor DarkGray
    return
}

# Cancel window: Ctrl+] just quit idf.py monitor's own terminal UI, it has no
# say over the -Export/-Clean/-Analyze that follows -- so if you meant -Flash
# ONLY and typed -Export by accident, this is the chance to bail before
# anything actually leaves the board. Data is append-mode on SPIFFS either way,
# so skipping here costs nothing. Press 'n' to skip; any other key (or letting
# the timer run out) proceeds right away, so correct/intentional -Export runs
# aren't meaningfully slowed down.
Write-Host "`nMonitor closed - exporting $Role CSVs from $Port in 5s. Press 'n' to skip." -ForegroundColor Yellow
$skipExport = $false
$deadline = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $deadline) {
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::N) { $skipExport = $true }
        break   # any keypress decides it now -- don't make them sit out the timer
    }
    Start-Sleep -Milliseconds 100
}
if ($skipExport) {
    Write-Host "Export skipped. Data is safe on $Port's SPIFFS." -ForegroundColor Green
    Write-Host $laterHint -ForegroundColor DarkGray
    return
}

# Spans export + whatever analysis follows, for the "total" line at the very
# end of the script - the one place both the -Analyze and non-Analyze exit
# paths converge, so it always reports the full tail of the run regardless of
# which stages actually ran.
$exportAnalysisStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Exporting $Role CSVs from $Port ..." -ForegroundColor Green
Push-Location (Join-Path $base 'tools')
try {
    $exportArgs = @('export_logs.py', '--port', $Port, '--role', $Role,
                    '--topology', $Topology, '--location', $Location,
                    '--attack', $Attack, '--repeat', $Repeat,
                    '--scenario', $Scenario)
    # Name the file after the BOARD, not the socket it happened to be plugged into.
    if ($Label) { $exportArgs += @('--label', $Label) }
    # File a control victim (flashed attack=none) with its attack run's folder.
    if ($DestAttack -ne 'none') { $exportArgs += @('--attack-dir', $DestAttack) }
    if ($Clean) { $exportArgs += '--delete' }   # wipe board AFTER a good download
    $exportStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    python @exportArgs
    $exportStopwatch.Stop()
} finally {
    Pop-Location
}
Write-Host ("Done in {0}. Files are in tools\exports\." -f (Format-Elapsed ([int]$exportStopwatch.Elapsed.TotalSeconds))) -ForegroundColor Green
if ($Clean) { Write-Host "Board logs wiped (--delete) - next run starts empty. SD card mirror archived (--archive-sd), not deleted." -ForegroundColor Green }

# 3) Optional auto-analysis (M6+M7+M8). The CSVs stay put in exports\; we just READ
#    this run's exports subfolder and write the feature table (M6+M7) AND the EDA
#    plots/tables (M8) into the MIRRORING folder under analysis\. Routing matches
#    export_logs.py exactly: a control victim uses -DestAttack, otherwise -Attack;
#    'none' -> baseline. Topology dir names mirror export_logs.py's _TOPOLOGY_DIR so
#    exports\<a>\<t>\ <-> analysis\<a>\<t>\.
if ($Analyze) {
    $attackDir = if ($DestAttack -ne 'none') { $DestAttack }
                 elseif ($Attack -ne 'none') { $Attack }
                 else { 'baseline' }
    $topoDir = switch ($Topology) {
        'star'    { 'star' }
        'tree'    { 'tree' }
        'linear'  { 'linear' }
        'partial' { 'partial_mesh' }
    }
    # 'none' must NOT become a real folder segment - it's the pre-scenario
    # default, so an un-scenario'd run (the vast majority) resolves to the
    # SAME path this always used. Must stay byte-identical to _subdir_for()
    # in tools\export_logs.py and Get-RunDirs in run_wizard.ps1.
    $scenarioSeg = if ($Scenario -and $Scenario -ne 'none') { "\$Scenario" } else { '' }
    $exportSub   = Join-Path $base "tools\exports\$attackDir\$topoDir\$Location$scenarioSeg"
    $analysisSub = Join-Path $base "analysis\$attackDir\$topoDir\$Location$scenarioSeg"

    # Pick a python for the pipeline. The ESP-IDF shell's `python` (the py3.11 IDF
    # env) may lack the analysis deps while a separate CPython has them, so scan a
    # few candidates. Two tiers: features.py (M6+M7) needs only pandas/numpy, but
    # eda.py (M8) also needs matplotlib/seaborn/scipy/scikit-learn. Prefer a python
    # with the FULL stack (runs both); fall back to a pandas-only one (features
    # only, EDA skipped with a hint). Data is already safe in exports\, so if none
    # is usable we just skip analysis rather than failing the run.
    $edaPy = $null        # full EDA stack -> can run features AND eda
    $featuresPy = $null   # at least pandas/numpy -> can run features
    foreach ($cand in @('python', 'python3', 'C:\Python314\python.exe')) {
        if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
        & $cand -c "import pandas, numpy, matplotlib, seaborn, scipy, sklearn" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $edaPy = $cand
            if (-not $featuresPy) { $featuresPy = $cand }
            break
        }
        if (-not $featuresPy) {
            & $cand -c "import pandas, numpy" 2>$null
            if ($LASTEXITCODE -eq 0) { $featuresPy = $cand }
        }
    }

    if (-not $featuresPy) {
        Write-Host "Skipping auto-analysis: no python with pandas/numpy found." -ForegroundColor Yellow
        Write-Host "  Fix once:  pip install -r analysis\requirements.txt   then re-run with -Analyze." -ForegroundColor DarkGray
    }
    elseif (-not (Test-Path $exportSub)) {
        Write-Host "Skipping auto-analysis: no exported CSVs in $exportSub." -ForegroundColor Yellow
    }
    else {
        if (-not (Test-Path $analysisSub)) { New-Item -ItemType Directory -Force -Path $analysisSub | Out-Null }
        $windowedOut = Join-Path $analysisSub 'windowed_dataset.csv'
        $featOut = Join-Path $analysisSub 'feature_table.csv'

        # ── TRIM FIRST — must stay identical to analyze.ps1's Invoke-Analyze ──
        # This step was MISSING here until sep. 22, 2026, while analyze.ps1 has
        # always done it. The consequence was not cosmetic: a raw export folder
        # can hold SEVERAL boot sessions, and the one that matters is NOT simply
        # the longest (the smart trimmer scores phase progression — a real 400-row
        # run beat a 3000-row idle session). So auto-analysis after a capture was
        # silently folding idle/boot sessions into the feature table, while a later
        # `.\analyze.ps1` on the SAME capture trimmed them out and produced a
        # DIFFERENT table — written to the very same feature_table.csv path, with
        # nothing in the artifact to say which pipeline produced it.
        # If one of these two call sites changes, change the other.
        $analysisSrc = $exportSub
        $trimmedDir  = Join-Path $exportSub 'trimmed'
        # Clear a stale trimmed/ from an earlier partial run: the analysis tools
        # glob the folder, so leftovers load as if they were this run's data.
        if (Test-Path $trimmedDir) { Remove-Item $trimmedDir -Recurse -Force }
        Write-Host "`nAuto-analysis (trim): trim_run.py over $attackDir\$topoDir\$Location$scenarioSeg ..." -ForegroundColor Cyan
        Push-Location (Join-Path $base 'tools')
        try { & $featuresPy trim_run.py $exportSub --apply } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) {
            # Never fatal: the raw export is the evidence and is untouched. Fall
            # back to the raw folder and SAY SO, rather than letting the numbers
            # below look like they came from a trimmed capture.
            Write-Host "Trim failed (exit $LASTEXITCODE) - analysing the RAW export. Re-run .\analyze.ps1 once fixed." -ForegroundColor Yellow
        }
        elseif (Test-Path $trimmedDir) {
            $analysisSrc = $trimmedDir
            Write-Host "Trimmed -> analysing trimmed\ (raw export untouched)" -ForegroundColor Green
        }
        else {
            Write-Host "Trim produced no trimmed\ folder - analysing the RAW export." -ForegroundColor Yellow
        }

        Write-Host "`nAuto-analysis (M6): $featuresPy preprocess.py over $attackDir\$topoDir\$Location$scenarioSeg ..." -ForegroundColor Cyan
        $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()
        Push-Location (Join-Path $base 'analysis')
        try { & $featuresPy preprocess.py $analysisSrc -o $windowedOut } finally { Pop-Location }
        $stageWatch.Stop()
        $m6Elapsed = Format-Elapsed ([int]$stageWatch.Elapsed.TotalSeconds)

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Preprocess step failed after $m6Elapsed (exit $LASTEXITCODE). Data is still safe in exports\; see the error above." -ForegroundColor Yellow
        } else {
            Write-Host "Windowed dataset done in $m6Elapsed -> analysis\$attackDir\$topoDir\$Location$scenarioSeg\windowed_dataset.csv" -ForegroundColor Green

            Write-Host "Auto-analysis (M7): $featuresPy features.py over $attackDir\$topoDir\$Location$scenarioSeg ..." -ForegroundColor Cyan
            $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()
            Push-Location (Join-Path $base 'analysis')
            try { & $featuresPy features.py $analysisSrc -o $featOut } finally { Pop-Location }
            $stageWatch.Stop()
            $m7Elapsed = Format-Elapsed ([int]$stageWatch.Elapsed.TotalSeconds)
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Feature step failed after $m7Elapsed (exit $LASTEXITCODE). Data is still safe in exports\; see the error above." -ForegroundColor Yellow
            } else {
                Write-Host "Features done in $m7Elapsed -> analysis\$attackDir\$topoDir\$Location$scenarioSeg\feature_table.csv" -ForegroundColor Green

                # M8 EDA — needs the full stack. Runs on the feature table we just wrote.
                if ($edaPy) {
                    $edaOut = Join-Path $analysisSub 'eda_output'
                    Write-Host "Auto-analysis (M8): $edaPy eda.py -> $attackDir\$topoDir\$Location$scenarioSeg\eda_output ..." -ForegroundColor Cyan
                    $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()
                    Push-Location (Join-Path $base 'analysis')
                    try { & $edaPy eda.py $featOut -o $edaOut } finally { Pop-Location }
                    $stageWatch.Stop()
                    $m8Elapsed = Format-Elapsed ([int]$stageWatch.Elapsed.TotalSeconds)
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "EDA done in $m8Elapsed -> analysis\$attackDir\$topoDir\$Location$scenarioSeg\eda_output\" -ForegroundColor Green
                    } else {
                        Write-Host "EDA step failed after $m8Elapsed (exit $LASTEXITCODE). feature_table.csv is fine; see the error above." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Skipping M8/EDA: python has pandas but not matplotlib/seaborn/scipy/scikit-learn." -ForegroundColor Yellow
                    Write-Host "  Fix once:  pip install -r analysis\requirements.txt   then re-run with -Analyze." -ForegroundColor DarkGray
                }
            }
        }
    }
}

# Reported unconditionally at the very end - the one point where the -Analyze
# and non-Analyze paths above both converge, so this always covers whatever
# actually ran (export alone, or export + M6/M7/M8).
Write-Host ("`nExport + analysis: {0} total" -f (Format-Elapsed ([int]$exportAnalysisStopwatch.Elapsed.TotalSeconds))) -ForegroundColor DarkGray
