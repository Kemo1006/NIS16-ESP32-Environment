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
  the wizard lists the saved presets for you to pick from, shows what the chosen
  one contains - boards, ports, roles, attacker, MACs - and asks you to confirm
  before anything is flashed.

  Presets are filed one folder per member: presets\<member>\<cell>.json, e.g.
  presets\Bas\linear-blackhole-none-g402.json. The filename already spells the
  experiment cell (topology-attack-scenario-location), so the folder is what
  carries the one thing it cannot - WHOSE boards the roster describes. That is
  what lets your preset and an absent member's preset for the same cell both
  keep the plain cell name instead of one being hand-renamed. The picker lists
  yours first, then the other members, each under its own heading, and new
  presets are filed automatically by matching their MACs against
  member_boards.json. Loose .json files directly under presets\ still load, and
  show as UNFILED until you file them from the picker.

.PARAMETER Repeat
  Override the preset's repeat number - the one thing that changes between r1/r2/r3.
  Supplied on the command line it wins; picking a preset from the menu prompts for it.

.PARAMETER SkipMacCheck
  Skip reading the attacker board's MAC and comparing it to mesh_config.h.

.EXAMPLE
  .\run_wizard.ps1 -DryRun
  .\run_wizard.ps1
  .\run_wizard.ps1 -Preset presets\Bas\linear-blackhole-none-g402.json -Repeat 2
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

# Bright role colors for a black console background -- root/child/attacker at a
# glance in board summaries and roster listings. Named ConsoleColor values (Cyan/
# Yellow/etc used elsewhere in this file) can't express these exact hex values, so
# these are raw ANSI 24-bit escapes instead; Windows 10/11's default console and
# Windows Terminal both render them. $script:AnsiReset MUST follow every use or the
# color bleeds into whatever Write-Host prints next.
$script:RoleAnsi = @{
    root     = "$([char]27)[38;2;254;189;23m"   # #FEBD17
    child    = "$([char]27)[38;2;27;192;186m"   # #1BC0BA
    attacker = "$([char]27)[38;2;253;184;217m"  # #FDB8D9
}
$script:AnsiReset = "$([char]27)[0m"

function Colorize-Role {
    # Wraps $Text in the role's ANSI color + reset. $Role should be 'root',
    # 'attacker', or anything else (treated as 'child') -- callers pass a board's
    # Role/Kind field, not a raw hex value.
    param([string]$Text, [string]$Role)
    $key = if ($Role -eq 'root') { 'root' } elseif ($Role -eq 'attacker') { 'attacker' } else { 'child' }
    return "$($script:RoleAnsi[$key])$Text$script:AnsiReset"
}

$memberBoardsTool = Join-Path $base 'tools\Show-MemberBoards.ps1'
if (Test-Path $memberBoardsTool) { . $memberBoardsTool }

# ---------------------------------------------------------------- helpers ----

function Read-Line {
    # EVERY prompt in the wizard goes through here, so the 'm' escape below -
    # and 'cls' - are available everywhere by construction. There is no
    # prompt you can get stuck on needing Ctrl+C, and no need to Ctrl+C just to
    # get a clean terminal back either. 'b' is deliberately NOT handled here:
    # back only means something where there is a previous question to return
    # to, so it stays opt-in per call site via Test-BackAnswer.
    # -Redraw lets a menu function (Show-Menu, Show-CaptureWizardMenu, ...) hand
    # back the scriptblock that printed its title/options, so 'cls' can replay it
    # after Clear-Host instead of leaving a blank screen with only the one-line
    # prompt on it - Clear-Host wipes everything Read-Line itself has no memory of.
    param([string]$Prompt, [scriptblock]$Redraw)
    while ($true) {
        Write-Host -NoNewline $Prompt
        $raw = Read-Host
        if (Test-ClearScreenAnswer $raw) {
            Clear-Host
            if ($Redraw) { & $Redraw }
            continue
        }
        if (Test-MainMenuAnswer $raw) { Request-MainMenu }
        return $raw
    }
}

function Test-BackAnswer {
    # Shared "did they type b/back" check for every prompt that opts into
    # -AllowBack below, so the wizard's step machine (the "from menus" capture
    # flow) has one consistent way to recognise it everywhere.
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('b', 'back')))
}

function Test-ClearScreenAnswer {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -eq 'cls'))
}

$script:MainMenuSignal = 'WIZARD-RETURN-TO-MAIN-MENU'
$script:BackSignal     = 'WIZARD-GO-BACK'

function Test-MainMenuAnswer {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('m', 'menu', 'main')))
}

$script:NavLocked = $false

function Request-MainMenu {
    # Unwinds to the wizard's outermost loop from ANY prompt depth. Thrown rather
    # than returned because prompts sit several helpers deep (Select-Port inside
    # the roster step inside the step machine) and threading a sentinel back up
    # through every one of those returns would mean touching every call site --
    # and missing one would leave exactly the dead end this exists to remove.
    # try/finally still unwinds normally, so Pop-Location and friends are not
    # skipped. Caught once, at the :wizard loop near the bottom of this file.
    if ($script:NavLocked) {
        # Past the Proceed gate some boards may already be flashed. Quietly landing
        # back on the main menu there would look like nothing had happened and invite
        # a second run over a half-flashed set.
        Write-Host ""
        Write-Host "  'm' is disabled once flashing has started - boards are already part-way" -ForegroundColor Yellow
        Write-Host "  through this run. Answer the prompt, or Ctrl+C if you really must stop." -ForegroundColor Yellow
        return
    }
    throw $script:MainMenuSignal
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

function Get-FreeNodeLabel {
    # Lowest nodeN not already used. For boards this laptop records but never
    # touches (a root or attacker on someone else's laptop): the label only names
    # them in the hand-off summary, so prompting for one asks the operator to
    # invent a value their own machine will never act on.
    param([string[]]$Taken)
    $n = 1
    while ($Taken -contains "node$n") { $n++ }
    return "node$n"
}

function Show-Menu {
    # Returns the 0-based index of the chosen option, or -1 if the caller
    # passed -AllowBack and the operator typed 'b'/'back' - callers that opt
    # in are expected to check for -1 before indexing anything with it.
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = -1,   # -1 = no default, must choose
        [switch]$AllowBack,
        # Optional index -> section heading, printed ABOVE the option at that
        # index (e.g. @{ 0 = '-- YOURS (Bas)'; 3 = '-- Kyle' }). Purely visual:
        # the numbering stays one sequential 1..N run over $Options, exactly as
        # it is without headings, so a heading can never shift what "[3]" means.
        [hashtable]$GroupHeaders
    )
    # Captured as a scriptblock (not just run inline) so it can be handed to
    # Read-Line as -Redraw: 'cls' Clear-Hosts the whole screen, and this is the
    # only place that knows how to put the title/options back afterward.
    $draw = {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($GroupHeaders -and $GroupHeaders.ContainsKey($i)) {
                Write-Host ""
                Write-Host ("  {0}" -f $GroupHeaders[$i]) -ForegroundColor DarkCyan
            }
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
    }
    & $draw
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid selection for '$Title' after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        # Spells out both paths on the prompt itself instead of relying on the
        # reader already knowing "[N]" means "the default" - same reasoning as
        # the list marker above.
        # 'm' is handled inside Read-Line for every prompt in the wizard; it is
        # advertised here (and on the other hand-written prompts) so it is
        # discoverable rather than a hidden keyword.
        $navHint = if ($AllowBack) { ", 'b' back, 'm' main menu, 'cls' clear" } else { ", 'm' main menu, 'cls' clear" }
        # A one-option menu read as "type 1-1", which looks like a typo for a
        # range, and Enter was rejected there even though there was nothing else
        # it could have meant. Both are spelled for the single-option case.
        $range = if ($Options.Count -eq 1) { "1" } else { "1-$($Options.Count)" }
        $hint = if ($DefaultIndex -ge 0) {
            "Press Enter to keep [$($DefaultIndex + 1)], or type $range for another option$navHint > "
        } elseif ($Options.Count -eq 1) {
            "Press Enter (or type 1) - only one choice here$navHint > "
        } else {
            "Type $range$navHint > "
        }
        $raw = Read-Line $hint -Redraw $draw
        if ($AllowBack -and (Test-BackAnswer $raw)) { return -1 }
        if (-not $raw -and $DefaultIndex -ge 0) { return $DefaultIndex }
        # Enter on a single-option menu takes the only option - there is no other
        # answer it could resolve to, so demanding the keystroke was pure friction.
        if (-not $raw -and $Options.Count -eq 1) { return 0 }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return ($n - 1)
        }
        if ($Options.Count -eq 1) { Write-Host "  Enter 1 (the only option)." -ForegroundColor Yellow }
        else { Write-Host "  Enter a number from 1 to $($Options.Count)." -ForegroundColor Yellow }
    }
}

