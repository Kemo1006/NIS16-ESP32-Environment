<#
.SYNOPSIS
  Interactive numbered-menu front-end for run.ps1.

.DESCRIPTION
  Walks you through one capture run - attack, topology, location, repeat, and the
  board roster - then drives every board through run.ps1 in the correct order
  (children first, ROOT last) with -Export on the children and -Analyze on the root,
  so CSVs and the M6->M8 analysis land automatically.

  Orchestration only: every flash/export/analysis is still done by run.ps1.

  MULTI-LAPTOP SPLIT: when a group has several laptops (e.g. Laptop A runs the
  root + some children, Laptop B runs the blackhole attacker + other children),
  answer the roster questions for the FULL experiment on every laptop, then mark
  which of those boards are physically plugged into THIS one when asked. Boards
  marked as living on another laptop are recorded for the hand-off summary and
  the blackhole attacker-MAC cross-check, but are never flashed/run/saved from
  here - each laptop only ever executes and saves presets for its OWN boards.

.PARAMETER DryRun
  Walk the menus and print the command list, but execute nothing.

.PARAMETER Preset
  Load a saved roster (JSON) instead of answering the menus again. Omit it and
  the wizard lists presets\*.json for you to pick from, shows what the chosen one
  contains - boards, ports, roles, attacker, MACs - and asks you to confirm
  before anything is flashed.

.PARAMETER Repeat
  Override the preset's repeat number - the one thing that changes between r1/r2/r3.
  Supplied on the command line it wins; picking a preset from the menu prompts for it.

.PARAMETER SkipMacCheck
  Skip reading the attacker board's MAC and comparing it to mesh_config.h.

.EXAMPLE
  .\run_wizard.ps1 -DryRun
  .\run_wizard.ps1
  .\run_wizard.ps1 -Preset presets\linear-blackhole.json -Repeat 2
#>
param(
    [switch]$DryRun,
    [string]$Preset,
    [int]$Repeat = 0,
    [switch]$SkipMacCheck
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot

# Build output goes OUTSIDE OneDrive -- same reasoning and same tag formula as
# run.ps1 (keep these two in sync so both scripts resolve the SAME build dir
# for the same board/variant and share ccache-warm output instead of doubling
# disk/build time). Safe to delete %LOCALAPPDATA%\esp32_builds\<tag> anytime.
$repoTag   = (Split-Path (Split-Path $base -Parent) -Leaf) + '_' + ([math]::Abs($base.GetHashCode())).ToString('x8')
$buildRoot = Join-Path $env:LOCALAPPDATA "esp32_builds\$repoTag"

# Capture -Repeat NOW, before anything assigns to $repeat. PowerShell variable names
# are case-INSENSITIVE, so the $Repeat parameter and a local $repeat are one and the
# same variable - loading a preset into $repeat would silently clobber the override.
$repeatOverride = $Repeat

# Every prompt loop is bounded by this. Without it, a prompt whose input stream has
# run dry (piped stdin, non-interactive shell) re-prompts forever on empty reads.
$script:MaxPromptTries = 8

# Ports identified this session via Invoke-Identify (COM -> "MAC -> name"), so a
# port read once shows what it is everywhere else in this run - port list, role
# menus - without re-reading it (each read briefly resets the board).
$script:IdentifiedPorts = @{}

$ATTACKS    = @('none', 'blackhole', 'wormhole')
$TOPOLOGIES = @('linear', 'tree', 'star', 'partial')
$LOCATIONS  = @('home', 'G402', 'DLSU_Library', 'Goks')

# Run-to-run variation the panel asked for. 'none' is byte-identical to the
# pre-scenario wizard. Keep the ValidateSet in run.ps1 in sync with this list.
$SCENARIOS = @('none', 'burst', 'highload', 'mobility', 'powercycle')
$SCENARIO_LABELS = @(
    "none        - today's behaviour, no variation",
    'burst       - CODE: one child fires 100 probes back-to-back in the attack window',
    'highload    - CODE: every child probes 4x faster for the whole run',
    'mobility    - HUMAN: you move one child from spot A to spot B (checklist only)',
    'powercycle  - HUMAN: you unplug/replug one child (checklist only)'
)

# ---------------------------------------------------------------- helpers ----

function Read-Line {
    param([string]$Prompt)
    Write-Host -NoNewline $Prompt
    return (Read-Host)
}

function Test-BackAnswer {
    # Shared "did they type b/back" check for every prompt that opts into
    # -AllowBack below, so the wizard's step machine (the "from menus" capture
    # flow) has one consistent way to recognise it everywhere.
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('b', 'back')))
}

function Test-ScenarioNeedsTarget {
    # burst/mobility/powercycle need exactly ONE child picked as the subject
    # (the burst sender / the node moved / the node power-cycled). highload
    # applies to every child automatically; none needs nothing.
    param([string]$Scenario)
    return $Scenario -in @('burst', 'mobility', 'powercycle')
}

function Test-BurstEligible {
    # Only victim_main.c carries the burst logic, so a board is eligible only
    # if it will BE victim_main.c: a plain child, a blackhole VICTIM (not the
    # attacker relay), or a wormhole run's 'control' board. Attacker / wormhole
    # A / B boards build blackhole_victim.c / wormhole_victim.c and are not
    # eligible in this version.
    param($Child)
    return $Child.Kind -in @('plain', 'victim', 'control')
}

function Show-Menu {
    # Returns the 0-based index of the chosen option, or -1 if the caller
    # passed -AllowBack and the operator typed 'b'/'back' - callers that opt
    # in are expected to check for -1 before indexing anything with it.
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = -1,   # -1 = no default, must choose
        [switch]$AllowBack
    )
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -eq $DefaultIndex) {
            # The default is marked right on its option line, not only in the
            # prompt below, so scanning the list alone shows what Enter picks.
            # The numbers are bracketed [N] to match the "keep [N]" prompt hint;
            # on their own the brackets could read as "already chosen", so the
            # explicit "<- default (press Enter)" marker is what actually signals
            # the default here - the brackets are just the selector style.
            Write-Host ("  [{0}] {1}  <- default (press Enter)" -f ($i + 1), $Options[$i]) -ForegroundColor Green
        }
        else {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i])
        }
    }
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid selection for '$Title' after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        # Spells out both paths on the prompt itself instead of relying on the
        # reader already knowing "[N]" means "the default" - same reasoning as
        # the list marker above.
        $backHint = if ($AllowBack) { ", or 'b' to go back" } else { '' }
        $hint = if ($DefaultIndex -ge 0) {
            "Press Enter to keep [$($DefaultIndex + 1)], or type 1-$($Options.Count) for another option$backHint > "
        } else {
            "Type 1-$($Options.Count)$backHint > "
        }
        $raw = Read-Line $hint
        if ($AllowBack -and (Test-BackAnswer $raw)) { return -1 }
        if (-not $raw -and $DefaultIndex -ge 0) { return $DefaultIndex }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return ($n - 1)
        }
        Write-Host "  Enter a number from 1 to $($Options.Count)." -ForegroundColor Yellow
    }
}

function Get-PortList {
    # Instant enumeration - no esptool, no board contact. Identification is on demand.
    $names = @()
    try { $names = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object) } catch { $names = @() }

    $desc = @{}
    try {
        Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\(COM\d+\)' } |
            ForEach-Object {
                if ($_.Name -match '\((COM\d+)\)') {
                    $desc[$Matches[1]] = ($_.Name -replace '\s*\(COM\d+\)\s*$', '')
                }
            }
    } catch { }

    $out = @()
    foreach ($n in $names) {
        $d = $desc[$n]
        if (-not $d) { $d = 'unknown device' }
        $out += [pscustomobject]@{ Port = $n; Description = $d; Kind = (Get-PortKind -Description $d) }
    }
    return $out
}

function Get-PortKind {
    # Classifies a COM device by its driver description, so the wizard can refuse
    # to drive esptool/export_logs at hardware that is not an ESP32. Everything
    # with a serial driver lands in the same list - Bluetooth links, a Logitech
    # receiver, a hub's virtual port - and esptool's first move is to yank DTR/RTS
    # and shove the device into a bootloader handshake it was never designed for.
    #
    #   BRIDGE  - a USB-to-UART bridge chip; what an ESP32 dev board shows up as.
    #   BLOCKED - positively identified as something else. Never touched.
    #   UNKNOWN - can't tell. Allowed, but only after typing the port name.
    #
    # Deny is checked BEFORE allow on purpose: a description can contain both
    # (e.g. a Bluetooth stack that also says "Serial"), and the safe reading of an
    # ambiguous name is the one that doesn't poke someone's mouse receiver.
    param([string]$Description)
    $d = [string]$Description

    $deny = @(
        'bluetooth', 'logitech', 'logi ', 'unifying', 'lightspeed',
        'printer', 'modem', 'fax', 'scanner',
        'mouse', 'keyboard', 'gamepad', 'joystick', 'headset', 'audio', 'webcam', 'camera',
        'hub', 'smartcard', 'smart card', 'fingerprint',
        'intel(r) active management', 'amt ', 'virtual machine', 'vmware', 'hyper-v'
    )
    foreach ($k in $deny) {
        if ($d -like "*$k*") { return 'BLOCKED' }
    }

    # The bridge chips actually used on ESP32 dev boards, plus the generic names
    # Windows gives them when the vendor driver isn't installed.
    $allow = @(
        'cp210', 'cp 210', 'silicon labs',
        'ch340', 'ch341', 'ch910', 'wch',
        'ftdi', 'ft232', 'ft231', 'future technology',
        'prolific', 'pl2303',
        'usb-serial', 'usb serial', 'usb to uart', 'usb-to-uart', 'usb-enhanced-serial'
    )
    foreach ($k in $allow) {
        if ($d -like "*$k*") { return 'BRIDGE' }
    }

    return 'UNKNOWN'
}

function Format-PortKindTag {
    # Suffix shown next to every port in every picker, so the safe choice is
    # visible before anything is selected rather than only after.
    param([string]$Kind)
    switch ($Kind) {
        'BRIDGE'  { return '' }
        'BLOCKED' { return '  << NOT an ESP32 - blocked' }
        default   { return '  << unrecognised - confirm needed' }
    }
}

function Test-PortSafeToTouch {
    # The single gate in front of anything that opens or resets a port (esptool
    # erase/MAC read, export_logs GET/SET_LOCATION). Returns $true only if it is
    # safe, or the operator has explicitly vouched for an unrecognised port.
    #
    # $Action is quoted back so the prompt says what is about to happen - "erase"
    # and "read the location" deserve very different amounts of hesitation.
    param([string]$Port, [string]$Action = 'talk to this port', [switch]$Quiet)

    $known = @(Get-PortList | Where-Object { $_.Port -eq $Port }) | Select-Object -First 1
    $kind  = if ($known) { $known.Kind } else { 'UNKNOWN' }
    $desc  = if ($known) { $known.Description } else { 'not currently enumerated' }

    if ($kind -eq 'BRIDGE') { return $true }

    if ($kind -eq 'BLOCKED') {
        Write-Host ""
        Write-Host ("REFUSED: {0} is '{1}'." -f $Port, $desc) -ForegroundColor Red
        Write-Host ("That is not an ESP32, so the wizard will not {0}." -f $Action) -ForegroundColor Red
        Write-Host "esptool resets a port by pulling DTR/RTS, which other USB hardware is" -ForegroundColor Red
        Write-Host "not built to survive. Unplug it or pick a real board instead." -ForegroundColor Red
        return $false
    }

    if ($Quiet) { return $false }

    Write-Host ""
    Write-Host ("{0} is '{1}' - not a recognised USB-to-UART bridge." -f $Port, $desc) -ForegroundColor Yellow
    Write-Host ("If it is NOT one of your ESP32s, {0} could damage or confuse it." -f $Action) -ForegroundColor Yellow
    Write-Host "Use 'identify a port' first if you are unsure." -ForegroundColor Yellow
    $ans = Read-Line ("  Type the port name ({0}) to confirm it IS your board, anything else to skip > " -f $Port)
    if ($ans.Trim().ToUpper() -eq $Port.ToUpper()) { return $true }

    Write-Host ("  Skipped {0} - not confirmed." -f $Port) -ForegroundColor DarkGray
    return $false
}

function Select-MultiplePorts {
    # Shared bulk-port-picker for any action that lets the operator pick several
    # boards at once ('all' or comma/space-separated numbers) - originally lived
    # inline inside Invoke-SetLocationBoards's bulk branch, pulled out here so a
    # second bulk action (Invoke-WipeBoards) doesn't have to re-carry its own
    # copy of the same ~60 lines, including the dedupe fix below.
    #
    # Dedupes by .Port via a hashtable - NOT Select-Object/Sort-Object -Unique,
    # which compare [pscustomobject]s by property SHAPE in Windows PowerShell
    # 5.1, not by value. Three distinct ports with identical property names
    # silently collapsed to ONE the first time this was tried here - picking
    # "1,2,3" acted on only the first board and left the other two untouched
    # with no error, just a confirmation table that said "1 board(s)" and was
    # easy to read past. Every pick is also run through Test-PortSafeToTouch
    # before being returned, so a bulk pick can't reach something that isn't
    # a recognised ESP32 without the operator confirming it individually.
    #
    # Caller must already know $Ports.Count -gt 0 - the "nothing to pick from"
    # message differs per action (wipe vs. write-location), so that guard stays
    # at each call site rather than living here.
    #
    # Returns the vetted, deduped port objects, or @() if the operator typed
    # nothing usable or nothing survived the safety check. Callers should treat
    # an empty result as "do nothing" and `continue` their own loop.
    param(
        [Parameter(Mandatory)][object[]]$Ports,
        [Parameter(Mandatory)][string]$Action
    )

    $bridges = @($Ports | Where-Object { $_.Kind -eq 'BRIDGE' })
    Write-Host ""
    Write-Host "Only pick boards you've confirmed ARE your ESP32s (use 'identify' above" -ForegroundColor DarkGray
    Write-Host "first if unsure) - anything else on this list is some other USB device." -ForegroundColor DarkGray
    if ($bridges.Count -gt 0) {
        Write-Host ("Type 'all' for the {0} detected ESP32 board(s): {1}" -f $bridges.Count, (($bridges | ForEach-Object { $_.Port }) -join ', ')) -ForegroundColor DarkGray
    }
    $which  = Read-Line "Which port numbers? ('all', or comma/space separated e.g. 1,3,5) > "
    $picked = @()

    if ($which.Trim() -in @('all', 'ALL', 'All', 'a', 'A')) {
        if ($bridges.Count -eq 0) {
            Write-Host "  No recognised ESP32 boards detected - pick numbers by hand instead." -ForegroundColor Yellow
            return @()
        }
        $picked = @($bridges)
        Write-Host ("  Selected all {0} detected ESP32 board(s)." -f $picked.Count) -ForegroundColor Green
    }
    else {
        foreach ($tok in ($which -split '[,\s]+' | Where-Object { $_ })) {
            $wn = 0
            if ([int]::TryParse($tok, [ref]$wn) -and $wn -ge 1 -and $wn -le $Ports.Count) {
                $picked += $Ports[$wn - 1]
            }
            else {
                Write-Host ("  Ignoring invalid entry '{0}'." -f $tok) -ForegroundColor Yellow
            }
        }
    }

    $seen   = @{}
    $unique = @()
    foreach ($p in $picked) {
        if (-not $seen.ContainsKey($p.Port)) { $seen[$p.Port] = $true; $unique += $p }
    }
    $picked = @($unique)
    if ($picked.Count -eq 0) { Write-Host "  Nothing valid selected." -ForegroundColor Yellow; return @() }

    # Drop anything positively identified as other hardware, and make each
    # unrecognised port earn its place individually. A bulk pick is exactly
    # where a stray number ends up aimed at a receiver or a Bluetooth link
    # without being noticed.
    $vetted = @()
    foreach ($p in $picked) {
        if ($p.Kind -eq 'BRIDGE') { $vetted += $p; continue }
        if (Test-PortSafeToTouch -Port $p.Port -Action $Action) { $vetted += $p }
    }
    $picked = @($vetted)
    if ($picked.Count -eq 0) { Write-Host "  No usable boards left after the safety check." -ForegroundColor Yellow; return @() }

    # NOT `return ,$picked`: every call site already wraps this call in @(...),
    # and Write-Output enumerates a returned array into the pipeline one
    # element at a time regardless of count (0, 1, or many) - the caller's
    # @() correctly recollects that into an array of the right size. A leading
    # unary comma would instead emit $picked itself as ONE pipeline object,
    # which the caller's @() then wraps in an outer 1-element array - so
    # picking 3 boards reported "1 board(s)" and printed "System.Object[]"
    # instead of a port name. Caught by testing bulk wipe with 3 boards.
    return $picked
}

function Invoke-Identify {
    # Reads the board's MAC via the existing tools\board_check.py and names the node.
    # Gated like every other port action: "identify" sounds passive, but reading a
    # MAC resets the chip into its bootloader, which is exactly the thing that
    # must not be aimed at a receiver or a hub.
    param([string]$TargetPort)
    if (-not (Test-PortSafeToTouch -Port $TargetPort -Action 'reset it to read a MAC')) { return }
    Write-Host "  Reading $TargetPort (this takes a few seconds) ..." -ForegroundColor DarkGray
    Push-Location (Join-Path $base 'tools')
    try {
        $out = & python board_check.py --port $TargetPort --wait 1
        $rc = $LASTEXITCODE
        $hit = $out | Select-String -Pattern 'MAC\s+([0-9a-fA-F:]{17})\s+->\s+(.+)$' | Select-Object -First 1
        if ($hit) {
            Write-Host ("  " + $hit.Line.Trim()) -ForegroundColor Green
            $mac  = $hit.Matches[0].Groups[1].Value
            $name = $hit.Matches[0].Groups[2].Value
            $script:IdentifiedPorts[$TargetPort] = "$mac -> $name"
        }
        elseif ($rc -eq 2) {
            Write-Host "  Could not identify: esptool not available in this shell." -ForegroundColor Yellow
            Write-Host "  Run from the ESP-IDF PowerShell, or: pip install esptool" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  Could not read a MAC from $TargetPort (exit $rc)." -ForegroundColor Yellow
            Write-Host "  Port may be empty, held by another process, or on a charge-only cable." -ForegroundColor DarkGray
        }
    }
    finally { Pop-Location }
}

function Wait-ForNewPort {
    # Diffs the live port list before/after so a board that ISN'T plugged in yet
    # (the common case once you run out of free USB sockets) can still be assigned
    # without the user having to know or type its COM number in advance.
    param([string]$For)
    Write-Host ""
    Write-Host ("Plug in {0} now (unplug another board first if you're out of free USB ports)." -f $For) -ForegroundColor Yellow
    $before = @(Get-PortList | Select-Object -ExpandProperty Port)
    Read-Line "Press Enter once it's plugged in > " | Out-Null
    Start-Sleep -Milliseconds 800   # Windows needs a beat to enumerate a freshly-plugged device
    $after = @(Get-PortList | Select-Object -ExpandProperty Port)
    $new = @($after | Where-Object { $before -notcontains $_ })

    if ($new.Count -eq 1) {
        Write-Host ("  Detected {0}." -f $new[0]) -ForegroundColor Green
        return $new[0]
    }
    if ($new.Count -gt 1) {
        Write-Host "  Multiple new ports appeared:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $new.Count; $i++) { Write-Host ("    [{0}] {1}" -f ($i + 1), $new[$i]) }
        $which = Read-Line "  Which one is it? > "
        $n = 0
        if ([int]::TryParse($which, [ref]$n) -and $n -ge 1 -and $n -le $new.Count) { return $new[$n - 1] }
    }
    Write-Host "  No new port detected - type it manually instead." -ForegroundColor Yellow
    return $null
}