function Show-CaptureWizardMenu {
    # Grouped version of the top-level "What do you want to do?" menu, same
    # CAPTURE/DATA/MAINTENANCE/VERIFY grouping menu.ps1's Show-MainMenu uses for
    # its own main menu - kept in the same spirit (not a shared function, since
    # the two launchers' option sets differ). Each item carries its REAL 0-based
    # modeIdx (what the `if ($modeIdx -eq N)` checks at the call site expect
    # back), but the NUMBER PRINTED ON SCREEN is a separate, always-sequential
    # 1..10 position in display order - $order/$display below is the lookup
    # between the two, so "[3]" always means "the 3rd line on screen" even
    # though DATA's first item is modeIdx 4 and MAINTENANCE's is modeIdx 1.
    $categories = @(
        @{ Name = 'CAPTURE'; Items = @(
            @{ Idx = 0; Text = 'Run a capture (attack/baseline + topology - the normal flow)' }
            @{ Idx = 9; Text = 'Run a capture without a preset (skip the preset picker - answer the menus, like menu.ps1)' }
        ) }
        @{ Name = 'DATA'; Items = @(
            @{ Idx = 4; Text = 'Import CSVs from a pulled SD card - one board, or several at once (no board/COM contact)' }
            @{ Idx = 16; Text = 'Sync capture data with GitHub (push / pull / test) - raw CSVs only, never code' }
            @{ Idx = 10; Text = 'Trim exported CSVs only (tools\trim_run.py --apply - writes trimmed/ copies, raw export untouched)' }
            @{ Idx = 7; Text = 'Run analysis only (M6->M8 on already-exported CSVs - no board/COM contact)' }
            @{ Idx = 14; Text = 'View a saved run log (a past run''s console output, incl. any errors - no board/COM contact)' }
        ) }
        @{ Name = 'MAINTENANCE'; Items = @(
            @{ Idx = 1; Text = "Wipe a board clean (full erase, no firmware - for when you're not sure what's on it)" }
            @{ Idx = 2; Text = 'Write/update location.txt on an already-running board (over USB)' }
            @{ Idx = 3; Text = 'Firmware self-test - build + flash ONE board and check the SD/location code (no capture, no attack, no export)' }
            @{ Idx = 6; Text = 'Identify all boards (COM port + MAC, every board at once - no capture, no attack)' }
            @{ Idx = 17; Text = 'Member board list (edit / open json / snapshots - submenu)' }
            @{ Idx = 15; Text = 'Delete a folder from a running board''s SD card (e.g. blackhole > linear > G402 - PERMANENT, over USB)' }
        ) }
        @{ Name = 'VERIFY'; Items = @(
            @{ Idx = 5; Text = 'Verify a run (paper-backed 3-sigma attack check - no board/COM contact)' }
        ) }
    )
    $exitIdx = 8

    $order = @()
    foreach ($cat in $categories) { foreach ($item in $cat.Items) { $order += $item.Idx } }
    $order += $exitIdx   # always last on screen
    $display = @{}   # real modeIdx -> number printed on screen
    for ($i = 0; $i -lt $order.Count; $i++) { $display[$order[$i]] = $i + 1 }

    # Same reasoning as Show-Menu's $draw: handed to Read-Line as -Redraw so
    # 'cls' can put this whole grouped listing back after Clear-Host wipes it.
    $draw = {
        if (Get-Command Show-MemberBoards -ErrorAction SilentlyContinue) {
            Show-MemberBoards -Path (Join-Path $base 'member_boards.json')
        }
        Write-Host ""
        Write-Host "What do you want to do?" -ForegroundColor Cyan
        foreach ($cat in $categories) {
            Write-Host ""
            Write-Host ("-- {0}" -f $cat.Name) -ForegroundColor DarkCyan
            foreach ($item in $cat.Items) {
                $num = $display[$item.Idx]
                if ($item.Idx -eq 0) {
                    Write-Host ("  [{0}] {1}  <- default (press Enter)" -f $num, $item.Text) -ForegroundColor Green
                } else {
                    Write-Host ("  [{0}] {1}" -f $num, $item.Text)
                }
            }
        }
        Write-Host ""
        Write-Host ("  [{0}] Exit the wizard" -f $display[$exitIdx])
    }
    & $draw

    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid selection for 'What do you want to do?' after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        $raw = Read-Line "Press Enter to keep [1], or type 1-$($order.Count) for another option, 'm' main menu, 'cls' clear > " -Redraw $draw
        if (-not $raw) { return 0 }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $order.Count) { return $order[$n - 1] }
        Write-Host ("  Enter a number from 1 to {0}." -f $order.Count) -ForegroundColor Yellow
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
        # -wait 5 (not 1): board_check.py's own reset (during its bootloader/flash
        # checks) happens right before this, so 5s gives its runtime listen a real
        # shot at the boot banner - see [[wizard-prebuild-and-live-identify-2026-09]].
        $out = & python board_check.py --port $TargetPort --wait 5
        $rc = $LASTEXITCODE
        $hit = $out | Select-String -Pattern 'MAC\s+([0-9a-fA-F:]{17})\s+->\s+(.+)$' | Select-Object -First 1
        if ($hit) {
            Write-Host ("  " + $hit.Line.Trim()) -ForegroundColor Green
            $mac  = $hit.Matches[0].Groups[1].Value
            $name = $hit.Matches[0].Groups[2].Value
            # firmware-short is a LIVE read of what's actually running - never a
            # roster guess. Appended only when board_check.py got far enough to
            # print it (it can't, if the bootloader check itself failed).
            $fwHit = $out | Select-String -Pattern 'firmware-short:\s+(.+)$' | Select-Object -First 1
            if ($fwHit) {
                $fwTag = $fwHit.Matches[0].Groups[1].Value.Trim()
                Write-Host ("    firmware: {0}" -f $fwTag) -ForegroundColor Green
                $name = "$name  ($fwTag)"
            }
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
    # With -AllowBack the port list grows a "go back" entry and returns the
    # $script:BackSignal string. A distinct sentinel, not $null: $null already
    # means "this board is on another laptop" in Select-PortOrRemote's contract,
    # and conflating the two would silently mark a board remote when the operator
    # only meant to re-answer the previous question.
    # -Taken hides ports already assigned to an earlier board in this SAME
    # roster from the numbered pick-list - the list you're choosing FROM should
    # not still show a port you (or an earlier step) already gave to node2 as if
    # it were free for node3 too. It only hides them from the auto-numbered
    # list: "type a port manually" still reaches a taken port on purpose, for
    # the genuine shared-port/swap-mode case (see $swapMode below), with a
    # confirm so that stays a deliberate choice, not an accidental duplicate.
    param([string]$For, [object[]]$Ports, [switch]$AllowBack, [string[]]$Taken = @())
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid port chosen for $For after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        $shown = @($Ports | Where-Object { $Taken -notcontains $_.Port })
        Write-Host ""
        Write-Host "Select port for $For :" -ForegroundColor Cyan
        if ($shown.Count -eq 0) {
            if ($Ports.Count -eq 0) {
                Write-Host "  (no COM ports detected - a charge-only USB cable creates no port)" -ForegroundColor Yellow
            } else {
                Write-Host "  (every detected port is already assigned to another board in this roster -" -ForegroundColor Yellow
                Write-Host "  auto-detect a new one, or type one manually to share a port on purpose)" -ForegroundColor Yellow
            }
        }
        for ($i = 0; $i -lt $shown.Count; $i++) {
            $tag = ''
            if ($script:IdentifiedPorts.ContainsKey($shown[$i].Port)) {
                $tag = "  [{0}]" -f $script:IdentifiedPorts[$shown[$i].Port]
            }
            $kindTag = Format-PortKindTag $shown[$i].Kind
            $color   = switch ($shown[$i].Kind) { 'BLOCKED' { 'DarkGray' } 'UNKNOWN' { 'Yellow' } default { 'Gray' } }
            Write-Host ("  [{0}] {1,-7} - {2}{3}{4}" -f ($i + 1), $shown[$i].Port, $shown[$i].Description, $tag, $kindTag) -ForegroundColor $color
        }
        # Actions continue the same numbering as the ports above - one flat numbered
        # list, same convention as every other menu in this wizard (Show-Menu).
        $identifyOneIdx = $shown.Count + 1
        $identifyAllIdx = $shown.Count + 2
        $autoDetectIdx  = $shown.Count + 3
        $manualIdx      = $shown.Count + 4
        $backIdx        = if ($AllowBack) { $shown.Count + 5 } else { -1 }
        Write-Host ("  [{0}] identify a port (reads its MAC)" -f $identifyOneIdx)
        Write-Host ("  [{0}] identify ALL listed ports (reads each one in turn, takes a while)" -f $identifyAllIdx)
        Write-Host ("  [{0}] auto-detect (not plugged in yet - plug it in now, wizard finds the new port)" -f $autoDetectIdx)
        Write-Host ("  [{0}] type a port manually (also how to deliberately share an already-taken port)" -f $manualIdx)
        if ($AllowBack) { Write-Host ("  [{0}] go back to the previous question" -f $backIdx) }
        $navHint = if ($AllowBack) { "  ('b' back, 'm' main menu, 'cls' clear)" } else { "  ('m' main menu, 'cls' clear)" }
        $raw = Read-Line ">$navHint "

        if ($AllowBack -and (Test-BackAnswer $raw)) { return $script:BackSignal }

        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n)) {
            Write-Host "  Enter a number from the list above." -ForegroundColor Yellow
            continue
        }

        if ($AllowBack -and $n -eq $backIdx) { return $script:BackSignal }

        if ($n -ge 1 -and $n -le $shown.Count) {
            # This port goes on to be flashed by run.ps1 - the single most
            # destructive thing the wizard does to whatever is on the other end.
            if (-not (Test-PortSafeToTouch -Port $shown[$n - 1].Port -Action 'flash firmware to it')) { continue }
            return $shown[$n - 1].Port
        }
        if ($n -eq $identifyOneIdx) {
            if ($shown.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            $which = Read-Line '  Which listed port number? > '
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $shown.Count) {
                Invoke-Identify -TargetPort $shown[$wn - 1].Port
            }
            else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }
        if ($n -eq $identifyAllIdx) {
            if ($shown.Count -eq 0) { Write-Host "  Nothing to identify." -ForegroundColor Yellow; continue }
            Write-Host ""
            foreach ($p in $shown) {
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
                if (-not (Test-PortSafeToTouch -Port $manual -Action 'flash firmware to it')) { continue }
                if ($Taken -contains $manual) {
                    $ans = Read-Line ("  {0} is already assigned to another board - SHARE it (swap mode, boards take turns)? [y/N] > " -f $manual)
                    if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
                }
                return $manual
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
    # Returns a port string, $null for "not on this laptop", or $script:BackSignal
    # when -AllowBack is set and the operator wants the previous question again.
    param([string]$For, [object[]]$Ports, [bool]$MultiLaptop, [switch]$AllowBack, [string[]]$Taken = @())
    if ($MultiLaptop) {
        $hint = if ($AllowBack) { " ('b' back, 'm' main menu, 'cls' clear)" } else { " ('m' main menu, 'cls' clear)" }
        $ans = Read-Line "  Is $For plugged into THIS laptop? [Y/n]$hint > "
        if ($AllowBack -and (Test-BackAnswer $ans)) { return $script:BackSignal }
        if ($ans -eq 'n' -or $ans -eq 'N') { return $null }
    }
    return (Select-Port -For $For -Ports $Ports -AllowBack:$AllowBack -Taken $Taken)
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

    # Same self-heal run.ps1 does before it builds/flashes: a build dir can be left
    # pointing at a different repo path (moved/re-cloned) or half-configured by an
    # interrupted build (Ctrl+Break, killed idf.py) -- either way idf.py's
    # generated sdkconfig.h/build.ninja is broken and every rebuild just reuses the
    # same broken tree. This call goes straight to idf.py (not through run.ps1), so
    # it needs its own copy of the same check.
    $cacheFile = Join-Path $buildDir "CMakeCache.txt"
    if (Test-Path $cacheFile) {
        $expectedHome   = (Join-Path $base $proj) -replace '\\', '/'
        $cachedHomeLine = Select-String -Path $cacheFile -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
        $pathMismatch   = $cachedHomeLine -and (($cachedHomeLine.Line -split '=', 2)[1]).TrimEnd('/') -ne $expectedHome.TrimEnd('/')
        $sdkconfigH     = Join-Path $buildDir "config\sdkconfig.h"
        $sdkconfigOk    = (Test-Path $sdkconfigH) -and (Select-String -Path $sdkconfigH -Pattern '^#define CONFIG_IDF_TARGET_ESP32\b' -Quiet)
        if ($pathMismatch -or -not $sdkconfigOk) {
            Write-Host "Stale build dir '$buildDir' is misconfigured (moved repo or interrupted build) -- wiping it so this run reconfigures cleanly." -ForegroundColor Yellow
            Remove-Item -Recurse -Force $buildDir
        }
    }

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

function Format-BuildStamp {
    # "2026-09-17 14:32:07" (csv_logger.c's runs.csv "built" column, via
    # import_sdcard.py --list-json) -> "09 / 17 / 2026 14:32", the leftmost
    # column of the card file picker. Fixed 20 chars wide so the "|" after it
    # lines up down the list whether or not a given file has a stamp.
    # Mirrored in menu.ps1 - keep the two in sync.
    param([string]$Stamp)
    if ($Stamp -match '^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})') {
        return ('{0} / {1} / {2} {3}:{4}' -f $Matches[2], $Matches[3], $Matches[1], $Matches[4], $Matches[5])
    }
    return '(no build stamp)'
}

function Select-CardFiles {
    # Numbered picker over everything a card holds, so an import can be "just
    # these two files" instead of all-or-nothing.
    #
    # The leftmost column is the build date+time of the FIRMWARE that logged
    # each file (see sd_status_build_stamp()). That column is the whole point:
    # a board with no RTC cannot date its own captures, so without it a file
    # left on the card by a session weeks ago is indistinguishable from one
    # written ten minutes ago - which is exactly how a half-finished run that
    # got interrupted, fixed and forgotten ends up silently re-imported as
    # today's data. Newest stamp first, and the newest is coloured green, so
    # "the flash I am running now" is the block at the top of the list.
    #
    # Returns $null to cancel, or a hashtable:
    #   Rel            = @() for ALL, or the card-relative paths picked
    #   IncludeAborted = $true if the operator confirmed aborted files
    # Mirrored in menu.ps1 - keep the two in sync.
    #
    # $Card is only used for the 'd' (delete straight off the card) command
    # below - a PERMANENT filesystem delete, separate from --delete-source
    # (which only ever removes a file AFTER Import-OneSdCard has verified its
    # copy landed). This lets the operator clear out junk/aborted files (e.g.
    # the 0-row ABORTED entry in the listing) they never intend to import,
    # without importing something first just to trigger that cleanup.
    param([Parameter(Mandatory)]$Files, [string]$Card)

    # Sorted newest-build-first; unknown stamps sink to the bottom (they can
    # only be pre-stamp firmware, i.e. older than anything that has one).
    $sorted = @($Files | Sort-Object `
        @{ Expression = { if ($_.built) { $_.built } else { '' } }; Descending = $true }, `
        @{ Expression = { '{0}/{1}/{2}' -f $_.attack, $_.topology, $_.location } }, `
        @{ Expression = { [int]$_.boot } })

    # Deliberately NOT wrapped in @(): this is compared with -eq against a
    # scalar below, and a 1-element array on the right of -eq is the classic
    # PowerShell footgun (it coerces rather than compares cleanly).
    $newest = $sorted | Where-Object { $_.built } | Select-Object -First 1 -ExpandProperty built

    $draw = {
        Write-Host ""
        Write-Host "On this card:" -ForegroundColor Cyan
        Write-Host "  (leftmost column = when the FIRMWARE that logged the file was built - not" -ForegroundColor DarkGray
        Write-Host "   when it ran. Every boot of one flash shares it, so it tells today's" -ForegroundColor DarkGray
        Write-Host "   captures from ones an older flash left behind.)" -ForegroundColor DarkGray
        Write-Host ""
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $f = $sorted[$i]
            $stamp = Format-BuildStamp $f.built
            # Green = newest firmware on this card (almost always "the one you
            # just flashed"); yellow = an older flash left this here.
            $stampColor = if (-not $f.built) { 'DarkGray' }
                          elseif ($newest -and $f.built -eq $newest) { 'Green' }
                          else { 'Yellow' }
            Write-Host ("  [{0}] " -f ($i + 1)) -NoNewline
            Write-Host ("{0,-20}" -f $stamp) -NoNewline -ForegroundColor $stampColor
            Write-Host (" | {0}" -f $f.name)

            $bits = @("{0}/{1}/{2}" -f $f.attack, $f.topology, $f.location)
            $bits += "boot $($f.boot)"
            if ($null -ne $f.run) { $bits += "run $($f.run)" }
            $bits += "$($f.rows) rows"
            if ($f.archived) { $bits += '_archive' }
            $noteColor = 'DarkGray'
            if ($f.clean -eq $false) { $bits += 'ABORTED (started, never closed cleanly)'; $noteColor = 'Yellow' }
            if ($f.already) { $bits += "already imported as $($f.already)"; $noteColor = 'DarkGray' }
            Write-Host ("      {0}" -f ($bits -join '  |  ')) -ForegroundColor $noteColor
        }
    }
    & $draw

    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            throw "No valid card file selection after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
        }
        $raw = Read-Line ("`nImport which? numbers (e.g. 1,3 or 1-{0}), 'a' = ALL, 'd1,3' = delete those from the card (no import), 'c' = cancel > " -f $sorted.Count) -Redraw $draw
        if (-not $raw) { Write-Host "  Type numbers, 'a', 'd<numbers>' or 'c'." -ForegroundColor Yellow; continue }
        $raw = $raw.Trim()
        if ($raw -eq 'c' -or $raw -eq 'C') { return $null }

        if ($raw -match '^[dD]\s*(.+)$') {
            $spec = $Matches[1].Trim()
            $delIdxs = @()
            $badDel = $false
            foreach ($tok in ($spec -split ',')) {
                $t = $tok.Trim()
                if (-not $t) { continue }
                if ($t -match '^(\d+)\s*-\s*(\d+)$') {
                    $lo = [int]$Matches[1]; $hi = [int]$Matches[2]
                    if ($lo -lt 1 -or $hi -gt $sorted.Count -or $lo -gt $hi) { $badDel = $true; break }
                    $delIdxs += $lo..$hi
                }
                elseif ($t -match '^\d+$') {
                    $n = [int]$t
                    if ($n -lt 1 -or $n -gt $sorted.Count) { $badDel = $true; break }
                    $delIdxs += $n
                }
                else { $badDel = $true; break }
            }
            if ($badDel -or $delIdxs.Count -eq 0) {
                Write-Host ("  'd' needs numbers from 1 to {0} after it (e.g. d1,3 or d1-2)." -f $sorted.Count) -ForegroundColor Yellow
                continue
            }
            $toDelete = @($delIdxs | Sort-Object -Unique | ForEach-Object { $sorted[$_ - 1] })

            Write-Host ""
            Write-Host "  DELETE from the card (PERMANENT - not the exports/ copy, the SD card file itself):" -ForegroundColor Red
            foreach ($d in $toDelete) { Write-Host ("    {0}" -f $d.name) -ForegroundColor Red }
            $confirm = Read-Line ("  Delete {0} file(s) from the card? [y/N] > " -f $toDelete.Count)
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "  Cancelled - nothing deleted." -ForegroundColor DarkGray
                continue
            }

            $deletedRel = @()
            foreach ($d in $toDelete) {
                if (-not $Card) {
                    Write-Host ("    Skipped {0} - no card path known." -f $d.name) -ForegroundColor Yellow
                    continue
                }
                $full = Join-Path $Card $d.rel
                try {
                    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                    Write-Host ("    Deleted {0}" -f $d.name) -ForegroundColor Green
                    $deletedRel += $d.rel
                }
                catch { Write-Host ("    FAILED to delete {0}: {1}" -f $d.name, $_.Exception.Message) -ForegroundColor Yellow }
            }
            if ($deletedRel.Count -gt 0) {
                $sorted = @($sorted | Where-Object { $deletedRel -notcontains $_.rel })
            }
            if ($sorted.Count -eq 0) {
                Write-Host "  Nothing left on this card." -ForegroundColor DarkGray
                return $null
            }
            & $draw
            continue
        }

        $picked = @()
        if ($raw -eq 'a' -or $raw -eq 'A') {
            $picked = @($sorted)
        }
        else {
            # Comma list of single numbers and/or N-M ranges.
            $bad = $false
            $idxs = @()
            foreach ($tok in ($raw -split ',')) {
                $t = $tok.Trim()
                if (-not $t) { continue }
                if ($t -match '^(\d+)\s*-\s*(\d+)$') {
                    $lo = [int]$Matches[1]; $hi = [int]$Matches[2]
                    if ($lo -lt 1 -or $hi -gt $sorted.Count -or $lo -gt $hi) { $bad = $true; break }
                    $idxs += $lo..$hi
                }
                elseif ($t -match '^\d+$') {
                    $n = [int]$t
                    if ($n -lt 1 -or $n -gt $sorted.Count) { $bad = $true; break }
                    $idxs += $n
                }
                else { $bad = $true; break }
            }
            if ($bad -or $idxs.Count -eq 0) {
                Write-Host ("  Enter numbers from 1 to {0} (e.g. 1,3 or 1-3), 'a' for all, or 'c' to cancel." -f $sorted.Count) -ForegroundColor Yellow
                continue
            }
            $picked = @($idxs | Sort-Object -Unique | ForEach-Object { $sorted[$_ - 1] })
        }

        # Aborted files are skipped by default (import_sdcard.py --include-aborted)
        # because a cut-off capture is partial data. Picking one BY NUMBER is an
        # explicit choice though, so ask rather than silently dropping it - and
        # if the answer is no, drop it here so the count shown is honest.
        $aborted = @($picked | Where-Object { $_.clean -eq $false })
        $includeAborted = $false
        if ($aborted.Count -gt 0) {
            Write-Host ""
            foreach ($a in $aborted) { Write-Host ("  ABORTED: {0}" -f $a.name) -ForegroundColor Yellow }
            $ans = Read-Line ("  {0} of the file(s) you picked never closed cleanly (power loss, a killed run) - import them anyway? [y/N] > " -f $aborted.Count)
            if ($ans -eq 'y' -or $ans -eq 'Y') {
                $includeAborted = $true
            }
            else {
                $picked = @($picked | Where-Object { $_.clean -ne $false })
                if ($picked.Count -eq 0) {
                    Write-Host "  Nothing left selected." -ForegroundColor DarkGray
                    return $null
                }
            }
        }

        $already = @($picked | Where-Object { $_.already })
        if ($already.Count -gt 0) {
            Write-Host ("  NOTE: {0} of these is already in exports/ and will be skipped by the import." -f $already.Count) -ForegroundColor DarkGray
        }

        # "ALL" stays an empty Rel list rather than every path spelled out: it
        # means "no --files filter", which is the long-standing whole-card
        # behaviour, and keeps the command line short.
        $isAll = ($picked.Count -eq $sorted.Count) -and ($aborted.Count -eq 0 -or $includeAborted)
        return @{
            Rel            = if ($isAll) { @() } else { @($picked | ForEach-Object { $_.rel }) }
            IncludeAborted = $includeAborted
        }
    }
}

function Import-OneSdCard {
    # Lists what the card holds (import_sdcard.py --list-json) and lets the
    # operator pick files by number, then runs a DRY RUN of exactly that
    # selection and shows what it found, then asks before it actually copies
    # anything - the same "preview, then confirm" shape as the rest of the
    # wizard, applied to the one write this whole SD-import flow makes.
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
        # What's on the card, before anything is selected or copied. Separate
        # from the dry run below on purpose: this is the pick-by-number list
        # (with each file's firmware build date), the dry run is the preview of
        # the copy the selection produces.
        $listArgs = @('import_sdcard.py', '--card', $Card, '--repeat', $Repeat, '--scenario', $Scenario)
        if ($Roster) { $listArgs += @('--roster', $Roster) }
        $listOut = & python @listArgs --list-json 2>&1
        $rc = $LASTEXITCODE
        if ($rc -ne 0) {
            $listOut | ForEach-Object { Write-Host "  $_" }
            Write-Host ("  import_sdcard.py --list-json exited {0} (python/pyserial missing? run from the ESP-IDF 5.3 PowerShell)." -f $rc) -ForegroundColor Yellow
            return
        }
        # --list-json puts the array on stdout and warnings on stderr, but 2>&1
        # merges both into one stream here - so take the JSON line rather than
        # the whole capture, or a roster warning would break ConvertFrom-Json.
        $jsonLine = @($listOut | ForEach-Object { "$_" } |
            Where-Object { $_.TrimStart().StartsWith('[') }) | Select-Object -Last 1
        $cardFiles = @()
        if ($jsonLine) {
            # PS 5.1 ConvertFrom-Json emits a JSON array as ONE Object[] item;
            # ForEach-Object unrolls it so each file is its own element.
            try { $cardFiles = @($jsonLine | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $cardFiles = @() }
        }

        if ($cardFiles.Count -eq 0) {
            Write-Host "  Nothing to import from here." -ForegroundColor DarkGray
            return
        }

        $sel = Select-CardFiles -Files $cardFiles -Card $Card
        if ($null -eq $sel) {
            Write-Host "  Cancelled - nothing copied." -ForegroundColor DarkGray
            return
        }
        if ($sel.Rel.Count -gt 0) { $pyArgs += @('--files', ($sel.Rel -join ',')) }
        if ($sel.IncludeAborted -and $pyArgs -notcontains '--include-aborted') { $pyArgs += '--include-aborted' }

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
        Write-Host ("`nNaming from preset {0} [{1}] (matches {2}/{3}/{4}/{5})." -f `
            $presetMatches[0].File.Name, (Format-PresetOwner $presetMatches[0].File.Owner), `
            $attack, $topology, $scenario, $location) -ForegroundColor DarkGray
    }
    elseif ($presetMatches.Count -gt 1) {
        # With one folder per member, every member's preset for this cell has the
        # SAME filename - so the owner has to be on the line or this is a list of
        # identical-looking choices. Defaults to this laptop's member, which is
        # whose card is being imported in the ordinary case.
        $myMember = Get-MyMember
        $rOpts = @($presetMatches | ForEach-Object {
            $own = Format-PresetOwner $_.File.Owner
            if ($myMember -and $_.File.Owner -eq $myMember) { "{0,-30} {1}  (you)" -f $_.File.Name, $own }
            else { "{0,-30} {1}" -f $_.File.Name, $own }
        })
        $myIdx = 0
        for ($i = 0; $i -lt $presetMatches.Count; $i++) {
            if ($myMember -and $presetMatches[$i].File.Owner -eq $myMember) { $myIdx = $i; break }
        }
        $rIdx = Show-Menu -Title 'Several saved presets match this attack/topology/scenario/location - name from which?' -Options $rOpts -DefaultIndex $myIdx
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

function Invoke-IdentifyAllBoards {
    # Scans EVERY detected, non-blocked COM port and reads its MAC + node name in
    # one pass -- the "which physical board is which" question Invoke-Identify
    # answers one port at a time, done for the whole desk at once. Read-only
    # (board_check.py's bootloader MAC read only), gated per-port by
    # Test-PortSafeToTouch exactly like Invoke-Identify, so a mouse receiver or
    # Bluetooth link enumerated as a serial port is never poked. Mirrors
    # menu.ps1's "Identify a board" (multi mode) - keep the two in sync.
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($ports.Count -eq 0) {
        Write-Host ""
        Write-Host "  No usable COM ports detected. Is anything plugged in?" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host ("Detected {0} port(s):" -f $ports.Count) -ForegroundColor Cyan
    foreach ($p in $ports) {
        $tag = if ($p.Kind -eq 'UNKNOWN') { '  << unrecognised - will ask to confirm' } else { '' }
        Write-Host ("   {0,-7} ({1}){2}" -f $p.Port, $p.Description, $tag)
    }
    Write-Host ""
    Write-Host ("Reading all {0} board(s) -- MAC + node number ..." -f $ports.Count) -ForegroundColor DarkGray

    $results = @()
    Push-Location (Join-Path $base 'tools')
    try {
        foreach ($p in $ports) {
            Write-Host ("  {0} ..." -f $p.Port) -ForegroundColor DarkGray
            if (-not (Test-PortSafeToTouch -Port $p.Port -Action 'reset it to read a MAC')) {
                $results += [pscustomobject]@{ Port = $p.Port; Mac = $null; Node = 'skipped (not confirmed)' }
                continue
            }
            # -wait 5 (not 1): gives board_check.py's runtime listen a real shot at
            # the boot banner - see [[wizard-prebuild-and-live-identify-2026-09]].
            $out = & python board_check.py --port $p.Port --wait 5
            $hit = $out | Select-String -Pattern 'MAC\s+([0-9a-fA-F:]{17})\s+->\s+(.+)$' | Select-Object -First 1
            if ($hit) {
                $mac  = $hit.Matches[0].Groups[1].Value.ToLower()
                $node = $hit.Matches[0].Groups[2].Value
                # firmware-short is a LIVE read of what's actually running - never
                # a roster guess. Folded into $node so it flows through to the
                # attacker-MAC cross-check table below along with everything else.
                $fwHit = $out | Select-String -Pattern 'firmware-short:\s+(.+)$' | Select-Object -First 1
                if ($fwHit) { $node = "$node  ($($fwHit.Matches[0].Groups[1].Value.Trim()))" }
                $script:IdentifiedPorts[$p.Port] = "$mac -> $node"
                Write-Host ("    MAC {0}  ->  {1}" -f $mac, $node) -ForegroundColor Green
            } else {
                $mac  = $null
                $node = 'could not identify (no MAC read)'
                Write-Host ("    Could not read a MAC from {0} -- unplugged, port busy, or esptool unavailable." -f $p.Port) -ForegroundColor Yellow
            }
            $results += [pscustomobject]@{ Port = $p.Port; Mac = $mac; Node = $node }
        }
    } finally { Pop-Location }

    # Read before the summary prints (not just for the cross-check below) so ROOT/
    # attacker rows can be colored immediately instead of only after a second pass.
    $configured = Get-ConfiguredAttackerMac

    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    foreach ($r in $results) {
        $macDisp = if ($r.Mac) { $r.Mac } else { '(unread)' }
        $role = if ($r.Node -match '\(ROOT\)') { 'root' } elseif ($configured -and $r.Mac -eq $configured) { 'attacker' } else { 'child' }
        $line = ("   {0,-7} {1,-17} {2}" -f $r.Port, $macDisp, $r.Node)
        Write-Host (Colorize-Role $line $role)
    }

    # ---- cross-check against the compiled blackhole attacker MAC ------------
    # BLACKHOLE_ATTACKER_MAC is baked into VICTIM firmware at BUILD time -- if it
    # doesn't match whichever board is actually wearing the attacker role right
    # now, every victim probe addresses a MAC nothing in the mesh holds and the
    # whole run logs zero arrivals with no error pointing at why. This reads the
    # boards just identified against that compiled value before any flashing.
    Write-Host ""
    if (-not $configured) {
        Write-Host "  (Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h -- skipping attacker cross-check.)" -ForegroundColor DarkGray
        return
    }
    Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $configured) -ForegroundColor Cyan
    $readOk  = @($results | Where-Object { $_.Mac })
    $matches = @($readOk | Where-Object { $_.Mac -eq $configured })

    if ($matches.Count -eq 1) {
        Write-Host ("  MATCH -- {0} ({1}) is the configured attacker. Victim boards will reach it." -f $matches[0].Port, $matches[0].Node) -ForegroundColor Green
        return
    }
    if ($matches.Count -gt 1) {
        Write-Host ("  WARNING: {0} of the boards just read all report this SAME MAC -- that should not happen (duplicate/cloned MAC?)." -f $matches.Count) -ForegroundColor Red
        return
    }
    if ($readOk.Count -eq 0) {
        Write-Host "  Could not confirm -- no MAC was successfully read from any board above." -ForegroundColor Yellow
        return
    }

    Write-Host "  NO MATCH among the boards just read -- none of these is the configured attacker." -ForegroundColor Red
    Write-Host "  Victim probes targeting $configured will find nothing in the mesh and vanish for the" -ForegroundColor Red
    Write-Host "  WHOLE run (baseline included), with every blackhole feature coming out all-NaN." -ForegroundColor Red
    $fixOpts = @($readOk | ForEach-Object { "$($_.Port)  ($($_.Mac))  $($_.Node)" })
    $fixOpts += 'Leave as-is'
    $fixIdx = Show-Menu -Title 'Point BLACKHOLE_ATTACKER_MAC at one of the boards just read instead?' -Options $fixOpts -DefaultIndex ($fixOpts.Count - 1)
    if ($fixIdx -lt $readOk.Count) {
        $target = $readOk[$fixIdx]
        if (Set-ConfiguredAttackerMac -Mac $target.Mac -PortLabel $target.Port) {
            Write-Host ("  Fixed -- mesh_config.h now targets {0} ({1}). The next build will pick it up." -f $target.Mac, $target.Port) -ForegroundColor Green
        } else {
            Write-Host "  Could not write mesh_config.h -- fix it by hand before flashing victims." -ForegroundColor Red
        }
    } else {
        Write-Host "  Left as-is -- victim boards will still target the wrong MAC until this is fixed." -ForegroundColor Yellow
    }
}

function Get-CaptureSummary {
    # What preprocess.py/features.py will actually load from ONE folder (both glob
    # *.csv non-recursively). PDR, LatencyHopRatio and TunnelLatency come only from
    # a root's *_arrivals.csv, so a folder without one yields those columns as NaN.
    # Mirrored in menu.ps1 - keep the two in sync.
    param([string]$Dir)
    $names = @(Get-ChildItem -Path $Dir -Filter *.csv -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name } | Where-Object { $_ -like '*_telem.csv' -or $_ -like '*_arrivals.csv' })
    $telem        = @($names | Where-Object { $_ -like '*_telem.csv' })
    $arrivals     = @($names | Where-Object { $_ -like '*_arrivals.csv' })
    $arrivalHeads = @($arrivals | ForEach-Object { $_ -replace '_\d{8}_\d{6}_arrivals\.csv$', '' })
    $rootsMissing = @($telem | Where-Object { $_ -like 'root_*' } |
        Where-Object { ($_ -replace '_\d{8}_\d{6}_telem\.csv$', '') -notin $arrivalHeads })
    return [pscustomobject]@{
        Names                = $names
        Telem                = $telem
        Arrivals             = $arrivals
        RootsMissingArrivals = $rootsMissing
    }
}

function Select-AnalysisInput {
    # Returns the folder to analyse, or $null to cancel. Prefers trimmed\ (the
    # cleaned copies Invoke-TrimOnly writes), refuses to use it silently when it
    # is missing boards the raw export has, and stops before a run that would
    # produce no PDR. Mirrors menu.ps1's Select-AnalysisInput - keep in sync.
    param([string]$Export)

    $trimmedDir = Join-Path $Export 'trimmed'
    $raw  = Get-CaptureSummary -Dir $Export
    $trim = Get-CaptureSummary -Dir $trimmedDir
    $inputDir = $Export
    $in = $raw

    if ($trim.Names.Count -gt 0) {
        $notTrimmed = @($raw.Names | Where-Object { $_ -notin $trim.Names })
        Write-Host ""
        if ($notTrimmed.Count -gt 0) {
            Write-Host ("  trimmed\ is OUT OF DATE - {0} raw file(s) have no trimmed copy:" -f $notTrimmed.Count) -ForegroundColor Yellow
            foreach ($n in $notTrimmed) { Write-Host "    $n" -ForegroundColor Yellow }
            Write-Host "  Analysing trimmed\ now would leave those out. Re-run 'Trim exported CSVs only' first." -ForegroundColor Yellow
            $ans = Read-Line "  Use trimmed\ anyway (t), the raw export (r), or cancel (c)? [c] > "
            if ($ans -eq 't' -or $ans -eq 'T') { $inputDir = $trimmedDir; $in = $trim }
            elseif ($ans -eq 'r' -or $ans -eq 'R') { }
            else { Write-Host "  Cancelled." -ForegroundColor DarkGray; return $null }
        }
        else {
            $ans = Read-Line "  trimmed\ found. Analyse the trimmed copies (t, recommended) or the raw export (r)? [t] > "
            if ($ans -ne 'r' -and $ans -ne 'R') { $inputDir = $trimmedDir; $in = $trim }
        }
    }
    else {
        Write-Host "`n  No trimmed\ folder - analysing the raw export. (Run 'Trim exported CSVs only' first to analyse trimmed data.)" -ForegroundColor DarkGray
    }

    if ($in.Telem.Count -eq 0) {
        Write-Host ("`n  No *_telem.csv in {0} - nothing to analyse." -f $inputDir) -ForegroundColor Yellow
        return $null
    }

    if ($in.Arrivals.Count -eq 0 -or $in.RootsMissingArrivals.Count -gt 0) {
        Write-Host ""
        if ($in.Arrivals.Count -eq 0) {
            Write-Host ("  NO *_arrivals.csv in {0}" -f $inputDir) -ForegroundColor Red
            Write-Host "  PDR, LatencyHopRatio and TunnelLatency will be EMPTY (NaN) for every node." -ForegroundColor Red
        }
        foreach ($r in $in.RootsMissingArrivals) {
            Write-Host ("  Root capture with no matching arrivals file: {0}" -f $r) -ForegroundColor Yellow
        }
        Write-Host "  Only the board flashed as ROOT for this run logs arrivals. Import THAT board's SD card" -ForegroundColor DarkGray
        Write-Host "  (or USB-export it). A root file from another board or run is not a substitute - move it out." -ForegroundColor DarkGray
        $cont = Read-Line "  Continue anyway? [y/N] > "
        if ($cont -ne 'y' -and $cont -ne 'Y') { Write-Host "  Cancelled." -ForegroundColor DarkGray; return $null }
    }

    return $inputDir
}

function Invoke-RunAnalysisOnly {
    # Standalone M6->M8 pipeline (preprocess.py -> features.py -> eda.py) over an
    # already-exported (or SD-imported) folder -- the same three stages run.ps1's
    # -Analyze switch chains automatically after a root export, exposed here to
    # (re-)run analysis without touching a board (a fixed preprocessing bug, or a
    # topology this laptop never itself flashed). Mirrors menu.ps1's "Run
    # analysis only" action - keep the two in sync.
    Write-Host ""
    Write-Host "Nothing here touches a board or a COM port -- runs preprocess.py -> features.py" -ForegroundColor DarkGray
    Write-Host "-> eda.py over an already-exported folder." -ForegroundColor DarkGray

    $attackIdx   = Show-Menu -Title 'Which attack?' -Options @('none (baseline)', 'blackhole', 'wormhole') -DefaultIndex 0
    $rAttack     = @('none', 'blackhole', 'wormhole')[$attackIdx]
    $topoIdx     = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex 0
    $rTopology   = $TOPOLOGIES[$topoIdx]
    $scenarioIdx = Show-Menu -Title 'Scenario (what this capture used, if any):' -Options $SCENARIO_LABELS -DefaultIndex 0
    $rScenario   = $SCENARIOS[$scenarioIdx]
    $locationIdx = Show-Menu -Title 'Location:' -Options $LOCATIONS -DefaultIndex 0
    $rLocation   = $LOCATIONS[$locationIdx]

    $dirs = Get-RunDirs -Attack $rAttack -Topology $rTopology -Location $rLocation -Scenario $rScenario
    if (-not (Test-Path $dirs.Export)) {
        Write-Host ("`n  {0} doesn't exist -- export a board or import a card for this run first." -f $dirs.Export) -ForegroundColor Yellow
        return
    }

    $inputDir = Select-AnalysisInput -Export $dirs.Export
    if (-not $inputDir) { return }

    # Same two-tier python scan run.ps1's -Analyze uses: prefer a python with the
    # full EDA stack (matplotlib/seaborn/scipy/scikit-learn) so M6+M7+M8 all run;
    # fall back to a pandas/numpy-only one (M6+M7 only, M8 skipped with a hint)
    # rather than failing the whole thing.
    $edaPy = $null
    $featuresPy = $null
    foreach ($cand in @('python', 'python3', 'C:\Python314\python.exe')) {
        if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
        & $cand -c "import pandas, numpy, matplotlib, seaborn, scipy, sklearn" 2>$null
        if ($LASTEXITCODE -eq 0) { $edaPy = $cand; if (-not $featuresPy) { $featuresPy = $cand }; break }
        if (-not $featuresPy) {
            & $cand -c "import pandas, numpy" 2>$null
            if ($LASTEXITCODE -eq 0) { $featuresPy = $cand }
        }
    }
    if (-not $featuresPy) {
        Write-Host "`n  No python with pandas/numpy found -- pip install -r analysis\requirements.txt first." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $dirs.Analysis)) { New-Item -ItemType Directory -Force -Path $dirs.Analysis | Out-Null }
    $windowedOut = Join-Path $dirs.Analysis 'windowed_dataset.csv'
    $featOut     = Join-Path $dirs.Analysis 'feature_table.csv'
    $edaOut      = Join-Path $dirs.Analysis 'eda_output'

    Write-Host ""
    Write-Host ("Running: python analysis\preprocess.py {0} -o {1}" -f $inputDir, $windowedOut) -ForegroundColor DarkGray
    Write-Host ("     ->  python analysis\features.py {0} -o {1}" -f $inputDir, $featOut) -ForegroundColor DarkGray
    if ($edaPy) {
        Write-Host ("     ->  python analysis\eda.py {0} -o {1}" -f $featOut, $edaOut) -ForegroundColor DarkGray
    } else {
        Write-Host "     ->  (EDA/M8 skipped -- $featuresPy lacks matplotlib/seaborn/scipy/scikit-learn)" -ForegroundColor DarkGray
    }
    $goAns = Read-Line "`nRun this now? [Y/n] > "
    if ($goAns -eq 'n' -or $goAns -eq 'N') { Write-Host "  Skipped." -ForegroundColor DarkGray; return }

    Push-Location (Join-Path $base 'analysis')
    try {
        Write-Host "`nM6: preprocess.py ..." -ForegroundColor Cyan
        & $featuresPy preprocess.py $inputDir -o $windowedOut
        if ($LASTEXITCODE -ne 0) { Write-Host "Preprocess failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }

        Write-Host "M7: features.py ..." -ForegroundColor Cyan
        & $featuresPy features.py $inputDir -o $featOut
        if ($LASTEXITCODE -ne 0) { Write-Host "Features step failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }

        if ($edaPy) {
            Write-Host "M8: eda.py ..." -ForegroundColor Cyan
            & $edaPy eda.py $featOut -o $edaOut
            if ($LASTEXITCODE -ne 0) {
                Write-Host "EDA failed (exit $LASTEXITCODE); feature_table.csv is fine, see the error above." -ForegroundColor Yellow
            } else {
                Write-Host ("Done -> analysis\$($dirs.AttackDir)\$($dirs.TopoDir)\$rLocation\eda_output\") -ForegroundColor Green
            }
        } else {
            Write-Host "Skipping M8/EDA: $featuresPy lacks matplotlib/seaborn/scipy/scikit-learn." -ForegroundColor Yellow
            Write-Host "  Fix once: pip install -r analysis\requirements.txt" -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
}

function Invoke-TrimOnly {
    # Standalone tools\trim_run.py step, kept OUT of Invoke-RunAnalysisOnly so
    # trimming stays a deliberate, visible step. "Run analysis only" picks up
    # the trimmed\ folder this writes (see Select-AnalysisInput).
    #
    # --apply only, never --in-place: trim_run.py's own default already writes
    # trimmed COPIES into a trimmed\ subfolder and leaves the raw export
    # byte-for-byte alone (see tools\trim_run.py's own SAFETY section) - nothing
    # extra is needed here to keep the raw dataset intact.
    # Mirrors menu.ps1's "Trim exported CSVs only" action - keep the two in sync.
    Write-Host ""
    Write-Host "Nothing here touches a board or a COM port -- runs tools\trim_run.py --apply" -ForegroundColor DarkGray
    Write-Host "over an already-exported folder. Writes to a trimmed\ subfolder; the raw" -ForegroundColor DarkGray
    Write-Host "export is never modified or deleted." -ForegroundColor DarkGray

    $attackIdx   = Show-Menu -Title 'Which attack?' -Options @('none (baseline)', 'blackhole', 'wormhole') -DefaultIndex 0
    $rAttack     = @('none', 'blackhole', 'wormhole')[$attackIdx]
    $topoIdx     = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex 0
    $rTopology   = $TOPOLOGIES[$topoIdx]
    $scenarioIdx = Show-Menu -Title 'Scenario (what this capture used, if any):' -Options $SCENARIO_LABELS -DefaultIndex 0
    $rScenario   = $SCENARIOS[$scenarioIdx]
    $locationIdx = Show-Menu -Title 'Location:' -Options $LOCATIONS -DefaultIndex 0
    $rLocation   = $LOCATIONS[$locationIdx]

    $dirs = Get-RunDirs -Attack $rAttack -Topology $rTopology -Location $rLocation -Scenario $rScenario
    if (-not (Test-Path $dirs.Export)) {
        Write-Host ("`n  {0} doesn't exist -- export a board or import a card for this run first." -f $dirs.Export) -ForegroundColor Yellow
        return
    }

    $trimmedDir = Join-Path $dirs.Export 'trimmed'
    Write-Host ""
    Write-Host ("Running: python tools\trim_run.py {0} --apply" -f $dirs.Export) -ForegroundColor DarkGray
    Write-Host ("     ->  {0}" -f $trimmedDir) -ForegroundColor DarkGray
    $goAns = Read-Line "`nRun this now? [Y/n] > "
    if ($goAns -eq 'n' -or $goAns -eq 'N') { Write-Host "  Skipped." -ForegroundColor DarkGray; return }

    Push-Location $base
    try {
        python (Join-Path $base 'tools\trim_run.py') $dirs.Export --apply
        if ($LASTEXITCODE -ne 0) { Write-Host "Trim failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }
        Write-Host ("`nDone -> {0}" -f $trimmedDir) -ForegroundColor Green
        Write-Host "  'Run analysis only' will offer this trimmed\ folder as its input." -ForegroundColor DarkGray
    } finally { Pop-Location }
}

function Invoke-DataSync {
    # tools\push_data.py does all git work in a private clone, so this folder's
    # code/staged changes/stash are never touched. Mirrors menu.ps1's data-sync
    # actions - keep the two in sync.
    param([ValidateSet('push', 'pull', 'test')][string]$Mode, [ValidateSet('exports', 'presets')][string]$Area = 'exports')
    $py = Join-Path $base 'tools\push_data.py'
    Write-Host ""
    if ($Mode -eq 'test') {
        Write-Host "Makes 3 dummy CSVs (10 rows: Animal, Sex) under sync_test\<this computer>\ and pushes" -ForegroundColor DarkGray
        Write-Host "them the same way real data is pushed. Run it on a second laptop too (without" -ForegroundColor DarkGray
        Write-Host "pulling first) - both computers' files must end up on GitHub." -ForegroundColor DarkGray
    } elseif ($Area -eq 'presets') {
        if ($Mode -eq 'pull') {
            Write-Host "Copies teammates' saved presets from GitHub into presets\<them>\ (never code). Lists them" -ForegroundColor DarkGray
            Write-Host "and asks first; a preset you already have is never overwritten. Pushes nothing." -ForegroundColor DarkGray
        } else {
            Write-Host "Pushes your saved presets under presets\<you>\ (never code, never capture data)." -ForegroundColor DarkGray
            Write-Host "Shows what will go up and asks before pushing, then offers teammates' new presets." -ForegroundColor DarkGray
        }
    } elseif ($Mode -eq 'pull') {
        Write-Host "Copies teammates' capture CSVs from GitHub into tools\exports\ (never code). Lists them and" -ForegroundColor DarkGray
        Write-Host "asks first; a file you already have is never overwritten. Pushes nothing." -ForegroundColor DarkGray
    } else {
        Write-Host "Pushes raw capture CSVs under tools\exports\ (never code, never trimmed\ or analysis\)." -ForegroundColor DarkGray
        Write-Host "Shows what will go up and asks before pushing, then offers teammates' new files." -ForegroundColor DarkGray
    }
    Push-Location $base
    try {
        python $py $Mode --area $Area
        if ($LASTEXITCODE -ne 0) { Write-Host "Data sync failed (exit $LASTEXITCODE) - see the message above." -ForegroundColor Red; return }
        if ($Mode -eq 'test') {
            $ans = Read-Line "`nRemove ALL test files from GitHub now? Say n if a teammate still has to run the test. [y/N] > "
            if ($ans -eq 'y' -or $ans -eq 'Y') {
                python $py test-cleanup --yes
                if ($LASTEXITCODE -ne 0) { Write-Host "Cleanup failed (exit $LASTEXITCODE)." -ForegroundColor Red }
            }
        }
    } finally { Pop-Location }
}

function Invoke-DataSyncMenu {
    # The push_data.py actions live behind one main-menu entry instead of several,
    # so the main menu stays scannable. Loops so a push can be followed by a pull
    # (or a presets upload) without going back out to the main menu first.
    while ($true) {
        switch (Show-Menu -Title 'Capture data sync (GitHub) - raw CSVs and presets only, never code:' -Options @(
            "Push my capture data to GitHub - merges with teammates' pushes",
            "Pull teammates' capture data from GitHub - never overwrites your files",
            "Upload my saved presets to GitHub - shares presets\<you>\*.json, fetches teammates' new ones back too",
            'Test the sync - push 3 dummy animal CSVs to prove two laptops never overwrite each other',
            'Back to the main menu'
        ) -DefaultIndex 4) {
            0 { Invoke-DataSync -Mode push -Area exports }
            1 { Invoke-DataSync -Mode pull -Area exports }
            2 { Invoke-DataSync -Mode push -Area presets }
            3 { Invoke-DataSync -Mode test }
            4 { return }
        }
    }
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

function Resolve-BoardMac {
    # Best-effort MAC for the final confirm table: prefer what's already known
    # (a preset that recorded it, or this session's Invoke-Identify cache) over
    # reading the chip again - both Get-BoardMac and Invoke-Identify briefly
    # reset the board, and every board here is about to be flashed anyway so a
    # fresh read is harmless, but a cached value is free. Skips the live read
    # under -SkipMacCheck/-DryRun, same gate the attacker-MAC precheck uses, so
    # neither flag still touches a single board. Caches a fresh read back onto
    # $Board.Mac so a later "record MACs into the preset?" step doesn't re-read.
    param($Board, [switch]$SkipLiveRead)
    if ($Board.Mac) { return $Board.Mac }
    if ($script:IdentifiedPorts.ContainsKey($Board.Port)) {
        $cached = $script:IdentifiedPorts[$Board.Port]
        $mac = ($cached -split ' -> ')[0].Trim()
        if ($mac -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { return $mac.ToLower() }
    }
    if ($SkipLiveRead) { return $null }
    $mac = Get-BoardMac -TargetPort $Board.Port
    if ($mac) {
        # Caching is a convenience; it must never be able to END A RUN. A
        # PSCustomObject cannot gain a property by assignment, so a board built
        # without a Mac field threw here - at the confirm table, i.e. AFTER every
        # question was answered and after the attacker-MAC gate had already
        # rewritten mesh_config.h. Every construction site now seeds Mac = '',
        # and this stays defensive so re-introducing that gap costs a re-read
        # instead of the whole session.
        if ($Board.PSObject.Properties['Mac']) { $Board.Mac = $mac }
        else { $Board | Add-Member -NotePropertyName Mac -NotePropertyValue $mac -Force }
    }
    return $mac
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

function Invoke-DeleteSdFolder {
    # PERMANENT delete of a folder on a running board's SD card (DELETE_SD_PATH in
    # csv_logger.c), e.g. blackhole > linear > G402. Same serial path and same
    # "board must already be booted" requirement as Set-SdLocation. The operator
    # has to type DELETE per folder - no bulk option on purpose.
    $sdAttackDirs = @('baseline', 'blackhole', 'wormhole')
    $sdTopoDirs   = @('linear', 'tree', 'star', 'partial_mesh')

    while ($true) {
        $ports = @(Get-PortList)
        $portOpts = @($ports | ForEach-Object {
            $tag = ''
            if ($script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [{0}]" -f $script:IdentifiedPorts[$_.Port] }
            "{0,-7} - {1}{2}{3}" -f $_.Port, $_.Description, $tag, (Format-PortKindTag $_.Kind)
        })
        $portOpts += 'Type a port manually'
        $portOpts += 'Done - back to the main menu'

        Write-Host ""
        Write-Host "The board must already be booted with its SD card in (same as writing location.txt)." -ForegroundColor DarkGray
        $pIdx = Show-Menu -Title 'Delete a folder from the SD card of which ALREADY-RUNNING board?' -Options $portOpts -DefaultIndex -1
        if ($pIdx -eq $portOpts.Count - 1) { return }

        $target = $null
        if ($pIdx -eq $portOpts.Count - 2) {
            $manual = Read-Line '  Port (e.g. COM20) > '
            if ($manual) { $target = $manual.Trim().ToUpper() }
        }
        else { $target = $ports[$pIdx].Port }
        if (-not $target) { continue }
        if (-not (Test-PortSafeToTouch -Port $target -Action 'delete a folder on its SD card')) { continue }

        $aIdx = Show-Menu -Title 'Attack folder:' -Options (@($sdAttackDirs) + @('Cancel')) -DefaultIndex -1
        if ($aIdx -eq $sdAttackDirs.Count) { continue }
        $parts = @($sdAttackDirs[$aIdx])

        $tIdx = Show-Menu -Title ("Topology folder inside {0}:" -f $parts[0]) -Options (@($sdTopoDirs) + @(
            ("ALL of {0} (delete the whole {0} folder)" -f $parts[0]), 'Cancel')) -DefaultIndex -1
        if ($tIdx -eq $sdTopoDirs.Count + 1) { continue }
        if ($tIdx -lt $sdTopoDirs.Count) {
            $parts += $sdTopoDirs[$tIdx]

            $lIdx = Show-Menu -Title ("Location folder inside {0}:" -f ($parts -join ' > ')) -Options (@($LOCATIONS) + @(
                ("ALL of {0} (delete the whole {1} folder)" -f ($parts -join ' > '), $parts[1]), 'Cancel')) -DefaultIndex -1
            if ($lIdx -eq $LOCATIONS.Count + 1) { continue }
            if ($lIdx -lt $LOCATIONS.Count) { $parts += $LOCATIONS[$lIdx] }
        }

        $relPath = $parts -join '/'
        Write-Host ""
        Write-Host ("  {0}: DELETE {1}  (and everything inside it)" -f $target, ($parts -join ' > ')) -ForegroundColor Red
        Write-Host "  This is PERMANENT - the CSVs on the card cannot be recovered afterwards." -ForegroundColor Red
        Write-Host "  Import anything you still need from this card first." -ForegroundColor Yellow

        if ($DryRun) {
            Write-Host "`nDRY RUN - would send DELETE_SD_PATH=$relPath to $target here." -ForegroundColor Yellow
            continue
        }

        $confirm = Read-Line "  Proceed? [y/N] > "
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "  Cancelled - nothing deleted." -ForegroundColor DarkGray
            continue
        }

        Write-Host ("`n  {0} DELETE_SD_PATH={1} ..." -f $target, $relPath) -ForegroundColor DarkGray
        Push-Location (Join-Path $base 'tools')
        try {
            # Under the script-wide 'Stop', PS 5.1 turns the first stderr line into
            # an exception and drops the rest - including the failure hint.
            $ErrorActionPreference = 'Continue'
            $out = & python -u export_logs.py --port $target --delete-sd-path $relPath 2>&1
            $color = if ($LASTEXITCODE -eq 0) { 'Green' } else { 'Yellow' }
            foreach ($line in @($out)) { Write-Host ("    " + "$line") -ForegroundColor $color }
        }
        catch { Write-Host ("    " + $_.Exception.Message) -ForegroundColor Yellow }
        finally { Pop-Location }
    }
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

function Set-AttackSubRoles {
    # Interactive "who holds the attacker / Node A / Node B seat" picker among
    # the non-root boards in $Roster. Shared by Edit-BoardInteractive's 'Kind'
    # field (reassign just the seat) and its 'Role' field (a root swap needs
    # the exact same reassignment run against the new child set, so the
    # "exactly one attacker" / "exactly one A and one B" invariant can never
    # be left broken by either edit). A cancelled ('b' back) pick leaves
    # whatever the roster already had untouched.
    param([Parameter(Mandatory)]$Roster, [Parameter(Mandatory)][string]$Attack)

    $peers  = @($Roster | Where-Object { $_.Role -ne 'root' })
    if ($peers.Count -eq 0) { return }
    $labels = @($peers | ForEach-Object { "$($_.Label)  ($($_.Port))" })

    if ($Attack -eq 'blackhole') {
        $pickIdx = Show-Menu -Title "Which board is the BLACKHOLE ATTACKER? (exactly one)" -Options $labels -AllowBack
        if ($pickIdx -ge 0) {
            for ($ci = 0; $ci -lt $peers.Count; $ci++) {
                if ($ci -eq $pickIdx) { $peers[$ci].Kind = 'attacker'; $peers[$ci].Display = 'blackhole ATTACKER' }
                else                  { $peers[$ci].Kind = 'victim';   $peers[$ci].Display = 'blackhole victim' }
            }
        }
    }
    elseif ($Attack -eq 'wormhole') {
        $idxA = Show-Menu -Title "Which board is WORMHOLE Node A (exit / re-injects to root)?" -Options $labels -AllowBack
        if ($idxA -ge 0) {
            $idxB = -1
            while ($true) {
                $idxB = Show-Menu -Title "Which board is WORMHOLE Node B (entry / captures + tunnels)?" -Options $labels -AllowBack
                if ($idxB -eq -1 -or $idxB -ne $idxA) { break }
                Write-Host "   Node B must be a different board from Node A." -ForegroundColor Yellow
            }
            if ($idxB -ge 0) {
                for ($ci = 0; $ci -lt $peers.Count; $ci++) {
                    if     ($ci -eq $idxA) { $peers[$ci].Kind = 'A'; $peers[$ci].Display = 'wormhole Node A (exit)' }
                    elseif ($ci -eq $idxB) { $peers[$ci].Kind = 'B'; $peers[$ci].Display = 'wormhole Node B (entry)' }
                    else                    { $peers[$ci].Kind = 'control'; $peers[$ci].Display = 'control (plain firmware)' }
                }
            }
        }
    }
}

function Edit-BoardInteractive {
    # Per-node edit reached from the pre-flash plan summary (same purpose as
    # menu.ps1's function of the same name; a separate implementation since the
    # two scripts' board/roster models differ). Always operates on ONE LOCAL
    # board from $Roster (== $runRoster -- remote/multi-laptop boards never
    # reach it and aren't editable here). A blackhole/wormhole role change
    # reassigns every LOCAL peer the same way step 8 above does (attacker/
    # victim, or A/B/control), so the "exactly one attacker" / "exactly one A
    # and one B" invariant can never be left broken by an edit. -HasRemoteAttackRole
    # hides that field entirely when the attacker/A/B seat is on another laptop --
    # reassigning it among local boards only would create a second one instead
    # of moving it.
    param(
        [Parameter(Mandatory)][pscustomobject]$Board,
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)][string]$Attack,
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)][object[]]$Ports,
        [bool]$HasRemoteAttackRole = $false
    )

    while ($true) {
        Write-Host ""
        Write-Host ("Editing node: {0}  ({1}, {2})" -f $Board.Label, $Board.Port, $Board.Display) -ForegroundColor Cyan

        $fields = @()
        $fields += @{ Key = 'Role';  Text = "Role               $($Board.Role)" }
        $fields += @{ Key = 'Label'; Text = "Label              $($Board.Label)" }
        $fields += @{ Key = 'Port';  Text = "Port               $($Board.Port)" }
        if ($Board.Role -ne 'root' -and $Attack -in @('blackhole', 'wormhole') -and -not $HasRemoteAttackRole) {
            $fields += @{ Key = 'Kind'; Text = "Attack role        $($Board.Display)" }
        }
        if ((Test-ScenarioNeedsTarget $Scenario) -and $Board.Role -ne 'root') {
            $onOff = if ($Board.ScenarioTarget) { 'Yes' } else { 'No' }
            $fields += @{ Key = 'ScenarioTarget'; Text = "Scenario target    $onOff" }
        }

        $opts = @($fields | ForEach-Object { $_.Text })
        $opts += 'Done editing this node'
        $idx = Show-Menu -Title "Which field?" -Options $opts -DefaultIndex ($opts.Count - 1)
        if ($idx -eq -1 -or $idx -eq ($opts.Count - 1)) { break }

        switch ($fields[$idx].Key) {
            'Role' {
                # Exactly one root, always -- so "change this board's role" is
                # really "pick which board should be root": promoting one
                # implicitly demotes whichever board holds it now.
                $opts2 = @($Roster | ForEach-Object {
                    $tag = if ($_.Role -eq 'root') { '  (current root)' } else { '' }
                    "$($_.Label)  ($($_.Port))$tag"
                })
                $curRootIdx = 0
                for ($ri = 0; $ri -lt $Roster.Count; $ri++) { if ($Roster[$ri].Role -eq 'root') { $curRootIdx = $ri } }
                $newRootIdx = Show-Menu -Title "Which board should be ROOT?" -Options $opts2 -DefaultIndex $curRootIdx
                if ($newRootIdx -ge 0) {
                    $newRoot = $Roster[$newRootIdx]
                    if ($newRoot.Role -eq 'root') {
                        Write-Host "   Already root -- unchanged." -ForegroundColor Yellow
                    } else {
                        $oldRoot = $Roster | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1
                        if ($oldRoot) {
                            $oldRoot.Role = 'child'
                            # Safe default Kind for this attack type -- overwritten
                            # below by Set-AttackSubRoles whenever that runs; this
                            # is what the demoted board is left with when it
                            # doesn't (HasRemoteAttackRole -- the seat isn't local).
                            # 'plain' is only correct for a baseline (attack=none)
                            # run; using it under blackhole/wormhole would build
                            # this board as an uninvolved baseline child while root
                            # still announces the attack phase.
                            if     ($Attack -eq 'blackhole') { $oldRoot.Kind = 'victim';  $oldRoot.Display = 'blackhole victim' }
                            elseif ($Attack -eq 'wormhole')  { $oldRoot.Kind = 'control'; $oldRoot.Display = 'control (plain firmware)' }
                            else                               { $oldRoot.Kind = 'plain';   $oldRoot.Display = 'plain child' }
                        }
                        $newRoot.Role = 'root'
                        $newRoot.Kind = 'root'
                        $newRoot.Display = 'ROOT (announces the phases)'
                        $newRoot.ScenarioTarget = $false

                        $oldLbl = if ($oldRoot) { $oldRoot.Label } else { '(none)' }
                        Write-Host ("   {0} is now ROOT; {1} is now a child." -f $newRoot.Label, $oldLbl) -ForegroundColor Green

                        if ($Attack -in @('blackhole', 'wormhole') -and -not $HasRemoteAttackRole) {
                            Write-Host "   Reassign the attack sub-role among the new child set:" -ForegroundColor DarkGray
                            Set-AttackSubRoles -Roster $Roster -Attack $Attack
                        }
                    }
                }
            }
            'Label' {
                $new = Read-Line "New label > [$($Board.Label)] "
                if ($new) {
                    if (@($Roster | Where-Object { $_ -ne $Board } | ForEach-Object { $_.Label }) -contains $new) {
                        Write-Host "   That label is already used by another board -- unchanged." -ForegroundColor Yellow
                    } else {
                        $Board.Label = $new
                    }
                }
            }
            'Port' {
                $taken = @($Roster | Where-Object { $_ -ne $Board -and $_.Port } | ForEach-Object { $_.Port })
                $new = Select-Port -For $Board.Label -Ports $Ports -Taken $taken
                if ($new -and $new -ne $script:BackSignal) { $Board.Port = $new }
            }
            'Kind' {
                Set-AttackSubRoles -Roster $Roster -Attack $Attack
            }
            'ScenarioTarget' {
                if ($Board.ScenarioTarget) {
                    $Board.ScenarioTarget = $false
                    $Board.Display = $Board.Display -replace ' \+ .* TARGET$', ''
                } else {
                    $eligible = if ($Scenario -eq 'burst') { @($Roster | Where-Object { Test-BurstEligible $_ }) } else { @($Roster | Where-Object { $_.Role -ne 'root' }) }
                    if ($eligible -notcontains $Board) {
                        Write-Host "   This board can't carry the $Scenario scenario (wrong attack role for it)." -ForegroundColor Yellow
                    } else {
                        foreach ($c in $Roster) {
                            $c.ScenarioTarget = $false
                            $c.Display = $c.Display -replace ' \+ .* TARGET$', ''
                        }
                        $Board.ScenarioTarget = $true
                        $Board.Display += " + $($Scenario.ToUpper()) TARGET"
                    }
                }
            }
        }
    }
}

function Add-BoardInteractive {
    # Counterpart to Remove-BoardInteractive, reached from the same pre-flash
    # "Adjust the plan?" menu - see [[thesis_cc_wizard_hardware_safety]], same
    # "one explicit node at a time" convention as Edit-BoardInteractive. Picks
    # a port the same way the original manual roster builder does
    # (Select-Port, -Taken hides ports already in $Roster). $Roster is a
    # fixed-size PowerShell array, so this can't append in place - it returns
    # the updated roster (a NEW array) and the caller reassigns $runRoster
    # with it, same contract as Remove-BoardInteractive.
    param(
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)][string]$Attack,
        [Parameter(Mandatory)][object[]]$Ports
    )

    $taken     = @($Roster | Where-Object { $_.Port } | ForEach-Object { $_.Port })
    $suggested = Get-FreeNodeLabel -Taken @($Roster | ForEach-Object { $_.Label })
    $raw = Read-Line "New node label > [$suggested] (or 'b' back) "
    if (Test-BackAnswer $raw) { return $Roster }
    $label = if (-not $raw) { $suggested } else { $raw.Trim() }
    if (@($Roster | ForEach-Object { $_.Label }) -contains $label) {
        Write-Host "   '$label' is already taken - node not added." -ForegroundColor Yellow
        return $Roster
    }

    $port = Select-Port -For $label -Ports $Ports -AllowBack -Taken $taken
    if ($port -eq $script:BackSignal) { return $Roster }

    # New nodes join as the "uninvolved" seat for this attack (plain victim /
    # control) rather than attacker/A/B - promoting straight to a sub-role that
    # must stay unique is what the confirm below is for, not the default.
    $kind = 'plain'; $display = 'plain child'
    if ($Attack -eq 'blackhole') { $kind = 'victim'; $display = 'blackhole victim' }
    elseif ($Attack -eq 'wormhole') { $kind = 'control'; $display = 'control (plain firmware)' }

    $newBoard = [pscustomobject]@{
        Label = $label; Port = $port; Role = 'child'; Kind = $kind
        Display = $display; ScenarioTarget = $false
        Mac = ''   # same field set as every other board - Resolve-BoardMac writes here
    }
    Write-Host ("   Added {0} on {1} ({2})." -f $label, $port, $display) -ForegroundColor Green

    $updated = @($Roster) + $newBoard
    if ($Attack -in @('blackhole', 'wormhole')) {
        $ans = Read-Line "   Make this node the attack sub-role instead (reassign attacker/A/B)? [y/N] > "
        if ($ans -eq 'y' -or $ans -eq 'Y') { Set-AttackSubRoles -Roster $updated -Attack $Attack }
    }
    return $updated
}

function Remove-BoardInteractive {
    # Counterpart to Add-BoardInteractive. Refuses to remove the ROOT outright
    # (see Edit-BoardInteractive's 'Role' field for the deliberate way to hand
    # root to another board first) and refuses a removal that would break the
    # "exactly one attacker" / "exactly one A and one B" invariant a blackhole/
    # wormhole run depends on downstream. Returns the updated roster (a NEW
    # array, same reason as Add-BoardInteractive) or the original $Roster
    # unchanged if the operator backs out or the removal is refused.
    param(
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)][string]$Attack,
        [Parameter(Mandatory)][string]$Scenario
    )

    if (@($Roster).Count -le 1) {
        Write-Host "   Only one node left - nothing to remove." -ForegroundColor Yellow
        return $Roster
    }

    $opts = @($Roster | ForEach-Object { "$($_.Label)  ($($_.Port), $($_.Display))" })
    $idx = Show-Menu -Title "Remove which node?" -Options $opts -AllowBack
    if ($idx -eq -1) { return $Roster }

    $victim = $Roster[$idx]
    if ($victim.Role -eq 'root') {
        Write-Host "   Can't remove the ROOT directly - edit that node's Role to hand root to another board first, then remove it." -ForegroundColor Yellow
        return $Roster
    }

    $remaining         = @($Roster | Where-Object { $_ -ne $victim })
    $remainingChildren = @($remaining | Where-Object { $_.Role -ne 'root' })

    if ($Attack -eq 'blackhole' -and $remainingChildren.Count -lt 2) {
        Write-Host "   Blackhole needs at least one attacker AND one victim - removing $($victim.Label) would leave too few children. Not removed." -ForegroundColor Yellow
        return $Roster
    }
    if ($Attack -eq 'wormhole' -and $remainingChildren.Count -lt 2) {
        Write-Host "   Wormhole needs both a Node A AND a Node B - removing $($victim.Label) would leave too few children. Not removed." -ForegroundColor Yellow
        return $Roster
    }

    $ans = Read-Line ("   Remove {0} ({1})? [y/N] > " -f $victim.Label, $victim.Port)
    if ($ans -ne 'y' -and $ans -ne 'Y') { return $Roster }

    $wasSubRole = $victim.Kind -in @('attacker', 'A', 'B')
    $wasTarget  = [bool]$victim.ScenarioTarget
    Write-Host ("   Removed {0}." -f $victim.Label) -ForegroundColor Green

    if ($wasSubRole -and $Attack -in @('blackhole', 'wormhole')) {
        Write-Host "   That node held the attack sub-role - reassign it among what's left:" -ForegroundColor DarkGray
        Set-AttackSubRoles -Roster $remaining -Attack $Attack
    }

    if ($wasTarget -and (Test-ScenarioNeedsTarget $Scenario)) {
        $eligible = if ($Scenario -eq 'burst') { @($remainingChildren | Where-Object { Test-BurstEligible $_ }) } else { @($remainingChildren) }
        if ($eligible.Count -eq 0) {
            Write-Host "   That node was the $Scenario target and no remaining child can carry it - pick a different scenario, or add a node before confirming." -ForegroundColor Yellow
        } else {
            $labels = @($eligible | ForEach-Object { "$($_.Label)  ($($_.Port))  -  $($_.Display)" })
            $tIdx = Show-Menu -Title "Which node is now the $Scenario TARGET? (exactly one)" -Options $labels -DefaultIndex 0
            if ($tIdx -ge 0) {
                $eligible[$tIdx].ScenarioTarget = $true
                $eligible[$tIdx].Display += " + $($Scenario.ToUpper()) TARGET"
            }
        }
    }

    return $remaining
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

function Get-PresetRoot { return (Join-Path $base 'presets') }

function Get-PresetMemberNames {
    # The member list member_boards.json is keyed by (Cal / Bas / Kyle), which is
    # what the per-member preset folders are named after. Falls back to the fixed
    # list in Show-MemberBoards.ps1 when that file is missing or unreadable, so
    # the preset folders never depend on the roster file being present.
    if ($script:BoardMembers) { return @($script:BoardMembers) }
    return @('Cal', 'Bas', 'Kyle')
}

function Get-MyMemberPath { return (Join-Path $base 'my_member.txt') }

function Get-MyMember {
    # Which member THIS laptop belongs to - the only thing that cannot be
    # derived from the files themselves, since every laptop sees the same
    # presets\ tree. Stored in its own one-line file rather than as a key in
    # member_boards.json, because Save-MemberBoardData rebuilds that file from
    # _help + members only and would silently drop any extra key on the next
    # board-list edit.
    $p = Get-MyMemberPath
    if (-not (Test-Path $p)) { return '' }
    try { $v = (Get-Content -Raw -Path $p -ErrorAction Stop).Trim() } catch { return '' }
    if ($v -and (Get-PresetMemberNames) -contains $v) { return $v }
    return ''
}

function Set-MyMember {
    param([string]$Name)
    [System.IO.File]::WriteAllText((Get-MyMemberPath), $Name, (New-Object System.Text.UTF8Encoding $false))
}

function Select-MyMember {
    # Asked once, then remembered. Returns '' if the operator backs out - callers
    # treat that as "no owner known" rather than guessing a name.
    param([switch]$Force)
    $mine = Get-MyMember
    if ($mine -and -not $Force) { return $mine }

    $names = @(Get-PresetMemberNames)
    Write-Host ""
    Write-Host "Whose laptop is this? (used to put YOUR presets first, and to file new ones)" -ForegroundColor Cyan
    Write-Host "  Stored in my_member.txt - change it any time from the member board list menu." -ForegroundColor DarkGray
    $opts = @($names) + @('Skip - do not remember')
    $idx = Show-Menu -Title 'This laptop belongs to:' -Options $opts -DefaultIndex ([Math]::Max(0, $names.IndexOf($mine)))
    if ($idx -ge $names.Count) { return '' }
    Set-MyMember -Name $names[$idx]
    Write-Host ("  Remembered: {0}" -f $names[$idx]) -ForegroundColor Green
    return $names[$idx]
}

function Get-PresetOwnerFromPath {
    # A preset's owner is the member folder it sits in: presets\<Member>\x.json.
    # Loose files directly under presets\ predate the split and have no owner.
    param([string]$FullName)
    $root = [System.IO.Path]::GetFullPath((Get-PresetRoot)).TrimEnd('\')
    $dirName = [System.IO.Path]::GetFullPath((Split-Path $FullName -Parent)).TrimEnd('\')
    if ($dirName -eq $root) { return '' }
    $leaf = Split-Path $dirName -Leaf
    if ((Get-PresetMemberNames) -contains $leaf) { return $leaf }
    return $leaf
}

function Get-PresetFiles {
    # Newest first - the preset you used last is almost always the one you want.
    #
    # Recurses, because presets are filed one folder per member:
    # presets\Bas\linear-blackhole-none-g402.json. The filename already spells
    # the experiment cell (topology-attack-scenario-location), so the ONE thing
    # it cannot express is whose boards the roster describes - and two members'
    # preset for the same cell collide on name. The folder carries the owner so
    # both keep the plain cell name, instead of one being hand-renamed
    # '...-kyle.json' and the pair becoming indistinguishable a week later.
    #
    # Each item gets an .Owner note property ('' for a loose pre-split file
    # still sitting directly under presets\); everything else about the object
    # is the FileInfo callers already use (.FullName / .Name / .LastWriteTime).
    $dir = Get-PresetRoot
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem -Path $dir -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $_ | Add-Member -NotePropertyName Owner -NotePropertyValue (Get-PresetOwnerFromPath -FullName $_.FullName) -Force -PassThru
        })
}

function Format-PresetOwner {
    param([string]$Owner)
    if ($Owner) { return $Owner }
    return '(unfiled)'
}

function Find-PresetOwnerByMac {
    # Guesses whose boards a roster describes by matching its MACs against
    # member_boards.json. That file stores either a full MAC or just the
    # first:last byte pair ("20:38"), and a preset stores the full MAC, so the
    # comparison is on those two bytes - the same shortening Format-ShortMac
    # already displays. Returns the member with the most matching boards, or ''
    # when nothing matches (no MACs recorded yet, someone else's boards).
    param($Roster)
    if (-not (Get-Command Read-MemberBoardData -ErrorAction SilentlyContinue)) { return '' }
    $data = $null
    try { $data = Read-MemberBoardData -Path (Join-Path $base 'member_boards.json') } catch { return '' }
    if (-not $data) { return '' }

    $shorten = {
        param([string]$Mac)
        $m = ([string]$Mac).Trim().ToLower() -replace '[^0-9a-f]', ''
        if ($m.Length -ge 12) { return ('{0}:{1}' -f $m.Substring(0, 2), $m.Substring(10, 2)) }
        if ($m.Length -eq 4)  { return ('{0}:{1}' -f $m.Substring(0, 2), $m.Substring(2, 2)) }
        return ''
    }

    $rosterMacs = @($Roster | ForEach-Object { & $shorten $_.Mac } | Where-Object { $_ })
    if ($rosterMacs.Count -eq 0) { return '' }

    $best = ''
    $bestHits = 0
    foreach ($name in (Get-PresetMemberNames)) {
        # .Contains, not .ContainsKey: Read-MemberBoardData builds Members as
        # [ordered]@{}, and OrderedDictionary has no ContainsKey on PS 5.1.
        if (-not $data.Members.Contains($name)) { continue }
        $their = @($data.Members[$name] | ForEach-Object { & $shorten $_.mac } | Where-Object { $_ })
        $hits = @($rosterMacs | Where-Object { $their -contains $_ }).Count
        if ($hits -gt $bestHits) { $bestHits = $hits; $best = $name }
    }
    return $best
}

function Select-PresetOwner {
    # Whose boards is this preset for? Defaults to whatever the MACs say, then
    # to this laptop's member - so the absent-member case (you flashing Kyle's
    # boards) files itself correctly without you having to remember to say so.
    param($Roster, [string]$Title = 'Whose boards is this preset for?')
    $names = @(Get-PresetMemberNames)
    $detected = Find-PresetOwnerByMac -Roster $Roster
    $mine     = Get-MyMember
    $default  = if ($detected) { $detected } elseif ($mine) { $mine } else { $names[0] }

    $opts = @($names | ForEach-Object {
        $tags = @()
        if ($_ -eq $detected) { $tags += 'MACs match this member' }
        if ($_ -eq $mine)     { $tags += 'this laptop' }
        if ($tags.Count -gt 0) { "{0}  ({1})" -f $_, ($tags -join ', ') } else { $_ }
    })
    $opts += 'Leave unfiled (save straight into presets\)'

    $idx = Show-Menu -Title $Title -Options $opts -DefaultIndex ([Math]::Max(0, $names.IndexOf($default)))
    if ($idx -ge $names.Count) { return '' }
    return $names[$idx]
}

# ESP-IDF's monitor colorizes I/W/E log-level tags with ANSI SGR escapes
# (ESC[0;32m ... ESC[0m). Start-Transcript can capture those bytes verbatim
# depending on the machine/terminal that ran the capture, and replaying them
# through Write-Host on a console without VT processing turns them into
# mojibake fragments (stray box characters with a trailing "32m") instead of
# the plain readable text ESP-IDF prints. Strips them for DISPLAY only - the
# .log file on disk is never touched.
$script:AnsiEscapeRegex = [regex]::new([char]27 + '\[[0-9;]*[a-zA-Z]')
function Remove-AnsiEscapes {
    param([string]$Line)
    if ($null -eq $Line) { return $Line }
    return $script:AnsiEscapeRegex.Replace($Line, '')
}

function Invoke-ViewRunLog {
    # Reads run_logs\*.log - the console transcripts a run saves when the
    # operator says yes to "Save a full log of this run" during a capture
    # (see the -saveRunLog block in the execute section below). Filenames use
    # the same base as the preset that drove the run (or the topology-attack-
    # scenario-location pattern when none was used), plus a timestamp, so a
    # log and its preset are easy to spot as a pair. No board/COM contact.
    $dir = Join-Path $base 'run_logs'
    if (-not (Test-Path $dir)) {
        Write-Host "`nNo run_logs\ folder yet - it's created the first time a run's log is saved." -ForegroundColor Yellow
        return
    }
    $files = @(Get-ChildItem -Path $dir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        Write-Host "`nNo saved run logs yet - run_logs\ is empty." -ForegroundColor Yellow
        return
    }

    $opts = @($files | ForEach-Object {
        "{0,-55} {1}  ({2:N0} KB)" -f $_.Name, $_.LastWriteTime.ToString('MMM dd HH:mm'), ($_.Length / 1KB)
    })
    $opts += 'Back'
    $idx = Show-Menu -Title 'View which run log?' -Options $opts -DefaultIndex 0
    if ($idx -eq $files.Count) { return }
    $file = $files[$idx]

    $picking = $true
    while ($picking) {
        switch (Show-Menu -Title "$($file.Name) - how do you want to view it?" -Options @(
            'Print the last 100 lines here (quick look for errors)',
            'Print the whole file here',
            'Open the full file in Notepad',
            'Delete this log',
            'Back'
        ) -DefaultIndex 0) {
            0 {
                Write-Host ""
                Get-Content -Path $file.FullName -Tail 100 -Encoding UTF8 |
                    ForEach-Object { Write-Host (Remove-AnsiEscapes $_) }
            }
            1 {
                Write-Host ""
                Get-Content -Path $file.FullName -Encoding UTF8 |
                    ForEach-Object { Write-Host (Remove-AnsiEscapes $_) }
            }
            2 { Start-Process notepad.exe $file.FullName }
            3 {
                $confirm = Read-Line "  Delete $($file.Name)? [y/N] > "
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    Remove-Item -Path $file.FullName -Force
                    Write-Host "  Deleted." -ForegroundColor Green
                    $picking = $false
                }
            }
            4 { $picking = $false }
        }
    }
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
    # $Owner is recorded in the file as well as in the folder name it lives in.
    # The folder is what the picker groups by; the field is what survives the
    # file being copied, emailed or pulled out of the tree, so a loose preset
    # can still say whose boards it describes. Omitted = keep whatever the file
    # already had (a re-save of an existing preset must not blank its owner).
    param([string]$Path, [string]$Attack, [string]$Topology, [string]$Location,
          [int]$RepeatNum, $Roster, [string]$Scenario = 'none', [string]$Owner)
    if (-not $PSBoundParameters.ContainsKey('Owner')) {
        $Owner = Get-PresetOwnerFromPath -FullName $Path
        if (-not $Owner) {
            $existing = Read-PresetFile -Path $Path
            if ($existing -and $existing.PSObject.Properties['owner']) { $Owner = [string]$existing.owner }
        }
    }
    $toSave = [pscustomobject]@{
        attack   = $Attack
        topology = $Topology
        location = $Location
        scenario = $Scenario
        owner    = $Owner
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

function Get-LiveMacMap {
    # port -> lowercase MAC for every plugged-in, non-BLOCKED port. Ports already
    # read this session (identify / identify ALL) come from that cache instead
    # of resetting the board again. Unreadable ports are left out of the map.
    param([object[]]$Ports)
    $map = @{}
    foreach ($p in @($Ports | Where-Object { $_.Kind -ne 'BLOCKED' })) {
        if ($script:IdentifiedPorts.ContainsKey($p.Port)) {
            $cached = ($script:IdentifiedPorts[$p.Port] -split ' -> ')[0].Trim()
            if ($cached -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') {
                $map[$p.Port] = $cached.ToLower()
                Write-Host ("  {0,-7} {1}  (already identified)" -f $p.Port, $map[$p.Port]) -ForegroundColor DarkGray
                continue
            }
        }
        if (-not (Test-PortSafeToTouch -Port $p.Port -Action 'reset it to read a MAC')) { continue }
        Write-Host ("  {0,-7} reading ..." -f $p.Port) -ForegroundColor DarkGray
        $mac = Get-BoardMac -TargetPort $p.Port
        if ($mac) {
            $map[$p.Port] = $mac
            $script:IdentifiedPorts[$p.Port] = "$mac -> (MAC read only)"
            Write-Host ("  {0,-7} {1}" -f $p.Port, $mac) -ForegroundColor Green
        }
        else {
            Write-Host ("  {0,-7} could not read (busy, not an ESP32, or esptool missing)" -f $p.Port) -ForegroundColor Yellow
        }
    }
    return $map
}

function Sync-RosterPortsByMac {
    # A COM number belongs to the USB SOCKET, not the board, so moving boards to
    # other sockets or a hub renumbers them. Every board with a recorded MAC is
    # moved to whichever live port now reports that MAC. Returns the boards that
    # still need a port picked by hand: no recorded MAC, MAC not found on any
    # port, or their old port is now occupied by a different preset board.
    # Changes $Roster in place (in memory only) and only after a [Y/n] preview.
    param($Roster, [object[]]$Ports)

    $recorded = @($Roster | Where-Object { $_.Mac -and $_.Port })
    if ($recorded.Count -eq 0) {
        Write-Host "  No board in this preset has a recorded MAC - ports have to be picked by hand." -ForegroundColor Yellow
        $liveNames = @($Ports | Select-Object -ExpandProperty Port)
        return [pscustomobject]@{ Applied = $false; Unresolved = @($Roster | Where-Object { $_.Port -and $liveNames -notcontains $_.Port }); MacMap = @{} }
    }

    Write-Host ""
    Write-Host "Reading the MAC on each plugged-in port to find the preset's boards ..." -ForegroundColor DarkGray
    $macMap = Get-LiveMacMap -Ports $Ports
    $portByMac = @{}
    foreach ($k in $macMap.Keys) { $portByMac[$macMap[$k]] = $k }

    $moves = @()
    $notFound = @()
    foreach ($b in $recorded) {
        $want = ([string]$b.Mac).ToLower()
        if ($portByMac.ContainsKey($want)) {
            if ($portByMac[$want] -ne $b.Port) {
                $moves += [pscustomobject]@{ Board = $b; From = $b.Port; To = $portByMac[$want] }
            }
        }
        else { $notFound += $b }
    }

    $matched   = @($recorded | Where-Object { $notFound -notcontains $_ })
    $claimed   = @($matched | ForEach-Object { $portByMac[([string]$_.Mac).ToLower()] })
    $liveNames = @($Ports | Select-Object -ExpandProperty Port)
    # A board that wasn't matched by MAC keeps its old port only if that port is
    # still plugged in, no matched board is moving onto it, and it doesn't
    # provably hold a different board (a MAC was read there and it isn't this
    # board's recorded one).
    $unresolved = @()
    foreach ($b in @($Roster | Where-Object { $_.Port -and $matched -notcontains $_ })) {
        $gone     = $liveNames -notcontains $b.Port
        $taken    = $claimed -contains $b.Port
        $otherMac = $b.Mac -and $macMap.ContainsKey($b.Port) -and $macMap[$b.Port] -ne ([string]$b.Mac).ToLower()
        if ($gone -or $taken -or $otherMac) { $unresolved += $b }
    }

    Write-Host ""
    if ($moves.Count -eq 0) {
        Write-Host "  Every board with a recorded MAC is already on the right port." -ForegroundColor Green
    }
    else {
        Write-Host "  Matched by MAC:" -ForegroundColor Cyan
        foreach ($m in $moves) {
            Write-Host ("    {0,-8} {1,-7} -> {2,-7} ({3})" -f $m.Board.Label, $m.From, $m.To, $m.Board.Mac) -ForegroundColor Green
        }
    }
    foreach ($b in $notFound) {
        Write-Host ("    {0,-8} MAC {1} is not on any plugged-in port" -f $b.Label, $b.Mac) -ForegroundColor Yellow
    }

    if ($moves.Count -eq 0) {
        return [pscustomobject]@{ Applied = $false; Unresolved = $unresolved; MacMap = $macMap }
    }
    $ans = Read-Line "`n  Use these ports? [Y/n] > "
    if ($ans -eq 'n' -or $ans -eq 'N') {
        return [pscustomobject]@{ Applied = $false; Unresolved = @($Roster | Where-Object { $_.Port -and $liveNames -notcontains $_.Port }); MacMap = $macMap }
    }
    foreach ($m in $moves) { $m.Board.Port = $m.To }
    return [pscustomobject]@{ Applied = $true; Unresolved = $unresolved; MacMap = $macMap }
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
        $backHint = if ($AllowBack) { " (or 'b' back, 'm' main menu, 'cls' clear)" } else { '' }
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
    # Whose boards, stated before the roster itself: two members' preset for the
    # same cell are the same filename, so this is the line that tells them apart.
    $ownerName = Get-PresetOwnerFromPath -FullName $Path
    if (-not $ownerName -and $Cfg.PSObject.Properties['owner']) { $ownerName = [string]$Cfg.owner }
    $myName = Get-MyMember
    $ownerTag = if (-not $ownerName) { '(unfiled - not in a member folder)' }
                elseif ($myName -and $ownerName -eq $myName) { "{0}  (you)" -f $ownerName }
                else { $ownerName }
    $ownerColor = if (-not $ownerName) { 'Yellow' } elseif ($myName -and $ownerName -eq $myName) { 'Green' } else { 'Cyan' }
    Write-Host ("  Boards of: {0}" -f $ownerTag) -ForegroundColor $ownerColor
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
        $role = if ($b.Role -eq 'root') { 'root' } elseif ($b.Kind -eq 'attacker') { 'attacker' } else { 'child' }
        if ($miss) { Write-Host $line -ForegroundColor Yellow } else { Write-Host (Colorize-Role $line $role) }
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

# Everything from the mode menu to the end of the run is wrapped in this one loop
# so that typing 'm' at ANY prompt (Read-Line throws $script:MainMenuSignal) lands
# back on the mode menu instead of killing the wizard. Only this outermost frame
# catches it; a genuine error still propagates untouched. The body is left at its
# original indentation on purpose - re-indenting ~1200 lines would bury the real
# change in whitespace noise, and PowerShell does not care either way.
$originalPreset = $Preset
:wizard while ($true) {
try {
$Preset = $originalPreset

$attack = ''; $topology = ''; $location = ''; $repeat = 1; $scenario = 'none'
$roster = @()

# ------------------------------------------------------------ preset picker ----
# Runs only when no -Preset was given AND at least one preset exists AND the
# mode menu's "without a preset" option wasn't the one picked, so `-Preset
# <path>`, a tree with no presets\ folder, and that mode option all behave
# the same way: straight to the manual menus below. On commit it sets $Preset
# to a FULL path (Test-Path below resolves against the caller's CWD, not
# $base) and falls through to the loader.

$presetFromPicker = $false
$bannerShown      = $false
$forceManual      = $false

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

        $modeIdx = Show-CaptureWizardMenu

        if ($modeIdx -eq 8) { Write-Host ""; Write-Host "Bye - nothing was flashed." -ForegroundColor DarkGray; exit 0 }
        if ($modeIdx -eq 0) { break }
        if ($modeIdx -eq 9) { $forceManual = $true; break }
        if ($modeIdx -eq 1) { Invoke-WipeBoards; continue }
        if ($modeIdx -eq 2) { Invoke-SetLocationBoards; continue }
        if ($modeIdx -eq 3) { Invoke-FirmwareSelfTest; continue }
        if ($modeIdx -eq 4) { Invoke-ImportSdCard; continue }
        if ($modeIdx -eq 5) { Invoke-VerifyRun; continue }
        if ($modeIdx -eq 6) { Invoke-IdentifyAllBoards; continue }
        if ($modeIdx -eq 7) { Invoke-RunAnalysisOnly; continue }
        if ($modeIdx -eq 10) { Invoke-TrimOnly; continue }
        if ($modeIdx -eq 14) { Invoke-ViewRunLog; continue }
        if ($modeIdx -eq 15) { Invoke-DeleteSdFolder; continue }
        if ($modeIdx -eq 17) {
            while ($true) {
                $whoNow = Get-MyMember
                $whoTag = if ($whoNow) { $whoNow } else { 'not set' }
                $sub = Show-Menu -Title "Member board list:" -Options @(
                    'Edit the member board list (the Cal / Bas / Kyle table above - no board contact)',
                    'Open member_boards.json directly (text editor - faster for hand edits)',
                    'Save/load a named board-list snapshot (like a preset - who had which board, incl. burst/mobility/powercycle job)',
                    ("Set whose laptop this is (now: {0}) - puts YOUR presets first and files new ones under you" -f $whoTag)
                ) -DefaultIndex 0 -AllowBack
                if ($sub -eq -1) { break }
                switch ($sub) {
                    0 { Edit-MemberBoards -Path (Join-Path $base 'member_boards.json') }
                    1 { Open-MemberBoardsFile -Path (Join-Path $base 'member_boards.json') }
                    2 { Manage-MemberBoardSnapshots -LivePath (Join-Path $base 'member_boards.json') }
                    3 { Select-MyMember -Force | Out-Null }
                }
            }
            continue
        }
        if ($modeIdx -eq 16) { Invoke-DataSyncMenu; continue }
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
    $presetFiles = if ($forceManual) { @() } else { @(Get-PresetFiles) }
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
            # Ordered YOUR member's presets first, then the other members, then
            # anything still unfiled - nothing is hidden, because flashing an
            # absent member's boards from their preset is a normal thing to do
            # here and must stay one pick away. $presetFiles is re-ordered to
            # match what is printed so index N of the menu is index N of the
            # array, the same invariant the flat list relied on.
            $myMember = Get-MyMember
            $groups = New-Object System.Collections.Specialized.OrderedDictionary
            if ($myMember) {
                $lbl = "-- YOURS ({0})" -f $myMember
                $groups[$lbl] = @($presetFiles | Where-Object { $_.Owner -eq $myMember })
            }
            foreach ($m in (Get-PresetMemberNames)) {
                if ($myMember -and $m -eq $myMember) { continue }
                $mine = @($presetFiles | Where-Object { $_.Owner -eq $m })
                if ($mine.Count -gt 0) { $groups["-- $m"] = $mine }
            }
            $loose = @($presetFiles | Where-Object { -not $_.Owner })
            if ($loose.Count -gt 0) { $groups['-- UNFILED (not in a member folder yet)'] = $loose }

            $presetFiles = @()
            $headers = @{}
            foreach ($key in $groups.Keys) {
                $items = @($groups[$key])
                if ($items.Count -eq 0) { continue }
                $headers[$presetFiles.Count] = $key
                $presetFiles += $items
            }

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

            $idx = Show-Menu -Title 'Load a saved preset?' -Options $opts -DefaultIndex 0 -GroupHeaders $headers
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
                    'File this preset under a member (move it into presets\<member>\)',
                    'Delete this preset (e.g. an accidental duplicate)',
                    'Pick a different preset',
                    'No preset - answer the menus instead'
                ) -DefaultIndex 0) {

                    0 { $Preset = $file.FullName; $presetFromPicker = $true; $deciding = $false; $picking = $false }

                    1 {
                        Write-Host ""
                        $changed = $false
                        $drifted = $false
                        $pickPorts = Get-PortList
                        $pickNames = @($pickPorts | Select-Object -ExpandProperty Port)
                        foreach ($b in $preview) {
                            if ($pickNames -notcontains $b.Port) {
                                Write-Host ("  {0,-8} {1,-7} not plugged in" -f $b.Label, $b.Port) -ForegroundColor Yellow
                                if ($b.Mac) { $drifted = $true }
                                continue
                            }
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
                                # Don't overwrite: the recorded MAC is how this board is
                                # found again on its new port. Copying the other board's
                                # MAC in here would make the preset lie about both.
                                $owner = $preview | Where-Object { $_ -ne $b -and $_.Mac -eq $got } | Select-Object -First 1
                                $who   = if ($owner) { "that is $($owner.Label)'s board" } else { 'not a board from this preset' }
                                Write-Host ("  {0,-8} {1,-7} DRIFT - preset says {2}, port holds {3} ({4})" -f $b.Label, $b.Port, $b.Mac, $got, $who) -ForegroundColor Red
                                $drifted = $true
                            }
                        }
                        if ($drifted) {
                            Write-Host ""
                            Write-Host "  Boards are on different ports than the preset recorded (moved sockets / hub)." -ForegroundColor Yellow
                            $reAns = Read-Line "  Re-match every board to its port by MAC now? [Y/n] > "
                            if ($reAns -ne 'n' -and $reAns -ne 'N') {
                                $sync = Sync-RosterPortsByMac -Roster $preview -Ports $pickPorts
                                if ($sync.Applied) { $changed = $true }
                                foreach ($u in @($sync.Unresolved)) {
                                    Write-Host ("  {0,-8} still has no confirmed port - you'll be asked for it after 'Yes - use it'." -f $u.Label) -ForegroundColor Yellow
                                }
                            }
                        }
                        if ($changed) {
                            $ans = Read-Line "`n  Write these MACs/ports back into the preset? [y/N] > "
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
                        # How a preset that predates the per-member folders (or one
                        # filed under the wrong member) gets sorted, one file at a
                        # time and always with the operator naming the member - no
                        # bulk auto-move, since guessing wrong here would silently
                        # attribute one member's boards to another.
                        $newOwner = Select-PresetOwner -Roster $preview `
                            -Title ("File '{0}' under which member?" -f $file.Name)
                        if (-not $newOwner) {
                            Write-Host "  Left where it is." -ForegroundColor DarkGray
                        }
                        elseif ($newOwner -eq $file.Owner) {
                            Write-Host ("  Already filed under {0}." -f $newOwner) -ForegroundColor DarkGray
                        }
                        else {
                            $destDir = Join-Path (Get-PresetRoot) $newOwner
                            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
                            $dest = Join-Path $destDir $file.Name
                            if (Test-Path $dest) {
                                Write-Host ("  {0} already has a preset called {1} - rename one of them first." -f $newOwner, $file.Name) -ForegroundColor Yellow
                            }
                            else {
                                Move-Item -LiteralPath $file.FullName -Destination $dest
                                # Re-stamp the owner recorded INSIDE the file too, so a
                                # copy that later leaves this folder still says whose it is.
                                Save-Preset -Path $dest -Attack ([string]$cfg.attack) `
                                    -Topology ([string]$cfg.topology) -Location ([string]$cfg.location) `
                                    -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -Owner $newOwner
                                Write-Host ("  Moved -> presets\{0}\{1}" -f $newOwner, $file.Name) -ForegroundColor Green
                                $presetFiles = @(Get-PresetFiles)
                                $deciding = $false
                            }
                        }
                    }

                    6 {
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

                    7 { $deciding = $false }
                    8 { $deciding = $false; $picking = $false }
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
    $livePorts   = @(Get-PortList)
    # The manual (non-preset) branch below sets this at its own "how many
    # child boards" step; a preset skips that step entirely, so without this
    # $ports stays unset (-> $null) all the way to the post-summary "Adjust
    # the plan" loop, where Add-BoardInteractive's Mandatory -Ports parameter
    # then rejects the null outright ("Cannot bind argument to parameter
    # 'Ports' because it is null") and Edit-BoardInteractive's port picker
    # silently shows no ports at all - a preset-driven run could never add or
    # edit a node. Same live snapshot the port-drift fix below already uses.
    $ports       = $livePorts
    $liveNames   = @($livePorts | Select-Object -ExpandProperty Port)
    $missing     = @($roster | Where-Object { $liveNames -notcontains $_.Port })
    $haveMacs    = @($roster | Where-Object { $_.Mac }).Count -gt 0
    $canReadMacs = $haveMacs -and -not ($DryRun -or $SkipMacCheck)
    $remapped    = $false
    $toPick      = @()

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "These ports in the preset are not plugged in right now:" -ForegroundColor Yellow
        foreach ($m in $missing) {
            Write-Host ("  {0,-8} {1,-7} {2}" -f $m.Label, $m.Port, $m.Display) -ForegroundColor Yellow
        }
        $toPick = $missing
        if ($canReadMacs) {
            Write-Host "COM numbers follow the USB socket, not the board - moving boards to other" -ForegroundColor DarkGray
            Write-Host "sockets or a hub renumbers them. The preset recorded each board's MAC, so" -ForegroundColor DarkGray
            Write-Host "the wizard can find which port each one is on now." -ForegroundColor DarkGray
            $findAns = Read-Line "`nFind the boards by their recorded MAC? (reads each plugged-in ESP32 port, briefly resets it) [Y/n] > "
            if ($findAns -ne 'n' -and $findAns -ne 'N') {
                $sync     = Sync-RosterPortsByMac -Roster $roster -Ports $livePorts
                $remapped = $sync.Applied
                $toPick   = @($sync.Unresolved)
            }
        }
        elseif ($haveMacs) {
            $why = if ($DryRun) { 'dry run' } else { '-SkipMacCheck' }
            Write-Host "Not reading boards to match them by MAC ($why) - pick the ports by hand." -ForegroundColor DarkGray
        }
    }
    elseif ($canReadMacs) {
        # Every port still exists, but on a hub or after re-plugging, two boards
        # can trade COM numbers - nothing above would notice, and each board
        # would be flashed and labelled as the other.
        $chkAns = Read-Line "`nCheck each port still holds the board the preset recorded (matches by MAC, briefly resets each board)? [Y/n] > "
        if ($chkAns -ne 'n' -and $chkAns -ne 'N') {
            $sync     = Sync-RosterPortsByMac -Roster $roster -Ports $livePorts
            $remapped = $sync.Applied
            $toPick   = @($sync.Unresolved)
        }
    }

    if ($toPick.Count -gt 0) {
        Write-Host ""
        Write-Host "These boards still need a port:" -ForegroundColor Yellow
        foreach ($m in $toPick) {
            $macTxt = if ($m.Mac) { $m.Mac } else { 'no MAC recorded' }
            Write-Host ("  {0,-8} was {1,-7} {2}  ({3})" -f $m.Label, $m.Port, $m.Display, $macTxt) -ForegroundColor Yellow
        }
        $fixAns = Read-Line "`nPick replacement ports for them now? [Y/n] > "
        if ($fixAns -ne 'n' -and $fixAns -ne 'N') {
            $done = @()
            foreach ($m in $toPick) {
                # Hide ports already held by boards that are settled (not being
                # re-picked) or were re-picked just before this one.
                $taken = @($roster | Where-Object { $_ -ne $m -and ($toPick -notcontains $_ -or $done -contains $_) } |
                    ForEach-Object { $_.Port })
                $newPort = Select-Port -For "$($m.Label) ($($m.Display))" -Ports $livePorts -Taken $taken
                $done += $m
                if (-not $newPort -or $newPort -eq $m.Port) { continue }
                $m.Port = $newPort
                $remapped = $true

                # Keep a MAC only when this session actually read one on the picked
                # port (identify / the MAC match above); otherwise the board on that
                # socket is unknown and a stale MAC would be trusted downstream.
                $liveMac = $null
                if ($script:IdentifiedPorts.ContainsKey($newPort)) {
                    $c = ($script:IdentifiedPorts[$newPort] -split ' -> ')[0].Trim()
                    if ($c -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { $liveMac = $c.ToLower() }
                }
                if ($liveMac) {
                    if ($m.Mac -and ([string]$m.Mac).ToLower() -ne $liveMac) {
                        Write-Host ("   {0} holds {1}, not the {2} this preset recorded for {3} - recording the new MAC (board replaced?)." -f $newPort, $liveMac, $m.Mac, $m.Label) -ForegroundColor Yellow
                    }
                    $m.Mac = $liveMac
                }
                else {
                    $m.Mac = ''
                }
            }
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
    # 5 root-here? + multi-laptop (its own inner retry loop, not two step numbers),
    # 6 child count, 7 per-child roster (one child per visit,
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
    $rootHere    = $true
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
                # Two questions, one step: asked in an inner loop (not a new top-level
                # step number) so 'b' on the second one re-asks the first instead of
                # unwinding all the way to step 4 - the same "one step, own retry loop"
                # idiom step 6/7 use below for their own multi-part prompts.
                :rootStep while ($true) {
                    Write-Host ""
                    $rootAns = Read-Line "`nIs the ROOT board physically on THIS laptop? [Y/n] (or 'b' back, 'm' main menu) > "
                    if (Test-BackAnswer $rootAns) { $step = 4; continue flow }
                    $rootHere = -not ($rootAns -eq 'n' -or $rootAns -eq 'N')

                    if (-not $rootHere) {
                        # Root lives elsewhere - that alone makes this a multi-laptop
                        # split, so skip re-asking the split question below; it would
                        # just confirm what "no" already said. Roster questions still
                        # cover the FULL experiment so labels/ports line up with
                        # whichever laptop the root and any other remote boards are on.
                        $multiLaptop = $true
                        $step = 6
                        continue flow
                    }

                    Write-Host ""
                    Write-Host "Is this ONE experiment's boards ALSO split across other laptops? e.g. this" -ForegroundColor DarkGray
                    Write-Host "laptop runs the root + some children, another runs the attacker + the rest." -ForegroundColor DarkGray
                    Write-Host "Answer the roster questions below for the FULL experiment on every laptop," -ForegroundColor DarkGray
                    Write-Host "then mark which of the OTHER boards are physically here when asked." -ForegroundColor DarkGray
                    $multiAns = Read-Line "`nSplit across multiple laptops? [y/N] (or 'b' back, 'm' main menu) > "
                    if (Test-BackAnswer $multiAns) { continue rootStep }
                    $multiLaptop = ($multiAns -eq 'y' -or $multiAns -eq 'Y')
                    $step = 6
                    continue flow
                }
            }

            6 {
                Write-Host ""
                Write-Host "CHILD boards = every physical ESP32 EXCEPT the root - you'll pick the root" -ForegroundColor DarkGray
                Write-Host "separately in the next step, so don't count it here." -ForegroundColor DarkGray
                Write-Host "  e.g. 3 ESP32s total (1 root + 2 children)  -> enter 2" -ForegroundColor DarkGray
                Write-Host "       10 ESP32s total (1 root + 9 children) -> enter 9" -ForegroundColor DarkGray
                Write-Host "       just the root, no children at all     -> enter 0" -ForegroundColor DarkGray
                if ($multiLaptop) {
                    Write-Host "  Multi-laptop: count the FULL experiment's children, not just this laptop's." -ForegroundColor DarkGray
                }

                $newCount = $childCount
                $tries = 0
                $backCount = $false
                while ($true) {
                    $tries++
                    if ($tries -gt $script:MaxPromptTries) { throw "No valid child count after $script:MaxPromptTries attempts - aborting." }
                    $raw = Read-Line "`nHow many CHILD boards (NOT counting the root)? > [$childCount] (or 'b' back, 'm' main menu) "
                    if (Test-BackAnswer $raw) { $backCount = $true; break }
                    if (-not $raw) { break }
                    $n = 0
                    if ([int]::TryParse($raw, [ref]$n) -and $n -ge 0 -and $n -le 9) {
                        # Wormhole needs two distinct children to be the A and B tunnel ends; with
                        # one child (or none) the Node B menu could never offer a board that isn't Node A.
                        if ($attack -eq 'wormhole' -and $n -lt 2) {
                            Write-Host "  Wormhole needs at least 2 children (Node A and Node B)." -ForegroundColor Yellow
                            continue
                        }
                        $newCount = $n
                        break
                    }
                    Write-Host "  Enter a number from 0 to 9." -ForegroundColor Yellow
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
                    $raw = Read-Line "`nLabel for child $i > [$suggested] (or 'b' back, 'm' main menu) "
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

                $takenPorts = @($children | Where-Object { $_.Port } | Select-Object -ExpandProperty Port)
                $port = Select-PortOrRemote -For "$label (child $i of $childCount)" -Ports $ports -MultiLaptop $multiLaptop -AllowBack -Taken $takenPorts
                # Back here re-asks THIS child's label - nothing has been committed
                # to $children yet, so re-entering step 7 with $i unchanged is the
                # whole undo.
                if ($port -eq $script:BackSignal) { continue flow }

                $children += [pscustomobject]@{
                    Label          = $label
                    Port           = $port
                    Role           = 'child'
                    Kind           = 'plain'
                    Display        = 'plain child'
                    ScenarioTarget = $false
                    # Empty, but PRESENT: Resolve-BoardMac caches a fresh read
                    # back onto this field, and a PSCustomObject cannot gain a
                    # property by assignment. Every board built here has to
                    # carry the same fields ConvertTo-Roster gives a board
                    # loaded from a preset, or the two paths diverge and
                    # whichever one lacks a field dies the moment it is written.
                    Mac            = ''
                }
                $i++
                continue flow
            }

            8 {
                # Assign attack roles. Asking "which one" enforces the count rule by construction.
                # Coming back into this step must not stack a second auto-added remote
                # attacker on top of the one a previous visit created. Only boards THIS
                # step invented carry .Synthetic, so a real remote child the operator
                # entered in step 7 and picked as attacker survives untouched.
                $children = @($children | Where-Object { -not $_.Synthetic })

                if ($attack -eq 'blackhole') {
                    $labels = @($children | ForEach-Object {
                        $tag = ''
                        if ($_.Port -and $script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [$($script:IdentifiedPorts[$_.Port])]" }
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)$tag"
                    })
                    # MULTI-LAPTOP SPLIT: the attacker may be on a teammate's laptop.
                    # Without this option the menu offered only local boards, so the
                    # only way through was to nominate one of YOUR victims as the
                    # attacker - which then sent the pre-flight gate off to read that
                    # board's MAC and rewrite mesh_config.h to the wrong value.
                    #
                    # The single-laptop escape below exists for the same reason, one
                    # step further: this menu USED to force one of the children to be
                    # the attacker, so a roster whose children are all VICTIMS was
                    # unreachable - with exactly one child the "choice" was no choice
                    # at all, and picking it produced an attacker with no victims,
                    # which the pre-flash warnings then (correctly) called a capture
                    # with no attack signature. Every child is a victim by default in
                    # a blackhole run; which ONE is the attacker is the exception, and
                    # "none of them" has to be sayable. A roster with no attacker is
                    # already a supported, warned-about state further down (see the
                    # "local victim(s) present but no attacker anywhere" warning).
                    $escapeIdx = $children.Count
                    if ($multiLaptop) { $labels += 'None of these - the ATTACKER is on ANOTHER laptop' }
                    else              { $labels += 'None of these - they are all VICTIMS (no attacker in this run)' }

                    $idx = Show-Menu -Title 'Which child is the BLACKHOLE ATTACKER? (exactly one)' -Options $labels -AllowBack
                    if ($idx -eq -1) { Undo-LastChild; $step = 7; continue flow }

                    if (-not $multiLaptop -and $idx -eq $escapeIdx) {
                        foreach ($c in $children) { $c.Kind = 'victim'; $c.Display = 'blackhole victim' }
                        Write-Host ""
                        Write-Host "  No attacker in this roster - every child is a victim. The capture will" -ForegroundColor Yellow
                        Write-Host "  carry NO attack signature unless an attacker joins this mesh from" -ForegroundColor Yellow
                        Write-Host "  somewhere else; you'll be warned again before anything is flashed." -ForegroundColor Yellow
                    }
                    elseif ($multiLaptop -and $idx -eq $escapeIdx) {
                        $remoteLabel = Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label)
                        $children += [pscustomobject]@{
                            Label          = $remoteLabel
                            Port           = $null
                            Role           = 'child'
                            Kind           = 'attacker'
                            Display        = 'blackhole ATTACKER (other laptop)'
                            ScenarioTarget = $false
                            Mac            = ''   # same field set as every other board - see the child above
                            Synthetic      = $true
                        }
                        foreach ($c in $children) {
                            if ($c.Kind -ne 'attacker') { $c.Kind = 'victim'; $c.Display = 'blackhole victim' }
                        }
                        Write-Host ""
                        Write-Host ("  Remote attacker recorded as '{0}' - tell that laptop's operator to use the" -f $remoteLabel) -ForegroundColor DarkGray
                        Write-Host "  same label. You'll be asked for its MAC before anything is flashed." -ForegroundColor DarkGray
                    }
                    else {
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
                }
                elseif ($attack -eq 'wormhole') {
                    $labels = @($children | ForEach-Object {
                        $tag = ''
                        if ($_.Port -and $script:IdentifiedPorts.ContainsKey($_.Port)) { $tag = "  [$($script:IdentifiedPorts[$_.Port])]" }
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)$tag"
                    })
                    # The two tunnel ends are opposite ends of ONE physical cable, so
                    # they are either both on this desk or both not - a roster where
                    # the cable spans two laptops is not a thing. Hence one combined
                    # escape here rather than a remote option on each of the two menus.
                    $menuLabels    = @($labels)
                    $bothRemoteIdx = -1
                    if ($multiLaptop) {
                        $bothRemoteIdx = $menuLabels.Count
                        $menuLabels += 'Neither - BOTH tunnel ends are on ANOTHER laptop'
                    }

                    $idxA = Show-Menu -Title 'Which child is WORMHOLE Node A (exit / re-injects to root)?' -Options $menuLabels -AllowBack
                    if ($idxA -eq -1) { Undo-LastChild; $step = 7; continue flow }

                    if ($multiLaptop -and $idxA -eq $bothRemoteIdx) {
                        $taken  = @($children | Select-Object -ExpandProperty Label)
                        $labelA = Get-FreeNodeLabel -Taken $taken
                        $labelB = Get-FreeNodeLabel -Taken (@($taken) + $labelA)
                        $children += [pscustomobject]@{
                            Label = $labelA; Port = $null; Role = 'child'; Kind = 'A'
                            Display = 'wormhole Node A (other laptop)'; ScenarioTarget = $false
                            Mac = ''; Synthetic = $true
                        }
                        $children += [pscustomobject]@{
                            Label = $labelB; Port = $null; Role = 'child'; Kind = 'B'
                            Display = 'wormhole Node B (other laptop)'; ScenarioTarget = $false
                            Mac = ''; Synthetic = $true
                        }
                        foreach ($c in $children) {
                            if ($c.Kind -notin @('A', 'B')) { $c.Kind = 'control'; $c.Display = 'control (plain firmware)' }
                        }
                        Write-Host ""
                        Write-Host ("  Remote tunnel ends recorded as '{0}' (A) and '{1}' (B) - the cable and both" -f $labelA, $labelB) -ForegroundColor DarkGray
                        Write-Host "  boards live on that laptop; nothing is flashed for them here." -ForegroundColor DarkGray
                        $step = if (Test-ScenarioNeedsTarget $scenario) { 9 } else { 10 }
                        continue flow
                    }

                    # Node B is picked from the REAL boards only - the combined escape
                    # above already covers "not here", and offering it again would let
                    # A be local while B is remote.
                    $idxB = -1
                    while ($true) {
                        $idxB = Show-Menu -Title 'Which child is WORMHOLE Node B (entry / captures + tunnels)?' -Options $labels -AllowBack
                        if ($idxB -eq -1) { continue flow }   # re-ask Node A (step 8 re-entry strips synthetics)
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
                # Strip a stale remote-target synthetic before re-picking - repeat
                # visits via 'b' must not stack a second one. Scoped to ONLY this
                # step's own marker (RemoteTargetSynthetic), never the generic
                # Synthetic flag, so a remote attacker/A/B board added in step 8
                # is never touched here.
                $children = @($children | Where-Object { -not $_.RemoteTargetSynthetic })

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
                    if ($multiLaptop) {
                        # No child on THIS laptop can carry it (root-only laptop, or
                        # every local child here is an attacker/wormhole A/B board) -
                        # same "not here" reasoning as the escape option below, just
                        # reached with nothing local left to pick FROM. Record it as
                        # remote outright instead of forcing a dead-end "go back" with
                        # no way through - this was the "no skip option" gap: unlike
                        # the blackhole/wormhole role menus, this step used to error
                        # out here even when the target legitimately lives elsewhere.
                        $remoteLabel = Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label)
                        $children += [pscustomobject]@{
                            Label = $remoteLabel; Port = $null; Role = 'child'; Kind = 'victim'
                            Display = "$scenario TARGET (other laptop)"; ScenarioTarget = $true
                            Mac = ''; Synthetic = $true; RemoteTargetSynthetic = $true
                        }
                        Write-Host ""
                        Write-Host ("  No child on THIS laptop can carry $scenario - remote target recorded as '{0}'." -f $remoteLabel) -ForegroundColor DarkGray
                        Write-Host "  Tell that laptop's operator to mark their own matching board as the target when THEY run the wizard." -ForegroundColor DarkGray
                        $step = 10
                        continue flow
                    }
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
                # MULTI-LAPTOP SPLIT: same reasoning as the attacker/wormhole escapes
                # above - the scenario target may be a board on a teammate's laptop,
                # never listed here at all. Without this, "which child is the target?"
                # forced picking one of YOUR boards even when the real target is
                # elsewhere. Always offered when multiLaptop, so this menu is never
                # the one place in the wizard that can't say "not here".
                $escapeIdx = -1
                if ($multiLaptop) {
                    $escapeIdx = $labels.Count
                    $labels += "None of these - the $($scenario.ToUpper()) TARGET is on ANOTHER laptop"
                }
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
                if ($multiLaptop -and $idx -eq $escapeIdx) {
                    $remoteLabel = Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label)
                    $children += [pscustomobject]@{
                        Label = $remoteLabel; Port = $null; Role = 'child'; Kind = 'victim'
                        Display = "$scenario TARGET (other laptop)"; ScenarioTarget = $true
                        Mac = ''; Synthetic = $true; RemoteTargetSynthetic = $true
                    }
                    Write-Host ""
                    Write-Host ("  Remote $scenario target recorded as '{0}' - tell that laptop's operator to mark" -f $remoteLabel) -ForegroundColor DarkGray
                    Write-Host "  their own matching board as the target when THEY run the wizard." -ForegroundColor DarkGray
                }
                else {
                    $eligible[$idx].ScenarioTarget = $true
                    $eligible[$idx].Display += " + $($scenario.ToUpper()) TARGET"
                }
                $step = 10
                continue flow
            }

            10 {
                if (-not $rootHere) {
                    # Step 5 already said the root is on another laptop. It is never
                    # built, flashed, exported or saved from here - it is in the roster
                    # only so the hand-off summary can name it - so asking for a label
                    # was asking the operator to supply a value this laptop never uses.
                    $rootLabel = Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label)
                    $rootPort  = $null
                    Write-Host ""
                    Write-Host ("ROOT is on another laptop - recorded as '{0}', nothing flashed for it here." -f $rootLabel) -ForegroundColor DarkGray
                    $step = 11
                    continue flow
                }

                $backRoot = $false
                $ltries = 0
                while ($true) {
                    $ltries++
                    if ($ltries -gt $script:MaxPromptTries) { throw "No valid root label after $script:MaxPromptTries attempts - aborting." }
                    $raw = Read-Line "`nLabel for the ROOT board > [node1] (or 'b' back, 'm' main menu) "
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

                # Whether root is here was already settled in step 5 (and the remote
                # case returned above), so this only ever runs for a local root.
                $takenPorts = @($children | Where-Object { $_.Port } | Select-Object -ExpandProperty Port)
                $rootPort = Select-Port -For "$rootLabel (ROOT)" -Ports $ports -AllowBack -Taken $takenPorts
                if ($rootPort -eq $script:BackSignal) { continue flow }
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
            Mac            = ''   # same field set as every other board - see the child above
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
# Used later to gate the pre-flash edit-a-node feature's attack-role field:
# if the attacker/A/B seat is on ANOTHER laptop, reassigning it among local
# boards only would leave two boards holding that seat instead of one -- so
# that field is hidden rather than risking a broken multi-laptop split.
$hasRemoteAttackRole = (@($remoteBoards | Where-Object { $_.Kind -in @('attacker', 'A', 'B') })).Count -gt 0
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
            # One fully-parenthesised expression: in argument mode the bare '+' used
            # to be parsed as its own argument, printing "MAC ( + dry run + )."
            $why = if ($DryRun) { 'dry run' } else { '-SkipMacCheck' }
            Write-Host ("Not asking for {0}'s MAC ({1})." -f $remoteAttacker.Label, $why) -ForegroundColor DarkGray
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

# Wrapped as a scriptblock (not just run inline) so the edit-a-node loop just
# below can rebuild $plan (Params comes from New-RunParams, a snapshot -- it
# does NOT auto-follow a later edit to the Board it was built from) and
# reprint the box after each change, instead of the operator having to trust
# an edit "took" with no visible confirmation.
$buildAndPrintPlan = {
    $script:plan = @()
    foreach ($b in $runRoster) {
        $script:plan += [pscustomobject]@{
            Board  = $b
            Params = (New-RunParams -Board $b -Attack $attack -Topology $topology -Location $location -RepeatNum $repeat -Scenario $scenario)
        }
    }

    $script:dirs        = Get-RunDirs -Attack $attack -Topology $topology -Location $location -Scenario $scenario
    $script:attackDir   = $dirs.AttackDir
    $script:topoDir     = $dirs.TopoDir
    $script:exportDir   = $dirs.Export
    $script:analysisDir = $dirs.Analysis

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host ("  Attack   : {0}" -f $attack)
    Write-Host ("  Topology : {0}" -f $topology)
    Write-Host ("  Scenario : {0}" -f $scenario)
    Write-Host ("  Location : {0}" -f $location)
    Write-Host ("  Repeat   : {0}" -f $repeat)
    Write-Host ("  Mode     : {0}" -f $(if ($swapMode) { 'shared port - swap boards between steps' } else { 'separate ports - no swapping' }))
    if ($scenario -in @('mobility', 'powercycle')) {
        # $plan only covers THIS laptop's own boards ($runRoster) - a target
        # recorded remote (RemoteTargetSynthetic, see step 9's escape) is real
        # and correctly absent from $plan, so it needs its own check here or
        # this would wrongly print "(none picked!)" for a valid multi-laptop split.
        $tgt = $plan | Where-Object { $_.Board.ScenarioTarget } | Select-Object -First 1
        $remoteTgt = $fullRoster | Where-Object { $_.ScenarioTarget -and -not $_.Port } | Select-Object -First 1
        $tgtLbl = if ($tgt) { $tgt.Board.Label }
                  elseif ($remoteTgt) { "$($remoteTgt.Label) (on another laptop - not YOUR job)" }
                  else { '(none picked!)' }
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
        $mac = Resolve-BoardMac -Board $p.Board -SkipLiveRead:($SkipMacCheck -or $DryRun)
        $macDisp = if ($mac) { $mac } else { '(unread)' }
        $line = ("   [{0}] {1,-8} {2,-27} {3,-7} {4,-17} {5}" -f $step, $p.Board.Label, $p.Board.Display, $p.Board.Port, $macDisp, $tail)
        $role = if ($p.Board.Role -eq 'root') { 'root' } elseif ($p.Board.Kind -eq 'attacker') { 'attacker' } else { 'child' }
        Write-Host (Colorize-Role $line $role)
    }
    Write-Host ""
    Write-Host "  Exports  -> $exportDir"
    Write-Host "  Analysis -> $analysisDir"
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
}
& $buildAndPrintPlan

# ---- optional adjustments, right after the summary (no blind apply-to-all --
# see [[thesis_cc_wizard_hardware_safety]]: any node change is on ONE node the
# operator picked by number; a topology change is explicit and global by
# nature. $plan is rebuilt+reprinted after every change, and nothing is
# touched until "Proceed?" below runs). --------------------------------------
while ($true) {
    $adjIdx = Show-Menu -Title "Adjust the plan before confirming?" -Options @(
        'Edit a specific node (port/label/role/scenario target/attack sub-role)',
        'Add a node',
        'Remove a node',
        'Change topology for this run',
        'Change scenario for this run',
        'Nothing more -- continue to confirm'
    ) -DefaultIndex 5
    if ($adjIdx -eq 5) { break }

    if ($adjIdx -eq 0) {
        $pickIdx = Show-Menu -Title "Which node?" -Options (@($runRoster | ForEach-Object { "$($_.Label)  ($($_.Port), $($_.Display))" }))
        if ($pickIdx -ge 0) {
            Edit-BoardInteractive -Board $runRoster[$pickIdx] -Roster $runRoster -Attack $attack -Scenario $scenario -Ports $ports -HasRemoteAttackRole $hasRemoteAttackRole
        }
    }
    elseif ($adjIdx -eq 1) {
        $runRoster = Add-BoardInteractive -Roster $runRoster -Attack $attack -Ports $ports
    }
    elseif ($adjIdx -eq 2) {
        $runRoster = Remove-BoardInteractive -Roster $runRoster -Attack $attack -Scenario $scenario
    }
    elseif ($adjIdx -eq 3) {
        $topoOpts = @('tree', 'star', 'linear', 'partial')
        $topoIdx2 = Show-Menu -Title "Topology (every board, same)?" -Options @(
            'tree     (default self-organising)',
            'star     (all direct children of root)',
            'linear   (forced chain)',
            'partial  (physical placement)'
        ) -DefaultIndex ([array]::IndexOf($topoOpts, $topology))
        if ($topoIdx2 -ge 0) { $topology = $topoOpts[$topoIdx2] }
    }
    elseif ($adjIdx -eq 4) {
        # Lets a loaded preset's scenario be changed here - previously the only
        # way to run a different scenario than what a preset was saved with was
        # to abandon the preset and answer every menu from scratch.
        $scenIdx2 = Show-Menu -Title "Scenario (run-to-run variation the panel asked for)?" -Options $SCENARIO_LABELS -DefaultIndex ([array]::IndexOf($SCENARIOS, $scenario))
        if ($scenIdx2 -ge 0 -and $SCENARIOS[$scenIdx2] -ne $scenario) {
            $scenario = $SCENARIOS[$scenIdx2]

            # Any target picked for the OLD scenario belongs to that scenario, not
            # this one - clear it (local marks and any earlier remote hand-off) so
            # a stale " + TARGET" suffix or a leftover remote synthetic doesn't
            # survive the switch.
            foreach ($c in $runRoster) {
                $c.ScenarioTarget = $false
                $c.Display = $c.Display -replace ' \+ .* TARGET$', ''
            }
            $fullRoster   = @($fullRoster | Where-Object { -not $_.RemoteTargetSynthetic })
            $remoteBoards = @($fullRoster | Where-Object { -not $_.Port })

            if (Test-ScenarioNeedsTarget $scenario) {
                $eligible = if ($scenario -eq 'burst') { @($runRoster | Where-Object { Test-BurstEligible $_ }) } else { @($runRoster | Where-Object { $_.Role -ne 'root' }) }

                if ($eligible.Count -eq 0 -and $remoteBoards.Count -gt 0) {
                    # No local node can carry it (e.g. every local child here is an
                    # attacker/wormhole A/B board) - same "not here" escape the
                    # manual flow's own scenario-target step offers, just reached
                    # with nothing local left to pick FROM.
                    $remoteLabel = Get-FreeNodeLabel -Taken @($fullRoster | ForEach-Object { $_.Label })
                    $fullRoster += [pscustomobject]@{
                        Label = $remoteLabel; Port = $null; Role = 'child'; Kind = 'victim'
                        Display = "$scenario TARGET (other laptop)"; ScenarioTarget = $true
                        Mac = ''; Synthetic = $true; RemoteTargetSynthetic = $true
                    }
                    $remoteBoards = @($fullRoster | Where-Object { -not $_.Port })
                    Write-Host ("   No local node can carry $scenario - remote target recorded as '{0}'." -f $remoteLabel) -ForegroundColor DarkGray
                    Write-Host "   Tell that laptop's operator to mark their own matching board as the target when THEY run the wizard." -ForegroundColor DarkGray
                }
                elseif ($eligible.Count -eq 0) {
                    Write-Host "   No node can carry the $scenario scenario - add an eligible node, or pick a different scenario." -ForegroundColor Yellow
                }
                else {
                    $labels = @($eligible | ForEach-Object { "$($_.Label)  ($($_.Port))  -  $($_.Display)" })
                    # Always offered, never gated on $remoteBoards (a pre-existing
                    # remote marker) or $multiLaptop (unset here - that flag is only
                    # ever answered by the manual flow's own multi-laptop question,
                    # which a preset-driven run skips entirely). Picking it is always
                    # an explicit operator choice (DefaultIndex stays on a real board,
                    # never this one), so there's no risk of silently fabricating a
                    # phantom board - same "never a dead end" rule the manual flow's
                    # own equivalent menus already follow (see the multiLaptop escapes
                    # above, e.g. around line 4685).
                    $escapeIdx = $labels.Count
                    $labels += "None of these - the $($scenario.ToUpper()) TARGET is on ANOTHER laptop"
                    $tIdx = Show-Menu -Title "Which node is the $scenario TARGET? (exactly one)" -Options $labels -DefaultIndex 0
                    if ($tIdx -ge 0 -and $tIdx -eq $escapeIdx) {
                        $remoteLabel = Get-FreeNodeLabel -Taken @($fullRoster | ForEach-Object { $_.Label })
                        $fullRoster += [pscustomobject]@{
                            Label = $remoteLabel; Port = $null; Role = 'child'; Kind = 'victim'
                            Display = "$scenario TARGET (other laptop)"; ScenarioTarget = $true
                            Mac = ''; Synthetic = $true; RemoteTargetSynthetic = $true
                        }
                        $remoteBoards = @($fullRoster | Where-Object { -not $_.Port })
                        Write-Host ("   Remote $scenario target recorded as '{0}' - tell that laptop's operator to mark" -f $remoteLabel) -ForegroundColor DarkGray
                        Write-Host "   their own matching board as the target when THEY run the wizard." -ForegroundColor DarkGray
                    }
                    elseif ($tIdx -ge 0) {
                        $eligible[$tIdx].ScenarioTarget = $true
                        $eligible[$tIdx].Display += " + $($scenario.ToUpper()) TARGET"
                    }
                }
            }
        }
    }

    # A node's Role may have just changed, or one was added/removed -- re-sort
    # (root last), same invariant as the original roster construction relies
    # on downstream.
    $runRoster = @($runRoster | Where-Object { $_.Role -ne 'root' }) + @($runRoster | Where-Object { $_.Role -eq 'root' })
    & $buildAndPrintPlan
}

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

# Scriptblock so both the plain flow and the post-pre-build menu share it.
# -Ask:$false skips the "save?" yes/no (the operator already picked "save").
# A loaded preset that was then edited (node added/removed/changed in the
# "Adjust the plan?" step above) only affects THIS run unless written back -
# offered here as its own yes/no, separate from "save as a new preset" below,
# so a plain unedited replay is never prompted to overwrite anything.
$savePresetFlow = { param([bool]$Ask)
if ($Preset) {
    $updateAns = if ($Ask) { Read-Line ("`nSave these changes back into {0}? [y/N] > " -f (Split-Path -Leaf $Preset)) } else { 'y' }
    if ($updateAns -eq 'y' -or $updateAns -eq 'Y') {
        if ($DryRun) {
            Write-Host "  Dry run - not reading the boards, so MACs won't be refreshed." -ForegroundColor DarkGray
        }
        else {
            $macAns = Read-Line "  Refresh each board's MAC in the preset? (reads each board, ~2s each) [Y/n] > "
            if ($macAns -ne 'n' -and $macAns -ne 'N') {
                Write-Host ""
                # $runRoster only - a preset saves THIS laptop's own boards; a
                # multi-laptop split's remote boards have no port to read anyway.
                Add-BoardMacs -Roster $runRoster -Known $macsRead | Out-Null
            }
        }
        Save-Preset -Path $Preset -Attack $attack -Topology $topology `
            -Location $location -RepeatNum $repeat -Roster $runRoster -Scenario $scenario
        Write-Host ("  Updated -> {0}" -f $Preset) -ForegroundColor Green
    }
}

if (-not $Preset) {
    $saveAns = if ($Ask) { Read-Line "`nSave this roster as a preset for the next repeat? [y/N] > " } else { 'y' }
    if ($saveAns -eq 'y' -or $saveAns -eq 'Y') {
        # Whose boards this roster is, asked BEFORE the filename: it decides the
        # folder, which is what lets two members keep the same plain cell name
        # (linear-blackhole-none-g402.json) instead of one having to be
        # hand-renamed. Pre-answered from the MACs, so flashing an absent
        # member's boards files itself under THEM without you remembering to say so.
        $presetOwner = Select-PresetOwner -Roster $runRoster
        $presetDir = if ($presetOwner) { Join-Path (Get-PresetRoot) $presetOwner } else { Get-PresetRoot }
        if (-not (Test-Path $presetDir)) { New-Item -ItemType Directory -Force -Path $presetDir | Out-Null }
        $suggested = "$topoDir-$attackDir-$scenario-$($location.ToLower()).json"
        if ($presetOwner) {
            Write-Host ("  Saving under presets\{0}\ (whose boards this roster is)." -f $presetOwner) -ForegroundColor DarkGray
        }
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
            -Location $location -RepeatNum $repeat -Roster $runRoster -Scenario $scenario -Owner $presetOwner
        Write-Host "  Saved -> $presetPath" -ForegroundColor Green
        Write-Host "  Next time just run .\run_wizard.ps1 and pick it from the list." -ForegroundColor DarkGray
    }
}
}

# ------------------------------------------------------------- pre-build ----
# Compile every node's variant up front (children first, root last - same order
# as the flash chain) via run.ps1 -BuildOnly, so the build dir and -D flags are
# run.ps1's own, never a copy that can drift. Touches no board and no port, so
# 'm' stays live and a stop afterwards leaves nothing half-flashed. Afterwards
# the flash chain below only links/flashes (ninja no-op) instead of compiling
# between Ctrl+] presses.
$preBuilt = $false
if (-not $DryRun) {
    $pbAns = Read-Line "`nPre-build every node's firmware first? (compile only - no board touched; then pick: start the run or save the preset) [Y/n] > "
    if ($pbAns -ne 'n' -and $pbAns -ne 'N') {
        if ($cleanBuild) {
            Write-Host ""
            Write-Host "Removing build_* under $buildRoot ..." -ForegroundColor Yellow
            Remove-Item -Recurse -Force (Join-Path $buildRoot 'child_node\build_*') -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force (Join-Path $buildRoot 'root_node\build_*')  -ErrorAction SilentlyContinue
            $cleanBuild = $false
        }

        $buildPlan = @()
        $seenDirs  = @{}
        foreach ($p in $plan) {
            $bd = Get-BoardBuildDir -Params $p.Params
            if (-not $seenDirs.ContainsKey($bd)) { $seenDirs[$bd] = $true; $buildPlan += $p }
        }

        $failed = @()
        $bi = 0
        $buildWatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($p in $buildPlan) {
            $bi++
            Write-Host ""
            Write-Host ("=== Pre-build [{0}/{1}] {2} - {3} ===" -f $bi, $buildPlan.Count, $p.Board.Label, $p.Board.Display) -ForegroundColor Cyan
            $buildParams = [ordered]@{}
            foreach ($k in $p.Params.Keys) { $buildParams[$k] = $p.Params[$k] }
            $buildParams.BuildOnly = $true
            $global:LASTEXITCODE = 0
            & (Join-Path $base 'run.ps1') @buildParams
            if ($LASTEXITCODE -ne 0) { $failed += $p.Board.Label }
        }
        $buildWatch.Stop()

        if ($failed.Count -gt 0) {
            Write-Host ""
            Write-Host ("BUILD FAILED for: {0}" -f ($failed -join ', ')) -ForegroundColor Red
            Write-Host "Nothing was flashed. Fix the compile error above and re-run the wizard." -ForegroundColor Red
            return
        }
        Write-Host ""
        Write-Host ("All {0} variant(s) built in {1}." -f $buildPlan.Count, (Format-Duration ([int]$buildWatch.Elapsed.TotalSeconds))) -ForegroundColor Green
        $preBuilt = $true
    }
}

if ($preBuilt) {
    # No default on purpose: options 1-2 erase and flash real boards, so Enter
    # alone must not start that.
    $nextIdx = Show-Menu -Title "Firmware ready. What next?" -Options @(
        'Start the run now (wipe + flash + monitor each board, root last)',
        'Save the preset, then start the run',
        'Save the preset and stop here (compiled firmware stays for next time)',
        'Stop here without saving (nothing flashed)'
    )
    if ($nextIdx -in @(1, 2)) { & $savePresetFlow $false }
    if ($nextIdx -in @(2, 3)) {
        Write-Host ""
        Write-Host "Stopped before flashing - no board was touched." -ForegroundColor Yellow
        Write-Host "Builds are cached per COM port: rerun on the same ports and the flash step skips compiling." -ForegroundColor DarkGray
        if ($originalPreset) {
            # -Preset is the "just run this" entry point, so there is no mode menu
            # behind it to return to.
            return
        }
        $bannerShown = $false
        continue wizard
    }
}
else {
    & $savePresetFlow $true
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

if (-not $preBuilt) {
    $go = Read-Line "`nProceed? [y/N] > "
    if ($go -ne 'y' -and $go -ne 'Y') {
        Write-Host "Aborted - nothing flashed." -ForegroundColor Yellow
        return
    }
}

# Full console log of this run (every board's flash/monitor output, incl. any
# errors) - opt-in, same naming convention as a preset so the two pair up on
# sight: <preset-base-name>_<timestamp>.log, or <topology>-<attack>-<scenario>-
# <location>_<timestamp>.log when no preset is involved. Reviewable later from
# the wizard's DATA menu ("View a saved run log" -> Invoke-ViewRunLog).
$saveLogAns = Read-Line "`nSave a full log of this run (console output incl. any errors, viewable later from the wizard)? [Y/n] > "
$saveRunLog = ($saveLogAns -ne 'n' -and $saveLogAns -ne 'N')
$runLogPath = $null
$transcriptStarted = $false
if ($saveRunLog) {
    $runLogDir = Join-Path $base 'run_logs'
    if (-not (Test-Path $runLogDir)) { New-Item -ItemType Directory -Force -Path $runLogDir | Out-Null }
    $logBaseName = if ($Preset) { [IO.Path]::GetFileNameWithoutExtension($Preset) } else { "$topoDir-$attackDir-$scenario-$($location.ToLower())" }
    $runLogPath = Join-Path $runLogDir ("{0}_{1}.log" -f $logBaseName, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    # Clear any stray transcript left running from an earlier aborted run before
    # starting a fresh one - Start-Transcript errors if one is already active.
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
    try {
        Start-Transcript -Path $runLogPath -ErrorAction Stop | Out-Null
        $transcriptStarted = $true
        Write-Host "  Logging this run -> $runLogPath" -ForegroundColor DarkGray
    } catch {
        Write-Host ("  Could not start the run log ({0}) - continuing without saving it." -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

# Everything above this line is answerable and reversible; below it, boards get
# written to. See Request-MainMenu.
$script:NavLocked = $true

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

# try/finally so the run log (if any) is always closed off - including on the
# FAILED-child `exit 1` below, since PowerShell unwinds finally blocks on exit
# just like any other scope exit.
try {
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
}
finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host "  Run log saved -> $runLogPath" -ForegroundColor Green
        Write-Host "  Review it later from the wizard's DATA menu -> View a saved run log." -ForegroundColor DarkGray
    }
}

break wizard
}
catch {
    # Only the 'm' escape is handled here; every real failure keeps its original
    # behaviour (message, stack, non-zero exit) by being rethrown untouched.
    if ($_.Exception.Message -ne $script:MainMenuSignal) { throw }
    if ($originalPreset) {
        # -Preset is the "just run this" entry point, so there is no mode menu
        # behind it to return to.
        Write-Host ""
        Write-Host "Nothing to go back to (-Preset was given) - exiting." -ForegroundColor DarkGray
        break wizard
    }
    Write-Host ""
    Write-Host "Back to the main menu - nothing was flashed." -ForegroundColor Cyan
    $bannerShown = $false
    continue wizard
}
}