function Select-Port {
    param([string]$For, [object[]]$Ports)
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid port chosen for $For after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        Write-Host ""
        Write-Host "Select port for $For :" -ForegroundColor Cyan
        if ($Ports.Count -eq 0) {
            Write-Host "  (no COM ports detected - a charge-only USB cable creates no port)" -ForegroundColor Yellow
        }
        for ($i = 0; $i -lt $Ports.Count; $i++) {
            $tag = ''
            if ($script:IdentifiedPorts.ContainsKey($Ports[$i].Port)) {
                $tag = "  [{0}]" -f $script:IdentifiedPorts[$Ports[$i].Port]
            }
            $kindTag = Format-PortKindTag $Ports[$i].Kind
            $color   = switch ($Ports[$i].Kind) { 'BLOCKED' { 'DarkGray' } 'UNKNOWN' { 'Yellow' } default { 'Gray' } }
            Write-Host ("  [{0}] {1,-7} - {2}{3}{4}" -f ($i + 1), $Ports[$i].Port, $Ports[$i].Description, $tag, $kindTag) -ForegroundColor $color
        }
        # Actions continue the same numbering as the ports above - one flat numbered
        # list, same convention as every other menu in this wizard (Show-Menu).
        $identifyOneIdx = $Ports.Count + 1
        $identifyAllIdx = $Ports.Count + 2
        $autoDetectIdx  = $Ports.Count + 3
        $manualIdx      = $Ports.Count + 4
        Write-Host ("  [{0}] identify a port (reads its MAC)" -f $identifyOneIdx)
        Write-Host ("  [{0}] identify ALL listed ports (reads each one in turn, takes a while)" -f $identifyAllIdx)
        Write-Host ("  [{0}] auto-detect (not plugged in yet - plug it in now, wizard finds the new port)" -f $autoDetectIdx)
        Write-Host ("  [{0}] type a port manually" -f $manualIdx)
        $raw = Read-Line '> '

        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n)) {
            Write-Host "  Enter a number from the list above." -ForegroundColor Yellow
            continue
        }

        if ($n -ge 1 -and $n -le $Ports.Count) {
            # This port goes on to be flashed by run.ps1 - the single most
            # destructive thing the wizard does to whatever is on the other end.
            if (-not (Test-PortSafeToTouch -Port $Ports[$n - 1].Port -Action 'flash firmware to it')) { continue }
            return $Ports[$n - 1].Port
        }
        if ($n -eq $identifyOneIdx) {
            if ($Ports.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            $which = Read-Line '  Which listed port number? > '
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $Ports.Count) {
                Invoke-Identify -TargetPort $Ports[$wn - 1].Port
            }
            else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }
        if ($n -eq $identifyAllIdx) {
            if ($Ports.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            Write-Host ""
            foreach ($p in $Ports) {
                Write-Host ("Identifying {0} ..." -f $p.Port) -ForegroundColor DarkGray
                Invoke-Identify -TargetPort $p.Port
            }
            continue
        }
        if ($n -eq $autoDetectIdx) {
            $found = Wait-ForNewPort -For $For
            if ($found) { return $found }
            continue
        }
        if ($n -eq $manualIdx) {
            $manual = Read-Line '  Port (e.g. COM20) > '
            if ($manual) {
                $manual = $manual.Trim().ToUpper()
                # Typing the port by hand skips the list, so it has to be checked
                # here too - otherwise the guard is one typo wide.
                if (Test-PortSafeToTouch -Port $manual -Action 'flash firmware to it') { return $manual }
            }
            continue
        }
        Write-Host "  Invalid choice." -ForegroundColor Yellow
    }
}

function Select-PortOrRemote {
    # Wraps Select-Port for a MULTI-LAPTOP SPLIT roster (see the file's own
    # .DESCRIPTION): a board in the full experiment roster may not be reachable
    # from THIS wizard instance at all - it lives on a teammate's laptop. Asking
    # "is it here?" only when $MultiLaptop is set keeps the single-laptop path
    # byte-for-byte unchanged: no new prompt, no behavior change, when nobody
    # has opted into a split.
    # Returns a port string, or $null for "not on this laptop".
    param([string]$For, [object[]]$Ports, [bool]$MultiLaptop)
    if ($MultiLaptop) {
        $ans = Read-Line "  Is $For plugged into THIS laptop? [Y/n] > "
        if ($ans -eq 'n' -or $ans -eq 'N') { return $null }
    }
    return (Select-Port -For $For -Ports $Ports)
}

function Invoke-WipeBoards {
    # Standalone maintenance path - does NOT touch run.ps1 or the attack/topology/
    # location config at all. For when you've lost track of what firmware/role is
    # on a physical board (easy to do once you're swapping 10 boards across 3
    # ports) and just want it blank before it goes back into rotation, without
    # accidentally kicking off a real capture in the process.
    $ports = Get-PortList
    $wiped = @()

    while ($true) {
        Write-Host ""
        Write-Host "Wipe which board? (full chip erase - board ends up BLANK, no firmware at all)" -ForegroundColor Cyan
        if ($ports.Count -eq 0) {
            Write-Host "  (no COM ports detected - a charge-only USB cable creates no port)" -ForegroundColor Yellow
        }
        for ($i = 0; $i -lt $ports.Count; $i++) {
            $tag = ''
            if ($script:IdentifiedPorts.ContainsKey($ports[$i].Port)) {
                $tag = "  [{0}]" -f $script:IdentifiedPorts[$ports[$i].Port]
            }
            $doneTag = if ($wiped -contains $ports[$i].Port) { '  (wiped this session)' } else { '' }
            $kindTag = Format-PortKindTag $ports[$i].Kind
            $color   = switch ($ports[$i].Kind) { 'BLOCKED' { 'DarkGray' } 'UNKNOWN' { 'Yellow' } default { 'Gray' } }
            Write-Host ("  [{0}] {1,-7} - {2}{3}{4}{5}" -f ($i + 1), $ports[$i].Port, $ports[$i].Description, $tag, $doneTag, $kindTag) -ForegroundColor $color
        }
        $allIdx      = $ports.Count + 1
        $identifyIdx = $ports.Count + 2
        $manualIdx   = $ports.Count + 3
        $backIdx     = $ports.Count + 4
        Write-Host ("  [{0}] wipe SEVERAL boards you pick (faster than one by one)" -f $allIdx)
        Write-Host ("  [{0}] identify a port first (reads its MAC, does not wipe anything)" -f $identifyIdx)
        Write-Host ("  [{0}] type a port manually" -f $manualIdx)
        Write-Host ("  [{0}] done - back to the main menu" -f $backIdx)
        $raw = Read-Line '> '

        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n)) { Write-Host "  Enter a number from the list above." -ForegroundColor Yellow; continue }

        if ($n -eq $backIdx) { break }

        if ($n -eq $allIdx) {
            if ($ports.Count -eq 0) { Write-Host "  No boards listed to erase." -ForegroundColor Yellow; continue }

            $picked = @(Select-MultiplePorts -Ports $ports -Action 'erase it')
            if ($picked.Count -eq 0) { continue }

            Write-Host ""
            Write-Host ("This PERMANENTLY erases everything on the {0} board(s) below - firmware," -f $picked.Count) -ForegroundColor Yellow
            Write-Host "SD-status cache, all of it. There is no undo; each board must be reflashed" -ForegroundColor Yellow
            Write-Host "afterward to do anything." -ForegroundColor Yellow
            foreach ($p in $picked) {
                $tag = ''
                if ($script:IdentifiedPorts.ContainsKey($p.Port)) { $tag = "  [{0}]" -f $script:IdentifiedPorts[$p.Port] }
                $doneTag = if ($wiped -contains $p.Port) { '  (wiped this session)' } else { '' }
                Write-Host ("  {0,-7} - {1}{2}{3}" -f $p.Port, $p.Description, $tag, $doneTag)
            }

            $goAns = Read-Line "`nErase all $($picked.Count) board(s) above? [y/N] > "
            if ($goAns -ne 'y' -and $goAns -ne 'Y') { Write-Host "  Skipped - nothing erased." -ForegroundColor DarkGray; continue }

            foreach ($p in $picked) {
                if ($DryRun) {
                    Write-Host ("`nDRY RUN - would erase {0} here; not touching real hardware." -f $p.Port) -ForegroundColor Yellow
                    continue
                }
                Write-Host ("`nErasing $($p.Port) (takes ~10-15s) ...") -ForegroundColor Yellow
                & esptool.py --chip esp32 --port $p.Port erase_flash
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ("  {0} wiped clean." -f $p.Port) -ForegroundColor Green
                    $wiped += $p.Port
                    $script:IdentifiedPorts.Remove($p.Port) | Out-Null   # stale name/MAC label - board is blank now
                }
                else {
                    Write-Host ("  erase_flash failed on {0} (exit {1}) - port busy, board unplugged, or esptool not on PATH." -f $p.Port, $LASTEXITCODE) -ForegroundColor Red
                }
            }
            $ports = Get-PortList
            continue
        }

        if ($n -eq $identifyIdx) {
            if ($ports.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            $which = Read-Line '  Which listed port number? > '
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $ports.Count) {
                Invoke-Identify -TargetPort $ports[$wn - 1].Port
            }
            else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }

        $target = $null
        if ($n -eq $manualIdx) {
            $manual = Read-Line '  Port (e.g. COM20) > '
            if ($manual) { $target = $manual.Trim().ToUpper() }
        }
        elseif ($n -ge 1 -and $n -le $ports.Count) {
            $target = $ports[$n - 1].Port
        }
        else {
            Write-Host "  Invalid choice." -ForegroundColor Yellow
        }
        if (-not $target) { continue }

        # Before the erase confirmation, not after: a blocked port should never
        # get as far as a y/N prompt that reads like it is about to work.
        if (-not (Test-PortSafeToTouch -Port $target -Action 'erase it')) { continue }

        if ($DryRun) {
            Write-Host ("`nDRY RUN - would erase {0} here; not touching real hardware." -f $target) -ForegroundColor Yellow
            continue
        }

        $confirm = Read-Line ("`nThis PERMANENTLY erases everything on {0} - firmware, SD-status cache, all of it. There is no undo; the board must be reflashed afterward to do anything. Continue? [y/N] > " -f $target)
        if ($confirm -ne 'y' -and $confirm -ne 'Y') { Write-Host "  Skipped." -ForegroundColor DarkGray; continue }

        Write-Host ("Erasing $target (takes ~10-15s) ...") -ForegroundColor Yellow
        & esptool.py --chip esp32 --port $target erase_flash
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("  {0} wiped clean." -f $target) -ForegroundColor Green
            $wiped += $target
            $script:IdentifiedPorts.Remove($target) | Out-Null   # stale name/MAC label - board is blank now
        }
        else {
            Write-Host ("  erase_flash failed on {0} (exit {1}) - port busy, board unplugged, or esptool not on PATH." -f $target, $LASTEXITCODE) -ForegroundColor Red
        }
        $ports = Get-PortList
    }

    if ($wiped.Count -gt 0) {
        Write-Host ""
        Write-Host ("Wiped this session: {0}" -f ($wiped -join ', ')) -ForegroundColor Green
    }
}

function Invoke-FirmwareSelfTest {
    # Build + flash ONE board and prove the SD/location code works - no capture,
    # no attack, no topology shaping, no export, no analysis, nothing written to
    # exports/ or analysis/. Exists because the only way to try a firmware change
    # used to be to start a real capture run, which drags in a roster, a preset,
    # an attack, and a pile of output folders you then have to clean up.
    #
    # Flashes BASELINE/TREE deliberately (-DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1,
    # command centre off) - the neutral build, identical to what a plain baseline
    # capture would flash, so it shares that build dir and ccache instead of
    # leaving an orphan one behind.
    #
    # ROOT is the default role on purpose: mesh_setup_init() runs BEFORE
    # csv_logger_init() (victim_main.c), and a child blocks there waiting for a
    # parent that isn't powered on - so a lone child can leave the serial command
    # task unstarted for a minute or more, and every probe below would time out
    # on a board that is actually fine. A root never waits for a parent.
    if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "idf.py is not on PATH - run this from the 'ESP-IDF 5.3 PowerShell' window." -ForegroundColor Red
        return
    }

    $ports = Get-PortList
    $port  = Select-Port -For 'the board to self-test' -Ports $ports
    if (-not $port) { return }

    $roleIdx = Show-Menu -Title 'Flash which role for the test?' -Options @(
        'root  (recommended - boots standalone, no parent needed)',
        'child (only if a root is already powered on, or it will sit waiting to join)'
    ) -DefaultIndex 0
    $role = if ($roleIdx -eq 1) { 'child' } else { 'root' }
    $proj = if ($role -eq 'root') { 'root_node' } else { 'child_node' }

    # Same build-dir naming run.ps1 uses for a baseline/tree run on this port, so
    # the two share cached objects rather than doubling build time and disk.
    # Absolute path under $buildRoot (see top of file) -- keeps compiled output
    # off OneDrive; $proj (root_node/child_node) stays the CMake source dir.
    $portTag  = ($port -replace '[^A-Za-z0-9]', '')
    $buildDir = Join-Path $buildRoot "$proj\build_${role}_none_tree_$portTag"

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  FIRMWARE SELF-TEST - no capture, no attack, no export" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host ("  Board    : {0}" -f $port)
    Write-Host ("  Role     : {0}" -f $role)
    Write-Host ("  Build    : baseline / tree (ACTIVE_ATTACK=255, MESH_TOPOLOGY=1)")
    Write-Host ("  Build dir: {0}" -f $buildDir) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Then checks, over USB:" -ForegroundColor DarkGray
    Write-Host "    [1] GET_LOCATION answers at all (the new command is present)" -ForegroundColor DarkGray
    Write-Host "    [2] what location.txt currently holds" -ForegroundColor DarkGray
    Write-Host "    [3] optionally SET a location and READ IT BACK to prove the round trip" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Nothing is written to exports/ or analysis/. The board IS flashed." -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "`nDRY RUN - would build + flash here; not touching real hardware." -ForegroundColor Yellow
        return
    }

    $go = Read-Line "`nBuild and flash $port now? [y/N] > "
    if ($go -ne 'y' -and $go -ne 'Y') { Write-Host "  Cancelled." -ForegroundColor DarkGray; return }

    Push-Location (Join-Path $base $proj)
    try {
        Write-Host "`nBuilding + flashing (first build can take several minutes) ..." -ForegroundColor Cyan
        # flash WITHOUT monitor: the monitor would hold the port open, and every
        # check below needs to open it itself. The monitor is offered at the end.
        idf.py -B $buildDir -DACTIVE_ATTACK=255 -DMESH_TOPOLOGY=1 -p $port flash
        $flashRc = $LASTEXITCODE
    }
    finally { Pop-Location }

    if ($flashRc -ne 0) {
        Write-Host ""
        Write-Host ("BUILD/FLASH FAILED (exit {0}) - the checks below are skipped." -f $flashRc) -ForegroundColor Red
        Write-Host "A compile error here is the firmware change itself; scroll up for the first error." -ForegroundColor Red
        return
    }
    Write-Host "`nFlashed OK." -ForegroundColor Green

    # The board reboots into the SD check, then mesh init, then csv_logger_init()
    # - which is what starts the serial command task. Poll rather than guess a
    # single delay: a root is quick, a child that joins a mesh is not.
    Write-Host "Waiting for the board to boot and start its serial command task ..." -ForegroundColor DarkGray
    $read     = $null
    $deadline = (Get-Date).AddSeconds(75)
    $attempt  = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        Start-Sleep -Seconds 6
        $read = Get-SdLocation -TargetPort $port
        if ($read.State -ne 'UNKNOWN') { break }
        Write-Host ("  no answer yet (try {0}) ..." -f $attempt) -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  RESULTS" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green

    if (-not $read -or $read.State -eq 'UNKNOWN') {
        Write-Host "  [FAIL] GET_LOCATION never answered." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Either the board hasn't reached csv_logger_init() yet (a child with" -ForegroundColor Yellow
        Write-Host "  no root waits at mesh_setup_init), or the SD card would not mount." -ForegroundColor Yellow
        Write-Host "  Open the monitor below and look for the 'SD ENV:' line." -ForegroundColor Yellow
        if ($read -and $read.Lines) {
            foreach ($line in $read.Lines) { Write-Host ("    " + $line) -ForegroundColor DarkGray }
        }
    }
    else {
        Write-Host "  [PASS] GET_LOCATION answered - the new command is live on this board." -ForegroundColor Green
        switch ($read.State) {
            'OK'      { Write-Host ("  [INFO] location.txt currently holds: {0}" -f $read.Value) -ForegroundColor Green }
            'NONE'    { Write-Host "  [INFO] location.txt is MISSING - this board would record nothing to its card." -ForegroundColor Yellow }
            'INVALID' { Write-Host ("  [INFO] location.txt holds an unrecognised value: '{0}' - records nothing." -f $read.Value) -ForegroundColor Yellow }
        }

        # The round trip is the real proof: write a value, read it back, and see
        # the SAME value come out of the card. Optional, because it does change
        # what is on the card.
        Write-Host ""
        $rtAns = Read-Line "Also test the write path (SET a location, then read it back)? [y/N] > "
        if ($rtAns -eq 'y' -or $rtAns -eq 'Y') {
            $wasLoc = if ($read.State -eq 'OK') { $read.Value } else { $null }
            if ($wasLoc) {
                Write-Host ("  This card currently says {0}. It will be restored at the end." -f $wasLoc) -ForegroundColor DarkGray
            }
            $rtOptions = @($LOCATIONS) + @('Cancel - skip the write test')
            $rtIdx = Show-Menu -Title 'Write which location for the test?' -Options $rtOptions -DefaultIndex -1
            if ($rtIdx -lt $LOCATIONS.Count) {
                $rtLoc = $LOCATIONS[$rtIdx]

                Write-Host ("`n  SET_LOCATION={0} ..." -f $rtLoc) -ForegroundColor DarkGray
                $w = Set-SdLocation -TargetPort $port -Location $rtLoc
                foreach ($line in $w.Lines) { Write-Host ("    " + $line) -ForegroundColor DarkGray }

                if (-not $w.Ok) {
                    Write-Host "  [FAIL] the write was rejected - see the reason above." -ForegroundColor Red
                }
                else {
                    Write-Host "  reading it back ..." -ForegroundColor DarkGray
                    $back = Get-SdLocation -TargetPort $port
                    if ($back.State -eq 'OK' -and $back.Value -eq $rtLoc) {
                        Write-Host ("  [PASS] round trip OK - wrote {0}, card reads back {0}." -f $rtLoc) -ForegroundColor Green
                    }
                    else {
                        Write-Host ("  [FAIL] wrote {0} but the card reads back: {1}" -f $rtLoc, (Format-SdLocationState $back)) -ForegroundColor Red
                    }

                    # Put the card back the way it was found. A diagnostic that
                    # quietly leaves a board recording to the wrong site is worse
                    # than no diagnostic at all.
                    if ($wasLoc -and $wasLoc -ne $rtLoc) {
                        Write-Host ("`n  restoring {0} ..." -f $wasLoc) -ForegroundColor DarkGray
                        $restore = Set-SdLocation -TargetPort $port -Location $wasLoc
                        if ($restore.Ok) {
                            Write-Host ("  [PASS] restored to {0}." -f $wasLoc) -ForegroundColor Green
                        }
                        else {
                            Write-Host ("  [WARN] could NOT restore {0} - this board is left set to {1}." -f $wasLoc, $rtLoc) -ForegroundColor Red
                        }
                    }
                    elseif (-not $wasLoc) {
                        Write-Host ("`n  Note: this card had no valid location before, so it is left set to {0}." -f $rtLoc) -ForegroundColor Yellow
                    }
                }
            }
        }
    }

    # A location written over serial only takes effect on the NEXT boot check, so
    # confirming 'SD ENV: OK' means rebooting - which the monitor does anyway.
    Write-Host ""
    $monAns = Read-Line "Open the monitor to watch the boot log ('SD ENV:' line)? Ctrl+] quits. [y/N] > "
    if ($monAns -eq 'y' -or $monAns -eq 'Y') {
        Push-Location (Join-Path $base $proj)
        try {
            Write-Host "Press Ctrl+] to leave the monitor and come back here." -ForegroundColor Cyan
            idf.py -B $buildDir -p $port monitor
        }
        finally { Pop-Location }
    }

    Write-Host ""
    Write-Host "Self-test done. Nothing was exported and no run was recorded." -ForegroundColor Green
}

function Invoke-SetLocationBoards {
    # Standalone maintenance path - same reasoning as Invoke-WipeBoards above: this
    # used to be reachable ONLY from inside the preset picker's "Use this preset?"
    # submenu, so fixing a board's location.txt on a fresh roster meant saving a
    # throwaway preset first just to unlock the option. Pulled out to the top-level
    # menu so it works whether or not a preset exists yet.
    #
    # CAVEAT (unchanged from the original): this sends GET_LOCATION/SET_LOCATION
    # over the ALREADY-RUNNING board's serial dispatcher (see csv_logger.c) - it
    # only works once that board has booted and joined the mesh THIS session. It
    # does NOT help a board that hasn't been flashed/booted yet; for that, write
    # location.txt onto the card directly with a reader before it goes into the
    # board.
    #
    # Every write path here now READS the card first and shows "<was> -> <now>",
    # skipping boards already sitting at the chosen site. It used to overwrite
    # blind, because the firmware had no way to report a location back.
    $ports = Get-PortList

    while ($true) {
        Write-Host ""
        Write-Host "Write/update location.txt on which ALREADY-RUNNING board?" -ForegroundColor Cyan
        if ($ports.Count -eq 0) {
            Write-Host "  (no COM ports detected - a charge-only USB cable creates no port)" -ForegroundColor Yellow
        }
        for ($i = 0; $i -lt $ports.Count; $i++) {
            $tag = ''
            if ($script:IdentifiedPorts.ContainsKey($ports[$i].Port)) {
                $tag = "  [{0}]" -f $script:IdentifiedPorts[$ports[$i].Port]
            }
            $kindTag = Format-PortKindTag $ports[$i].Kind
            $color   = switch ($ports[$i].Kind) { 'BLOCKED' { 'DarkGray' } 'UNKNOWN' { 'Yellow' } default { 'Gray' } }
            Write-Host ("  [{0}] {1,-7} - {2}{3}{4}" -f ($i + 1), $ports[$i].Port, $ports[$i].Description, $tag, $kindTag) -ForegroundColor $color
        }
        $allIdx      = $ports.Count + 1
        $identifyIdx = $ports.Count + 2
        $manualIdx   = $ports.Count + 3
        $backIdx     = $ports.Count + 4
        Write-Host ("  [{0}] write ONE location to SEVERAL boards you pick (faster than one by one)" -f $allIdx)
        Write-Host ("  [{0}] identify a port first (reads its MAC, changes nothing)" -f $identifyIdx)
        Write-Host ("  [{0}] type a port manually" -f $manualIdx)
        Write-Host ("  [{0}] done - back to the main menu" -f $backIdx)
        $raw = Read-Line '> '

        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n)) { Write-Host "  Enter a number from the list above." -ForegroundColor Yellow; continue }
        if ($n -eq $backIdx) { break }

        if ($n -eq $identifyIdx) {
            if ($ports.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            $which = Read-Line '  Which listed port number? > '
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $ports.Count) {
                Invoke-Identify -TargetPort $ports[$wn - 1].Port
            }
            else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }

        if ($n -eq $allIdx) {
            if ($ports.Count -eq 0) { Write-Host "  No boards listed to write to." -ForegroundColor Yellow; continue }

            $picked = @(Select-MultiplePorts -Ports $ports -Action 'write a location to it')
            if ($picked.Count -eq 0) { continue }

            $locOptions = @($LOCATIONS) + @('Cancel - write nothing')
            $locIdx = Show-Menu -Title 'Write which location to the boards you picked?' -Options $locOptions -DefaultIndex -1
            if ($locIdx -eq $LOCATIONS.Count) { Write-Host "  Cancelled - nothing written." -ForegroundColor DarkGray; continue }
            $loc = $LOCATIONS[$locIdx]

            # Read each board FIRST, so the confirmation shows what is actually on
            # the card and what it would become. A board already sitting at $loc
            # is left alone entirely - rewriting it is a pointless card write, and
            # listing it as "-> G402" hides that nothing needed doing.
            Write-Host ""
            Write-Host ("Reading each board's current location.txt ({0} board(s), a few seconds each) ..." -f $picked.Count) -ForegroundColor DarkGray
            $plan = @()
            foreach ($p in $picked) {
                $cur = if ($DryRun) { @{ State = 'UNKNOWN'; Value = $null } } else { Get-SdLocation -TargetPort $p.Port }
                $plan += [pscustomobject]@{
                    Port    = $p.Port
                    Current = $cur
                    Skip    = ($cur.State -eq 'OK' -and $cur.Value -eq $loc)
                }
            }

            Write-Host ""
            $toWrite = @($plan | Where-Object { -not $_.Skip })
            $blind   = @($plan | Where-Object { $_.Current.State -eq 'UNKNOWN' })
            foreach ($row in $plan) {
                $tag = ''
                if ($script:IdentifiedPorts.ContainsKey($row.Port)) { $tag = "  [{0}]" -f $script:IdentifiedPorts[$row.Port] }
                $was = Format-SdLocationState $row.Current
                if ($row.Skip) {
                    Write-Host ("  {0,-7} {1,-38} already set - leaving alone{2}" -f $row.Port, $was, $tag) -ForegroundColor DarkGray
                }
                else {
                    Write-Host ("  {0,-7} {1,-38} -> {2}{3}" -f $row.Port, $was, $loc, $tag)
                }
            }
            if ($blind.Count -gt 0) {
                Write-Host ""
                Write-Host ("{0} board(s) above could not be read - for those this is still a BLIND" -f $blind.Count) -ForegroundColor Yellow
                Write-Host "overwrite of whatever the card holds. A board that has not booted yet, or" -ForegroundColor Yellow
                Write-Host "is running firmware from before GET_LOCATION, cannot report its location." -ForegroundColor Yellow
            }
            if ($toWrite.Count -eq 0) {
                Write-Host "`n  Every board picked is already set to $loc - nothing to write." -ForegroundColor Green
                $ports = Get-PortList
                continue
            }

            $goAns = Read-Line "`nWrite $loc to $($toWrite.Count) of $($picked.Count) board(s)? [y/N] > "
            if ($goAns -ne 'y' -and $goAns -ne 'Y') { Write-Host "  Skipped - nothing written." -ForegroundColor DarkGray; continue }

            foreach ($row in $toWrite) {
                if ($DryRun) {
                    Write-Host ("`nDRY RUN - would send SET_LOCATION=$loc to {0} here." -f $row.Port) -ForegroundColor Yellow
                    continue
                }
                Write-Host ("`n  {0} SET_LOCATION=$loc ..." -f $row.Port) -ForegroundColor DarkGray
                $r = Set-SdLocation -TargetPort $row.Port -Location $loc
                $color = if ($r.Ok) { 'Green' } else { 'Yellow' }
                foreach ($line in $r.Lines) { Write-Host ("    " + $line) -ForegroundColor $color }
            }
            if (-not $DryRun) {
                Write-Host "`nReboot or reflash each board above to confirm 'SD ENV: OK' before relying on it." -ForegroundColor DarkGray
            }
            $ports = Get-PortList
            continue
        }

        $target = $null
        if ($n -eq $manualIdx) {
            $manual = Read-Line '  Port (e.g. COM20) > '
            if ($manual) { $target = $manual.Trim().ToUpper() }
        }
        elseif ($n -ge 1 -and $n -le $ports.Count) {
            $target = $ports[$n - 1].Port
        }
        else {
            Write-Host "  Invalid choice." -ForegroundColor Yellow
        }
        if (-not $target) { continue }
        if (-not (Test-PortSafeToTouch -Port $target -Action 'write a location to it')) { continue }

        # Check the card BEFORE offering the menu, so the choice is made knowing
        # what is already there. A board whose card reads NONE/INVALID is the one
        # actually losing data (csv_logger.c mirrors nothing without a valid
        # location), which is worth saying out loud at the moment of the fix.
        $cur = if ($DryRun) { @{ State = 'UNKNOWN'; Value = $null } } else { Get-SdLocation -TargetPort $target }
        Write-Host ""
        switch ($cur.State) {
            'OK'      { Write-Host ("{0} currently records to: {1}" -f $target, $cur.Value) -ForegroundColor Green }
            'NONE'    { Write-Host ("{0} has NO location.txt - it is writing nothing to its SD card." -f $target) -ForegroundColor Yellow }
            'INVALID' { Write-Host ("{0} holds an unrecognised location '{1}' - it is writing nothing to its SD card." -f $target, $cur.Value) -ForegroundColor Yellow }
            default   { Write-Host ("{0}'s current location.txt could not be read - anything below is a BLIND overwrite." -f $target) -ForegroundColor Yellow }
        }

        # No default here on purpose: Show-Menu's blank-Enter-picks-default behavior
        # is dangerous for an overwrite - hitting Enter without meaning to would
        # silently pick option 1 and overwrite whatever was already correct. A
        # "cancel" option is offered explicitly instead of a bracketed default.
        $locOptions = @($LOCATIONS) + @("Cancel - don't write anything to $target")
        $locIdx = Show-Menu -Title "Set $target's location to:" -Options $locOptions -DefaultIndex -1
        if ($locIdx -eq $LOCATIONS.Count) {
            Write-Host "  Cancelled - nothing written." -ForegroundColor DarkGray
            continue
        }
        $loc = $LOCATIONS[$locIdx]

        if ($cur.State -eq 'OK' -and $cur.Value -eq $loc) {
            Write-Host ("  {0} already records to {1} - nothing to write." -f $target, $loc) -ForegroundColor Green
            continue
        }

        if ($DryRun) {
            Write-Host ("`nDRY RUN - would send SET_LOCATION=$loc to $target here; not touching real hardware.") -ForegroundColor Yellow
            continue
        }

        # Confirm before sending rather than after, since there is no undo.
        Write-Host ""
        Write-Host ("  {0}: {1} -> {2}" -f $target, (Format-SdLocationState $cur), $loc) -ForegroundColor Yellow
        $goAns = Read-Line "Proceed? [y/N] > "
        if ($goAns -ne 'y' -and $goAns -ne 'Y') {
            Write-Host "  Skipped - nothing written." -ForegroundColor DarkGray
            continue
        }

        Write-Host ("`n  {0} SET_LOCATION=$loc ..." -f $target) -ForegroundColor DarkGray
        $r = Set-SdLocation -TargetPort $target -Location $loc
        $color = if ($r.Ok) { 'Green' } else { 'Yellow' }
        foreach ($line in $r.Lines) { Write-Host ("    " + $line) -ForegroundColor $color }
        Write-Host "  Reboot or reflash this board to confirm 'SD ENV: OK' before relying on it." -ForegroundColor DarkGray

        $ports = Get-PortList
    }
}

function Get-SdCardCandidates {
    # Every mounted filesystem drive, flagged as "looks like ours" if its root
    # directly holds one of the three folders tools\import_sdcard.py scans for
    # (baseline\, blackhole\, wormhole\) - the same top-level shape csv_logger.c
    # writes to the card. Read-only: Test-Path only, nothing opened or changed.
    $out = @()
    $repoQualifier = Split-Path $base -Qualifier
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $root = "$($d.Name):\"
        if (-not (Test-Path $root)) { continue }
        $looksLikeCard = [bool](@('baseline', 'blackhole', 'wormhole') | Where-Object { Test-Path (Join-Path $root $_) } | Select-Object -First 1)
        $out += [pscustomobject]@{
            Root          = $root
            LooksLikeCard = $looksLikeCard
            IsRepoDrive   = ("$($d.Name):" -eq $repoQualifier)
        }
    }
    return $out
}

function Import-OneSdCard {
    # Runs tools\import_sdcard.py DRY RUN first and shows exactly what it found,
    # then asks before it actually copies anything - the same "preview, then
    # confirm" shape as the rest of the wizard, applied to the one write this
    # whole SD-import flow makes. A card import only ever copies (never moves
    # or deletes from the card - see the script's own header), so the worst
    # case of a wrong pick is a wasted scan, not lost data.
    param([string]$Card, [int]$Repeat, [string]$Boots, [switch]$IncludeAborted,
          [string]$Roster, [switch]$DeleteSource, [string]$ExpectPrefix, [string]$Scenario = 'none')

    if (-not (Test-Path $Card)) {
        Write-Host ("  {0} is not reachable right now." -f $Card) -ForegroundColor Yellow
        return
    }

    $pyArgs = @('import_sdcard.py', '--card', $Card, '--repeat', $Repeat, '--scenario', $Scenario)
    if ($Boots) { $pyArgs += @('--boots', $Boots) }
    if ($IncludeAborted) { $pyArgs += '--include-aborted' }
    if ($Roster) { $pyArgs += @('--roster', $Roster) }
    if ($DeleteSource) { $pyArgs += '--delete-source' }

    Write-Host ""
    Write-Host ("Scanning {0} (repeat {1}) ..." -f $Card, $Repeat) -ForegroundColor DarkGray
    Push-Location (Join-Path $base 'tools')
    try {
        $dryOut = & python @pyArgs --dry-run 2>&1
        $rc = $LASTEXITCODE
        $dryOut | ForEach-Object { Write-Host "  $_" }
        if ($rc -ne 0) {
            Write-Host ("  import_sdcard.py exited {0} - see above (python/pyserial missing? run from the ESP-IDF 5.3 PowerShell)." -f $rc) -ForegroundColor Yellow
            return
        }

        $foundLine  = $dryOut | Select-String -Pattern '^Dry run: (\d+) file' | Select-Object -Last 1
        $foundCount = if ($foundLine) { [int]$foundLine.Matches[0].Groups[1].Value } else { 0 }
        if ($foundCount -eq 0) {
            Write-Host "  Nothing to import from here." -ForegroundColor DarkGray
            return
        }

        # ExpectPrefix is the attack\topology\location the operator just picked
        # (Invoke-ImportSdCard). A card can only be scanned whole (_scan() in
        # import_sdcard.py always walks all 48 attack/topology/location leaves),
        # so this is a heads-up, not a filter - anything the scan found outside
        # that one leaf still gets imported (into ITS OWN correct folder, named
        # from what THAT file's path says), this just flags that the card is
        # carrying more than the single run the operator described.
        if ($ExpectPrefix) {
            $foreign = $dryOut | Select-String -Pattern '^\s*(?:WOULD COPY|SKIP)\s+(\S+)' |
                Where-Object { -not $_.Matches[0].Groups[1].Value.StartsWith($ExpectPrefix, [StringComparison]::OrdinalIgnoreCase) }
            if ($foreign) {
                Write-Host ""
                Write-Host ("  NOTE: this card also has {0} file(s) outside {1}\ - probably a different run left on the same card. They'll still be imported/named correctly on their own; just flagging it in case the wrong card got picked." -f $foreign.Count, $ExpectPrefix) -ForegroundColor Yellow
            }
        }

        $goAns = Read-Line "`nCopy these files for real? [y/N] > "
        if ($goAns -ne 'y' -and $goAns -ne 'Y') {
            Write-Host "  Skipped - nothing copied." -ForegroundColor DarkGray
            return
        }
        $realOut = & python @pyArgs 2>&1
        $rc = $LASTEXITCODE
        $realOut | ForEach-Object { Write-Host "  $_" }
        if ($rc -ne 0) { Write-Host ("  import_sdcard.py exited {0} - see above." -f $rc) -ForegroundColor Yellow }
    }
    catch {
        Write-Host ("  Could not run import_sdcard.py: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Write-Host "  Is python on PATH? Run from the ESP-IDF 5.3 PowerShell window." -ForegroundColor DarkGray
    }
    finally { Pop-Location }
}

function Invoke-ImportSdCard {
    # The no-laptop counterpart to a USB export (see tools\import_sdcard.py's
    # own header comment): a board that ran off a wall charger/powerbank has
    # no CSVs to pull over serial, only whatever csv_logger.c mirrored onto its
    # SD card.
    #
    # Asks the same three questions the capture flow (main option [1]) already
    # asks - attack, topology, location - then a repeat number, and derives
    # everything else itself: which preset names the boards (matched by that
    # same attack/topology/location), and which mounted drive is the card.
    # Roster choice, delete-on-verify and boot filtering used to be separate
    # prompts answered fresh on every single pull, back when a card could
    # carry many un-imported boots at once. --delete-source is now always on
    # (below), so a card normally holds exactly one new file per board by the
    # time it's pulled - asking "which boots, filter aborted, delete after?"
    # on every import was solving a problem that no longer exists day to day.
    Write-Host ""
    Write-Host "Pop the SD card out of the board and read it with a card reader on THIS" -ForegroundColor DarkGray
    Write-Host "laptop - nothing here touches a board or a COM port." -ForegroundColor DarkGray

    # Step machine, same shape/back-navigation as the capture flow's attack ->
    # topology -> location - this asks the run apart the same way instead of a
    # different vocabulary for the same three facts.
    $attackIdx   = 1
    $topologyIdx = 0
    $scenarioIdx = 0
    $locationIdx = 0
    $repeat      = 1
    $step = 0
    :askFlow while ($step -le 4) {
        switch ($step) {
            0 {
                $idx = Show-Menu -Title 'What attack was this capture?' -Options @(
                    'baseline  (no attack - the control run)',
                    'blackhole (attacker relays, then drops victim probes)',
                    'wormhole  (A<->B tunnel)'
                ) -DefaultIndex $attackIdx -AllowBack
                # No earlier LOCAL step to land on - this function is its own
                # self-contained flow (entered fresh from the main menu each
                # time), so "back" here just means "cancel the import."
                if ($idx -eq -1) { return }
                $attackIdx = $idx
                $attack = $ATTACKS[$attackIdx]
                $step = 1
                continue askFlow
            }
            1 {
                $idx = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex $topologyIdx -AllowBack
                if ($idx -eq -1) { $step = 0; continue askFlow }
                $topologyIdx = $idx
                $topology = $TOPOLOGIES[$topologyIdx]
                $step = 2
                continue askFlow
            }
            2 {
                $idx = Show-Menu -Title 'Scenario (what this capture used, if any):' -Options $SCENARIO_LABELS -DefaultIndex $scenarioIdx -AllowBack
                if ($idx -eq -1) { $step = 1; continue askFlow }
                $scenarioIdx = $idx
                $scenario = $SCENARIOS[$scenarioIdx]
                $step = 3
                continue askFlow
            }
            3 {
                $idx = Show-Menu -Title 'Location (where the run physically happened):' -Options $LOCATIONS -DefaultIndex $locationIdx -AllowBack
                if ($idx -eq -1) { $step = 2; continue askFlow }
                $locationIdx = $idx
                $location = $LOCATIONS[$locationIdx]
                $step = 4
                continue askFlow
            }
            4 {
                Write-Host ""
                Write-Host "Which attempt (repeat) does this card belong to? Same numbering as a normal" -ForegroundColor DarkGray
                Write-Host "capture's r1/r2/r3 - the board itself has no way to know this." -ForegroundColor DarkGray
                $r = Read-RepeatNumber -Attack $attack -Topology $topology -DefaultRepeat $repeat -AllowBack
                if ($r -eq -1) { $step = 3; continue askFlow }
                $repeat = $r
                $step = 5
                continue askFlow
            }
        }
    }

    $dirs         = Get-RunDirs -Attack $attack -Topology $topology -Location $location -Scenario $scenario
    $expectPrefix = "$($dirs.AttackDir)\$($dirs.TopoDir)\$location\$scenario"

    # Roster: auto-match a saved preset for this exact attack/topology/scenario/
    # location - that preset already lists the boards THIS run used (matched by
    # MAC), so a second "which roster?" prompt would just be re-answering the
    # questions just asked. Falls back to the card's own victim_NODE_<MAC>
    # naming (never an error) when nothing matches.
    $rosterPath    = ''
    $presetMatches = @(Get-PresetFiles | ForEach-Object {
        $cfg = Read-PresetFile $_.FullName
        $cfgScenario = if ($cfg -and $cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario } else { 'none' }
        if ($cfg -and [string]$cfg.attack -eq $attack -and [string]$cfg.topology -eq $topology -and [string]$cfg.location -eq $location -and $cfgScenario -eq $scenario) {
            [pscustomobject]@{ File = $_; Cfg = $cfg }
        }
    })
    if ($presetMatches.Count -eq 1) {
        $rosterPath = $presetMatches[0].File.FullName
        Write-Host ("`nNaming from preset {0} (matches {1}/{2}/{3}/{4})." -f $presetMatches[0].File.Name, $attack, $topology, $scenario, $location) -ForegroundColor DarkGray
    }
    elseif ($presetMatches.Count -gt 1) {
        $rOpts = @($presetMatches | ForEach-Object { $_.File.Name })
        $rIdx = Show-Menu -Title 'Several saved presets match this attack/topology/scenario/location - name from which?' -Options $rOpts -DefaultIndex 0
        $rosterPath = $presetMatches[$rIdx].File.FullName
    }
    else {
        Write-Host "`nNo saved preset matches this attack/topology/scenario/location - files keep the card's own victim_NODE_<MAC> naming." -ForegroundColor DarkGray
    }

    # Drive: auto-pick when exactly one mounted drive has the attack-folder
    # shape - only ask when that's ambiguous (no card found yet, or several
    # readers plugged in at once). Bounded like every other prompt loop here
    # ($script:MaxPromptTries): on a dead input stream an unbounded retry
    # would spin printing this menu until the process is killed.
    $tries = 0
    :cardFlow while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid card selection after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }

        $drives     = @(Get-SdCardCandidates)
        $candidates = @($drives | Where-Object { $_.LooksLikeCard })
        $picked     = @()

        if ($candidates.Count -eq 1) {
            $picked = @($candidates[0].Root)
            Write-Host ("`nUsing {0} (only drive with a baseline/blackhole/wormhole folder tree)." -f $picked[0]) -ForegroundColor DarkGray
        }
        else {
            Write-Host ""
            Write-Host "Insert the card (or plug in its reader), then pick it below:" -ForegroundColor Cyan
            if ($drives.Count -eq 0) {
                Write-Host "  (no drives detected - unusual; type a path manually below)" -ForegroundColor Yellow
            }
            for ($di = 0; $di -lt $drives.Count; $di++) {
                $d = $drives[$di]
                $tag   = if ($d.LooksLikeCard) { '  [has baseline/blackhole/wormhole folders - looks like ours]' }
                         elseif ($d.IsRepoDrive) { '  << this project lives here - almost certainly not the card' }
                         else { '  << no attack folders found at its root' }
                $color = if ($d.LooksLikeCard) { 'Green' } else { 'DarkGray' }
                Write-Host ("  [{0}] {1}{2}" -f ($di + 1), $d.Root, $tag) -ForegroundColor $color
            }
            # Numbered in the order they are PRINTED. The bulk option only
            # appears when there are 2+ cards to apply it to, and computing
            # the indices unconditionally used to leave a hole in the list.
            $next = $drives.Count + 1
            $allIdx = -1
            if ($candidates.Count -gt 1) {
                $allIdx = $next++
                Write-Host ("  [{0}] import ALL {1} card-looking drives above now (same run: {2}/{3}/{4}, repeat {5})" -f $allIdx, $candidates.Count, $attack, $topology, $location, $repeat)
            }
            $manualIdx = $next++
            $rescanIdx = $next++
            $doneIdx   = $next++
            Write-Host ("  [{0}] type a drive/folder path manually" -f $manualIdx)
            Write-Host ("  [{0}] rescan (just inserted/ejected a card)" -f $rescanIdx)
            Write-Host ("  [{0}] cancel - back to the main menu" -f $doneIdx)

            $raw = Read-Line '> '
            $n = 0
            if (-not [int]::TryParse($raw, [ref]$n)) { Write-Host "  Enter a number from the list above." -ForegroundColor Yellow; continue cardFlow }
            $tries = 0

            if ($n -eq $doneIdx) { return }
            if ($n -eq $rescanIdx) { continue cardFlow }

            if ($n -eq $manualIdx) {
                $path = Read-Line '  Card path (e.g. E:\) > '
                if (-not $path) { continue cardFlow }
                $picked = @($path)
            }
            elseif ($allIdx -gt 0 -and $n -eq $allIdx) {
                $picked = @($candidates | ForEach-Object { $_.Root })
            }
            elseif ($n -ge 1 -and $n -le $drives.Count) {
                $d = $drives[$n - 1]
                if (-not $d.LooksLikeCard) {
                    $conf = Read-Line ("  {0} does not look like a pulled SD card - import anyway? [y/N] > " -f $d.Root)
                    if ($conf -ne 'y' -and $conf -ne 'Y') { continue cardFlow }
                }
                $picked = @($d.Root)
            }
            else {
                Write-Host "  Enter a number from the list above." -ForegroundColor Yellow
                continue cardFlow
            }
        }

        foreach ($cardRoot in $picked) {
            if ($picked.Count -gt 1) {
                Write-Host ""
                Write-Host ("=== {0} ===" -f $cardRoot) -ForegroundColor Cyan
            }
            Import-OneSdCard -Card $cardRoot -Repeat $repeat -Roster $rosterPath -DeleteSource -ExpectPrefix $expectPrefix -Scenario $scenario
        }

        # Multiple boards from the SAME run (root + victim + attacker cards,
        # say) share this one attack/topology/location/repeat, so offer
        # another pull before dropping back to the main menu - defaulting to
        # no, since one card is the common case now.
        $again = Read-Line "`nImport another card for this same run? [y/N] > "
        if ($again -ne 'y' -and $again -ne 'Y') { break cardFlow }
    }
}

function Invoke-VerifyRun {
    # Paper-backed 3-sigma check (tools\verify_attack.py): compares a captured
    # run's feature_table.csv (M7/features.py output) against the published
    # attack signature and reports CONFIRMED / NOT CONFIRMED. Read-only -
    # never touches a board - so unlike every other option here this needs no
    # -DryRun gate or confirm-before-running. Mirrors menu.ps1's "Verify a
    # run" action, extended with the topology/scenario/location questions
    # Get-RunDirs needs to find the right feature_table.csv on its own.
    Write-Host ""
    Write-Host "Checks a captured run's feature_table.csv against the published 3-sigma" -ForegroundColor DarkGray
    Write-Host "attack signature. Needs M7 (features.py) already run for this run." -ForegroundColor DarkGray

    $vAttackIdx = Show-Menu -Title 'Which attack to verify?' -Options @(
        'auto-detect (reads Label values in the feature table)',
        'blackhole',
        'wormhole'
    ) -DefaultIndex 0
    $vAttack = @('auto', 'blackhole', 'wormhole')[$vAttackIdx]

    # feature_table.csv lives under the same attack/topology/location/scenario
    # tree Get-RunDirs computes for a capture. 'auto' has no folder of its own
    # to look in, so default the lookup to blackhole (the common case, same as
    # menu.ps1's verify flow) - it's just a starting guess, overridable below.
    $folderAttack = if ($vAttack -eq 'auto') { 'blackhole' } else { $vAttack }

    $topoIdx     = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex 0
    $topology    = $TOPOLOGIES[$topoIdx]
    $scenarioIdx = Show-Menu -Title 'Scenario (what this capture used, if any):' -Options $SCENARIO_LABELS -DefaultIndex 0
    $scenario    = $SCENARIOS[$scenarioIdx]
    $locationIdx = Show-Menu -Title 'Location:' -Options $LOCATIONS -DefaultIndex 0
    $location    = $LOCATIONS[$locationIdx]

    $dirs  = Get-RunDirs -Attack $folderAttack -Topology $topology -Location $location -Scenario $scenario
    $table = Join-Path $dirs.Analysis 'feature_table.csv'
    if (-not (Test-Path $table)) {
        Write-Host ("`n  {0} doesn't exist yet - run M7 (features.py) for this run first, or type a different path below." -f $table) -ForegroundColor Yellow
    }
    $typed = Read-Line ("`nfeature_table.csv path [{0}] > " -f $table)
    if ($typed) { $table = $typed }
    if (-not (Test-Path $table)) {
        Write-Host ("  {0} still doesn't exist - nothing to verify." -f $table) -ForegroundColor Yellow
        return
    }

    $vaArgs    = @($table)
    $attackTag = ''
    if ($vAttack -ne 'auto') { $vaArgs += @('--attack', $vAttack); $attackTag = " --attack $vAttack" }

    Write-Host ""
    Write-Host ("Running: python tools\verify_attack.py `"$table`"$attackTag") -ForegroundColor DarkGray
    Push-Location $base
    try { python (Join-Path $base 'tools\verify_attack.py') @vaArgs } finally { Pop-Location }
}

function Get-ConfiguredAttackerMac {
    # Parses  #define BLACKHOLE_ATTACKER_MAC   {0xB0, 0xCB, ...}  out of mesh_config.h
    # and returns it in lowercase colon form, or $null if it can't be read.
    $hdr = Join-Path $base 'components\mesh_common\include\mesh_config.h'
    if (-not (Test-Path $hdr)) { return $null }
    $hit = Select-String -Path $hdr -Pattern '^\s*#define\s+BLACKHOLE_ATTACKER_MAC\s+\{([^}]+)\}' |
        Select-Object -First 1
    if (-not $hit) { return $null }

    $bytes = @()
    foreach ($tok in ($hit.Matches[0].Groups[1].Value -split ',')) {
        if ($tok.Trim() -match '0x([0-9a-fA-F]{1,2})') {
            $bytes += $Matches[1].ToLower().PadLeft(2, '0')
        }
    }
    if ($bytes.Count -ne 6) { return $null }
    return ($bytes -join ':')
}

function Set-ConfiguredAttackerMac {
    # Rewrites the WHOLE #define line (array + trailing comment) so the comment
    # never goes stale pointing at the old port/MAC after an auto-fix.
    param([string]$Mac, [string]$PortLabel)
    $hdr = Join-Path $base 'components\mesh_common\include\mesh_config.h'
    if (-not (Test-Path $hdr)) { return $false }

    $bytes = ($Mac -split ':') | ForEach-Object { '0x' + $_.ToUpper() }
    $newLine = "#define BLACKHOLE_ATTACKER_MAC   {$($bytes -join ', ')} // $PortLabel (blackhole attacker) - $Mac"

    # NOT Get-Content -Raw: on Windows PowerShell 5.1 it misdetects this file's
    # no-BOM UTF-8 as the system codepage, corrupting every non-ASCII byte in
    # the file (the header's em-dash comments) on write-back. Read explicitly.
    $content = [System.IO.File]::ReadAllText($hdr, [System.Text.UTF8Encoding]::new($false))
    $pattern = '(?m)^\s*#define\s+BLACKHOLE_ATTACKER_MAC\s+\{[^}]*\}.*$'
    if ($content -notmatch $pattern) { return $false }

    $updated = $content -replace $pattern, $newLine
    # WriteAllText, not Set-Content -Encoding utf8: the latter adds a BOM in
    # Windows PowerShell 5.1, which a C header should not carry.
    [System.IO.File]::WriteAllText($hdr, $updated, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Get-PhaseDurations {
    # Parses the four PHASE_*_S constants out of mesh_config.h (seconds), the
    # same way Get-ConfiguredAttackerMac reads BLACKHOLE_ATTACKER_MAC above -
    # so the estimate moves when a campaign retunes phase lengths instead of
    # silently going stale, which is exactly the doc/code drift this project
    # has been bitten by before (see thesis-deviate.md history).
    #
    # Returns @{ Stabilise=; Baseline=; Attack=; Cooldown=; Total=; Ok= }.
    # Ok=$false means the header couldn't be read/parsed and Total is the
    # hardcoded fallback - callers MUST show that as a guess, never as fact.
    $hdr = Join-Path $base 'components\mesh_common\include\mesh_config.h'
    $names = @{
        Stabilise = 'PHASE_STABILISE_S'
        Baseline  = 'PHASE_BASELINE_S'
        Attack    = 'PHASE_ATTACK_S'
        Cooldown  = 'PHASE_COOLDOWN_S'
    }
    $vals = @{}
    $ok = Test-Path $hdr
    if ($ok) {
        foreach ($key in $names.Keys) {
            $hit = Select-String -Path $hdr -Pattern "^\s*#define\s+$($names[$key])\s+(\d+)U?" |
                Select-Object -First 1
            if ($hit) {
                $vals[$key] = [int]$hit.Matches[0].Groups[1].Value
            } else {
                $ok = $false
            }
        }
    }
    if (-not $ok) {
        # Fallback matches Table 4.1 as of this writing - only used if the
        # header is missing/renamed, and always flagged, never presented as
        # measured fact (see the two call sites below).
        $vals = @{ Stabilise = 60; Baseline = 300; Attack = 180; Cooldown = 120 }
    }
    $vals.Total = $vals.Stabilise + $vals.Baseline + $vals.Attack + $vals.Cooldown
    $vals.Ok = $ok
    return $vals
}

function Format-Duration {
    # Seconds -> "11 min" / "1 hr 5 min" / "43 sec", for estimate/elapsed lines.
    param([int]$Seconds)
    if ($Seconds -lt 60) { return "$Seconds sec" }
    $h = [math]::Floor($Seconds / 3600)
    $m = [math]::Floor(($Seconds % 3600) / 60)
    $s = $Seconds % 60
    if ($h -gt 0) { return "{0} hr {1} min" -f $h, $m }
    if ($s -eq 0) { return "$m min" }
    return "{0} min {1:D2} sec" -f $m, $s
}

function Get-BoardBuildDir {
    # Mirrors run.ps1's OWN build-dir naming (run.ps1:294-307) so the wizard can
    # check whether a board's build already exists (warm) or would be a first,
    # slower build (cold) - WITHOUT touching run.ps1, which stays the only place
    # that dir is actually created. Read-only prediction; if this ever drifts
    # from run.ps1's real naming the worst case is a wrong warm/cold guess in
    # the estimate, never a wrong build (run.ps1 computes its own dir itself).
    param($Params)
    $role = $Params.Role
    $attack = $Params.Attack
    $topology = $Params.Topology
    $suffix = "${role}_${attack}_${topology}"
    if ($attack -eq 'wormhole' -and $role -ne 'root' -and $Params.WormholeEnd) {
        $suffix += "_$($Params.WormholeEnd)"
    }
    if ($attack -eq 'blackhole' -and $role -ne 'root' -and $Params.BlackholeRole) {
        $suffix += "_$($Params.BlackholeRole)"
    }
    # SCENARIO TAG RULE (kept identical in run.ps1 and menu.ps1's Get-BuildDirSpec):
    # only a board that actually gets -DTRAFFIC_PROFILE takes a suffix, so
    # 'none'/'mobility'/'powercycle' builds are untouched.
    $scenario = $Params.Scenario
    if ($scenario -eq 'burst' -and ($role -eq 'root' -or $Params.ScenarioTarget)) { $suffix += '_burst' }
    if ($scenario -eq 'highload' -and $role -ne 'root') { $suffix += '_highload' }
    if ($Params.CommandCenter) { $suffix += '_cc' }
    $portTag = ($Params.Port -replace '[^A-Za-z0-9]', '')
    $proj = if ($role -eq 'root') { 'root_node' } else { 'child_node' }
    return Join-Path $buildRoot "$proj\build_${suffix}_$portTag"
}

function Get-BoardMac {
    # Reads the chip's eFuse MAC via the existing tools\Get-EspMac.ps1.
    # NOTE: the parameter is deliberately NOT called $Port - dot-sourcing that
    # script runs its own param([string]$Port,...) block in THIS scope and would
    # blank out a variable of that name before we got to use it.
    param([string]$TargetPort)
    $tool = Join-Path $base 'tools\Get-EspMac.ps1'
    if (-not (Test-Path $tool)) { return $null }
    try {
        . $tool                                   # dot-source: loads the function, runs nothing
        $r = Get-EspMac -Port $TargetPort
        if ($r -and $r.MAC) { return ([string]$r.MAC).ToLower() }
    }
    catch { return $null }
    return $null
}

function Get-SdLocation {
    # Reads a running board's location.txt WITHOUT changing it, so a write can be
    # shown as "Goks -> G402" instead of a blind overwrite, and skipped entirely
    # when it would be a no-op. Same serial path as Set-SdLocation, same
    # requirement that the board has actually booted.
    #
    # Returns .State, which callers must branch on rather than just reading
    # .Value: UNKNOWN means "could not read it" (no card, or firmware older than
    # GET_LOCATION), which is NOT the same as NONE ("read fine, the file isn't
    # there"). Treating the two alike would report an unreadable card as empty.
    #   OK      -> .Value is the recorded site
    #   NONE    -> no location.txt; the board mirrors nothing to its card
    #   INVALID -> .Value is the unrecognised raw text on the card
    #   UNKNOWN -> could not be read; fall back to the blind-overwrite warning
    param([string]$TargetPort)
    Push-Location (Join-Path $base 'tools')
    try {
        $out = & python export_logs.py --port $TargetPort --get-location 2>&1
        $hit = $out | Select-String -Pattern '^CURRENT_LOCATION:\s*(.+)$' | Select-Object -First 1
        if (-not $hit) { return @{ State = 'UNKNOWN'; Value = $null; Lines = @($out) } }

        $val = $hit.Matches[0].Groups[1].Value.Trim()
        if ($val -eq 'NONE')    { return @{ State = 'NONE';    Value = $null; Lines = @($out) } }
        if ($val -eq 'UNKNOWN') { return @{ State = 'UNKNOWN'; Value = $null; Lines = @($out) } }
        if ($val -like 'INVALID:*') {
            return @{ State = 'INVALID'; Value = $val.Substring(8).Trim(); Lines = @($out) }
        }
        return @{ State = 'OK'; Value = $val; Lines = @($out) }
    }
    catch { return @{ State = 'UNKNOWN'; Value = $null; Lines = @($_.Exception.Message) } }
    finally { Pop-Location }
}

function Format-SdLocationState {
    # One short phrase for a board's current location, for the confirm tables.
    param($Read)
    switch ($Read.State) {
        'OK'      { return $Read.Value }
        'NONE'    { return '(no location.txt - records nothing)' }
        'INVALID' { return ("(invalid: '{0}' - records nothing)" -f $Read.Value) }
        default   { return '(could not read)' }
    }
}

function Set-SdLocation {
    # Sends SET_LOCATION=<value> to an ALREADY-RUNNING board over the tools\
    # export_logs.py serial path (see csv_logger.c's serial dispatcher). Unlike
    # Get-BoardMac (which uses esptool and works even mid-reset/bootloader),
    # this needs the board to have already booted, joined the mesh, and reached
    # csv_logger_init() -- i.e. it fixes a card an already-running board found
    # broken (SD_STATUS_NO_LOCATION_FILE/BAD_LOCATION in its own boot log), not
    # one that's about to be freshly flashed. Takes effect on THAT board's next
    # boot, not this session.
    param([string]$TargetPort, [string]$Location)
    Push-Location (Join-Path $base 'tools')
    try {
        $out = & python export_logs.py --port $TargetPort --set-location $Location 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Lines = @($out) }
    }
    catch { return @{ Ok = $false; Lines = @($_.Exception.Message) } }
    finally { Pop-Location }
}

function New-RunParams {
    # Returns an ORDERED hashtable for splatting into run.ps1. Hashtable splatting
    # binds by parameter NAME; an array would bind positionally and shove the whole
    # thing into -Port.
    param($Board, [string]$Attack, [string]$Topology, [string]$Location, [int]$RepeatNum, [string]$Scenario = 'none')

    $h = [ordered]@{
        Port     = $Board.Port
        Role     = $Board.Role
        Label    = $Board.Label
        Topology = $Topology
        Location = $Location
        Repeat   = $RepeatNum
        Scenario = $Scenario
        Wipe     = $true
        Flash    = $true
    }
    if ($Board.ScenarioTarget) { $h.ScenarioTarget = $true }

    if ($Board.Role -eq 'root') {
        $h.Attack  = $Attack
        $h.Analyze = $true
        return $h
    }

    switch ($Board.Kind) {
        'attacker' { $h.Attack = 'blackhole'; $h.BlackholeRole = 'attacker' }
        'victim'   { $h.Attack = 'blackhole'; $h.BlackholeRole = 'victim' }
        'A'        { $h.Attack = 'wormhole';  $h.WormholeEnd   = 'A' }
        'B'        { $h.Attack = 'wormhole';  $h.WormholeEnd   = 'B' }
        # A wormhole control runs PLAIN victim firmware; only its export folder changes.
        'control'  { $h.Attack = 'none';      $h.DestAttack    = 'wormhole' }
        default    { $h.Attack = 'none' }
    }
    $h.Export = $true
    return $h
}

function Get-RunDirs {
    # The attack/topology folder names the whole pipeline agrees on. 'none' files
    # under baseline\ and 'partial' under partial_mesh\ - these MUST stay
    # byte-identical to _subdir_for()/_TOPOLOGY_DIR in tools\export_logs.py and to
    # s_attack_dirs/s_topo_dirs in components\mesh_common\src\sd_status.c.
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario = 'none')
    $attackDir = $Attack
    if ($Attack -eq 'none') { $attackDir = 'baseline' }
    $topoDir = switch ($Topology) {
        'star'    { 'star' }
        'tree'    { 'tree' }
        'linear'  { 'linear' }
        'partial' { 'partial_mesh' }
    }
    # 'none' must NOT become a real folder segment - it's the pre-scenario
    # default, so an un-scenario'd run (the vast majority) has to resolve to
    # the SAME path this always used, or preprocess.py's flat glob stops
    # finding it and a fresh run orphans itself one level below old data.
    # Must stay byte-identical to _subdir_for() in tools\export_logs.py.
    $scenarioSeg = if ($Scenario -and $Scenario -ne 'none') { "\$Scenario" } else { '' }
    return [pscustomobject]@{
        AttackDir = $attackDir
        TopoDir   = $topoDir
        Export    = (Join-Path $base "tools\exports\$attackDir\$topoDir\$Location$scenarioSeg")
        Analysis  = (Join-Path $base "analysis\$attackDir\$topoDir\$Location$scenarioSeg")
    }
}

function Get-PresetFiles {
    # Newest first - the preset you used last is almost always the one you want.
    $dir = Join-Path $base 'presets'
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem -Path $dir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
}

function Read-PresetFile {
    # Get-Content -Raw tolerates the UTF-8 BOM that Set-Content -Encoding UTF8
    # leaves on PS 5.1 - some presets on disk have one, some don't.
    param([string]$Path)
    try { return (Get-Content -Raw -Path $Path | ConvertFrom-Json) }
    catch { return $null }
}

function ConvertTo-Roster {
    # Board objects from a preset, re-imposing the ordering invariant the run
    # depends on: children first, root last, whatever order the file used.
    # NOTE: this projection hard-drops any key it does not name - a field added to
    # the save block must be added HERE too or it silently vanishes on load.
    param($Cfg)
    $loaded = @($Cfg.boards | ForEach-Object {
        [pscustomobject]@{
            Label          = [string]$_.Label
            Port           = [string]$_.Port
            Role           = [string]$_.Role
            Kind           = [string]$_.Kind
            Display        = [string]$_.Display
            Mac            = [string]$_.Mac    # '' for presets saved before MACs were recorded
            ScenarioTarget = [bool]$_.ScenarioTarget   # $false for presets saved before scenarios existed
        }
    })
    $roots = @($loaded | Where-Object { $_.Role -eq 'root' })
    return [pscustomobject]@{
        Roster    = (@($loaded | Where-Object { $_.Role -ne 'root' }) + $roots)
        RootCount = $roots.Count
    }
}

function Save-Preset {
    param([string]$Path, [string]$Attack, [string]$Topology, [string]$Location,
          [int]$RepeatNum, $Roster, [string]$Scenario = 'none')
    $toSave = [pscustomobject]@{
        attack   = $Attack
        topology = $Topology
        location = $Location
        scenario = $Scenario
        repeat   = $RepeatNum
        savedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        boards   = @($Roster | ForEach-Object {
            [pscustomobject]@{
                Label = $_.Label; Port = $_.Port; Role = $_.Role
                Kind  = $_.Kind;  Display = $_.Display; Mac = [string]$_.Mac
                ScenarioTarget = [bool]$_.ScenarioTarget
            }
        })
    }
    $toSave | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
}

function Add-BoardMacs {
    # Fills .Mac on every board by reading the chips. Returns the number read.
    # -Known lets a caller hand in a MAC it already read (the pre-flight gate
    # reads the attacker's) so no board is reset twice.
    param($Roster, [hashtable]$Known)
    $got = 0
    foreach ($b in $Roster) {
        if ($Known -and $Known.ContainsKey($b.Port) -and $Known[$b.Port]) {
            $b | Add-Member -NotePropertyName Mac -NotePropertyValue ([string]$Known[$b.Port]) -Force
            Write-Host ("  {0,-8} {1,-7} {2}  (already read)" -f $b.Label, $b.Port, $Known[$b.Port]) -ForegroundColor DarkGray
            $got++
            continue
        }
        Write-Host ("  {0,-8} {1,-7} reading ..." -f $b.Label, $b.Port) -ForegroundColor DarkGray
        $mac = Get-BoardMac -TargetPort $b.Port
        if ($mac) {
            Write-Host ("  {0,-8} {1,-7} {2}" -f $b.Label, $b.Port, $mac) -ForegroundColor Green
            $got++
        }
        else {
            Write-Host ("  {0,-8} {1,-7} could not read - left blank" -f $b.Label, $b.Port) -ForegroundColor Yellow
        }
        $b | Add-Member -NotePropertyName Mac -NotePropertyValue ([string]$mac) -Force
    }
    return $got
}

function Read-RepeatNumber {
    # Shared by the menu flow and the preset picker so the explanation lives once.
    # -AllowBack (menu flow only) returns -1 for 'b'/'back' - a real repeat
    # number is always >= 1, so -1 is an unambiguous "go back" sentinel.
    param([string]$Attack, [string]$Topology, [int]$DefaultRepeat = 1, [switch]$AllowBack)
    $attackWord = $Attack
    if ($Attack -eq 'none') { $attackWord = 'baseline' }
    Write-Host ""
    # This is NOT a capped 1/2/3 menu - it's any positive whole number (see the
    # TryParse below, which only requires $n -ge 1). 1/2/3 are spelled out
    # because that's what the M4 matrix actually needs per cell; 4+ is a plain
    # example line, not a special case, so typing 4, 5, 12... just works and
    # was never blocked - the old wording just never said so.
    Write-Host "Which attempt at this same capture is this?" -ForegroundColor Cyan
    Write-Host ("  1 = first time capturing '{0} + {1}'" -f $Topology, $attackWord) -ForegroundColor DarkGray
    Write-Host "  2 = you already captured it once, this is the second attempt" -ForegroundColor DarkGray
    Write-Host "  3 = third attempt" -ForegroundColor DarkGray
    Write-Host "  4, 5, 6... = any further attempt - type the actual number, no cap here" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  It ONLY tags the USB-exported CSV filename (..._r1_, _r2_, _r3_, ..._r4_," -ForegroundColor DarkGray
    Write-Host "  ...) so a re-run does not overwrite the previous one. It changes nothing" -ForegroundColor DarkGray
    Write-Host "  on the boards or firmware - just which number lands in that filename." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  The SD card's OWN copy numbers itself separately on-device (a lifetime" -ForegroundColor DarkGray
    Write-Host "  boot count for this board+location, not your answer here) and will" -ForegroundColor DarkGray
    Write-Host "  usually show a different, higher number - that's expected, not an error." -ForegroundColor DarkGray
    Write-Host "  Your real repeat number is applied later, when you import the card with" -ForegroundColor DarkGray
    Write-Host "  'import_sdcard.py --repeat N' - see docs/2026-09-14_SD-CARD.md." -ForegroundColor DarkGray
    if ($Attack -eq 'none') {
        Write-Host "  Baseline is the control run and is NOT part of the 24-run M4 matrix," -ForegroundColor DarkGray
        Write-Host "  so 1 is almost always right here." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  The M4 matrix only REQUIRES r1, r2 and r3 to count this cell as done -" -ForegroundColor DarkGray
        Write-Host "  a 4th+ attempt doesn't add to or break that, it's just extra data (e.g." -ForegroundColor DarkGray
        Write-Host "  redoing a run that failed partway, or one you don't trust)." -ForegroundColor DarkGray
    }
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) { throw "No valid repeat number after $script:MaxPromptTries attempts - aborting." }
        $backHint = if ($AllowBack) { " (or 'b' to go back)" } else { '' }
        $raw = Read-Line "> [$DefaultRepeat]$backHint "
        if ($AllowBack -and (Test-BackAnswer $raw)) { return -1 }
        if (-not $raw) { return $DefaultRepeat }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1) { return $n }
        Write-Host "  Enter a positive whole number." -ForegroundColor Yellow
    }
}

function Show-PresetDetails {
    # The point of the picker: everything the preset implies, before anything is
    # flashed. Ports are checked against what Windows currently enumerates, because
    # COM numbers are assigned per USB SOCKET - a preset saved last week can name a
    # port that is now a different board, or no board at all.
    param($Cfg, [string]$Path, [object[]]$Ports, $Roster)

    # Older presets predate the scenario field - treat a missing one as 'none'.
    $cfgScenario = if ($Cfg.PSObject.Properties['scenario']) { [string]$Cfg.scenario } else { 'none' }
    $dirs = Get-RunDirs -Attack ([string]$Cfg.attack) -Topology ([string]$Cfg.topology) -Location ([string]$Cfg.location) -Scenario $cfgScenario
    $live = @($Ports | Select-Object -ExpandProperty Port)
    $attackWord = [string]$Cfg.attack
    if ($attackWord -eq 'none') { $attackWord = 'baseline' }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host ("  Preset   : {0}" -f (Split-Path -Leaf $Path)) -ForegroundColor Cyan
    if ($Cfg.savedAt) { Write-Host ("  Saved    : {0}" -f [string]$Cfg.savedAt) -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host ("  Attack   : {0}" -f $attackWord)
    Write-Host ("  Topology : {0}" -f [string]$Cfg.topology)
    Write-Host ("  Scenario : {0}" -f $cfgScenario)
    Write-Host ("  Location : {0}" -f [string]$Cfg.location)
    Write-Host ("  Repeat   : {0}" -f [int]$Cfg.repeat)
    Write-Host ""
    Write-Host "  Boards (root is always last):"
    $step = 0
    foreach ($b in $Roster) {
        $step++
        $mac = if ($b.Mac) { $b.Mac } else { 'not recorded' }
        $miss = ''
        if ($live -notcontains $b.Port) { $miss = '  << port NOT PRESENT' }
        if ($b.ScenarioTarget) { $miss = "  << $cfgScenario TARGET$miss" }
        $line = ("   [{0}] {1,-8} {2,-27} {3,-7} {4,-19}{5}" -f $step, $b.Label, $b.Display, $b.Port, $mac, $miss).TrimEnd()
        if ($miss) { Write-Host $line -ForegroundColor Yellow } else { Write-Host $line }
    }

    # Free cross-check (a file read, no board contact): does this preset's attacker
    # match the MAC the victim firmware is compiled to send its probes to? A preset
    # naming a different attacker produces a clean run with no attack signature.
    if ([string]$Cfg.attack -eq 'blackhole') {
        $att = $Roster | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
        $wantMac = Get-ConfiguredAttackerMac
        Write-Host ""
        if (-not $att) {
            Write-Host "  WARNING: blackhole preset with no attacker board." -ForegroundColor Red
        }
        elseif (-not $wantMac) {
            Write-Host "  Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h." -ForegroundColor Yellow
        }
        else {
            # BLACKHOLE_ATTACKER_MAC is baked into the VICTIM firmware at BUILD time
            # (mesh_config.h -> compiled -> flashed). Every victim board already on the
            # bench only ever unicasts its probes to that one exact MAC, no matter
            # which physical board is wearing the "attacker" label in this roster - so
            # "who is the attacker" is really "whichever board holds this MAC", and
            # this preset's own attacker board only matters if its MAC equals it.
            Write-Host ("  mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $wantMac) -ForegroundColor Cyan
            Write-Host "  (compiled into victim firmware - victims only ever target THIS MAC)" -ForegroundColor DarkGray
            if (-not $att.Mac) {
                Write-Host ("    {0} is this preset's attacker, but its MAC is not recorded here." -f $att.Label) -ForegroundColor DarkGray
                Write-Host "    Choose 'Verify MACs now' to read it and cross-check, or 'Fix mesh_config.h" -ForegroundColor DarkGray
                Write-Host "    attacker MAC now' below to read-and-fix in one step." -ForegroundColor DarkGray
            }
            elseif ($att.Mac -eq $wantMac) {
                Write-Host ("    {0} matches - this IS the board victims will target. Correct." -f $att.Label) -ForegroundColor Green
            }
            else {
                Write-Host ("    MISMATCH: this preset's attacker, {0}, is {1}" -f $att.Label, $att.Mac) -ForegroundColor Red
                Write-Host ("    but victims were built to target a DIFFERENT MAC: {0}" -f $wantMac) -ForegroundColor Red
                Write-Host "    Result: probes still go out, but none get addressed to $($att.Label), so the" -ForegroundColor Red
                Write-Host "    run completes as a clean baseline with no attack signature at all." -ForegroundColor Red

                # Name the actual board behind the mismatch when possible - this is
                # the difference between "you picked the wrong board as attacker"
                # (an easy roster fix) and "mesh_config.h is just stale" (needs the
                # fix option below), and printing only the raw MACs left the operator
                # to work that out by hand.
                $sameMac = $Roster | Where-Object { $_.Mac -and $_.Mac -eq $wantMac -and $_ -ne $att } | Select-Object -First 1
                if ($sameMac) {
                    Write-Host ("    {0} in THIS roster already has that MAC - it should be the attacker," -f $sameMac.Label) -ForegroundColor Yellow
                    Write-Host "    not $($att.Label). Swap roles when building the roster, or use the fix" -ForegroundColor Yellow
                    Write-Host "    option below to point mesh_config.h at $($att.Label) instead." -ForegroundColor Yellow
                }
                else {
                    Write-Host "    No board in this roster has that MAC recorded either - it likely belongs" -ForegroundColor Yellow
                    Write-Host "    to a board outside this roster, or is stale from a wipe/reflash." -ForegroundColor Yellow
                }
                Write-Host "    Fix it below with 'Fix mesh_config.h attacker MAC now'." -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host ("  Exports  -> {0}" -f $dirs.Export)
    Write-Host ("  Analysis -> {0}" -f $dirs.Analysis)
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
}

function Format-RunParams {
    # Renders the splat hashtable the way you'd type it, for display only.
    param($P)
    $parts = @()
    foreach ($k in $P.Keys) {
        $v = $P[$k]
        if ($v -is [bool]) {
            if ($v) { $parts += "-$k" }
        }
        else { $parts += "-$k $v" }
    }
    return ($parts -join ' ')
}

# ================================================================ CONFIG =====
# Either loaded from a preset, or gathered through the menus below.

$attack = ''; $topology = ''; $location = ''; $repeat = 1; $scenario = 'none'
$roster = @()

# ------------------------------------------------------------ preset picker ----
# Runs only when no -Preset was given AND at least one preset exists, so both
# `-Preset <path>` and a tree with no presets\ folder behave exactly as before.
# On commit it sets $Preset to a FULL path (Test-Path below resolves against the
# caller's CWD, not $base) and falls through to the loader.

$presetFromPicker = $false
$bannerShown      = $false

# -Preset on the command line means "just run this, non-interactively" - the mode
# menu only shows up when nothing was passed, same condition as the preset picker.
if (-not $Preset) {
    # Looped, not a one-shot if/return: each submenu's OWN "done - back to the
    # main menu" option only breaks that submenu's inner while loop and returns
    # HERE. Without this wrapper loop, "here" was a bare `return` that ended the
    # whole script - so "back to the main menu" actually closed the wizard, one
    # level short of where its own label said it would land. Only "Run a
    # capture" (modeIdx 0) breaks out for real, falling through to the preset
    # picker / manual menus below.
    while ($true) {
        Write-Host ""
        Write-Host "=== Capture run wizard ===" -ForegroundColor Green
        if ($DryRun) { Write-Host "DRY RUN - nothing will be flashed." -ForegroundColor Yellow }
        $bannerShown = $true

        $modeIdx = Show-Menu -Title 'What do you want to do?' -Options @(
            'Run a capture (attack/baseline + topology - the normal flow)',
            "Wipe a board clean (full erase, no firmware - for when you're not sure what's on it)",
            'Write/update location.txt on an already-running board (over USB)',
            'Firmware self-test - build + flash ONE board and check the SD/location code (no capture, no attack, no export)',
            'Import CSVs from a pulled SD card - one board, or several at once (no board/COM contact)',
            'Verify a run (paper-backed 3-sigma attack check - no board/COM contact)'
        ) -DefaultIndex 0

        if ($modeIdx -eq 0) { break }
        if ($modeIdx -eq 1) { Invoke-WipeBoards; continue }
        if ($modeIdx -eq 2) { Invoke-SetLocationBoards; continue }
        if ($modeIdx -eq 3) { Invoke-FirmwareSelfTest; continue }
        if ($modeIdx -eq 4) { Invoke-ImportSdCard; continue }
        if ($modeIdx -eq 5) { Invoke-VerifyRun; continue }
    }
}

# Wraps the preset picker AND the preset-vs-menus block below in one loop so
# that pressing 'b' on the manual flow's very FIRST question (step 0, Attack
# type - it has no earlier local step to fall back to) can still go
# somewhere: back to this same preset picker, rather than being the one
# question in the whole flow with no way to back out of short of Ctrl+C.
$backToPresetPicker = $false
:restart while ($true) {

if (-not $Preset) {
    $presetFiles = @(Get-PresetFiles)
    if ($presetFiles.Count -gt 0) {
        if (-not $bannerShown) {
            Write-Host ""
            Write-Host "=== Capture run wizard ===" -ForegroundColor Green
            if ($DryRun) { Write-Host "DRY RUN - nothing will be flashed." -ForegroundColor Yellow }
            $bannerShown = $true
        }

        $pickPorts = Get-PortList
        $picking   = $true

        while ($picking) {
            # Show-Menu takes numbers only - there is no letter escape - so the
            # opt-out has to be the last numbered entry.
            $opts = @($presetFiles | ForEach-Object {
                $c = Read-PresetFile -Path $_.FullName
                if (-not $c) { "{0,-26} (unreadable)" -f $_.Name }
                else {
                    $a = [string]$c.attack
                    if ($a -eq 'none') { $a = 'baseline' }
                    "{0,-26} {1,-10} {2,-8} {3,-13} {4} board(s), {5}" -f
                        $_.Name, $a, [string]$c.topology, [string]$c.location,
                        @($c.boards).Count, $_.LastWriteTime.ToString('MMM dd')
                }
            })
            $opts += 'No preset - answer the menus instead'

            $idx = Show-Menu -Title 'Load a saved preset?' -Options $opts -DefaultIndex 0
            if ($idx -eq $presetFiles.Count) { break }

            $file = $presetFiles[$idx]
            $cfg  = Read-PresetFile -Path $file.FullName
            if (-not $cfg) {
                Write-Host ("  Could not parse {0} - pick another." -f $file.Name) -ForegroundColor Yellow
                continue
            }
            $preview = (ConvertTo-Roster -Cfg $cfg).Roster
            # Older presets predate the scenario field - treat a missing one as 'none'.
            $cfgScenario = if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario } else { 'none' }

            $deciding = $true
            while ($deciding) {
                Show-PresetDetails -Cfg $cfg -Path $file.FullName -Ports $pickPorts -Roster $preview

                switch (Show-Menu -Title 'Use this preset?' -Options @(
                    'Yes - use it',
                    'Verify MACs now (reads each board, ~2s each, briefly resets them)',
                    'Write/update location.txt on all boards'' SD cards (over USB, needs each board already running)',
                    'Fix mesh_config.h attacker MAC now (reads the attacker board, updates the build)',
                    'Show raw preset JSON (just to double-check the file itself, no board access)',
                    'Delete this preset (e.g. an accidental duplicate)',
                    'Pick a different preset',
                    'No preset - answer the menus instead'
                ) -DefaultIndex 0) {

                    0 { $Preset = $file.FullName; $presetFromPicker = $true; $deciding = $false; $picking = $false }

                    1 {
                        Write-Host ""
                        $changed = $false
                        foreach ($b in $preview) {
                            # A preset stores port names, and ports get reassigned -
                            # COM7 that was node3 last week can be a receiver today.
                            if (-not (Test-PortSafeToTouch -Port $b.Port -Action 'reset it to read a MAC')) { continue }
                            Write-Host ("  {0,-8} {1,-7} reading ..." -f $b.Label, $b.Port) -ForegroundColor DarkGray
                            $got = Get-BoardMac -TargetPort $b.Port
                            if (-not $got) {
                                Write-Host ("  {0,-8} {1,-7} could not read (port busy, empty, or esptool missing)" -f $b.Label, $b.Port) -ForegroundColor Yellow
                            }
                            elseif (-not $b.Mac) {
                                Write-Host ("  {0,-8} {1,-7} {2}  (was not recorded)" -f $b.Label, $b.Port, $got) -ForegroundColor Green
                                $b.Mac = $got; $changed = $true
                            }
                            elseif ($got -eq $b.Mac) {
                                Write-Host ("  {0,-8} {1,-7} {2}  matches" -f $b.Label, $b.Port, $got) -ForegroundColor Green
                            }
                            else {
                                Write-Host ("  {0,-8} {1,-7} DRIFT - preset says {2}, board is {3}" -f $b.Label, $b.Port, $b.Mac, $got) -ForegroundColor Red
                                Write-Host "           This port is not the board the preset was saved with." -ForegroundColor Red
                                $b.Mac = $got; $changed = $true
                            }
                        }
                        if ($changed) {
                            $ans = Read-Line "`n  Write these MACs back into the preset? [y/N] > "
                            if ($ans -eq 'y' -or $ans -eq 'Y') {
                                Save-Preset -Path $file.FullName -Attack ([string]$cfg.attack) `
                                    -Topology ([string]$cfg.topology) -Location ([string]$cfg.location) `
                                    -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario
                                $cfg = Read-PresetFile -Path $file.FullName
                                Write-Host ("  Updated -> {0}" -f $file.Name) -ForegroundColor Green
                            }
                        }
                    }

                    2 {
                        Write-Host ""
                        Write-Host "This sends SET_LOCATION over USB to whatever is CURRENTLY running on each" -ForegroundColor DarkGray
                        Write-Host "port -- it only works if that board already booted this session (mesh" -ForegroundColor DarkGray
                        Write-Host "joined). It fixes a card an already-running board reported broken; it does" -ForegroundColor DarkGray
                        Write-Host "NOT help a board that hasn't been flashed/booted yet." -ForegroundColor DarkGray
                        $presetLoc = [string]$cfg.location
                        Write-Host ""
                        Write-Host ("Reading each board's current location.txt ({0} board(s), a few seconds each) ..." -f $preview.Count) -ForegroundColor DarkGray
                        $locPlan = @()
                        foreach ($b in $preview) {
                            if (-not (Test-PortSafeToTouch -Port $b.Port -Action 'write a location to it')) { continue }
                            $cur = Get-SdLocation -TargetPort $b.Port
                            $locPlan += [pscustomobject]@{
                                Label   = $b.Label
                                Port    = $b.Port
                                Current = $cur
                                Skip    = ($cur.State -eq 'OK' -and $cur.Value -eq $presetLoc)
                            }
                        }

                        Write-Host ""
                        foreach ($row in $locPlan) {
                            $was = Format-SdLocationState $row.Current
                            if ($row.Skip) {
                                Write-Host ("  {0,-8} {1,-7} {2,-38} already set - leaving alone" -f $row.Label, $row.Port, $was) -ForegroundColor DarkGray
                            }
                            else {
                                Write-Host ("  {0,-8} {1,-7} {2,-38} -> {3}" -f $row.Label, $row.Port, $was, $presetLoc)
                            }
                        }
                        $locBlind   = @($locPlan | Where-Object { $_.Current.State -eq 'UNKNOWN' })
                        $locToWrite = @($locPlan | Where-Object { -not $_.Skip })
                        if ($locBlind.Count -gt 0) {
                            Write-Host ""
                            Write-Host ("{0} board(s) above could not be read - for those this is still a BLIND overwrite." -f $locBlind.Count) -ForegroundColor Yellow
                        }

                        if ($locPlan.Count -eq 0) {
                            Write-Host "`n  No usable boards left after the safety check - nothing to write." -ForegroundColor Yellow
                        }
                        elseif ($locToWrite.Count -eq 0) {
                            Write-Host "`n  Every board is already set to $presetLoc - nothing to write." -ForegroundColor Green
                        }
                        else {
                            $goAns = Read-Line "`nWrite $presetLoc to $($locToWrite.Count) of $($locPlan.Count) board(s)? [y/N] > "
                            if ($goAns -ne 'y' -and $goAns -ne 'Y') {
                                Write-Host "  Skipped - nothing written." -ForegroundColor DarkGray
                            }
                            else {
                                foreach ($row in $locToWrite) {
                                    Write-Host ("`n  {0,-8} {1,-7} SET_LOCATION={2} ..." -f $row.Label, $row.Port, $presetLoc) -ForegroundColor DarkGray
                                    $r = Set-SdLocation -TargetPort $row.Port -Location $presetLoc
                                    $color = if ($r.Ok) { 'Green' } else { 'Yellow' }
                                    foreach ($line in $r.Lines) { Write-Host ("    " + $line) -ForegroundColor $color }
                                }
                                Write-Host "`nReboot or reflash each board above to confirm 'SD ENV: OK' before relying on it." -ForegroundColor DarkGray
                            }
                        }
                    }

                    3 {
                        Write-Host ""
                        if ([string]$cfg.attack -ne 'blackhole') {
                            Write-Host ("This preset's attack is '{0}' - there is no attacker MAC to fix." -f [string]$cfg.attack) -ForegroundColor Yellow
                        }
                        else {
                            $att = $preview | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
                            if (-not $att) {
                                Write-Host "This preset has no attacker board - nothing to fix." -ForegroundColor Yellow
                            }
                            else {
                                $wantMac = Get-ConfiguredAttackerMac
                                if (-not $wantMac) {
                                    Write-Host "Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h - edit it by hand." -ForegroundColor Yellow
                                }
                                elseif ($DryRun) {
                                    # This action's whole point is a fresh hardware read, so there is
                                    # nothing useful to simulate - unlike the rest of the wizard's DRY
                                    # RUN messages, which describe a write that would happen. Refuse
                                    # outright rather than quietly resetting a real board under -DryRun.
                                    Write-Host ("DRY RUN - would reset {0} on {1} to read its MAC and compare to mesh_config.h; not touching real hardware." -f $att.Label, $att.Port) -ForegroundColor Yellow
                                }
                                elseif (-not (Test-PortSafeToTouch -Port $att.Port -Action 'reset it to read a MAC')) {
                                    # Test-PortSafeToTouch already explained why.
                                }
                                else {
                                    Write-Host ("Reading {0} on {1} to confirm its real MAC (briefly resets the board) ..." -f $att.Label, $att.Port) -ForegroundColor DarkGray
                                    $gotMac = Get-BoardMac -TargetPort $att.Port
                                    if (-not $gotMac) {
                                        Write-Host ("Could not read a MAC from {0} - is {1} actually plugged into it right now?" -f $att.Port, $att.Label) -ForegroundColor Yellow
                                    }
                                    elseif ($gotMac -eq $wantMac) {
                                        Write-Host ("Already matches - mesh_config.h already targets {0}'s real MAC ({1}). Nothing to fix." -f $att.Label, $gotMac) -ForegroundColor Green
                                    }
                                    else {
                                        Write-Host ""
                                        Write-Host ("  mesh_config.h currently targets : {0}" -f $wantMac) -ForegroundColor Yellow
                                        Write-Host ("  {0} on {1} is actually           : {2}" -f $att.Label, $att.Port, $gotMac) -ForegroundColor Yellow
                                        $fixAns = Read-Line ("`nUpdate mesh_config.h so victims target {0} ({1})? [y/N] > " -f $att.Label, $gotMac)
                                        if ($fixAns -eq 'y' -or $fixAns -eq 'Y') {
                                            $ok = Set-ConfiguredAttackerMac -Mac $gotMac -PortLabel "$($att.Port) ($($att.Label))"
                                            if ($ok) {
                                                Write-Host "  mesh_config.h updated - the next flash will pick it up (no wipe needed)." -ForegroundColor Green
                                                if ($att.Mac -ne $gotMac) {
                                                    $att.Mac = $gotMac
                                                    Save-Preset -Path $file.FullName -Attack ([string]$cfg.attack) `
                                                        -Topology ([string]$cfg.topology) -Location ([string]$cfg.location) `
                                                        -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario
                                                    $cfg = Read-PresetFile -Path $file.FullName
                                                    Write-Host ("  Also updated this preset's recorded MAC for {0}." -f $att.Label) -ForegroundColor Green
                                                }
                                            }
                                            else {
                                                Write-Host "  Could not edit mesh_config.h automatically - update it by hand." -ForegroundColor Red
                                            }
                                        }
                                        else {
                                            Write-Host "  Not fixed - the mismatch is still there." -ForegroundColor DarkGray
                                        }
                                    }
                                }
                            }
                        }
                    }

                    4 {
                        Write-Host ""
                        Write-Host ("--- {0} (raw file contents) ---" -f $file.Name) -ForegroundColor Cyan
                        Get-Content -Path $file.FullName -Raw | Write-Host
                        Write-Host "--- end of file ---" -ForegroundColor Cyan
                    }

                    5 {
                        Write-Host ""
                        $delAns = Read-Line ("Delete '{0}' permanently? [y/N] > " -f $file.Name)
                        if ($delAns -eq 'y' -or $delAns -eq 'Y') {
                            Remove-Item -Path $file.FullName -Force
                            Write-Host ("  Deleted -> {0}" -f $file.Name) -ForegroundColor Green
                            $presetFiles = @(Get-PresetFiles)   # refresh so the picker list drops it
                        }
                        else {
                            Write-Host "  Not deleted." -ForegroundColor DarkGray
                        }
                        $deciding = $false
                    }

                    6 { $deciding = $false }
                    7 { $deciding = $false; $picking = $false }
                }
            }
        }
    }
}

if ($Preset) {
    # ---------------------------------------------------------- from file ----
    if (-not (Test-Path $Preset)) { throw "Preset not found: $Preset" }
    $cfg = Get-Content -Raw -Path $Preset | ConvertFrom-Json

    $attack   = [string]$cfg.attack
    $topology = [string]$cfg.topology
    $location = [string]$cfg.location
    $repeat   = [int]$cfg.repeat
    # Older presets predate the scenario field - treat a missing one as 'none'
    # so a pre-scenario preset still loads unchanged.
    $scenario = if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario } else { 'none' }

    if ($ATTACKS    -notcontains $attack)   { throw "Preset has invalid attack '$attack'." }
    if ($TOPOLOGIES -notcontains $topology) { throw "Preset has invalid topology '$topology'." }
    if ($LOCATIONS  -notcontains $location) { throw "Preset has invalid location '$location'." }
    if ($SCENARIOS  -notcontains $scenario) { throw "Preset has invalid scenario '$scenario'." }
    if (-not $cfg.boards -or @($cfg.boards).Count -eq 0) { throw "Preset has no boards." }

    $conv = ConvertTo-Roster -Cfg $cfg
    # 0 is valid (a multi-laptop split preset for a laptop that doesn't hold the
    # root - see MULTI-LAPTOP SPLIT above); only 2+ is actually wrong.
    if ($conv.RootCount -gt 1) { throw "Preset must contain at most one root board (found $($conv.RootCount))." }
    $roster = $conv.Roster
    # A target-needing scenario with no board marked ScenarioTarget is a preset
    # that would silently do nothing on run - fail loudly instead of flashing a
    # 'burst'/'mobility'/'powercycle' run where nobody actually carries it out.
    if ((Test-ScenarioNeedsTarget $scenario) -and -not ($roster | Where-Object { $_.ScenarioTarget })) {
        throw "Preset's scenario is '$scenario' but no board is marked as the ScenarioTarget."
    }

    if (-not $bannerShown) {
        Write-Host ""
        Write-Host "=== Capture run wizard ===" -ForegroundColor Green
        $bannerShown = $true
    }
    # The picker already showed the file and its full contents - don't repeat it.
    if (-not $presetFromPicker) {
        Write-Host ("Loaded preset: {0}" -f $Preset) -ForegroundColor Green
    }

    # --- port drift -------------------------------------------------------
    # COM numbers are assigned per USB socket, so a preset's ports can point at a
    # different board - or nothing - in a later session. Enumerating is instant
    # and touches no board, so always check; only offer the fix when it bites.
    $livePorts = @(Get-PortList)
    $liveNames = @($livePorts | Select-Object -ExpandProperty Port)
    $missing   = @($roster | Where-Object { $liveNames -notcontains $_.Port })

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "These ports in the preset are not plugged in right now:" -ForegroundColor Yellow
        foreach ($m in $missing) {
            Write-Host ("  {0,-8} {1,-7} {2}" -f $m.Label, $m.Port, $m.Display) -ForegroundColor Yellow
        }
        $fixAns = Read-Line "`nPick replacement ports for them now? [Y/n] > "
        if ($fixAns -ne 'n' -and $fixAns -ne 'N') {
            $remapped = $false
            foreach ($m in $missing) {
                $newPort = Select-Port -For "$($m.Label) ($($m.Display))" -Ports $livePorts
                if ($newPort -and $newPort -ne $m.Port) {
                    $m.Port = $newPort
                    $m.Mac  = ''          # a different socket may well be a different board
                    $remapped = $true
                }
            }
            if ($remapped) {
                $ans = Read-Line "`nSave the corrected ports back into the preset? [y/N] > "
                if ($ans -eq 'y' -or $ans -eq 'Y') {
                    Save-Preset -Path $Preset -Attack $attack -Topology $topology `
                        -Location $location -RepeatNum $repeat -Roster $roster -Scenario $scenario
                    Write-Host ("  Updated -> {0}" -f (Split-Path -Leaf $Preset)) -ForegroundColor Green
                }
            }
        }
    }

    # --- repeat -----------------------------------------------------------
    # -Repeat still wins. Picking from the menu has no command line to carry it,
    # and a replay is nearly always a new attempt, so ask.
    if ($repeatOverride -gt 0) {
        $repeat = $repeatOverride
        Write-Host ("`nRepeat: {0}  (from -Repeat)" -f $repeat) -ForegroundColor DarkGray
    }
    elseif ($presetFromPicker) {
        $repeat = Read-RepeatNumber -Attack $attack -Topology $topology -DefaultRepeat $repeat
    }
}
else {
    # ------------------------------------------------------- from menus -----
    if (-not $bannerShown) {
        Write-Host ""
        Write-Host "=== Capture run wizard ===" -ForegroundColor Green
        if ($DryRun) { Write-Host "DRY RUN - nothing will be flashed." -ForegroundColor Yellow }
        $bannerShown = $true
    }

    # Step machine so a wrong answer doesn't cost re-typing every question
    # after it. Steps: 0 attack, 1 topology, 2 location, 3 scenario, 4 repeat,
    # 5 multi-laptop, 6 child count, 7 per-child roster (one child per visit,
    # driven by $i), 8 attacker/tunnel roles (skipped for baseline), 9 scenario
    # target (only for burst/mobility/powercycle), 10 root board. Each step's
    # prompt takes 'b'/'back' (wherever there is a previous step to return to)
    # and re-shows exactly that previous step - nothing past the step you land
    # on has been asked yet, so going back never has stale answers left over
    # from a later step.
    $attackIdx   = 1
    $topologyIdx = 0
    $locationIdx = 0
    $scenarioIdx = 0
    $repeat      = 1
    $multiLaptop = $false
    $childCount  = 2
    $children    = @()
    $i           = 1
    $rootLabel   = ''
    $rootPort    = $null

    # Pops the most recently committed child so the caller can re-ask it -
    # shared by every "back" landing that resumes mid-roster (step 7's back,
    # and step 8's back when there is no role step in between).
    function Undo-LastChild {
        $script:i = $script:childCount
        if ($script:children.Count -le 1) { $script:children = @() }
        else { $script:children = @($script:children[0..($script:children.Count - 2)]) }
    }

    $step = 0
    :flow while ($step -le 10) {
        switch ($step) {

            0 {
                $idx = Show-Menu -Title 'Attack type:' -Options @(
                    'baseline  (no attack - the control run)',
                    'blackhole (attacker relays, then drops victim probes)',
                    'wormhole  (A<->B tunnel; needs the physical cable)'
                ) -DefaultIndex $attackIdx -AllowBack
                if ($idx -eq -1) {
                    # No earlier LOCAL step to land on - back out of the whole
                    # manual flow instead, to the preset picker (:restart
                    # above). $step is pushed straight to 11 (past the loop's
                    # own $step -le 10 condition) so this exits the SAME way
                    # a normal completion does - the roster-building step
                    # right after the loop is what actually skips itself when
                    # $backToPresetPicker is set, not this line.
                    $backToPresetPicker = $true
                    $step = 11
                    continue flow
                }
                $attackIdx = $idx
                $attack = $ATTACKS[$attackIdx]
                $step = 1
                continue flow
            }

            1 {
                $idx = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex $topologyIdx -AllowBack
                if ($idx -eq -1) { $step = 0; continue flow }
                $topologyIdx = $idx
                $topology = $TOPOLOGIES[$topologyIdx]
                $step = 2
                continue flow
            }

            2 {
                $idx = Show-Menu -Title 'Location (where the run physically happens):' -Options $LOCATIONS -DefaultIndex $locationIdx -AllowBack
                if ($idx -eq -1) { $step = 1; continue flow }
                $locationIdx = $idx
                $location = $LOCATIONS[$locationIdx]
                $step = 3
                continue flow
            }

            3 {
                $idx = Show-Menu -Title 'Scenario (run-to-run variation the panel asked for):' -Options $SCENARIO_LABELS -DefaultIndex $scenarioIdx -AllowBack
                if ($idx -eq -1) { $step = 2; continue flow }
                $scenarioIdx = $idx
                $scenario = $SCENARIOS[$scenarioIdx]
                $step = 4
                continue flow
            }

            4 {
                if ($repeatOverride -gt 0) {
                    $repeat = $repeatOverride
                    Write-Host ("`nRepeat: {0}  (from -Repeat)" -f $repeat) -ForegroundColor DarkGray
                    $step = 5
                    continue flow
                }
                $r = Read-RepeatNumber -Attack $attack -Topology $topology -DefaultRepeat $repeat -AllowBack
                if ($r -eq -1) { $step = 3; continue flow }
                $repeat = $r
                $step = 5
                continue flow
            }

            5 {
                Write-Host ""
                Write-Host "Is this ONE experiment's boards split across MULTIPLE laptops? e.g. Laptop A" -ForegroundColor DarkGray
                Write-Host "runs the root + some children, Laptop B runs the attacker + other children." -ForegroundColor DarkGray
                Write-Host "Answer the roster questions below for the FULL experiment on every laptop," -ForegroundColor DarkGray
                Write-Host "then mark which boards are physically here when asked." -ForegroundColor DarkGray
                $multiAns = Read-Line "`nSplit across multiple laptops? [y/N] (or 'b' to go back) > "
                if (Test-BackAnswer $multiAns) { $step = 4; continue flow }
                $multiLaptop = ($multiAns -eq 'y' -or $multiAns -eq 'Y')
                $step = 6
                continue flow
            }

            6 {
                Write-Host ""
                Write-Host "CHILD boards = every physical ESP32 EXCEPT the root - you'll pick the root" -ForegroundColor DarkGray
                Write-Host "separately in the next step, so don't count it here." -ForegroundColor DarkGray
                Write-Host "  e.g. 3 ESP32s total (1 root + 2 children)  -> enter 2" -ForegroundColor DarkGray
                Write-Host "       10 ESP32s total (1 root + 9 children) -> enter 9" -ForegroundColor DarkGray
                if ($multiLaptop) {
                    Write-Host "  Multi-laptop: count the FULL experiment's children, not just this laptop's." -ForegroundColor DarkGray
                }

                $newCount = $childCount
                $tries = 0
                $backCount = $false
                while ($true) {
                    $tries++
                    if ($tries -gt $script:MaxPromptTries) { throw "No valid child count after $script:MaxPromptTries attempts - aborting." }
                    $raw = Read-Line "`nHow many CHILD boards (NOT counting the root)? > [$childCount] (or 'b' to go back) "
                    if (Test-BackAnswer $raw) { $backCount = $true; break }
                    if (-not $raw) { break }
                    $n = 0
                    if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le 9) {
                        # Wormhole needs two distinct children to be the A and B tunnel ends; with
                        # one child the Node B menu could never offer a board that isn't Node A.
                        if ($attack -eq 'wormhole' -and $n -lt 2) {
                            Write-Host "  Wormhole needs at least 2 children (Node A and Node B)." -ForegroundColor Yellow
                            continue
                        }
                        $newCount = $n
                        break
                    }
                    Write-Host "  Enter a number from 1 to 9." -ForegroundColor Yellow
                }
                if ($backCount) { $step = 5; continue flow }

                if ($newCount -ne $childCount) {
                    # A different count invalidates whatever was already entered -
                    # the labels/ports below no longer line up with anything.
                    $children = @()
                }
                $childCount = $newCount

                $ports = Get-PortList
                if (($childCount + 1) -gt $ports.Count) {
                    Write-Host ""
                    Write-Host ("{0} boards need ports but only {1} are plugged in right now." -f ($childCount + 1), $ports.Count) -ForegroundColor Yellow
                    Write-Host "When you reach a board that isn't plugged in yet, pick 'a' at the port prompt -" -ForegroundColor Yellow
                    Write-Host "swap it onto a free USB port and the wizard will find it for you." -ForegroundColor Yellow
                }

                $i = 1
                $step = 7
                continue flow
            }

            7 {
                if ($i -gt $childCount) {
                    $step = if ($attack -ne 'none') { 8 }
                            elseif (Test-ScenarioNeedsTarget $scenario) { 9 }
                            else { 10 }
                    continue flow
                }

                $suggested = "node$($i + 1)"
                $label = ''
                $backChild = $false
                $ltries = 0
                while ($true) {
                    $ltries++
                    if ($ltries -gt $script:MaxPromptTries) { throw "No valid label for child $i after $script:MaxPromptTries attempts - aborting." }
                    $raw = Read-Line "`nLabel for child $i > [$suggested] (or 'b' to go back) "
                    if (Test-BackAnswer $raw) { $backChild = $true; break }
                    $label = if (-not $raw) { $suggested } else { $raw.Trim() }
                    # The label is what names the CSV. Two boards sharing one silently overwrite
                    # each other's export - and in shared-port mode the label is the ONLY thing
                    # telling the boards apart.
                    if (@($children | Select-Object -ExpandProperty Label) -contains $label) {
                        Write-Host "  '$label' is already taken - each board needs a unique label (it names the CSV)." -ForegroundColor Yellow
                        continue
                    }
                    break
                }

                if ($backChild) {
                    if ($i -eq 1) { $step = 6; continue flow }
                    # Redo the PREVIOUS child (i-1), not "the last completed
                    # child" - unlike Undo-LastChild's callers below, $i here
                    # is still the in-progress index, not childCount+1.
                    $i--
                    if ($children.Count -le 1) { $children = @() }
                    else { $children = @($children[0..($children.Count - 2)]) }
                    continue flow
                }

                $port = Select-PortOrRemote -For "$label (child $i of $childCount)" -Ports $ports -MultiLaptop $multiLaptop

                $children += [pscustomobject]@{
                    Label          = $label
                    Port           = $port
                    Role           = 'child'
                    Kind           = 'plain'
                    Display        = 'plain child'
                    ScenarioTarget = $false
                }
                $i++
                continue flow
            }

            8 {
                # Assign attack roles. Asking "which one" enforces the count rule by construction.
                if ($attack -eq 'blackhole') {
                    $labels = @($children | ForEach-Object {
                        $tag = ''
                        if ($_.Port -and $script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [$($script:IdentifiedPorts[$_.Port])]" }
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)$tag"
                    })
                    $idx = Show-Menu -Title 'Which child is the BLACKHOLE ATTACKER? (exactly one)' -Options $labels -AllowBack
                    if ($idx -eq -1) { Undo-LastChild; $step = 7; continue flow }
                    for ($ci = 0; $ci -lt $children.Count; $ci++) {
                        if ($ci -eq $idx) {
                            $children[$ci].Kind = 'attacker'
                            $children[$ci].Display = 'blackhole ATTACKER'
                        }
                        else {
                            $children[$ci].Kind = 'victim'
                            $children[$ci].Display = 'blackhole victim'
                        }
                    }
                }
                elseif ($attack -eq 'wormhole') {
                    $labels = @($children | ForEach-Object {
                        $tag = ''
                        if ($_.Port -and $script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [$($script:IdentifiedPorts[$_.Port])]" }
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)$tag"
                    })
                    $idxA = Show-Menu -Title 'Which child is WORMHOLE Node A (exit / re-injects to root)?' -Options $labels -AllowBack
                    if ($idxA -eq -1) { Undo-LastChild; $step = 7; continue flow }
                    $idxB = -1
                    while ($true) {
                        $idxB = Show-Menu -Title 'Which child is WORMHOLE Node B (entry / captures + tunnels)?' -Options $labels
                        if ($idxB -ne $idxA) { break }
                        Write-Host "  Node B must be a different board from Node A." -ForegroundColor Yellow
                    }
                    for ($ci = 0; $ci -lt $children.Count; $ci++) {
                        if ($ci -eq $idxA) {
                            $children[$ci].Kind = 'A'; $children[$ci].Display = 'wormhole Node A (exit)'
                        }
                        elseif ($ci -eq $idxB) {
                            $children[$ci].Kind = 'B'; $children[$ci].Display = 'wormhole Node B (entry)'
                        }
                        else {
                            $children[$ci].Kind = 'control'; $children[$ci].Display = 'control (plain firmware)'
                        }
                    }
                }
                $step = if (Test-ScenarioNeedsTarget $scenario) { 9 } else { 10 }
                continue flow
            }

            9 {
                # Exactly one child is the scenario's subject: the burst sender,
                # the node moved, or the node power-cycled. Burst additionally
                # needs a board that will actually build victim_main.c - an
                # attacker relay or a wormhole A/B board can't carry it.
                $eligible = if ($scenario -eq 'burst') {
                    @($children | Where-Object { Test-BurstEligible $_ })
                } else {
                    @($children)
                }
                if ($eligible.Count -eq 0) {
                    Write-Host "`n  No child here can carry the burst (the attacker/wormhole A/B boards can't) -" -ForegroundColor Yellow
                    Write-Host "  go back and add a plain child, or pick a different scenario." -ForegroundColor Yellow
                    if ($attack -ne 'none') { $step = 8 } else { Undo-LastChild; $step = 7 }
                    continue flow
                }
                $labels = @($eligible | ForEach-Object {
                    $tag = ''
                    if ($_.Port -and $script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [$($script:IdentifiedPorts[$_.Port])]" }
                    $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                    "$($_.Label)  ($portText)$tag  -  $($_.Display)"
                })
                $idx = Show-Menu -Title "Which child is the $scenario TARGET? (exactly one)" -Options $labels -AllowBack
                if ($idx -eq -1) {
                    if ($attack -ne 'none') { $step = 8 } else { Undo-LastChild; $step = 7 }
                    continue flow
                }
                foreach ($c in $children) {
                    # Strip a stale marker before re-marking, so going back and
                    # forth through this step never stacks " + TARGET" suffixes
                    # on a Display string that already has one.
                    $c.ScenarioTarget = $false
                    $c.Display = $c.Display -replace ' \+ .* TARGET$', ''
                }
                $eligible[$idx].ScenarioTarget = $true
                $eligible[$idx].Display += " + $($scenario.ToUpper()) TARGET"
                $step = 10
                continue flow
            }

            10 {
                $backRoot = $false
                $ltries = 0
                while ($true) {
                    $ltries++
                    if ($ltries -gt $script:MaxPromptTries) { throw "No valid root label after $script:MaxPromptTries attempts - aborting." }
                    $raw = Read-Line "`nLabel for the ROOT board > [node1] (or 'b' to go back) "
                    if (Test-BackAnswer $raw) { $backRoot = $true; break }
                    $rootLabel = if (-not $raw) { 'node1' } else { $raw.Trim() }
                    if (@($children | Select-Object -ExpandProperty Label) -contains $rootLabel) {
                        Write-Host "  '$rootLabel' is already taken by a child - the root needs its own label." -ForegroundColor Yellow
                        continue
                    }
                    break
                }

                if ($backRoot) {
                    if (Test-ScenarioNeedsTarget $scenario) { $step = 9 }
                    elseif ($attack -ne 'none') { $step = 8 }
                    else { Undo-LastChild; $step = 7 }
                    continue flow
                }

                $rootPort = Select-PortOrRemote -For "$rootLabel (ROOT)" -Ports $ports -MultiLaptop $multiLaptop
                $step = 11
                continue flow
            }
        }
    }

    # Children first, root LAST - the root drives the phase broadcasts, and its
    # -Analyze must run after every child's CSV is already on disk. Skipped
    # when step 0 sent us back to the preset picker - $children/$rootLabel/
    # $rootPort never got filled in, so there is nothing real to build yet.
    if (-not $backToPresetPicker) {
        $roster = @($children) + @([pscustomobject]@{
            Label          = $rootLabel
            Port           = $rootPort
            Role           = 'root'
            Kind           = 'root'
            Display        = 'ROOT (announces the phases)'
            ScenarioTarget = $false
        })
    }
}

if ($backToPresetPicker) { $backToPresetPicker = $false; continue restart }
break restart
}

$fullRoster = $roster
$runRoster  = @($fullRoster | Where-Object { $_.Port })
$children   = @($runRoster | Where-Object { $_.Role -ne 'root' })

# ------------------------------------------------- multi-laptop hand-off ----
$remoteBoards = @($fullRoster | Where-Object { -not $_.Port })
if ($remoteBoards.Count -gt 0) {
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "  Boards on ANOTHER laptop (not flashed/run/saved from here):" -ForegroundColor Yellow
    foreach ($rb in $remoteBoards) {
        Write-Host ("    {0,-8} {1}" -f $rb.Label, $rb.Display) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host ("  Give that laptop's operator the SAME answers: attack={0} topology={1} location={2} repeat={3}" -f $attack, $topology, $location, $repeat) -ForegroundColor DarkGray
    Write-Host "  and the SAME full roster (labels/roles above) - they mark only THEIR boards" -ForegroundColor DarkGray
    Write-Host "  as local when run_wizard.ps1 asks, and their boards mark yours as remote." -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
}
if ($runRoster.Count -eq 0) {
    Write-Host ""
    Write-Host "No boards on THIS laptop - nothing to flash/run/save here." -ForegroundColor Yellow
    return
}

# ------------------------------------------------- port-mode detection ----

$distinct = @($runRoster | Select-Object -ExpandProperty Port -Unique)
$swapMode = ($distinct.Count -lt $runRoster.Count) -or ($distinct.Count -gt (Get-PortList).Count)

if ($swapMode) {
    Write-Host ""
    Write-Host "More boards than free USB ports: some will need to be swapped in during the" -ForegroundColor Yellow
    Write-Host "run. Right before such a board's turn, the wizard checks whether its port is" -ForegroundColor Yellow
    Write-Host "still live and, if not, pauses and auto-detects the new one." -ForegroundColor Yellow
}

$cleanBuild = $false   # set below only if the user opts into it at the prompt

# Remembers the attacker MAC the pre-flight gate reads, so saving a preset later
# does not reset that board a second time just to learn what it already knows.
$macsRead = @{}

# ------------------------------------------------------- pre-flight gate ----

if ($attack -eq 'blackhole') {
    $att = $children | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
    $victimCount = @($children | Where-Object { $_.Kind -eq 'victim' }).Count
    # MULTI-LAPTOP SPLIT: the attacker may not be local at all - $att comes from
    # $children (already filtered to THIS laptop's boards), so check the FULL
    # roster to tell "no attacker anywhere" apart from "attacker is elsewhere".
    $remoteAttacker = $fullRoster | Where-Object { $_.Kind -eq 'attacker' -and -not $_.Port } | Select-Object -First 1

    if (-not $att -and $remoteAttacker) {
        # The attacker lives on a teammate's laptop. Victim firmware built HERE
        # still needs BLACKHOLE_ATTACKER_MAC to match THAT board's real MAC, and
        # this laptop cannot read it over serial - so ask for it instead of
        # silently trusting whatever mesh_config.h already happens to hold.
        if ($victimCount -eq 0) {
            Write-Host ""
            Write-Host "WARNING: this roster has an attacker but NO local victims." -ForegroundColor Red
            Write-Host "Nothing on THIS laptop addresses probes to it, so it contributes no attack" -ForegroundColor Red
            Write-Host "signature from here (other laptops' victims may still see it)." -ForegroundColor Red
        }

        $wantMac = Get-ConfiguredAttackerMac
        Write-Host ""
        Write-Host ("The blackhole ATTACKER ({0}) is on another laptop, not this one." -f $remoteAttacker.Label) -ForegroundColor Yellow
        if ($wantMac) { Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $wantMac) -ForegroundColor Cyan }

        if ($SkipMacCheck -or $DryRun) {
            Write-Host ("Not asking for {0}'s MAC (" -f $remoteAttacker.Label) + $(if ($DryRun) { 'dry run' } else { '-SkipMacCheck' }) + ")." -ForegroundColor DarkGray
        }
        else {
            Write-Host "Get it from that laptop first (run_wizard.ps1, or menu.ps1's 'Identify a" -ForegroundColor DarkGray
            Write-Host "board', run on the ATTACKER'S laptop), then type the printed MAC back here." -ForegroundColor DarkGray
            $typedMac = $null
            $tries = 0
            while ($true) {
                $tries++
                if ($tries -gt $script:MaxPromptTries) { Write-Host "  No valid MAC entered - continuing unverified." -ForegroundColor Yellow; break }
                $raw = Read-Line ("`n{0}'s MAC (aa:bb:cc:dd:ee:ff), blank to skip verification > " -f $remoteAttacker.Label)
                if (-not $raw) { break }
                if ($raw.Trim() -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { $typedMac = $raw.Trim().ToLower(); break }
                Write-Host "  Not a MAC (expected aa:bb:cc:dd:ee:ff)." -ForegroundColor Yellow
            }

            if (-not $typedMac) {
                Write-Host "  Skipped - verify mesh_config.h matches the other laptop's attacker by hand." -ForegroundColor Yellow
            }
            elseif ($typedMac -eq $wantMac) {
                Write-Host ("MATCH: mesh_config.h already targets {0}." -f $typedMac) -ForegroundColor Green
            }
            else {
                Write-Host ""
                Write-Host "MISMATCH - victims built on THIS laptop would carry NO attack signature." -ForegroundColor Red
                Write-Host ("  mesh_config.h expects : {0}" -f $wantMac) -ForegroundColor Red
                Write-Host ("  you entered           : {0}" -f $typedMac) -ForegroundColor Red

                $fixIdx = Show-Menu -Title 'What do you want to do?' -Options @(
                    "Update mesh_config.h to $typedMac ($($remoteAttacker.Label)) - automatic",
                    'Continue anyway without fixing (victims built here show no attack signature)',
                    "Abort - confirm the MAC with the attacker's laptop first"
                ) -DefaultIndex 0

                switch ($fixIdx) {
                    0 {
                        $ok = Set-ConfiguredAttackerMac -Mac $typedMac -PortLabel "$($remoteAttacker.Label) (other laptop)"
                        if ($ok) {
                            Write-Host "  mesh_config.h updated - the next flash will pick it up (no wipe needed)." -ForegroundColor Green
                        }
                        else {
                            Write-Host "  Could not edit mesh_config.h automatically - update it by hand, then re-run." -ForegroundColor Red
                            return
                        }
                    }
                    1 {
                        Write-Host "  Continuing without fixing - victims built here will carry no attack signature." -ForegroundColor Yellow
                    }
                    2 {
                        Write-Host "Aborted - nothing flashed." -ForegroundColor Yellow
                        return
                    }
                }
            }
        }
    }
    elseif (-not $att) {
        # Neither local nor recorded elsewhere in the full roster - nothing
        # blackhole-specific on THIS laptop to verify (root-only laptop, etc).
        if ($victimCount -gt 0) {
            Write-Host ""
            Write-Host "WARNING: local victim(s) present but no attacker anywhere in the roster." -ForegroundColor Red
            Write-Host "Nothing will address probes to an attacker, so there is no blackhole to" -ForegroundColor Red
            Write-Host "observe and the capture carries no attack signature." -ForegroundColor Red
        }
    }
    else {
        if ($victimCount -eq 0) {
            Write-Host ""
            Write-Host "WARNING: this roster has an attacker but NO victims." -ForegroundColor Red
            Write-Host "Nothing will address probes to the attacker, so there is no blackhole to" -ForegroundColor Red
            Write-Host "observe and the capture carries no attack signature." -ForegroundColor Red
        }

        $wantMac = Get-ConfiguredAttackerMac
        Write-Host ""
        if (-not $wantMac) {
            Write-Host "Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h - verify it by hand." -ForegroundColor Yellow
        }
        else {
            Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $wantMac) -ForegroundColor Cyan

            if ($SkipMacCheck -or $DryRun) {
                Write-Host ("Not reading $($att.Port) to confirm (" + $(if ($DryRun) { 'dry run' } else { '-SkipMacCheck' }) + ").") -ForegroundColor DarkGray
                Write-Host ("It must be the MAC of $($att.Label) on $($att.Port).") -ForegroundColor DarkGray
            }
            else {
                # In a shared-port roster the attacker may not be the board currently
                # plugged in (it could be #7 of 10) - catch that BEFORE attempting the
                # read instead of just failing and falling back to "continue unverified?".
                $liveNow = @(Get-PortList | Select-Object -ExpandProperty Port)
                if ($liveNow -notcontains $att.Port) {
                    Write-Host ""
                    Write-Host ("{0} (the attacker) is not currently on {1}." -f $att.Label, $att.Port) -ForegroundColor Yellow
                    $newPort = Wait-ForNewPort -For "$($att.Label) (attacker - needed now to verify its MAC)"
                    if (-not $newPort) { $newPort = Read-Line "  Port (e.g. COM20) > " }
                    if ($newPort) { $att.Port = $newPort.Trim().ToUpper() }
                }

                # This is the single most expensive mistake in the whole workflow: a wrong
                # MAC means every victim unicasts probes to a board that isn't in the mesh,
                # so the run completes normally and carries no attack signature at all.
                Write-Host ("Reading $($att.Label) on $($att.Port) to confirm (briefly resets the board) ...") -ForegroundColor DarkGray
                $gotMac = Get-BoardMac -TargetPort $att.Port
                if ($gotMac) { $macsRead[$att.Port] = $gotMac }

                if (-not $gotMac) {
                    Write-Host "Could not read that board's MAC (port busy, no board, or esptool missing)." -ForegroundColor Yellow
                    $ans = Read-Line "Continue without verifying? [y/N] > "
                    if ($ans -ne 'y' -and $ans -ne 'Y') { Write-Host "Aborted." -ForegroundColor Yellow; return }
                }
                elseif ($gotMac -eq $wantMac) {
                    Write-Host ("MATCH: $($att.Label) on $($att.Port) is $gotMac") -ForegroundColor Green
                    if ($remoteBoards.Count -gt 0) {
                        Write-Host ("  Multi-laptop split: give the other laptop(s) this MAC ({0}) when their" -f $gotMac) -ForegroundColor DarkGray
                        Write-Host "  wizard asks for the remote attacker's MAC." -ForegroundColor DarkGray
                    }
                }
                else {
                    Write-Host ""
                    Write-Host "MISMATCH - this run would produce NO attack signature." -ForegroundColor Red
                    Write-Host ("  mesh_config.h expects : {0}" -f $wantMac) -ForegroundColor Red
                    Write-Host ("  {0} on {1} actually is : {2}" -f $att.Label, $att.Port, $gotMac) -ForegroundColor Red

                    $fixIdx = Show-Menu -Title 'What do you want to do?' -Options @(
                        "Update mesh_config.h to $gotMac ($($att.Label)) and clean-rebuild automatically",
                        'Continue anyway without fixing (the capture will show no attack signature)',
                        "Abort - I'll plug in the board that already owns $wantMac, or fix this myself"
                    ) -DefaultIndex 0

                    switch ($fixIdx) {
                        0 {
                            $ok = Set-ConfiguredAttackerMac -Mac $gotMac -PortLabel "$($att.Port) ($($att.Label))"
                            if ($ok) {
                                # No forced wipe: BLACKHOLE_ATTACKER_MAC is a plain #define,
                                # not a CMake -D flag, so ninja's normal header-dependency
                                # tracking picks this up on the next idf.py build/flash and
                                # recompiles only the handful of files that #include
                                # mesh_config.h (same reasoning as I-009 in
                                # esp32-issues-Part2.md: don't fullclean unless truly needed).
                                Write-Host "  mesh_config.h updated - the next flash will pick it up (no wipe needed)." -ForegroundColor Green
                            }
                            else {
                                Write-Host "  Could not edit mesh_config.h automatically - update it by hand, then re-run." -ForegroundColor Red
                                return
                            }
                        }
                        1 {
                            Write-Host "  Continuing without fixing - this run will carry no attack signature." -ForegroundColor Yellow
                        }
                        2 {
                            Write-Host "Aborted - nothing flashed." -ForegroundColor Yellow
                            return
                        }
                    }
                }
            }
        }
    }
}
elseif ($attack -eq 'wormhole') {
    $na = $children | Where-Object { $_.Kind -eq 'A' } | Select-Object -First 1
    $nb = $children | Where-Object { $_.Kind -eq 'B' } | Select-Object -First 1
    Write-Host ""
    if ($na -and $nb) {
        Write-Host "Before flashing, confirm the A<->B cable is wired between" -ForegroundColor Yellow
        Write-Host "  $($na.Label) and $($nb.Label), and that uart_link_test passed." -ForegroundColor Yellow
    }
    elseif ($na -or $nb) {
        # Roster has only one tunnel end - its A<->B cable partner isn't in this run.
        $end = if ($na) { $na } else { $nb }
        Write-Host ("This roster flashes wormhole Node {0} ({1}) without its A<->B cable partner." -f $end.Kind, $end.Label) -ForegroundColor Yellow
        Write-Host "Both ends must be wired + uart_link_test'd together before a real capture." -ForegroundColor Yellow
    }
    # else: this roster flashes neither tunnel end (controls/root only) - no cable note.
}

$cleanAns = Read-Line "`nClean-rebuild build_* first? (usually NOT needed - idf.py picks up header/define changes on its own; only useful after a suspicious/interrupted build) [y/N] > "
$cleanBuild = ($cleanAns -eq 'y' -or $cleanAns -eq 'Y')

# --------------------------------------------------------- confirmation ----

$plan = @()
foreach ($b in $runRoster) {
    $plan += [pscustomobject]@{
        Board  = $b
        Params = (New-RunParams -Board $b -Attack $attack -Topology $topology -Location $location -RepeatNum $repeat -Scenario $scenario)
    }
}

$dirs        = Get-RunDirs -Attack $attack -Topology $topology -Location $location -Scenario $scenario
$attackDir   = $dirs.AttackDir
$topoDir     = $dirs.TopoDir
$exportDir   = $dirs.Export
$analysisDir = $dirs.Analysis

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Green
Write-Host ("  Attack   : {0}" -f $attack)
Write-Host ("  Topology : {0}" -f $topology)
Write-Host ("  Scenario : {0}" -f $scenario)
Write-Host ("  Location : {0}" -f $location)
Write-Host ("  Repeat   : {0}" -f $repeat)
Write-Host ("  Mode     : {0}" -f $(if ($swapMode) { 'shared port - swap boards between steps' } else { 'separate ports - no swapping' }))
if ($scenario -in @('mobility', 'powercycle')) {
    $tgt = $plan | Where-Object { $_.Board.ScenarioTarget } | Select-Object -First 1
    $tgtLbl = if ($tgt) { $tgt.Board.Label } else { '(none picked!)' }
    Write-Host "  NOTE     : this is a $scenario run - YOU must $scenario board $tgtLbl during it." -ForegroundColor Magenta
    Write-Host "             run.ps1 prints the full checklist again right before the root boots." -ForegroundColor Magenta
}
Write-Host ""
Write-Host "  Order (root is always last):"
$step = 0
foreach ($p in $plan) {
    $step++
    $tail = '-Export'
    if ($p.Board.Role -eq 'root') { $tail = '-Analyze' }
    if ($p.Board.ScenarioTarget) { $tail = "$tail  << $scenario TARGET" }
    Write-Host ("   [{0}] {1,-8} {2,-27} {3,-7} {4}" -f $step, $p.Board.Label, $p.Board.Display, $p.Board.Port, $tail)
}
Write-Host ""
Write-Host "  Exports  -> $exportDir"
Write-Host "  Analysis -> $analysisDir"
Write-Host "------------------------------------------------------------" -ForegroundColor Green

# --------------------------------------------------------- time estimate ----
# So you can set a phone alarm and walk away instead of watching the terminal
# for what's typically 30-45 min. Only the root's phase timing is genuinely
# known (it's a firmware constant, not a guess); build/flash time depends on
# your machine and is shown as a labelled approximation, never blended into
# the firm number so one bad guess can't quietly poison the whole estimate.

$durations  = Get-PhaseDurations
$childCount = ($plan | Where-Object { $_.Board.Role -ne 'root' }).Count

# Warm vs. cold per board: cold if -Wipe/-Flash will hit a build_* dir that
# doesn't exist yet, or a clean-rebuild was requested (which deletes it).
# These per-board minute budgets are a rough dev-loop observation (incremental
# build+flash+monitor-start vs. a from-scratch ~1000-object compile), not a
# measurement - labelled as such below.
$warmBuildMin = 2
$coldBuildMin = 4
$coldCount = 0
foreach ($p in $plan) {
    $bd = Get-BoardBuildDir -Params $p.Params
    if ($cleanBuild -or -not (Test-Path $bd)) { $coldCount++ }
}
$warmCount   = $plan.Count - $coldCount
$buildSec    = (($warmCount * $warmBuildMin) + ($coldCount * $coldBuildMin)) * 60
$attentionSec = $childCount * 60   # ~1 min/child: watch for the banner, press Ctrl+]
$rootSec     = [int]$durations.Total
$totalSec    = $buildSec + $attentionSec + $rootSec
$finishAt    = (Get-Date).AddSeconds($totalSec)

Write-Host ""
Write-Host "  Estimated time" -ForegroundColor Cyan
$phaseNote = "$($durations.Stabilise)s stabilise + $($durations.Baseline)s baseline + $($durations.Attack)s attack + $($durations.Cooldown)s cooldown"
if ($rootSec -gt 0) {
    if ($durations.Ok) {
        Write-Host ("    Root experiment   {0,-8} ({1})" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor DarkGray
    } else {
        Write-Host ("    Root experiment   ~{0,-7} ({1}) -- mesh_config.h unreadable, this is a HARDCODED FALLBACK, not measured" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor Yellow
    }
}
Write-Host ("    Build + flash     ~{0}          ({1} warm, {2} cold @ ~{3}min/~{4}min per board - varies with your machine)" -f (Format-Duration $buildSec), $warmCount, $coldCount, $warmBuildMin, $coldBuildMin) -ForegroundColor DarkGray
if ($childCount -gt 0) {
    Write-Host ("    Your attention    ~{0}          (press Ctrl+] at each child's banner, then it's hands-off)" -f (Format-Duration $attentionSec)) -ForegroundColor DarkGray
}
Write-Host "    ------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ("    Total            ~{0}, finishing around {1}" -f (Format-Duration $totalSec), $finishAt.ToString('HH:mm')) -ForegroundColor Cyan
if ($rootSec -gt 0) {
    Write-Host ("    Of that, {0} is a single unattended block during the root's run - that's the part worth an alarm." -f (Format-Duration $rootSec)) -ForegroundColor DarkGray
}

# ----------------------------------------------------------- save preset ----

if (-not $Preset) {
    $saveAns = Read-Line "`nSave this roster as a preset for the next repeat? [y/N] > "
    if ($saveAns -eq 'y' -or $saveAns -eq 'Y') {
        $presetDir = Join-Path $base 'presets'
        if (-not (Test-Path $presetDir)) { New-Item -ItemType Directory -Force -Path $presetDir | Out-Null }
        $suggested = "$topoDir-$attackDir-$scenario-$($location.ToLower()).json"
        $name = Read-Line "  Filename > [$suggested] "
        if (-not $name) { $name = $suggested }
        if ($name -notmatch '\.json$') { $name = "$name.json" }
        $presetPath = Join-Path $presetDir $name

        # A COM port does not identify a board - Windows assigns it per USB socket -
        # so without MACs a replayed preset cannot be checked against the hardware.
        # Reading resets each board, which costs nothing here: flashing is next.
        # Except under -DryRun, which by this script's convention touches no board
        # (same reason the pre-flight gate skips its read).
        if ($DryRun) {
            Write-Host "  Dry run - not reading the boards, so MACs will be left blank." -ForegroundColor DarkGray
        }
        else {
            $macAns = Read-Line "  Record each board's MAC into the preset? (reads each board, ~2s each) [Y/n] > "
            if ($macAns -ne 'n' -and $macAns -ne 'N') {
                Write-Host ""
                # $runRoster only - a preset saves THIS laptop's own boards; a
                # multi-laptop split's remote boards have no port to read anyway.
                Add-BoardMacs -Roster $runRoster -Known $macsRead | Out-Null
            }
        }

        Save-Preset -Path $presetPath -Attack $attack -Topology $topology `
            -Location $location -RepeatNum $repeat -Roster $runRoster -Scenario $scenario
        Write-Host "  Saved -> $presetPath" -ForegroundColor Green
        Write-Host "  Next time just run .\run_wizard.ps1 and pick it from the list." -ForegroundColor DarkGray
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - exact commands that would run:" -ForegroundColor Yellow
    if ($cleanBuild) {
        Write-Host "  (would first remove build_* under $buildRoot)" -ForegroundColor DarkGray
    }
    foreach ($p in $plan) {
        Write-Host ("  .\run.ps1 " + (Format-RunParams $p.Params)) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Nothing was flashed." -ForegroundColor Yellow
    return
}

$go = Read-Line "`nProceed? [y/N] > "
if ($go -ne 'y' -and $go -ne 'Y') {
    Write-Host "Aborted - nothing flashed." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------- execute ----

if ($cleanBuild) {
    Write-Host ""
    Write-Host "Removing build_* under $buildRoot ..." -ForegroundColor Yellow
    # BLACKHOLE_ATTACKER_MAC lives in the shared mesh_common header, which BOTH
    # projects compile against - so both build trees have to go, not just child_node.
    Remove-Item -Recurse -Force (Join-Path $buildRoot 'child_node\build_*') -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $buildRoot 'root_node\build_*')  -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Exit each monitor with Ctrl+]  -  NOT Ctrl+C (Ctrl+C kills this wizard too)." -ForegroundColor Yellow
if ($children.Count -gt 0) {
    Write-Host ""
    Write-Host "A CHILD flashed before the root has nothing to join yet, so it will spam" -ForegroundColor Yellow
    Write-Host "'[FIND] ... fail to find a network' for up to 60s - that is NORMAL, not stuck." -ForegroundColor Yellow
    Write-Host "It boots fine either way. Do not wait it out - press Ctrl+] as soon as you see" -ForegroundColor Yellow
    Write-Host "'=== VICTIM NODE STARTING ===' (or the matching attack banner) and move on." -ForegroundColor Yellow
}

$total = $plan.Count
$step = 0
$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$boardElapsed = [ordered]@{}   # Label -> seconds, for the "it took N min" summary
foreach ($p in $plan) {
    $step++
    $b = $p.Board

    Write-Host ""
    Write-Host ("=== [{0}/{1}] {2} - {3} on {4} ===" -f $step, $total, $b.Label, $b.Display, $b.Port) -ForegroundColor Cyan

    if ($b.Role -eq 'root') {
        # Recomputed HERE, not reused from the up-front estimate: any board
        # ahead of this one that ran slow (a cold build, a slow Ctrl+]) has
        # already eaten into the schedule, so "now + 11 min" is more honest
        # than "the estimate from before we started" by the time it matters.
        $rootEta = (Get-Date).AddSeconds([int]$durations.Total)
        Write-Host ""
        Write-Host ("  This is the root: the experiment runs {0} once the mesh forms." -f (Format-Duration ([int]$durations.Total))) -ForegroundColor Cyan
        Write-Host ("  Expected TERMINATE around {0} - set an alarm, nothing needs you until then." -f $rootEta.ToString('HH:mm')) -ForegroundColor Cyan
        Write-Host "  Then come back and press Ctrl+] to auto-export." -ForegroundColor Cyan
    }

    $boardStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Checked per board, not just when $swapMode was true at plan time: COM numbers
    # can be assigned per USB socket OR per device depending on the driver, so a
    # board's port from the selection phase may no longer be live by its turn -
    # either way, this catches it and re-detects rather than handing run.ps1 a
    # port nothing is listening on.
    $liveNow = @(Get-PortList | Select-Object -ExpandProperty Port)
    if ($liveNow -notcontains $b.Port) {
        Write-Host ("{0} is not currently on {1}." -f $b.Label, $b.Port) -ForegroundColor Yellow
        $newPort = Wait-ForNewPort -For "$($b.Label) ($($b.Display))"
        if (-not $newPort) { $newPort = Read-Line "  Port (e.g. COM20) > " }
        if ($newPort) {
            $b.Port = $newPort.Trim().ToUpper()
            $p.Params.Port = $b.Port
        }
    }

    Write-Host ("  .\run.ps1 " + (Format-RunParams $p.Params)) -ForegroundColor DarkGray

    $global:LASTEXITCODE = 0
    # Hashtable splat - binds by NAME. Must go through a variable: @(...) is an
    # array subexpression, not a splat, and would pass everything as one -Port value.
    $runParams = $p.Params
    & (Join-Path $base 'run.ps1') @runParams

    $boardStopwatch.Stop()
    $boardElapsed[$b.Label] = [int]$boardStopwatch.Elapsed.TotalSeconds

    # run.ps1 does not check $LASTEXITCODE after its own idf.py flash/monitor call,
    # so a dead flash would otherwise fall through into export and let the NEXT
    # board run against a blank one. Children abort the chain; on the root we only
    # warn, because by then every CSV is already exported and a nonzero code there
    # usually means the optional EDA stage failed, not the capture.
    if ($LASTEXITCODE -ne 0) {
        if ($b.Role -eq 'root') {
            Write-Host ""
            Write-Host ("WARNING: root step returned exit {0}." -f $LASTEXITCODE) -ForegroundColor Yellow
            Write-Host "Exports should still be on disk - check the folders below before re-running." -ForegroundColor Yellow
        }
        else {
            Write-Host ""
            Write-Host ("FAILED: {0} ({1}) returned exit {2}." -f $b.Label, $b.Display, $LASTEXITCODE) -ForegroundColor Red
            Write-Host ("Aborting - the remaining {0} board(s) were NOT run." -f ($total - $step)) -ForegroundColor Red
            exit 1
        }
    }
}

# ---------------------------------------------------------------- summary ----

$runStopwatch.Stop()

Write-Host ""
Write-Host ("All $total board(s) done in {0}." -f (Format-Duration ([int]$runStopwatch.Elapsed.TotalSeconds))) -ForegroundColor Green
foreach ($p in $plan) {
    $label = $p.Board.Label
    if ($boardElapsed.Contains($label)) {
        $tag = if ($p.Board.Role -eq 'root') { '   (root)' } else { '' }
        Write-Host ("    {0,-8} {1}{2}" -f $label, (Format-Duration $boardElapsed[$label]), $tag) -ForegroundColor DarkGray
    }
}
Write-Host "  Exports  -> $exportDir" -ForegroundColor Green

Write-Host "  Analysis -> $analysisDir" -ForegroundColor Green
Write-Host "             (windowed_dataset.csv, feature_table.csv, eda_output\)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Check the attack signature: in the root's *_arrivals.csv, each victim's" -ForegroundColor DarkGray
Write-Host "src_mac should go silent during gt_label=1 rows and resume at cooldown." -ForegroundColor DarkGray
if ($attack -ne 'none') {
    Write-Host ""
    Write-Host "Graded run? Record it:  python tools\run_matrix.py --autorecord" -ForegroundColor DarkGray
}
