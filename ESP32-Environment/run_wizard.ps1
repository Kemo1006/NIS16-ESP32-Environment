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
  presets\Bas\blackhole-linear-g402-stationary.json. The filename already spells the
  experiment cell (attack-topology-location-scenario), so the folder is what
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
  .\run_wizard.ps1 -Preset presets\Bas\blackhole-linear-g402-stationary.json -Repeat 2
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

# WINDOWS 260-CHARACTER PATH LIMIT - same rule, same numbers as run.ps1's
# Get-SafeBuildDir (see the comment there): a build dir longer than
# $MaxBuildDirLen goes under the short root, or gcc fails on the bootloader's
# .obj.d. Keep all three copies identical so they resolve the same dir.
$shortBuildRoot  = Join-Path $env:SystemDrive "esp32b\$repoTag"
$MaxBuildDirLen  = 110
function Get-SafeBuildDir {
    param([string]$Proj, [string]$DirName)
    $d = Join-Path $buildRoot "$Proj\$DirName"
    if ($d.Length -gt $MaxBuildDirLen) { $d = Join-Path $shortBuildRoot "$Proj\$DirName" }
    return $d
}

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

# Sources (COM port or drive root) an SD-import copy has actually succeeded from
# this session, so the next port/drive picker can mark them - easy to tell which
# boards/cards are already pulled without keeping a mental list by hand.
# Import-OneSdCard sets $script:LastImportOk; each caller then keys this on
# whichever source it passed (-Port or -Card).
$script:ImportedSources = @{}

$ATTACKS    = @('none', 'blackhole', 'wormhole')
$TOPOLOGIES = @('linear', 'tree', 'star', 'partial')
$LOCATIONS  = @('home', 'G402', 'DLSU_Library', 'Goks')

# Run-to-run variation the panel asked for. 'stationary' (formerly 'none') is byte-identical to the
# pre-scenario wizard. Keep the ValidateSet in run.ps1 in sync with this list.
$SCENARIOS = @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')
$SCENARIO_LABELS = @(
    "stationary  - no variation, nodes stay put (called 'none' in older runs)",
    'burst       - CODE: one child fires 300 probes back-to-back in the attack window',
    'highload    - CODE: every child probes 4x faster for the whole run',
    'jitter      - CODE: ROOT randomises baseline/attack window LENGTHS each boot, so elapsed time stops predicting the phase',
    'mobility    - HUMAN: you move one child from spot A to spot B (checklist only)',
    'powercycle  - HUMAN: you unplug/replug one child (checklist only)'
)

# Readable stamp in datasets\ names: sept27_0311AM (month word + day, 12-hour
# time, no year, no seconds). Mirrors make()/make_date() in tools\name_stamp.py -
# keep the month list identical. Explicit list, never ToString('MMM'): that is
# locale-dependent and gives "Sep", not "sept".
$NAME_MONTHS = @('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sept', 'oct', 'nov', 'dec')
function Get-NameStamp {
    $t = Get-Date
    $h = $t.Hour % 12
    if ($h -eq 0) { $h = 12 }
    $ampm = if ($t.Hour -lt 12) { 'AM' } else { 'PM' }
    return ('{0}{1:00}_{2:00}{3:00}{4}' -f $NAME_MONTHS[$t.Month - 1], $t.Day, $h, $t.Minute, $ampm)
}
function Get-NameDate {
    $t = Get-Date
    return ('{0}{1:00}' -f $NAME_MONTHS[$t.Month - 1], $t.Day)
}
function Get-StampedPath {
    # <Dir>\<Head>_<stamp><Ext>. The stamp is only minute-precise, so a name
    # already taken gets -2, -3, ... after the stamp instead of being overwritten.
    param([string]$Dir, [string]$Head, [string]$Ext)
    $stamp = Get-NameStamp
    $path = Join-Path $Dir ('{0}_{1}{2}' -f $Head, $stamp, $Ext)
    $n = 2
    while (Test-Path -LiteralPath $path) {
        $path = Join-Path $Dir ('{0}_{1}-{2}{3}' -f $Head, $stamp, $n, $Ext)
        $n++
    }
    return $path
}

# 'stationary' is the no-variation scenario; 'none' is its pre-sep-24-2026 name,
# still found in old presets and commands. The ONE place that rename lives.
function ConvertTo-Scenario([string]$Name) {
    if (-not $Name -or $Name -eq 'none') { return 'stationary' }
    return $Name
}

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

function Get-BoardColorRole {
    # The Colorize-Role key for a roster board: the attack boards of EITHER
    # attack share the pink 'attacker' color - blackhole's attacker and wormhole's
    # Node A / Node B (oct. 7, 2026: A/B used to fall through to the teal child
    # color, so the two wormhole ends didn't stand out the way the attacker does).
    param($Board)
    if ($Board.Role -eq 'root') { return 'root' }
    if ($Board.Kind -in @('attacker', 'A', 'B')) { return 'attacker' }
    return 'child'
}

# Per-tag colors for the preset picker's "-- MODE / topology / location / scenario"
# cell headings, so a long preset list can be scanned by color. Values are the
# ANSI SGR codes (the part between ESC[ and m). Attacks stay red-family and
# BASELINE is the only bold green; tags not listed here print uncolored.
$script:PresetTagAnsi = @{
    # mode
    BASELINE = '1;32'; BLACKHOLE = '1;31'; WORMHOLE = '1;95'
    # topology
    linear = '0;36'; star = '1;33'; tree = '1;94'; partial = '38;5;216'
    # location
    home = '0;34'; G402 = '0;35'; DLSU_Library = '0;96'; Goks = '38;5;180'
    # scenario
    stationary = '90'; burst = '33'; jitter = '1;93'; highload = '1;91'
    mobility = '38;5;39'; powercycle = '38;5;141'
}

function Format-PresetCell {
    # '-- BLACKHOLE / linear / G402 / stationary' with each tag in its color and
    # the '--' and '/' separators dim gray. $Attack is the raw cell value
    # ('none' prints as BASELINE).
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario)
    $e = [char]27
    $paint = {
        param([string]$Text)
        $code = if ($Text) { $script:PresetTagAnsi[$Text] } else { $null }
        if ($code) { "$e[$($code)m$Text$script:AnsiReset" } else { $Text }
    }
    $mode = if ($Attack -eq 'none') { 'BASELINE' } else { $Attack.ToUpper() }
    $sep  = "$e[90m / $script:AnsiReset"
    return "$e[90m--$script:AnsiReset " + (& $paint $mode) + $sep + (& $paint $Topology) + $sep + (& $paint $Location) + $sep + (& $paint $Scenario)
}

$memberBoardsTool = Join-Path $base 'tools\Show-MemberBoards.ps1'
if (Test-Path $memberBoardsTool) { . $memberBoardsTool }
# Latest-import record behind the green/yellow push/pull lists (Invoke-ImportSdCard).
$importBatchTool = Join-Path $base 'tools\ImportBatch.ps1'
if (Test-Path $importBatchTool) { . $importBatchTool }

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
    # Lowest nodeN not already used - fills gaps first (node2,4,5 taken -> node3),
    # else the next one up (node2-7 taken -> node8). node1 is the ROOT's label
    # by convention (the root prompt defaults to it), so a child never gets it:
    # children start at node2 even when the roster has no root in it (a preset
    # whose root lives on another laptop). -ForRoot is for labelling the root.
    # Also used for boards this laptop records but never touches (a root or
    # attacker on someone else's laptop): the label only names them in the
    # hand-off summary, so prompting for one asks the operator to invent a value
    # their own machine will never act on.
    param([string[]]$Taken, [switch]$ForRoot)
    $n = if ($ForRoot) { 1 } else { 2 }
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
        [hashtable]$GroupHeaders,
        # Opt-in shortcut: typing d<N> (or del/delete <N>) returns -2 with the
        # 0-based indexes left in $script:MenuDeleteIndexes, so the caller can
        # delete entries without opening them first. Several at once: d3,5,7 /
        # d 3 5 7 / d3-5 (all numbers refer to the list AS SHOWN). The caller
        # MUST check for -2.
        [switch]$AllowDelete
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
                # An empty heading is just a spacer - sets a trailing "Back" apart
                # from the last group without inventing a name for it.
                if ($GroupHeaders[$i]) { Write-Host ("  {0}" -f $GroupHeaders[$i]) -ForegroundColor DarkCyan }
            }
            if ($i -eq $DefaultIndex) {
                # The default is marked right on its option line, not only in the
                # prompt below, so scanning the list alone shows what Enter picks.
                # The numbers are bracketed [N] to match the "keep [N]" prompt hint;
                # on their own the brackets could read as "already chosen", so the
                # explicit "<- default (press Enter)" marker is what actually signals
                # the default here - the brackets are just the selector style.
                # A multi-line option (the preset picker's board list) keeps the
                # marker on its FIRST line, not trailing after the last detail row.
                $nl   = $Options[$i].IndexOf("`n")
                $head = if ($nl -ge 0) { $Options[$i].Substring(0, $nl) } else { $Options[$i] }
                $tail = if ($nl -ge 0) { $Options[$i].Substring($nl) } else { '' }
                Write-Host ("  [{0}] {1}  <- default (press Enter){2}" -f ($i + 1), $head, $tail) -ForegroundColor Green
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
        if ($AllowDelete) { $navHint = ", 'd<N>' delete (d3,5 or d3-5 for several)" + $navHint }
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
        if ($AllowDelete -and $raw -match '^(?i:d|del|delete)\s*(\d[\d,\s-]*)$') {
            $picked = @()
            $bad = $false
            foreach ($tok in ($Matches[1] -split '[,\s]+' | Where-Object { $_ })) {
                if ($tok -match '^(\d+)-(\d+)$') {
                    $lo = [int]$Matches[1]; $hi = [int]$Matches[2]
                    if ($lo -gt $hi -or ($hi - $lo) -gt 200) { $bad = $true; break }
                    $picked += @($lo..$hi)
                }
                elseif ($tok -match '^\d+$') { $picked += [int]$tok }
                else { $bad = $true; break }
            }
            if ($bad -or $picked.Count -eq 0) {
                Write-Host "  Use d<N>, d3,5,7 or d3-5 (numbers from the list)." -ForegroundColor Yellow
                continue
            }
            $script:MenuDeleteIndexes = @($picked | Sort-Object -Unique | ForEach-Object { $_ - 1 })
            return -2
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return ($n - 1)
        }
        if ($Options.Count -eq 1) { Write-Host "  Enter 1 (the only option)." -ForegroundColor Yellow }
        else { Write-Host "  Enter a number from 1 to $($Options.Count)." -ForegroundColor Yellow }
    }
}

function Test-NoExperimentData {
    # True when import_sdcard.py --list-json says this telemetry file holds only
    # phase 255 ("no broadcast heard yet") - a board that stopped before the
    # root's schedule reached it. $false when phases are unknown (over USB).
    param($File)
    if ($null -eq $File.phases) { return $false }
    $real = @(@($File.phases) | Where-Object { $_ -ne 255 })
    return ($real.Count -eq 0)
}

function Get-AbortCauseText {
    # One line on WHY an ABORTED file ended, from import_sdcard.py --list-json:
    #   ended_by  = reset reason of the next boot that reached logging
    #               (firmware from sep. 25, 2026 - runs.csv reset_reason column)
    #   status    = the card's status_<node>.txt now; its boot count vs this
    #               file's boot says whether the board ever booted again. That
    #               part works on older cards too - every firmware wrote it.
    # $null when there is nothing to say (e.g. over USB).
    param($File)
    switch ($File.ended_by) {
        'POWERON'  { return 'ended by a POWER CUT (unplugged / powerbank off) - the next boot was a plain power-on' }
        'BROWNOUT' { return 'ended by a BROWNOUT - the supply sagged (weak powerbank/charger/cable)' }
        { $_ -in @('PANIC', 'TASK_WDT', 'INT_WDT', 'WDT') } { return "ended by a CRASH ($_) - the firmware reset itself" }
    }
    $st = $File.status
    if ($null -eq $st -or $null -eq $st.boot_count) { return $null }
    $after = [int]$st.boot_count - [int]$File.boot
    if ($after -le 0) {
        return 'this was the board''s LAST boot on this card and it ended without closing (power cut or card pulled)'
    }
    $txt = "the board booted $after more time(s) after this file and never logged again"
    if ($null -ne $st.brownouts) {
        $txt += " - brownouts so far: $($st.brownouts), crashes: $($st.crashes), last reset: $($st.last_reset)"
    } else {
        $txt += ' - dying before logging starts looks like a brownout loop (weak powerbank/cable); reflash to record the reason'
    }
    return $txt
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
            @{ Idx = 4; Text = 'Export captured CSVs - from the board over USB, or from a pulled SD card (file list either way)' }
            @{ Idx = 16; Text = 'Sync data with GitHub (push / pull / test) - captures, analysis + EDA, run logs, presets. Never code' }
            @{ Idx = 10; Text = 'Trim exported CSVs only - SMART: keeps the session with the real phase progression, not just the longest (writes trimmed/ copies, raw export untouched)' }
            @{ Idx = 7; Text = 'Run analysis only (M6->M8 on already-exported CSVs - no board/COM contact)' }
            @{ Idx = 20; Text = 'Archive captured data - MOVES exports+analysis+PCAP+run logs into archive\<date>_<label>\ (shows what moves, flags data already archived, warns on COMPLETE runs)' }
            @{ Idx = 14; Text = 'View a saved run log (a past run''s console output start to end, filed by attack/topology/location - keep, archive, delete or push; no board/COM contact)' }
            @{ Idx = 28; Text = 'Delete dataset files from THIS LAPTOP (no File Explorer - every file shows its date + time; type DELETE to confirm; GitHub untouched)' }
        ) }
        @{ Name = 'MAINTENANCE'; Items = @(
            @{ Idx = 1; Text = "Wipe a board clean (full erase, no firmware - for when you're not sure what's on it)" }
            @{ Idx = 2; Text = 'Write/update location.txt on an already-running board (over USB)' }
            @{ Idx = 3; Text = 'Firmware self-test - build + flash ONE board and check the SD/location code (no capture, no attack, no export)' }
            @{ Idx = 29; Text = 'Wormhole UART tunnel test - flash uart_link_test to Node A + Node B and check the wire BOTH ways (quick or 2-min soak; no mesh, no capture)' }
            @{ Idx = 6; Text = 'Identify all boards (COM port + MAC, every board at once - no capture, no attack)' }
            @{ Idx = 17; Text = 'Member board list (edit / open json / snapshots - submenu)' }
            @{ Idx = 15; Text = 'Delete a folder from a running board''s SD card (e.g. blackhole > linear > G402 - PERMANENT, over USB)' }
        ) }
        @{ Name = 'VERIFY'; Items = @(
            @{ Idx = 5; Text = 'Verify a run (paper-backed 3-sigma attack check - no board/COM contact)' }
            @{ Idx = 18; Text = 'Campaign progress checklist - which runs are DONE, scanned from the folders (no board/COM contact)' }
            @{ Idx = 19; Text = 'Show TOPOLOGY STRUCTURE of a captured run (parent/child table rebuilt from the CSVs - for the paper/panel)' }
        ) }
        @{ Name = 'WIRESHARK'; Items = @(
            @{ Idx = 24; Text = 'Open a capture in Wireshark - pick a view (all boards, MY boards, one board, retries, joins, BLACKHOLE proof, WORMHOLE check...)' }
            @{ Idx = 25; Text = 'Open the NEWEST capture in Wireshark (overview of ALL boards of the run - no questions)' }
            @{ Idx = 26; Text = 'ESP32 sniffer board + watch LIVE in Wireshark (flash a SPARE board, record into datasets\PCAP\; Enter stops)' }
            @{ Idx = 23; Text = 'ESP32 sniffer board - record only, into datasets\PCAP\ (no run; no Mac needed; Enter stops)' }
            @{ Idx = 21; Text = 'MacBook sniffer test (~2 min, no attack run - proves the Mac Wireless Diagnostics Sniffer records ESP32 frames)' }
            @{ Idx = 22; Text = 'Check a sniffer capture file (Mac or ESP32 .pcap - mesh beacons/data, capture length, repairs a "cut short" file; then opens it)' }
            @{ Idx = 27; Text = 'MAC retry rate of a run - REAL 802.11 retries per link, baseline vs attack vs cooldown, from the sniffer (no board/COM contact)' }
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
    # A CP210x/CH340 can take several seconds to enumerate after plug-in (driver
    # load), so poll instead of one fixed 800 ms look - a single early look
    # misses a slow board and reports "no new port" while it is still appearing.
    $new = @()
    for ($try = 0; $try -lt 12 -and $new.Count -eq 0; $try++) {
        Start-Sleep -Milliseconds 700
        $after = @(Get-PortList | Select-Object -ExpandProperty Port)
        $new = @($after | Where-Object { $before -notcontains $_ })
    }
    if ($new.Count -gt 0) { Start-Sleep -Milliseconds 1200 }   # let a second new port (hub) show up too
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
    Write-Host "  No new port detected after ~8 s." -ForegroundColor Yellow
    Write-Host "  If the board was already plugged in before this prompt, or Windows gave it a COM number that was already listed," -ForegroundColor DarkGray
    Write-Host "  it can't show up as 'new' - pick it from the list ([4] identify reads its MAC) or type it manually." -ForegroundColor DarkGray
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
        # The `$_` guard matters: piping a $null $Ports (a caller that forgot
        # -Ports, or genuinely no ports) yields ONE iteration with $_ = $null,
        # whose .Port is also $null, which the -notcontains test happily passes.
        # $shown then holds a single null, Count reports 1, and the render loop
        # below dereferences $shown[0].Port into ContainsKey($null), which throws
        # "Key cannot be null" instead of printing "no COM ports detected".
        $shown = @($Ports | Where-Object { $_ -and $Taken -notcontains $_.Port })
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
            $imported = $script:ImportedSources.ContainsKey($shown[$i].Port)
            $importedTag = if ($imported) { '  << imported this session' } else { '' }
            $color = switch ($shown[$i].Kind) { 'BLOCKED' { 'DarkGray' } 'UNKNOWN' { 'Yellow' } default { 'Gray' } }
            if ($imported) { $color = 'Green' }
            Write-Host ("  [{0}] {1,-7} - {2}{3}{4}{5}" -f ($i + 1), $shown[$i].Port, $shown[$i].Description, $tag, $kindTag, $importedTag) -ForegroundColor $color
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
    $buildDir = Get-SafeBuildDir -Proj $proj -DirName "build_${role}_none_tree_$portTag"

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

function Read-UartLinkStats {
    # Listens on both boards' USB consoles while they run uart_link_test and
    # returns each board's FIRST and LAST "LINKSTAT tx= rx= lost= bad=" line.
    # The counters are cumulative since boot, so the result is the difference
    # between the two - boot-time noise (the half line a board catches when it
    # starts mid-ping) falls before the first line and never counts.
    # The clock starts once BOTH boards have reported (or after a 10 s grace, so
    # a dead board can't hang this), then runs $Seconds.
    param([string]$PortA, [string]$PortB, [int]$Seconds)
    $res = [ordered]@{}
    foreach ($k in @('A', 'B')) {
        $p = if ($k -eq 'A') { $PortA } else { $PortB }
        $res[$k] = [pscustomobject]@{ Port = $p; Sp = $null; Buf = ''; First = $null; Last = $null; Restarted = $false; Error = $null }
        try {
            $sp = New-Object System.IO.Ports.SerialPort $p, 115200
            # Both lines low so opening the port doesn't hold the ESP32 in reset.
            $sp.DtrEnable = $false; $sp.RtsEnable = $false
            # 1 MiB driver buffer: a full one is the silabser.sys BSOD trigger
            # (tools\serial_guard.py). Open() passes this to the driver.
            $sp.ReadBufferSize = 1MB
            $sp.Open()
            $res[$k].Sp = $sp
        } catch { $res[$k].Error = $_.Exception.Message }
    }

    $delta = {
        param($r)
        if (-not $r.First) { return $null }
        [pscustomobject]@{
            Tx = $r.Last.Tx - $r.First.Tx; Rx = $r.Last.Rx - $r.First.Rx
            Lost = $r.Last.Lost - $r.First.Lost; Bad = $r.Last.Bad - $r.First.Bad
        }
    }

    $graceEnd = (Get-Date).AddSeconds(10)
    $endAt    = $null
    $nextTick = (Get-Date).AddSeconds(5)
    # Q / Enter stops early and still shows results. Ctrl+C is NOT safe here: it
    # kills the script with the COM ports open mid-read, which is the trigger for
    # the silabser.sys BSOD. KeyAvailable throws when stdin is redirected
    # (scripted tests), so the key check just switches itself off then.
    $keysOk  = $true
    $stopped = $false
    $started = Get-Date
    Write-Host ("Listening on {0} (Node A) and {1} (Node B) ..." -f $PortA, $PortB) -ForegroundColor DarkGray
    Write-Host "  Press Q or Enter to stop early and see the results so far (not Ctrl+C)." -ForegroundColor DarkGray
    try {
        while ($true) {
            if ($keysOk) {
                try {
                    while ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Q' -or $key.Key -eq 'Enter') { $stopped = $true }
                    }
                } catch { $keysOk = $false }
                if ($stopped) { break }
            }
            foreach ($r in $res.Values) {
                if (-not $r.Sp) { continue }
                try { $r.Buf += $r.Sp.ReadExisting() } catch { $r.Error = $_.Exception.Message; continue }
                while (($nl = $r.Buf.IndexOf("`n")) -ge 0) {
                    $line  = $r.Buf.Substring(0, $nl).Trim()
                    $r.Buf = $r.Buf.Substring($nl + 1)
                    if ($line -match 'LINKSTAT tx=(\d+) rx=(\d+) lost=(\d+) bad=(\d+)') {
                        $s = [pscustomobject]@{ Tx = [long]$Matches[1]; Rx = [long]$Matches[2]; Lost = [long]$Matches[3]; Bad = [long]$Matches[4] }
                        # Counters going DOWN = this board rebooted mid-listen;
                        # measure from the reboot on rather than report nonsense.
                        if ($r.Last -and $s.Tx -lt $r.Last.Tx) { $r.First = $s; $r.Restarted = $true }
                        if (-not $r.First) { $r.First = $s }
                        $r.Last = $s
                    }
                }
            }
            if (-not $endAt -and ((($res.A.First) -and ($res.B.First)) -or (Get-Date) -ge $graceEnd)) {
                $endAt = (Get-Date).AddSeconds($Seconds)
            }
            if ($endAt -and (Get-Date) -ge $endAt) { break }
            if ($endAt -and (Get-Date) -ge $nextTick) {
                $left = [int][math]::Ceiling(($endAt - (Get-Date)).TotalSeconds)
                $da = & $delta $res.A
                $db = & $delta $res.B
                $fa = if ($da) { "A got {0} lost {1}" -f $da.Rx, $da.Lost } else { 'A: no LINKSTAT yet' }
                $fb = if ($db) { "B got {0} lost {1}" -f $db.Rx, $db.Lost } else { 'B: no LINKSTAT yet' }
                Write-Host ("  {0,3} s left   {1}   {2}" -f $left, $fa, $fb) -ForegroundColor DarkGray
                $nextTick = (Get-Date).AddSeconds(5)
            }
            Start-Sleep -Milliseconds 100
        }
    }
    finally {
        foreach ($r in $res.Values) { if ($r.Sp) { try { $r.Sp.Close() } catch { } } }
    }
    if ($stopped) {
        Write-Host ("  Stopped early after {0} s - the results below cover only that time." -f [int]((Get-Date) - $started).TotalSeconds) -ForegroundColor Yellow
    }
    foreach ($r in $res.Values) { $r | Add-Member -NotePropertyName Delta -NotePropertyValue (& $delta $r) -Force }
    return $res
}

function Write-UartTunnelResults {
    # One row per direction. A row is judged by the RECEIVING board's counters
    # (only the receiver can see what arrived); "Sent" is the sender's own count
    # over the same window, for scale. Lost includes garbled pings: a garbled
    # ping is dropped, so the next good one shows a sequence gap.
    param($Stats)
    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  RESULTS" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  Direction              Sent  Received    Lost  Garbled  Verdict"

    $verdicts = @{}
    foreach ($dir in @(@{ From = 'A'; To = 'B' }, @{ From = 'B'; To = 'A' })) {
        $snd = $Stats[$dir.From].Delta
        $rcv = $Stats[$dir.To].Delta
        $label = "{0} -> {1} ({1}'s GPIO16)" -f $dir.From, $dir.To
        $sent  = if ($snd) { $snd.Tx } else { '?' }
        if (-not $rcv) {
            $v = 'NODATA'
            $row = "  {0,-20} {1,6}  {2,8}  {3,6}  {4,7}  " -f $label, $sent, '?', '?', '?'
            $vText = "[NO DATA] board $($dir.To) never reported"; $vColor = 'Red'
        }
        else {
            $row = "  {0,-20} {1,6}  {2,8}  {3,6}  {4,7}  " -f $label, $sent, $rcv.Rx, $rcv.Lost, $rcv.Bad
            if ($rcv.Rx -eq 0) { $v = 'FAIL'; $vText = '[FAIL]'; $vColor = 'Red' }
            elseif ($rcv.Lost -eq 0 -and $rcv.Bad -eq 0) { $v = 'PASS'; $vText = '[PASS]'; $vColor = 'Green' }
            else {
                $v = 'WARN'
                $pct = 100.0 * $rcv.Lost / ($rcv.Rx + $rcv.Lost)
                $vText = '[WARN] {0:N1}% lost' -f $pct; $vColor = 'Yellow'
            }
        }
        $verdicts[$dir.From + $dir.To] = $v
        Write-Host -NoNewline $row
        Write-Host -NoNewline $vText -ForegroundColor $vColor
        if ($dir.From -eq 'B') { Write-Host "   <- the attack uses this one" -ForegroundColor DarkGray } else { Write-Host "" }
    }

    Write-Host ""
    foreach ($k in @('A', 'B')) {
        $r = $Stats[$k]
        if ($r.Error) {
            Write-Host ("  Node {0} ({1}): could not read the port - {2}" -f $k, $r.Port, $r.Error) -ForegroundColor Red
            Write-Host "  Close any idf.py monitor / serial terminal holding it - only one program can open a COM port." -ForegroundColor Yellow
        }
        elseif (-not $r.Delta) {
            Write-Host ("  Node {0} ({1}) printed no LINKSTAT lines - it is not running uart_link_test" -f $k, $r.Port) -ForegroundColor Red
            Write-Host "  (flash failed or it is stuck in the bootloader - press its EN/RST button and listen again)." -ForegroundColor Yellow
        }
        elseif ($r.Restarted) {
            Write-Host ("  Node {0} ({1}) rebooted while listening - its numbers cover only the time after that reboot." -f $k, $r.Port) -ForegroundColor Yellow
        }
    }

    $ba = $verdicts['BA']; $ab = $verdicts['AB']
    if ($ba -eq 'PASS' -and $ab -eq 'PASS') {
        Write-Host "  TUNNEL WIRE OK both ways - safe to start the wormhole capture." -ForegroundColor Green
    }
    elseif ($ba -eq 'PASS') {
        Write-Host "  B -> A (the direction the wormhole uses) is GOOD." -ForegroundColor Green
        Write-Host "  A -> B is not clean. The wormhole firmware never sends A -> B, so a capture still works," -ForegroundColor Yellow
        Write-Host "  but a bad wire in a bundle often means the others are loose too - reseat it." -ForegroundColor Yellow
    }
    elseif ($ba -eq 'WARN') {
        Write-Host "  B -> A works but DROPS pings - a loose joint or noise along the wire from B GPIO17 to A GPIO16." -ForegroundColor Yellow
        Write-Host "  In a capture every drop is a probe the tunnel never delivered (fewer duplicates at the root)." -ForegroundColor Yellow
        Write-Host "  Reseat every joint on that wire, use fewer/longer jumpers, twist it with the GND wire." -ForegroundColor Yellow
    }
    elseif ($ba -eq 'FAIL') {
        Write-Host "  The wire from B GPIO17 to A GPIO16 delivers NOTHING." -ForegroundColor Red
        Write-Host "  B tunnels probes TO A, so a wormhole capture now would carry NO attack signature." -ForegroundColor Red
    }
    if ($ba -eq 'FAIL' -or $ab -eq 'FAIL') {
        Write-Host ""
        Write-Host "  Check: TX/RX CROSSED (17 -> 16), GND shared between the boards, every joint along the chain." -ForegroundColor Yellow
        Write-Host "  Isolate: jumper ONE board's own GPIO17 -> GPIO16 and listen again. That board's row passing" -ForegroundColor Yellow
        Write-Host "  means the board is fine and the fault is the wire between the boards." -ForegroundColor Yellow
    }
}

function Invoke-UartTunnelTest {
    # Checks the wormhole's physical A<->B UART wire on its own, without a mesh,
    # a roster or a capture: flashes uart_link_test (ESP32-Environment\
    # uart_link_test, same UART1 pins + baud as WORMHOLE_UART_* in mesh_config.h)
    # to both tunnel boards and reads both consoles at once. The quick check
    # answers "is it connected"; the soak counts lost/garbled pings, which is
    # what matters for long or chained jumper wires. Overwrites both boards'
    # firmware - a normal wormhole capture run flashes the real firmware back.
    if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "idf.py is not on PATH - run this from the 'ESP-IDF 5.3 PowerShell' window." -ForegroundColor Red
        return
    }

    $ports = Get-PortList
    $portA = Select-Port -For 'Node A (tunnel EXIT - RECEIVES the tunnelled probes)' -Ports $ports
    if (-not $portA) { return }
    $portB = Select-Port -For 'Node B (tunnel ENTRY - SENDS probes into the tunnel)' -Ports $ports -Taken @($portA)
    if (-not $portB) { return }
    if ($portA -eq $portB) {
        Write-Host "  Node A and Node B must be two different boards on two different ports." -ForegroundColor Red
        return
    }

    $durIdx = Show-Menu -Title 'How long to test?' -Options @(
        'Quick check - 10 s, is the wire connected at all',
        'Soak test   - 2 min, counts LOST and GARBLED pings each way (use this for long / extended jumper wires)'
    ) -DefaultIndex 0
    $secs = if ($durIdx -eq 1) { 120 } else { 10 }

    $proj = 'uart_link_test'
    $dir  = Get-SafeBuildDir -Proj $proj -DirName 'build_uart_link_test'
    # sdkconfig inside the build dir, not the project folder - the project has
    # none checked in, and idf.py would otherwise drop one into the repo.
    $sdkArg = "-DSDKCONFIG=$(Join-Path $dir 'sdkconfig')"
    # Same self-heal as run.ps1: a build dir configured for a moved/re-cloned
    # repo path hard-fails idf.py, so wipe it and let it reconfigure.
    $cache = Join-Path $dir 'CMakeCache.txt'
    if (Test-Path $cache) {
        $want = ((Join-Path $base $proj) -replace '\\', '/').TrimEnd('/')
        $line = Select-String -Path $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
        if ($line -and (($line.Line -split '=', 2)[1].TrimEnd('/') -ne $want)) { Remove-Item -Recurse -Force $dir }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  WORMHOLE UART TUNNEL TEST - no mesh, no capture, no export" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host ("  Node A   : {0}" -f $portA)
    Write-Host ("  Node B   : {0}" -f $portB)
    Write-Host "  Wire     : A GPIO17 -> B GPIO16,  A GPIO16 <- B GPIO17,  GND <-> GND  (crossed)"
    Write-Host "  Link     : UART1, 115200 baud (same as WORMHOLE_UART_* in mesh_config.h)"
    Write-Host ("  Duration : {0}" -f $(if ($secs -eq 120) { 'soak test (2 min)' } else { 'quick check (10 s)' }))
    Write-Host ("  Build dir: {0}" -f $dir) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Both boards are FLASHED with uart_link_test - re-flash the real wormhole" -ForegroundColor Yellow
    Write-Host "  firmware (a normal capture run does this) before capturing. Leave the wires on." -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "`nDRY RUN - would build + flash here; not touching real hardware." -ForegroundColor Yellow
        return
    }

    $go = Read-Line ("`nBuild and flash uart_link_test to {0} (Node A) AND {1} (Node B) now? [y/N] > " -f $portA, $portB)
    if ($go -ne 'y' -and $go -ne 'Y') { Write-Host "  Cancelled." -ForegroundColor DarkGray; return }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location (Join-Path $base $proj)
    try {
        foreach ($t in @(@{ Port = $portA; Name = 'Node A' }, @{ Port = $portB; Name = 'Node B' })) {
            Write-Host ("`nFlashing {0} ({1}) - the first time also compiles, ~1 min ..." -f $t.Port, $t.Name) -ForegroundColor Cyan
            $global:LASTEXITCODE = 0
            idf.py -B $dir $sdkArg -p $t.Port flash
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Flash failed (usually a USB serial glitch) - retrying once at 115200 baud ..." -ForegroundColor Yellow
                idf.py -B $dir $sdkArg -p $t.Port -b 115200 flash
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("BUILD/FLASH FAILED on {0} ({1}) - nothing to listen to. A compile error is in" -f $t.Port, $t.Name) -ForegroundColor Red
                Write-Host "uart_link_test\main\uart_link_test.c; a flash error is usually the cable or a hub." -ForegroundColor Red
                return
            }
        }
    }
    finally { Pop-Location; $ErrorActionPreference = $prevEap }
    Write-Host "`nBoth boards flashed OK." -ForegroundColor Green
    Start-Sleep -Seconds 2   # Node B was reset by its flash a moment ago

    while ($true) {
        $stats = Read-UartLinkStats -PortA $portA -PortB $portB -Seconds $secs
        Write-UartTunnelResults -Stats $stats
        $other = if ($secs -eq 120) { 'Quick check now (10 s)' } else { 'Soak test now (2 min) - for long / extended wires' }
        $next = Show-Menu -Title 'Next?' -Options @(
            ("Listen again for {0} s - same boards, NO reflash (e.g. after reseating or wiggling a wire)" -f $secs),
            ("{0} - no reflash" -f $other),
            'Done - back to the main menu'
        ) -DefaultIndex 2
        if ($next -eq 2) { break }
        if ($next -eq 1) { $secs = if ($secs -eq 120) { 10 } else { 120 } }
    }

    Write-Host ""
    Write-Host ("Reminder: {0} and {1} still run uart_link_test. A wormhole capture run re-flashes them." -f $portA, $portB) -ForegroundColor Yellow
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

function Get-RunStampRaw {
    # The sortable ISO stamp a card file should be dated by.
    #
    # Prefers runs.csv's "started" - when the run ACTUALLY RAN - and falls back
    # to "built" (when the firmware was COMPILED) only for cards written before
    # the clock anchor existed. The fallback matters: a build stamp is identical
    # on every boot of one flash, so sorting by it puts every capture from one
    # flash in an arbitrary order and makes a re-run look like the original.
    # Mirrored in menu.ps1 - keep the two in sync.
    param($File)
    if ($File.started) { return [string]$File.started }
    if ($File.built)   { return [string]$File.built }
    return ''
}

function Test-RunStampEstimated {
    # $true when the stamp above is an EXTRAPOLATION from the firmware build
    # time rather than a real clock: either the board has never been given one
    # (runs.csv clock_src = "build"), or the card predates the clock anchor and
    # carries only a build stamp. The picker prefixes these with "~" so an
    # estimate can never be copied into notes as a measured capture time.
    # Mirrored in menu.ps1 - keep the two in sync.
    param($File)
    if ($File.started) { return ($File.clock_src -ne 'host') }
    return $true
}

function Format-RunStamp {
    # "2026-09-22 18:03:41" -> "09 / 22 / 2026 18:03", the leftmost column of
    # the card file picker, with "~" prepended for an estimate. Padded to 21
    # chars at the call site - 20 for the stamp plus the "~" - so the "|" after
    # it lines up down the list whether or not a given file has a stamp and
    # whether or not that stamp is an estimate.
    # Mirrored in menu.ps1 - keep the two in sync.
    param($File)
    $raw = Get-RunStampRaw $File
    if ($raw -match '^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})') {
        $t = ('{0} / {1} / {2} {3}:{4}' -f $Matches[2], $Matches[3], $Matches[1], $Matches[4], $Matches[5])
        if (Test-RunStampEstimated $File) { return "~$t" }
        return $t
    }
    return '(no date on card)'
}

function Format-ByteSize {
    # Bytes -> "812 B" / "43.2 KB" / "1.19 MB", for the file picker's size
    # column. Only used where a row count is unavailable (the over-USB listing),
    # so it has to be readable at a glance rather than exact.
    param([Parameter(Mandatory)][long]$Bytes)
    if ($Bytes -lt 0)       { return 'size unknown' }
    if ($Bytes -lt 1024)    { return ("{0} B" -f $Bytes) }
    if ($Bytes -lt 1048576) { return ("{0:N1} KB" -f ($Bytes / 1024)) }
    return ("{0:N2} MB" -f ($Bytes / 1048576))
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
    # Pass EITHER -Card (a pulled card: delete with Remove-Item) OR -Port (the
    # card still in a board: delete with export_logs.py --delete-sd-file, which
    # sends the firmware's DELETE_SD_FILE). Both give the operator the same 'd'
    # command; only the mechanism differs. -NoDelete still hides 'd' entirely
    # for any caller that wants a read-only picker.
    # A file the board currently has OPEN (the run in progress) is deleted too:
    # the firmware closes its SD copy first, and that run carries on logging to
    # SPIFFS only. The board accepts only *_telem.csv / *_arrivals.csv, so
    # runs.csv is never reachable this way.
    param([Parameter(Mandatory)]$Files, [string]$Card, [string]$Port, [switch]$NoDelete)

    # Sorted newest-RUN-first; unknown stamps sink to the bottom (they can only
    # be pre-anchor firmware, i.e. older than anything that has one).
    $sorted = @($Files | Sort-Object `
        @{ Expression = { Get-RunStampRaw $_ }; Descending = $true }, `
        @{ Expression = { '{0}/{1}/{2}' -f $_.attack, $_.topology, $_.location } }, `
        @{ Expression = { [int]$_.boot } })

    # Plain foreach rather than Where-Object | Select-Object -ExpandProperty:
    # this is compared with -eq against a scalar below, and a 1-element array on
    # the right of -eq is the classic PowerShell footgun (it coerces rather than
    # compares cleanly). A loop yields a string or nothing, never an array.
    $newest = ''
    foreach ($cf in $sorted) {
        $cs = Get-RunStampRaw $cf
        if ($cs) { $newest = $cs; break }
    }

    $draw = {
        Write-Host ""
        Write-Host "On this card:" -ForegroundColor Cyan
        Write-Host "  (leftmost column = when the run ACTUALLY RAN, from runs.csv. Newest first;" -ForegroundColor DarkGray
        Write-Host "   green = newest on this card, yellow = left behind by an earlier session.)" -ForegroundColor DarkGray
        Write-Host "  A leading ~ means that board has never been given a real clock, so the time" -ForegroundColor DarkGray
        Write-Host "   is EXTRAPOLATED from when its firmware was built - treat it as approximate." -ForegroundColor DarkGray
        Write-Host "   Exporting from this laptop once gives that board a real clock from then on." -ForegroundColor DarkGray
        Write-Host ""
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $f = $sorted[$i]
            $stamp = Format-RunStamp $f
            $fStamp = Get-RunStampRaw $f
            # Green = the most recent capture on this card (almost always "the
            # run you just did"); yellow = an earlier session left this here.
            # The "~" in $stamp, not the colour, carries "this is an estimate" -
            # recency and certainty are two different facts and collapsing them
            # into one colour would hide whichever lost.
            $stampColor = if (-not $fStamp) { 'DarkGray' }
                          elseif ($newest -and $fStamp -eq $newest) { 'Green' }
                          else { 'Yellow' }
            Write-Host ("  [{0}] " -f ($i + 1)) -NoNewline
            Write-Host ("{0,-21}" -f $stamp) -NoNewline -ForegroundColor $stampColor
            Write-Host (" | {0}" -f $f.name)

            $bits = @("{0}/{1}/{2}" -f $f.attack, $f.topology, $f.location)
            $bits += "boot $($f.boot)"
            if ($null -ne $f.run) { $bits += "run $($f.run)" }
            # $null = the source could not answer cheaply (the over-USB path,
            # where counting means streaming the file off the card first). It
            # must NOT render as "0 rows": 0 is a real, meaningful state here -
            # it is what a reset-interrupted capture looked like before the
            # fsync fix - and conflating the two would hide exactly the failure
            # this listing exists to surface. Show the byte size instead, which
            # always comes back and answers the same question well enough.
            if ($null -eq $f.rows) {
                $sizeTxt = if ($null -ne $f.bytes -and $f.bytes -ge 0) { Format-ByteSize $f.bytes } else { 'size unknown' }
                $bits += "rows unknown ($sizeTxt)"
            } else {
                $bits += "$($f.rows) rows"
                if ($f.rows -eq 0) { $bits += 'EMPTY - nothing was flushed to the card' }
            }
            if ($f.archived) { $bits += '_archive' }
            $noteColor = 'DarkGray'
            # What the file HOLDS, not just how it ended (mounted card only -
            # $null over USB). Only phase 255 = the board stopped before the
            # root's schedule reached it: no experiment data at all.
            $noData = Test-NoExperimentData $f
            if ($noData) { $bits += 'NO EXPERIMENT DATA (only pre-run phase 255 - not the run; check the card''s _archive\)' }
            elseif ($null -ne $f.phases) { $bits += ('phases ' + ((@($f.phases) | Where-Object { $_ -ne 255 }) -join ',')) }
            # live wins over clean=false: a run in progress is NOT an aborted one.
            if ($f.live -eq $true) {
                $bits += 'STILL RUNNING (board is mid-run - do not import yet)'
                $noteColor = 'Yellow'
            }
            elseif ($f.clean -eq $false) {
                $bits += 'ABORTED (started, never closed cleanly)'
                $noteColor = 'Yellow'
            }
            if ($noData) { $noteColor = 'Red' }
            # With no row count (USB listing of an unclosed file, or any arrivals
            # file) import_sdcard.py can only match node + repeat, NOT the boot -
            # so this may be an older run with the same repeat number, not this
            # file. Saying "already imported" there made a new run look done.
            if ($f.already -and $null -eq $f.rows) {
                $bits += "same node + repeat already in exports ($($f.already)) - may be an OLDER run; a new run needs a new repeat number"
                $noteColor = 'Yellow'
            }
            elseif ($f.already) { $bits += "already imported as $($f.already)"; $noteColor = 'DarkGray' }
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
        $canDelete = (-not $NoDelete) -and ($Card -or $Port)
        $prompt = if (-not $canDelete) {
            "`nImport which? numbers (e.g. 1,3 or 1-{0}), 'a' = ALL, 'c' = cancel > "
        } else {
            "`nImport which? numbers (e.g. 1,3 or 1-{0}), 'a' = ALL, 'd1,3' = delete those from the card (no import), 'c' = cancel > "
        }
        $raw = Read-Line ($prompt -f $sorted.Count) -Redraw $draw
        if (-not $raw) { Write-Host "  Type numbers, 'a', 'd<numbers>' or 'c'." -ForegroundColor Yellow; continue }
        $raw = $raw.Trim()
        if ($raw -eq 'c' -or $raw -eq 'C') { return $null }

        if ($raw -match '^[dD]\s*(.+)$' -and -not $canDelete) {
            Write-Host "  Deleting is not available from this listing." -ForegroundColor Yellow
            continue
        }
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
            foreach ($d in $toDelete) {
                $tag = if ($d.live -eq $true) { '   << RUN IN PROGRESS - its card copy stops here (SPIFFS keeps logging)' } else { '' }
                Write-Host ("    {0}{1}" -f $d.name, $tag) -ForegroundColor Red
            }
            $confirm = Read-Line ("  Delete {0} file(s) from the card? [y/N] > " -f $toDelete.Count)
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "  Cancelled - nothing deleted." -ForegroundColor DarkGray
                continue
            }

            $deletedRel = @()
            foreach ($d in $toDelete) {
                if ($Card) {
                    $full = Join-Path $Card $d.rel
                    try {
                        Remove-Item -LiteralPath $full -Force -ErrorAction Stop
                        Write-Host ("    Deleted {0}" -f $d.name) -ForegroundColor Green
                        $deletedRel += $d.rel
                    }
                    catch { Write-Host ("    FAILED to delete {0}: {1}" -f $d.name, $_.Exception.Message) -ForegroundColor Yellow }
                }
                elseif ($Port) {
                    # The board wants card-relative FORWARD slashes; a mounted-card
                    # listing reports Windows separators, so normalise either shape.
                    # [char]92 rather than a backslash literal: as a regex, '\' alone is an
                    # illegal trailing escape, and .Replace() is a plain string swap.
                    $rel = $d.rel.Replace([string][char]92, '/')
                    Push-Location (Join-Path $base 'tools')
                    $prevEap = $ErrorActionPreference
                    try {
                        # MUST be 'Continue' around the native call. Under the
                        # script-wide 'Stop' (line ~60), PS 5.1 turns a native
                        # command's first 2>&1 stderr line into a TERMINATING error --
                        # and export_logs.py prints its failure hint to stderr. That
                        # unwound past this loop to Import-OneSdCard's catch, which
                        # reported a bogus "Could not run import_sdcard.py / Is python
                        # on PATH?" and abandoned every remaining file in the same
                        # selection. Invoke-DeleteSdFolder already does this; the
                        # per-file path has to as well.
                        $ErrorActionPreference = 'Continue'
                        $out = & python -u export_logs.py --port $Port --delete-sd-file $rel 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host ("    Deleted {0}" -f $d.name) -ForegroundColor Green
                            $deletedRel += $d.rel
                        }
                        else {
                            $err = (@($out) | Where-Object { "$_" -match 'ERROR:' } | Select-Object -First 1)
                            $err = "$err".Trim()
                            # One board refusing a file must NOT stop the others: a
                            # selection routinely mixes the live run with old captures.
                            if ($err -match 'SD_FILE_IN_USE') {
                                Write-Host ("    SKIPPED {0}" -f $d.name) -ForegroundColor Yellow
                                Write-Host "      The board is writing to this file RIGHT NOW and did not release it" -ForegroundColor Yellow
                                Write-Host "      within 5 s - or its firmware predates live-file delete (reflash it)." -ForegroundColor Yellow
                                Write-Host "      Otherwise let it reach TERMINATE, then delete it." -ForegroundColor Yellow
                            }
                            else {
                                if (-not $err) { $err = 'the board did not confirm the delete' }
                                Write-Host ("    FAILED to delete {0}" -f $d.name) -ForegroundColor Yellow
                                Write-Host ("      {0}" -f $err) -ForegroundColor Yellow
                            }
                        }
                    }
                    catch {
                        Write-Host ("    FAILED to delete {0}: {1}" -f $d.name, $_.Exception.Message) -ForegroundColor Yellow
                    }
                    finally { $ErrorActionPreference = $prevEap; Pop-Location }
                }
                else {
                    Write-Host ("    Skipped {0} - no card path or port known." -f $d.name) -ForegroundColor Yellow
                    continue
                }
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
        # A file the board is STILL WRITING is not a candidate at all: it is not
        # a dead run, it is an unfinished one, and importing it yields a partial
        # capture indistinguishable from a complete one. Drop it before the
        # aborted prompt so it is never offered as "import anyway?".
        $liveSel = @($picked | Where-Object { $_.live -eq $true })
        if ($liveSel.Count -gt 0) {
            Write-Host ""
            foreach ($lv in $liveSel) {
                Write-Host ("  STILL RUNNING: {0}" -f $lv.name) -ForegroundColor Yellow
            }
            Write-Host "  That board is mid-run - the file is still being written." -ForegroundColor Yellow
            Write-Host "  Let the run reach TERMINATE, then export." -ForegroundColor Yellow
            # Over USB the board can be told to finish now (firmware END_RUN):
            # it closes the file cleanly, so nothing is lost by pulling the card
            # later. Only offered with -Port - a pulled card has no board to ask.
            if ($Port) {
                Write-Host ""
                Write-Host "  If the run is OVER (root finished, or this board missed TERMINATE)," -ForegroundColor Yellow
                Write-Host "  this board can close its file now. If it is still mid-run, the" -ForegroundColor Yellow
                Write-Host "  capture is cut short and stays marked ABORTED." -ForegroundColor Yellow
                $ans = Read-Host "  End this board's run now and close its file? [y/N]"
                if ($ans -match '^[Yy]') {
                    Push-Location (Join-Path $base 'tools')
                    $prevEap = $ErrorActionPreference
                    try {
                        $ErrorActionPreference = 'Continue'
                        $out = & python -u export_logs.py --port $Port --end-run 2>&1
                    }
                    finally { $ErrorActionPreference = $prevEap; Pop-Location }
                    $res = (@($out) | Where-Object { "$_" -match '^END_RUN_RESULT:' } | Select-Object -First 1)
                    $res = "$res" -replace '^END_RUN_RESULT:\s*', ''
                    switch ($res.Trim()) {
                        'COMPLETE'  { Write-Host "  Closed. The run had reached cooldown - capture is complete." -ForegroundColor Green }
                        'CUT_SHORT' { Write-Host "  Closed, but BEFORE cooldown - the capture is cut short (stays ABORTED)." -ForegroundColor Yellow }
                        'ALREADY'   { Write-Host "  The run had already ended on this board." -ForegroundColor Green }
                        default {
                            Write-Host "  END_RUN failed:" -ForegroundColor Red
                            @($out) | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
                        }
                    }
                    if ($res.Trim() -in @('COMPLETE', 'CUT_SHORT', 'ALREADY')) {
                        Write-Host "  Run the export again - the file now lists as closed." -ForegroundColor Cyan
                    }
                }
            }
            $picked = @($picked | Where-Object { $_.live -ne $true })
            if ($picked.Count -eq 0) {
                Write-Host "  Nothing left selected." -ForegroundColor DarkGray
                return $null
            }
        }

        $aborted = @($picked | Where-Object { $_.clean -eq $false })
        $includeAborted = $false
        if ($aborted.Count -gt 0) {
            Write-Host ""
            foreach ($a in $aborted) {
                $cause = Get-AbortCauseText $a
                if ($cause) { Write-Host ("  WHY: {0} {1}" -f $a.name, $cause) -ForegroundColor Yellow }
                if (Test-NoExperimentData $a) {
                    Write-Host ("  ABORTED: {0}  - NO EXPERIMENT DATA: only pre-run phase 255 rows. This boot never" -f $a.name) -ForegroundColor Red
                    Write-Host  "           heard the root's schedule, so it is NOT the run. Importing it adds nothing -" -ForegroundColor Red
                    Write-Host  "           validate_integrity FAILs it and analysis skips it. The run's own file is often" -ForegroundColor Red
                    Write-Host  "           in this card's _archive\ folder (the importer skips it) - look there first." -ForegroundColor Red
                    Write-Host  "           (Only firmware before sep. 25, 2026 writes these files or archives at boot.)" -ForegroundColor DarkGray
                } elseif ($null -ne $a.phases) {
                    Write-Host ("  ABORTED: {0}  - reached phase(s) {1}; ends early, the rest of the run is missing" -f $a.name, ((@($a.phases) | Where-Object { $_ -ne 255 }) -join ',')) -ForegroundColor Yellow
                } else {
                    Write-Host ("  ABORTED: {0}" -f $a.name) -ForegroundColor Yellow
                }
            }
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
    #
    # SOURCE: pass EITHER -Card (a pulled card in a reader) OR -Port (a running
    # board, read over USB). Everything after the source - the picker, the dry
    # run, the confirmation, the import itself - is identical, because
    # import_sdcard.py reports both sources in one --list-json shape. Keeping
    # this as ONE function is the point: two copies would drift, and the half
    # that is used less would be the one that rots.
    param([string]$Card, [string]$Port, [int]$Repeat, [string]$Boots, [switch]$IncludeAborted,
          [string]$Roster, [switch]$DeleteSource, [string]$ExpectPrefix, [string]$Scenario = 'stationary')

    # Set true only once a real (non-dry-run) copy exits 0 below. A script-scoped
    # flag, not a return value: the real-copy call further down is deliberately
    # left uncaptured (see its own comment) so its progress bar draws live -
    # giving this function a return value would risk that same call being
    # captured by a caller that assigns Import-OneSdCard's result.
    $script:LastImportOk = $false

    if (-not $Card -and -not $Port) {
        Write-Host "  Import-OneSdCard needs -Card or -Port." -ForegroundColor Red
        return
    }
    if ($Card -and -not (Test-Path $Card)) {
        Write-Host ("  {0} is not reachable right now." -f $Card) -ForegroundColor Yellow
        return
    }

    # The one place the two sources differ, expressed once and reused below.
    $srcArgs  = if ($Card) { @('--card', $Card) } else { @('--port', $Port) }
    $srcLabel = if ($Card) { $Card } else { "$Port (card still in the board)" }

    $pyArgs = @('import_sdcard.py') + $srcArgs + @('--repeat', $Repeat, '--scenario', $Scenario)
    if ($Boots) { $pyArgs += @('--boots', $Boots) }
    if ($IncludeAborted) { $pyArgs += '--include-aborted' }
    if ($Roster) { $pyArgs += @('--roster', $Roster) }
    if ($DeleteSource) { $pyArgs += '--delete-source' }

    Write-Host ""
    Write-Host ("Scanning {0} (repeat {1}) ..." -f $srcLabel, $Repeat) -ForegroundColor DarkGray
    if ($Port) {
        Write-Host "  Reading the card over USB - this leaves it in the board. Close idf.py monitor if this stalls." -ForegroundColor DarkGray
    }
    Push-Location (Join-Path $base 'tools')
    try {
        # What's on the card, before anything is selected or copied. Separate
        # from the dry run below on purpose: this is the pick-by-number list
        # (with each file's firmware build date), the dry run is the preview of
        # the copy the selection produces.
        $listArgs = @('import_sdcard.py') + $srcArgs + @('--repeat', $Repeat, '--scenario', $Scenario)
        if ($Roster) { $listArgs += @('--roster', $Roster) }
        $listOut = & python @listArgs --list-json 2>&1
        $rc = $LASTEXITCODE
        if ($rc -ne 0) {
            $listOut | ForEach-Object { Write-Host "  $_" }
            Write-Host ("  import_sdcard.py --list-json exited {0} (python/pyserial missing? run from the ESP-IDF 5.3 PowerShell)." -f $rc) -ForegroundColor Yellow
            if ($Port) {
                Write-Host "  Over USB this usually means one of: idf.py monitor still holds the port, the board" -ForegroundColor DarkGray
                Write-Host "  has no card in it, or it is running firmware older than LIST_SD (reflash it)." -ForegroundColor DarkGray
            }
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

        $sel = Select-CardFiles -Files $cardFiles -Card $Card -Port $Port
        if ($null -eq $sel) {
            Write-Host "  Cancelled - nothing copied." -ForegroundColor DarkGray
            return
        }
        if ($sel.Rel.Count -gt 0) { $pyArgs += @('--files', ($sel.Rel -join ',')) }
        if ($sel.IncludeAborted -and $pyArgs -notcontains '--include-aborted') { $pyArgs += '--include-aborted' }

        # MUST be 'Continue' around every native call here. Under the script-wide
        # 'Stop', PS 5.1 turns a native command's FIRST 2>&1 stderr line into a
        # TERMINATING error. The dry run survived only because it prints no
        # progress; the real copy below streams its progress bar to stderr
        # (export_logs.py's _progress), which unwound to the catch and reported a
        # bogus "Could not run import_sdcard.py / Is python on PATH?" while python
        # was working perfectly. Same trap, same fix as the delete path above.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try   { $dryOut = & python @pyArgs --dry-run 2>&1 }
        finally { $ErrorActionPreference = $prevEap }
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
            $wantPrefix = $ExpectPrefix.Replace('\', '/')
            # A wormhole control runs plain firmware, so its card says baseline/;
            # import_sdcard.py follows it with "FILED UNDER <attack>/" when it
            # belongs to an attack run. Judge that file by where it is filed.
            $dryLines = @($dryOut | ForEach-Object { "$_" })
            $foreign = @()
            for ($i = 0; $i -lt $dryLines.Count; $i++) {
                $mm = [regex]::Match($dryLines[$i], '^\s*(?:WOULD COPY|SKIP)\s+(\S+)')
                if (-not $mm.Success) { continue }
                $relp = $mm.Groups[1].Value.Replace('\', '/')
                for ($j = $i + 1; $j -le [Math]::Min($i + 2, $dryLines.Count - 1); $j++) {
                    $fm = [regex]::Match($dryLines[$j], 'FILED UNDER (\w+)/')
                    if ($fm.Success) { $relp = $fm.Groups[1].Value + $relp.Substring($relp.IndexOf('/')); break }
                }
                if (-not $relp.StartsWith($wantPrefix, [StringComparison]::OrdinalIgnoreCase)) { $foreign += $relp }
            }
            if ($foreign.Count -gt 0) {
                Write-Host ""
                Write-Host ("  NOTE: this card also has {0} file(s) outside {1}\ - probably a different run left on the same card. They'll still be imported/named correctly on their own; just flagging it in case the wrong card got picked." -f $foreign.Count, $ExpectPrefix) -ForegroundColor Yellow
            }
        }

        $goAns = Read-Line "`nCopy these files for real? [y/N] > "
        if ($goAns -ne 'y' -and $goAns -ne 'Y') {
            Write-Host "  Skipped - nothing copied." -ForegroundColor DarkGray
            return
        }
        # NOT captured with 2>&1 like the dry run: capturing held every line
        # until python exited (the screen looked frozen for the whole copy) and
        # turned each '\r' redraw of the progress bar into its own line. Run
        # straight on the console so the bar updates in place, live.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try   { & python @pyArgs }
        finally { $ErrorActionPreference = $prevEap }
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { Write-Host ("  import_sdcard.py exited {0} - see above." -f $rc) -ForegroundColor Yellow }
        else { $script:LastImportOk = $true }
    }
    catch {
        Write-Host ("  Could not run import_sdcard.py: {0}" -f $_.Exception.Message) -ForegroundColor Red
        # Was hardcoded "Is python on PATH? Run from the ESP-IDF 5.3 PowerShell":
        # it fires on ANY exception, so on 2026-09-22 it blamed python for a
        # stderr-promotion error while python was working perfectly, and named a
        # 5.3 window that does not exist on a 5.5 laptop. State the real causes.
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "  python is NOT on PATH - run this from the ESP-IDF PowerShell window." -ForegroundColor DarkGray
        }
        else {
            Write-Host "  python IS on PATH, so this is not a PATH problem. Usual causes: the COM" -ForegroundColor DarkGray
            Write-Host "  port is held by idf.py monitor, or the board stopped answering mid-copy." -ForegroundColor DarkGray
        }
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
    # WHERE THE CSVs COME FROM. Both routes read the SAME SD card and produce
    # the same files in exports/ - the only question is whether the card is
    # still in the board. Asked FIRST, before the run questions, because it is
    # the one decision that changes what the operator has to physically do.
    $srcIdx = Show-Menu -Title 'Where are the CSVs you want to export?' -Options @(
        'From the board over USB  (card STAYS in the board - just plug in the cable)',
        'From a pulled SD card    (card is out of the board, in a reader on this laptop)'
    ) -DefaultIndex 0 -AllowBack
    if ($srcIdx -eq -1) { return }
    $fromBoard = ($srcIdx -eq 0)

    Write-Host ""
    if ($fromBoard) {
        Write-Host "Reading the card THROUGH the board over USB - the card stays where it is." -ForegroundColor DarkGray
        Write-Host "Needs firmware with LIST_SD (reflash if the listing comes back empty), and" -ForegroundColor DarkGray
        Write-Host "idf.py monitor must be closed - only one program can hold a COM port." -ForegroundColor DarkGray
    }
    else {
        Write-Host "Pop the SD card out of the board and read it with a card reader on THIS" -ForegroundColor DarkGray
        Write-Host "laptop - nothing here touches a board or a COM port." -ForegroundColor DarkGray
    }

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

    $dirs = Get-RunDirs -Attack $attack -Topology $topology -Location $location -Scenario $scenario
    # NO scenario segment here, deliberately. This prefix is matched against a
    # CARD-relative path, and the card tree has no scenario level at all - it is
    # a host-side/ledger concept stamped at import time, exactly like --repeat
    # (see tools\import_sdcard.py's header). Appending it made the prefix
    # "<attack>\<topo>\<loc>\none", which no card path can ever start with, so
    # the "files outside this run" notice below fired on EVERY import and told
    # the operator every file was foreign. Separators are normalised at the
    # comparison, because a pulled card reports rel paths with "\" while the
    # over-USB listing reports them with "/".
    $expectPrefix = "$($dirs.AttackDir)/$($dirs.TopoDir)/$location"

    # Roster: auto-match a saved preset for this exact attack/topology/scenario/
    # location - that preset already lists the boards THIS run used (matched by
    # MAC), so a second "which roster?" prompt would just be re-answering the
    # questions just asked. Falls back to the card's own victim_NODE_<MAC>
    # naming (never an error) when nothing matches.
    $rosterPath    = ''
    $presetMatches = @(Get-PresetFiles | ForEach-Object {
        $cfg = Read-PresetFile $_.FullName
        $cfgScenario = ConvertTo-Scenario $(if ($cfg -and $cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })
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

    # This whole trip - every card until N to "another card?" - is ONE import
    # batch: what the Data sync push/pull lists show green (tools\ImportBatch.ps1).
    # Snapshot what tools\exports\ already holds, so only files copied from here
    # on count as this batch.
    $batchOn      = [bool](Get-Command Save-ImportBatch -ErrorAction SilentlyContinue)
    $batchBefore  = if ($batchOn) { @(Get-ExportCsvSet -Base $base) } else { @() }
    $batchStarted = if ($batchOn) { Get-UnixNow } else { 0 }

    # BOARD ROUTE: pick a COM port instead of a drive letter, then hand off to
    # the same Import-OneSdCard the pulled-card route uses. Everything past the
    # source - picker, dry run, confirmation, naming, exports/ layout - is
    # shared, so the two routes cannot drift apart.
    if ($fromBoard) {
        $tries = 0
        while ($true) {
            $tries++
            if ($tries -gt $script:MaxPromptTries) {
                throw "No valid board selection after $script:MaxPromptTries attempts - aborting. (Running non-interactively?)"
            }
            # -Ports is NOT optional: without it Select-Port pipes a $null down
            # its filter, $shown ends up holding one null element, and the very
            # first thing the render loop does is $shown[0].Port -> ContainsKey($null)
            # -> "Key cannot be null". Every other caller passes a list; so does this one.
            $ports = Get-PortList
            $port = Select-Port -For 'the board holding the card' -Ports $ports -AllowBack
            if (-not $port -or $port -eq $script:BackSignal) { return }
            $tries = 0

            # Same gate every other board-touching action goes through: do not
            # open a port that is not an ESP32. Reading the card is harmless in
            # itself, but the port is still opened and a Bluetooth link or a
            # random serial device is not what anyone meant to pick.
            if (-not (Test-PortSafeToTouch -Port $port -Action 'read its SD card over USB')) { continue }

            # --delete-source (auto-delete AFTER a verified copy) is still not
            # passed here, deliberately. The firmware can now remove a single
            # file (DELETE_SD_FILE), so it would work - but silently erasing a
            # board's only copy as a side effect of reading it is not something
            # to switch on by default. The picker's 'd' command is the explicit
            # opt-in, and it is offered for this USB path now.
            Import-OneSdCard -Port $port -Repeat $repeat -Roster $rosterPath `
                             -ExpectPrefix $expectPrefix -Scenario $scenario
            if ($script:LastImportOk) { $script:ImportedSources[$port] = Get-Date }
            if ($batchOn) { Save-ImportBatch -Base $base -Before $batchBefore -Started $batchStarted }

            Write-Host ""
            Write-Host "  Note: importing never deletes. To free space, use 'd<numbers>' in the" -ForegroundColor DarkGray
            Write-Host "  file list above (one capture at a time, over USB or a pulled card), or" -ForegroundColor DarkGray
            Write-Host "  the main menu's 'delete a folder from a running board's SD card'." -ForegroundColor DarkGray

            $again = Read-Line "`nExport from another board for this same run? [y/N] > "
            if ($again -ne 'y' -and $again -ne 'Y') { return }
        }
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
                $imported = $script:ImportedSources.ContainsKey($d.Root)
                $tag   = if ($d.LooksLikeCard) { '  [has baseline/blackhole/wormhole folders - looks like ours]' }
                         elseif ($d.IsRepoDrive) { '  << this project lives here - almost certainly not the card' }
                         else { '  << no attack folders found at its root' }
                if ($imported) { $tag += '  << imported this session' }
                $color = if ($imported) { 'Green' } elseif ($d.LooksLikeCard) { 'Green' } else { 'DarkGray' }
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
            if ($script:LastImportOk) { $script:ImportedSources[$cardRoot] = Get-Date }
        }
        if ($batchOn) { Save-ImportBatch -Base $base -Before $batchBefore -Started $batchStarted }

        # Multiple boards from the SAME run (root + victim + attacker cards,
        # say) share this one attack/topology/location/repeat, so offer
        # another pull before dropping back to the main menu - defaulting to
        # no, since one card is the common case now.
        $again = Read-Line "`nImport another card for this same run? [y/N] > "
        if ($again -ne 'y' -and $again -ne 'Y') { break cardFlow }
    }
}

function Invoke-ShowTopologyStructure {
    # Prints the MESH TOPOLOGY / parent-child table for an ALREADY-CAPTURED run,
    # rebuilt from its CSVs (tools\verify_topology.py --structure).
    #
    # WHY THIS IS A MENU ITEM
    #   The firmware prints this same banner over serial while a run is live, but
    #   that scrolls past and is not in the dataset - you cannot show it to a
    #   panel afterwards, and you cannot get it at all for an archived run. This
    #   rebuilds it from the exported CSVs, so any run ever captured can be
    #   printed on demand and pasted into the paper.
    #
    #   It also answers a review question directly: "show which one is parent mac
    #   address and child mac address". The UPLINK column IS the parent; every
    #   other MAC on a row is that node's own. The raw CSV's parent_mac is the
    #   parent's SoftAP BSSID (its STA MAC + 1), which is why reading the CSV by
    #   eye never lines up - this resolves it for you.
    Write-Host ""
    Write-Host "Nothing here touches a board or a COM port -- rebuilds the topology from" -ForegroundColor DarkGray
    Write-Host "an already-exported run's CSVs. UPLINK = that node's PARENT." -ForegroundColor DarkGray

    $attackIdx = Show-Menu -Title 'Which attack?' -Options @('none (baseline)', 'blackhole', 'wormhole') -DefaultIndex 1
    $sAttack   = @('none', 'blackhole', 'wormhole')[$attackIdx]
    $topoIdx   = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex 0
    $sTopology = $TOPOLOGIES[$topoIdx]
    $sLocation = Read-Line "Location (blank = search every location) > "

    # verify_topology.py takes the CLI topology name ('partial'); the wizard's
    # $TOPOLOGIES list already uses that vocabulary, so no translation needed
    # here - unlike analyze.ps1, which works in FOLDER names (partial_mesh).
    $vtArgs = @('--dir', (Join-Path $base 'datasets\exports'),
                '--topology', $sTopology, '--attack', $sAttack,
                '--expect', $sTopology, '--structure')
    if ($sLocation) { $vtArgs += @('--location', $sLocation) }

    Push-Location (Join-Path $base 'tools')
    try { python (Join-Path $base 'tools\verify_topology.py') @vtArgs }
    finally { Pop-Location }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Get-ArchiveLiveSummary {
    # What is sitting in tools/exports/ right now, grouped into the
    # <attack>/<topology>/<location>/<scenario> cells the campaign is counted in.
    param([string]$ExportsRoot)

    $cells = @{}
    if (-not (Test-Path $ExportsRoot)) { return @() }
    foreach ($f in Get-ChildItem $ExportsRoot -Recurse -File -ErrorAction SilentlyContinue) {
        if ($f.Name -eq '.gitkeep') { continue }
        $rel = $f.FullName.Substring($ExportsRoot.Length).TrimStart('\')
        $parts = $rel -split '\\'
        if ($parts.Count -lt 2) {
            # Loose file at the root of exports/ (run_ledger.csv lives here).
            $key = '(loose files)'
        } else {
            $key = ($parts[0..([Math]::Min(2, $parts.Count - 2))] -join ' / ')
        }
        if (-not $cells.ContainsKey($key)) {
            $cells[$key] = [PSCustomObject]@{
                Cell = $key; Files = 0; Bytes = 0L; Trimmed = 0; Roots = 0; Arrivals = 0
            }
        }
        $c = $cells[$key]
        $c.Files++
        $c.Bytes += $f.Length
        if ($rel -like '*trimmed*')     { $c.Trimmed++ }
        if ($f.Name -like 'root_*')     { $c.Roots++ }
        if ($f.Name -like '*arrivals*') { $c.Arrivals++ }
    }
    return @($cells.Values | Sort-Object Cell)
}

function Get-ArchiveDuplicateReport {
    # THE CHECK THAT WOULD HAVE SAVED 2026-09-22: is this capture ALREADY in an
    # archive? archive.ps1 MOVES data out of tools/exports/, which leaves the
    # git-tracked paths showing as deletions. A `git checkout` of those paths
    # "restores" files that were never lost, and the same run then exists twice --
    # inflating `runs found` in the campaign checklist and making two archive
    # folders claim the same capture.
    #
    # Name-match first (cheap), hash only the collisions, so this stays fast even
    # with a large archive/.
    param([string]$ExportsRoot, [string]$ArchiveRoot)

    $dups = @()
    if (-not (Test-Path $ExportsRoot) -or -not (Test-Path $ArchiveRoot)) { return $dups }

    $archiveByName = @{}
    foreach ($af in Get-ChildItem $ArchiveRoot -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue) {
        if (-not $archiveByName.ContainsKey($af.Name)) { $archiveByName[$af.Name] = @() }
        $archiveByName[$af.Name] += $af
    }

    foreach ($lf in Get-ChildItem $ExportsRoot -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue) {
        # run_ledger.csv is scaffold that archive.ps1 regenerates header-only every
        # time, so it is byte-identical across every archive by construction. It is
        # not a capture and flagging it as a duplicate is pure noise.
        if ($lf.Name -eq 'run_ledger.csv') { continue }
        if (-not $archiveByName.ContainsKey($lf.Name)) { continue }
        $liveHash = (Get-FileHash -Path $lf.FullName -Algorithm SHA256).Hash
        foreach ($af in $archiveByName[$lf.Name]) {
            if ($af.Length -ne $lf.Length) { continue }
            if ((Get-FileHash -Path $af.FullName -Algorithm SHA256).Hash -eq $liveHash) {
                $dups += [PSCustomObject]@{
                    Name = $lf.Name
                    In   = (Split-Path (Split-Path $af.FullName -Parent) -Leaf)
                    Where= $af.FullName.Substring($ArchiveRoot.Length).TrimStart('\')
                }
                break
            }
        }
    }
    return $dups
}

function Invoke-ArchiveMenu {
    # Wizard front end for archive.ps1. The MOVE itself stays in archive.ps1 --
    # one implementation, one place to fix. What this adds is the judgement that
    # archive.ps1 cannot make on its own: what is about to move, whether any of it
    # already lives in an archive, and whether any of it is a COMPLETE run that
    # the campaign is currently counting.
    Write-Host ""
    Write-Host "=== Archive captured data ===" -ForegroundColor Cyan
    Write-Host "Archiving MOVES datasets\exports\, generated datasets\analysis\ output, the sniffer" -ForegroundColor DarkGray
    Write-Host "captures in datasets\PCAP\ and the run logs in datasets\run_logs\ (not _archive\) into" -ForegroundColor DarkGray
    Write-Host "archive\<date>_<label>\ and resets the working tree. Nothing is deleted." -ForegroundColor DarkGray

    $exportsRoot = Join-Path $base 'datasets\exports'
    $archiveRoot = Join-Path $base 'datasets\archive'

    $cells = Get-ArchiveLiveSummary -ExportsRoot $exportsRoot
    $dataCells = @($cells | Where-Object { $_.Cell -ne '(loose files)' })

    # The sniffer captures and run logs archive.ps1 also moves (PCAP\ whole,
    # run_logs\ minus the log viewer's own _archive\).
    $pcapRoot = Join-Path $base 'datasets\PCAP'
    $logsRoot = Join-Path $base 'datasets\run_logs'
    $pcapFiles = @()
    if (Test-Path $pcapRoot) {
        $pcapFiles = @(Get-ChildItem $pcapRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.gitkeep' })
    }
    $logFiles = @()
    if (Test-Path $logsRoot) {
        $logFiles = @(Get-ChildItem $logsRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne '.gitkeep' -and $_.FullName.Substring($logsRoot.Length).TrimStart('\') -notlike '_archive\*' })
    }

    if (-not $dataCells.Count -and -not $pcapFiles.Count -and -not $logFiles.Count) {
        Write-Host ""
        Write-Host "  Nothing to archive - datasets\exports\, PCAP\ and run_logs\ hold no capture data." -ForegroundColor Yellow
        Write-Host "  (run_ledger.csv and the .gitkeep scaffold are not captures.)" -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press Enter to return to the menu" | Out-Null
        return
    }

    # ---- what is here -------------------------------------------------------
    Write-Host ""
    Write-Host "  ON DISK NOW (datasets\exports\)" -ForegroundColor Cyan
    Write-Host ("  {0,-34}{1,6}{2,10}{3,9}{4,10}" -f 'cell', 'files', 'size', 'root?', 'arrivals')
    Write-Host ("  " + ('-' * 70))
    foreach ($c in $cells) {
        $mb = if ($c.Bytes -ge 1MB) { "{0:N1} MB" -f ($c.Bytes / 1MB) } else { "{0:N0} KB" -f ($c.Bytes / 1KB) }
        $rootMark = if ($c.Roots -gt 0) { 'yes' } else { 'NO' }
        Write-Host ("  {0,-34}{1,6}{2,10}{3,9}{4,10}" -f $c.Cell, $c.Files, $mb, $rootMark, $c.Arrivals)
    }
    $pcapCount = @($pcapFiles | Where-Object { $_.Extension -eq '.pcap' -or $_.Extension -eq '.pcapng' }).Count
    $pcapBytes = [long](($pcapFiles | Measure-Object Length -Sum).Sum)
    Write-Host ""
    Write-Host ("  ALSO MOVES: {0} capture(s) in datasets\PCAP\ ({1} file(s) incl. .json, {2})" -f $pcapCount, $pcapFiles.Count, (Format-ByteSize $pcapBytes)) -ForegroundColor Cyan
    Write-Host ("              {0} run log(s) in datasets\run_logs\ (_archive\ stays)" -f $logFiles.Count) -ForegroundColor Cyan

    # ---- is any of it already archived? ------------------------------------
    Write-Host ""
    Write-Host "  Checking whether any of this is ALREADY in archive\ ..." -ForegroundColor DarkGray
    $dups = Get-ArchiveDuplicateReport -ExportsRoot $exportsRoot -ArchiveRoot $archiveRoot
    if ($dups.Count) {
        $byFolder = $dups | Group-Object In | Sort-Object Count -Descending
        Write-Host ""
        Write-Host ("  !! {0} file(s) here are BYTE-IDENTICAL to files already archived:" -f $dups.Count) -ForegroundColor Red
        foreach ($g in $byFolder) {
            Write-Host ("     {0,-40} {1} file(s)" -f $g.Name, $g.Count) -ForegroundColor Red
        }
        Write-Host "     Archiving again makes a SECOND copy of the same capture and" -ForegroundColor Yellow
        Write-Host "     inflates 'runs found' in the campaign checklist. A staged deletion" -ForegroundColor Yellow
        Write-Host "     under datasets\exports\ usually means archive.ps1 already moved it -" -ForegroundColor Yellow
        Write-Host "     check archive\ before restoring anything with git." -ForegroundColor Yellow
    } else {
        Write-Host "  None - every file here is new to archive\." -ForegroundColor Green
    }

    # ---- is any of it a COMPLETE run? --------------------------------------
    Write-Host ""
    Write-Host "  Completeness (inventory_cells.py, M4/M5 criteria) ..." -ForegroundColor DarkGray
    $completeLive = 0
    Push-Location $base
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # native stderr must not throw under 'Stop'
    try {
        $inv = & python (Join-Path $base 'tools\inventory_cells.py') --plan --repeats 1 2>&1
        $liveRows = @($inv | Select-String -Pattern '^\s*live\s+')
        foreach ($r in $liveRows) {
            $line = $r.ToString()
            Write-Host ("    {0}" -f $line.Trim()) -ForegroundColor DarkGray
            if ($line -match '\sOK\s*$') { $completeLive++ }
        }
        if (-not $liveRows.Count) {
            Write-Host "    (inventory reported no 'live' rows)" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ("    could not run inventory_cells.py: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
    }
    if ($completeLive -gt 0) {
        Write-Host ""
        Write-Host ("  NOTE: {0} COMPLETE run(s) are in here - they currently count toward M4." -f $completeLive) -ForegroundColor Yellow
        Write-Host "  Archiving keeps them counted (the checklist scans archive\ too), but" -ForegroundColor DarkGray
        Write-Host "  they leave datasets\exports\, so analyze.ps1 must be pointed at the" -ForegroundColor DarkGray
        Write-Host "  archive folder afterwards." -ForegroundColor DarkGray
    }

    # ---- a label suggestion drawn from what is actually here ---------------
    $suggest = if ($dups.Count -eq (Get-ChildItem $exportsRoot -Recurse -File -Filter '*.csv' -ErrorAction SilentlyContinue).Count -and $dups.Count -gt 0) {
        'duplicate-of-existing-archive'
    } elseif ($completeLive -eq 0) {
        'incomplete'
    } elseif ($dataCells.Count -eq 1) {
        ($dataCells[0].Cell -replace ' / ', '-')
    } else {
        'capture'
    }

    # ---- options ------------------------------------------------------------
    while ($true) {
        Write-Host ""
        Write-Host "  What do you want to do?" -ForegroundColor Cyan
        Write-Host "    [1] Preview only - show every file that would move, change NOTHING  <- default"
        Write-Host "    [2] Archive now  - prompts for a label and a reason"
        if ($dups.Count) {
            Write-Host "    [3] List the already-archived duplicates in full" -ForegroundColor Yellow
        }
        Write-Host "    [4] Cancel - go back"
        $pick = Read-Line "  Press Enter for [1], or type 1-4 > "
        if (-not $pick) { $pick = '1' }

        switch ($pick.Trim()) {
            '1' {
                Push-Location $base
                try { & (Join-Path $base 'archive.ps1') -WhatIf }
                finally { Pop-Location }
            }
            '2' {
                Write-Host ""
                if ($dups.Count) {
                    Write-Host "  Reminder: part of this is already archived (see above)." -ForegroundColor Yellow
                }
                $label = Read-Line ("  Short label for the folder [{0}] > " -f $suggest)
                if (-not $label) { $label = $suggest }
                $reason = Read-Line "  One line on WHY (recorded in the archive's README) > "
                if (-not $reason) { $reason = 'archived from the capture wizard' }
                Write-Host ""
                Write-Host ("  Will create: archive\{0}_{1}\" -f (Get-NameDate), $label) -ForegroundColor Cyan
                $go = Read-Line "  Proceed? [y/N] > "
                if ($go -eq 'y' -or $go -eq 'Y') {
                    Push-Location $base
                    try { & (Join-Path $base 'archive.ps1') -Label $label -Reason $reason -Force }
                    finally { Pop-Location }
                    Write-Host ""
                    Write-Host "  Archived. datasets\exports\ is back to a clean scaffold; PCAP\ and run_logs\ are emptied." -ForegroundColor Green
                    Read-Host "Press Enter to return to the menu" | Out-Null
                    return
                }
                Write-Host "  Cancelled - nothing moved." -ForegroundColor DarkGray
            }
            '3' {
                if (-not $dups.Count) { Write-Host "  No duplicates to list." -ForegroundColor DarkGray; continue }
                Write-Host ""
                foreach ($d in ($dups | Sort-Object Where)) {
                    Write-Host ("    {0}" -f $d.Name) -ForegroundColor Yellow
                    Write-Host ("        already at archive\{0}" -f $d.Where) -ForegroundColor DarkGray
                }
            }
            '4' { return }
            default { Write-Host "  Type 1, 2, 3 or 4." -ForegroundColor Yellow }
        }
    }
}

function Invoke-CampaignChecklist {
    # Tick-box progress table for the whole campaign, scanned from the folders.
    #
    # WHY IT SCANS INSTEAD OF TRACKING
    #   A hand-maintained checklist drifts the moment someone forgets to update
    #   it, and run_ledger.csv has sat header-only for weeks proving exactly
    #   that. This ticks a box because the CSVs are on disk AND pass the
    #   milestone criteria (root telemetry + non-empty arrivals + >= 3 children
    #   + every node >= 95% coverage), so the table cannot claim a run you do
    #   not actually have.
    #
    #   It also scans archive\*\exports\, because archive.ps1 MOVES captures out
    #   of tools\exports\ - which is how "zero wormhole captures" got written
    #   down while six complete wormhole runs were sitting in the archive.
    #
    # A capture that exists but FAILS a criterion stays unticked on purpose: it
    # has to be redone, so showing it as done would be worse than showing nothing.
    # Run the plain inventory to see WHY a given run failed.

    Write-Host ""
    Write-Host "=== Campaign progress checklist ===" -ForegroundColor Cyan
    Write-Host "Scanned from the folders only - no board/COM contact." -ForegroundColor DarkGray
    Write-Host "  [1] LIVE    - datasets\exports\ + datasets\analysis\ (what counts; archiving a run removes it)"
    Write-Host "  [2] ARCHIVE - archive\*\exports\ + archive\*\analysis\ (history)"
    $scope = 'live'
    $sAns = Read-Line "Which checklist? [1] > "
    if ($sAns -and $sAns.Trim() -eq '2') { $scope = 'archive' }

    $repeats = 1
    $ans = Read-Host "Planned repeats per cell? (1 = 128 attack + 16 benign runs, 4 = x4) [1]"
    if ($ans -and $ans.Trim() -match '^\d+$') { $repeats = [int]$ans.Trim() }

    Push-Location $base
    try {
        # Board first (oct. 7, 2026): progress bars, the next run and the next
        # field sessions on one screen; the full tick-box table follows it.
        $env:PYTHONIOENCODING = 'utf-8'
        python (Join-Path $base 'tools\inventory_cells.py') --board --scope $scope
        $sesAns = Read-Line "Show every remaining run grouped into field sessions? [y/N] > "
        if ($sesAns -eq 'y' -or $sesAns -eq 'Y') {
            python (Join-Path $base 'tools\inventory_cells.py') --sessions --scope $scope
        }
        $tblAns = Read-Line "Show the full tick-box checklist too? [Y/n] > "
        if ($tblAns -ne 'n' -and $tblAns -ne 'N') {
            python (Join-Path $base 'tools\inventory_cells.py') --checklist --scope $scope --repeats $repeats
        }
        Write-Host ""
        # Read-Line, NOT Read-YesNo: Read-YesNo is defined in menu.ps1 only and
        # this script does not dot-source it, so calling it here threw
        # CommandNotFoundException and killed the checklist AFTER it had already
        # printed (2026-09-22). Every other prompt in this file uses Read-Line.
        $invAns = Read-Line "Also show the full per-run inventory (with the reason each incomplete run failed)? [y/N] > "
        if ($invAns -eq 'y' -or $invAns -eq 'Y') {
            python (Join-Path $base 'tools\inventory_cells.py') --plan --repeats $repeats
        }
    }
    finally { Pop-Location }

    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Select-VerifyTable {
    # Which attempt's feature table to verify: feature_table_rN.csv is one
    # attempt (Select-AnalysisAttempt), feature_table.csv is every attempt
    # pooled or a single-attempt folder. Returns a path (possibly not yet
    # existing - the caller says so), or $null to go back.
    param([string]$AnalysisDir, [string]$ExportDir)
    $pooled = Join-Path $AnalysisDir 'feature_table.csv'
    $reps = @{}
    foreach ($n in @((Get-AttemptGroups -Dir $ExportDir).Keys)) { $reps[[int]$n] = $true }
    foreach ($f in @(Get-ChildItem -LiteralPath $AnalysisDir -Filter 'feature_table_r*.csv' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^feature_table_r(\d+)\.csv$') { $reps[[int]$Matches[1]] = $true }
    }
    $hasPerAttempt = @(Get-ChildItem -LiteralPath $AnalysisDir -Filter 'feature_table_r*.csv' -File -ErrorAction SilentlyContinue).Count -gt 0
    if ($reps.Count -le 1 -and -not $hasPerAttempt) { return $pooled }

    $sorted = @($reps.Keys | Sort-Object)
    $paths = @(); $opts = @(); $default = -1
    foreach ($n in $sorted) {
        $p = Join-Path $AnalysisDir "feature_table_r$n.csv"
        $paths += $p
        if (Test-Path -LiteralPath $p) {
            $opts += ("r{0}  -> feature_table_r{0}.csv (analysed {1:MMM. dd, yyyy h:mm tt})" -f $n, (Get-Item -LiteralPath $p).LastWriteTime)
            $default = $opts.Count - 1
        } else {
            $opts += ("r{0}  -> not analysed yet - run 'Run analysis only' for r{0} first" -f $n)
        }
    }
    if (Test-Path -LiteralPath $pooled) {
        $paths += $pooled
        $opts += 'all attempts together -> feature_table.csv  (PDR too high + latency blank if it pools attempts)'
    }
    if ($default -lt 0) { $default = $sorted.Count - 1 }

    $idx = Show-Menu -Title 'Which attempt (repeat) to verify?' -Options $opts -DefaultIndex $default -AllowBack
    if ($idx -lt 0) { return $null }
    return $paths[$idx]
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
    $table = Select-VerifyTable -AnalysisDir $dirs.Analysis -ExportDir $dirs.Export
    if ($null -eq $table) { Write-Host "  Skipped." -ForegroundColor DarkGray; return }
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

function Invoke-CheckSnifferFile {
    # Runs tools\check_pcap.py on a Mac Sniffer capture: packet count, mesh
    # beacons vs mesh DATA frames, capture span, and a _fixed copy when the file
    # ends in a partial packet (Wireshark's "cut short in the middle of a
    # packet"). No board/COM contact.
    param([string]$Path)
    if (-not $Path) {
        Write-Host ""
        Write-Host "Mac capture: copy the .pcap / .pcapng to this laptop first - newer macOS keeps it in /var/tmp." -ForegroundColor DarkGray
        Write-Host "ESP32 sniffer capture: it is already here, under datasets\PCAP\." -ForegroundColor DarkGray
        $Path = Read-Line "Capture file path (drag the file into this window, then Enter) > "
    }
    if (-not $Path) { return }
    $Path = $Path.Trim().Trim('"').Trim("'")
    Write-Host ""
    & python (Join-Path $base 'tools\check_pcap.py') $Path
    Request-OpenInWireshark -Path $Path
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

function Invoke-MacRetryReport {
    # The REAL 802.11 retry rate per radio link and phase, from the sniffer's own
    # captures (tools\pcap_retry.py, deviation D-15). The boards cannot measure it -
    # ESP-IDF only PRINTS its Wi-Fi stats - so the CSVs' retry_count is a software
    # counter that reads 0; the sniffer sees the Retry bit on every resent frame.
    # No board/COM contact. Same numbers features.py puts in MacRetryRate.
    $tool     = Join-Path $base 'tools\pcap_retry.py'
    $datasets = Join-Path $base 'datasets'
    while ($true) {
        Write-Host ""
        Write-Host "=== MAC retry rate (from the sniffer) ===" -ForegroundColor Cyan
        Write-Host "Pairing every capture in datasets\PCAP\ with its run (cached - only new/changed captures are re-read) ..." -ForegroundColor DarkGray
        & python $tool --all
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("pcap_retry.py --all failed (exit {0}) - see the error above." -f $LASTEXITCODE) -ForegroundColor Red
            Read-Host "Press Enter to return to the menu" | Out-Null
            return
        }

        # One _retry.json per capture sits beside it; refused captures were listed above with the reason.
        $usable = @()
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $datasets 'PCAP') -Recurse -Filter '*_retry.json' -File -ErrorAction SilentlyContinue)) {
            try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
            if ($m.refused -or -not $m.run_log) { continue }
            $stem = $f.FullName.Substring(0, $f.FullName.Length - '_retry.json'.Length)
            $pcap = @("$stem.pcap", "$stem.pcapng") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $pcap) { continue }
            $runLog = if ([System.IO.Path]::IsPathRooted($m.run_log)) { $m.run_log } else { Join-Path $datasets $m.run_log }
            $usable += [pscustomobject]@{ Meta = $m; Pcap = $pcap; RunLog = $runLog; Start = [double]$m.attack_start_epoch }
        }
        if ($usable.Count -eq 0) {
            Write-Host ""
            Write-Host "No capture has retry data yet (the reasons are listed above). Record a run with the ESP32 sniffer first." -ForegroundColor Yellow
            Read-Host "Press Enter to return to the menu" | Out-Null
            return
        }
        $usable = @($usable | Sort-Object Start -Descending)   # newest run first

        $opts = foreach ($u in $usable) {
            $i = $u.Meta.identity
            $when = [DateTimeOffset]::FromUnixTimeSeconds([long]$u.Start).ToOffset([TimeSpan]::FromHours(8)).ToString('MMM. dd, yyyy h:mm tt')
            # 'root run log' is the one normal source; anything else is the exported-CSV fallback.
            $src = if ($u.Meta.phase_source -and "$($u.Meta.phase_source)" -ne 'root run log') { '  [phases from exported CSVs]' } else { '' }
            "{0}/{1}/{2}/{3} r{4} - attack started {5}  ({6}){7}" -f $i.attack, $i.topology, $i.location, $i.scenario, $i.repeat, $when, (Split-Path $u.Pcap -Leaf), $src
        }
        $pick = Show-Menu -Title "Which run's MAC retry rate? (newest first)" -Options @($opts) -DefaultIndex 0 -AllowBack
        if ($pick -eq -1) { return }
        $u = $usable[$pick]

        Write-Host ""
        & python $tool $u.Pcap --run-log $u.RunLog --no-csv
        Write-Host ""
        # The report above explains itself (boards table, per-link verdicts, bottom line).
        Write-Host "  - Per-second values: the capture's _retry.csv, and MacRetryRate / MacFramesHeard in feature_table.csv." -ForegroundColor DarkGray
        Write-Host "    Blank there = NOT MEASURED (no sniffer for that run), never 'no retries'. Background: D-15 in" -ForegroundColor DarkGray
        Write-Host "    docs\deviations-limitations\thesis-deviate.md." -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press Enter to pick another run (then 'b' to go back)" | Out-Null
    }
}

function Write-MacSnifferSettings {
    # The two dropdowns in the Mac's Sniffer window, printed as highlighted
    # "chips" so the values to pick are the first thing the eye lands on. A
    # wrong channel is the #1 way a Mac capture comes back empty.
    param([int]$Channel, [string]$Prefix = '  3. ')
    Write-Host -NoNewline $Prefix
    Write-Host -NoNewline 'Channel '
    Write-Host -NoNewline (" {0} " -f $Channel) -ForegroundColor Black -BackgroundColor Yellow
    Write-Host -NoNewline '    Width '
    Write-Host -NoNewline ' 20 MHz ' -ForegroundColor Black -BackgroundColor Cyan
    Write-Host '    (wrong channel = empty file)' -ForegroundColor Yellow
}

function Invoke-MacSnifferTest {
    # ~2-minute smoke test for the MacBook's Wireless Diagnostics Sniffer, so a
    # teammate can prove the Mac actually records ESP32 frames BEFORE burning a
    # full 11-minute attack run on it (sep. 23 2026: a whole run came back as a
    # 0-byte capture). No flashing, no attack, no export: the boards just need
    # to be running the normal mesh firmware. A running mesh root beacons on
    # MESH_CHANNEL constantly, so if this laptop sees the root alive over USB
    # while the Mac records nothing, the fault is provably on the Mac side.
    $chan = 11
    $hdr = Join-Path $base 'components\mesh_common\include\mesh_config.h'
    $hit = if (Test-Path $hdr) { Select-String -Path $hdr -Pattern '^\s*#define\s+MESH_CHANNEL\s+(\d+)' | Select-Object -First 1 }
    if ($hit) { $chan = [int]$hit.Matches[0].Groups[1].Value }

    Write-Host ""
    Write-Host "=== MacBook sniffer test (short - no attack run) ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "On the MAC, before starting:" -ForegroundColor Cyan
    Write-Host "  1. Wi-Fi must be ON but NOT joined to any network." -ForegroundColor Yellow
    Write-Host "     (Option-click the Wi-Fi icon -> 'Disconnect from <network>'. Do NOT switch Wi-Fi off -"
    Write-Host "      the Sniffer uses the Wi-Fi radio, so Wi-Fi OFF = nothing to capture with = empty file.)"
    Write-Host "  2. Option-click Wi-Fi icon -> Open Wireless Diagnostics -> menu bar Window -> Sniffer"
    Write-MacSnifferSettings -Channel $chan
    Write-Host "     (boards must run firmware with MESH_FORCE_HT20 - boot log 'RF width ... STA 20 MHz, AP 20 MHz'."
    Write-Host "      Older firmware talks at 40 MHz, which a 20 MHz Mac hears as beacons only.)"
    Write-Host "  4. Put the Mac within 1-2 metres of the boards."
    Write-Host "  Don't press Start yet - the countdown below tells you when."
    Write-Host ""
    Write-Host "On the BOARDS: power them on with the normal mesh firmware (root at least; children optional)." -ForegroundColor Cyan
    Write-Host "  They'll start a normal run schedule and write a SHORT, incomplete run to their SD cards -" -ForegroundColor DarkGray
    Write-Host "  that's expected. Don't import it as a real capture." -ForegroundColor DarkGray

    # Optional live proof that the air had traffic: listen to the ROOT's serial.
    $rootPort = $null
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($ports.Count -gt 0) {
        $ans = Read-Line "`nIs the ROOT board plugged into THIS laptop by USB (lets me confirm it's transmitting)? [Y/n] > "
        if ($ans -ne 'n' -and $ans -ne 'N') {
            $pick = Select-Port -For 'the ROOT board (listen only - no flashing)' -Ports $ports -AllowBack
            if ($pick -and $pick -ne $script:BackSignal) { $rootPort = $pick }
        }
    }

    $secs = 90
    $ans = Read-Line "`nHow many seconds should the Mac capture? [90] > "
    $n = 0
    if ($ans -and [int]::TryParse($ans.Trim(), [ref]$n) -and $n -ge 20 -and $n -le 600) { $secs = $n }

    Read-Line "`nPress Enter, THEN click Start in the Mac's Sniffer window > " | Out-Null

    $sp = $null
    $lines = 0; $children = 0; $ctrl = 0; $serialErr = $null
    if ($rootPort) {
        try {
            $sp = New-Object System.IO.Ports.SerialPort $rootPort, 115200
            # Both lines low so opening the port doesn't hold the ESP32 in reset.
            $sp.DtrEnable = $false; $sp.RtsEnable = $false
            $sp.ReadTimeout = 250
            # 1 MiB driver buffer - see tools\serial_guard.py (silabser.sys BSOD).
            $sp.ReadBufferSize = 1MB
            $sp.Open()
        } catch {
            $serialErr = $_.Exception.Message
            $sp = $null
        }
    }

    $deadline = (Get-Date).AddSeconds($secs)
    $nextTick = Get-Date
    try {
        while ((Get-Date) -lt $deadline) {
            if ($sp) {
                try {
                    $l = $sp.ReadLine()
                    $lines++
                    if ($l -match 'Child connected') { $children++ }
                    if ($l -match '\[CTRL\]') { $ctrl++ }
                } catch [System.TimeoutException] { }
            } else {
                Start-Sleep -Milliseconds 250
            }
            if ((Get-Date) -ge $nextTick) {
                $left = [int][math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
                $msg = "  capturing... {0,3} s left" -f $left
                if ($sp) { $msg += ("   root serial: {0} lines, {1} child-connect events" -f $lines, $children) }
                Write-Host $msg -ForegroundColor DarkGray
                $nextTick = (Get-Date).AddSeconds(10)
            }
        }
    } finally {
        if ($sp -and $sp.IsOpen) { $sp.Close() }
    }

    Write-Host ""
    Write-Host ">>> Click STOP in the Mac's Sniffer window NOW. <<<" -ForegroundColor Green
    Write-Host ""
    Write-Host "What this laptop saw:" -ForegroundColor Cyan
    $rootAlive = $false
    if (-not $rootPort) {
        Write-Host "  (root serial not monitored - can't confirm the mesh was transmitting)" -ForegroundColor DarkGray
    } elseif ($serialErr) {
        Write-Host ("  Could not open {0}: {1}  (port busy? close any serial monitor)" -f $rootPort, $serialErr) -ForegroundColor Yellow
    } elseif ($lines -gt 0) {
        $rootAlive = $true
        Write-Host ("  ROOT ALIVE on {0}: {1} log lines, {2} child-connect events, {3} phase-control lines." -f $rootPort, $lines, $children, $ctrl) -ForegroundColor Green
        Write-Host ("  A running root beacons on channel {0} nonstop - there WAS traffic in the air." -f $chan) -ForegroundColor Green
    } else {
        Write-Host ("  Root on {0} printed NOTHING for {1} s - it may be hung/unpowered. Press its EN/RST button and retry." -f $rootPort, $secs) -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Now get the Mac's file:" -ForegroundColor Cyan
    Write-Host "  - WAIT ~10 s after Stop before touching the file. Opening/copying it while the Sniffer is" -ForegroundColor Yellow
    Write-Host "    still writing is what gives 'cut short in the middle of a packet' (or a 0-byte file)." -ForegroundColor Yellow
    Write-Host "  - Newer macOS saves it in /var/tmp (Finder: Cmd+Shift+G, type /var/tmp), older ones on the Desktop."
    Write-Host "    Take the newest .pcap / .pcapng with a timestamp matching just now; copy it to this laptop."
    Write-Host ""
    $pc = Read-Line "Paste the copied capture file's path here to check it now (Enter to skip) > "
    if ($pc) { Invoke-CheckSnifferFile -Path $pc; return }
    Write-Host ""
    Write-Host "Or check it by eye in Wireshark: filter  wlan.sa_resolved contains ""Espressif""" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Result:" -ForegroundColor Cyan
    Write-Host "  PASS  - Espressif frames are in the file -> the Mac sniffer works; do the real run the same way." -ForegroundColor Green
    Write-Host "  HALF  - file has frames but no Espressif ones -> Mac works; wrong channel, or too far from the boards."
    Write-Host "  FAIL  - file is 0 bytes / no frames at all:" -ForegroundColor Yellow
    if ($rootAlive) {
        Write-Host "          the mesh WAS transmitting (proved above), so the fault is on the MAC: re-check" -ForegroundColor Yellow
        Write-Host "          Wi-Fi ON-but-disconnected, then reboot the Mac. Still failing -> use an ESP32 sniffer" -ForegroundColor Yellow
        Write-Host "          board instead (docs\packet-capture\WIRESHARK-GUIDE.md section 4, Path A)." -ForegroundColor Yellow
    } else {
        Write-Host "          re-run this test WITH the root plugged in here, so we can tell Mac-fault from mesh-fault." -ForegroundColor Yellow
    }
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ---------------------------------------------------------- ESP32 sniffer ----
# A spare ESP32 running sniffer_node\ (passive, never joins the mesh) streams
# every frame it hears over USB; tools\sniff.py writes the .pcap. No SD card,
# no Mac, no extra hardware. Captures go to PCAP\ (git-ignored: too big for
# GitHub) with a .json beside each one saying how complete it is.

function Get-MeshChannel {
    $hdr = Join-Path $base 'components\mesh_common\include\mesh_config.h'
    $hit = if (Test-Path $hdr) { Select-String -Path $hdr -Pattern '^\s*#define\s+MESH_CHANNEL\s+(\d+)' | Select-Object -First 1 }
    if ($hit) { return [int]$hit.Matches[0].Groups[1].Value }
    return 11
}

function Find-Wireshark {
    $cmd = Get-Command Wireshark -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # A custom install folder (Bas's laptop: S:\Main Programs\...) is only known
    # to the installer's App Paths registry entry - the Program Files guess below
    # missed it, which silently hid the "show it live in Wireshark?" prompt.
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Wireshark.exe',
                       'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Wireshark.exe')) {
        try {
            $p = ([string](Get-ItemProperty -Path $key -ErrorAction Stop).'(default)').Trim('"')
            if ($p -and (Test-Path $p)) { return $p }
        } catch { }
    }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($root) {
            $p = Join-Path $root 'Wireshark\Wireshark.exe'
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Invoke-FlashSniffer {
    # Builds + flashes sniffer_node\ onto one board. $true on success. Build dir
    # is keyed by port like run.ps1's, under the same off-OneDrive build root.
    param([string]$Port)
    if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
        Write-Host "  idf.py is not available in this window - run the wizard from the ESP-IDF PowerShell." -ForegroundColor Red
        return $false
    }
    $proj = 'sniffer_node'
    $dir  = Get-SafeBuildDir -Proj $proj -DirName ("build_sniffer_{0}" -f ($Port -replace '[^A-Za-z0-9]', ''))
    # Same self-heal as run.ps1: a build dir configured for a moved/re-cloned
    # repo path hard-fails idf.py, so wipe it and let it reconfigure.
    $cache = Join-Path $dir 'CMakeCache.txt'
    if (Test-Path $cache) {
        $want = ((Join-Path $base $proj) -replace '\\', '/').TrimEnd('/')
        $line = Select-String -Path $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=' | Select-Object -First 1
        if ($line -and (($line.Line -split '=', 2)[1].TrimEnd('/') -ne $want)) { Remove-Item -Recurse -Force $dir }
    }
    Write-Host ""
    Write-Host ("Flashing the SNIFFER firmware to {0} (the first time compiles for ~1-2 min) ..." -f $Port) -ForegroundColor Cyan
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location (Join-Path $base $proj)
    try {
        $global:LASTEXITCODE = 0
        idf.py -B $dir -p $Port flash
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Flash failed (usually a USB serial glitch) - retrying once at 115200 baud ..." -ForegroundColor Yellow
            idf.py -B $dir -p $Port -b 115200 flash
        }
        $ok = ($LASTEXITCODE -eq 0)
    }
    finally { Pop-Location; $ErrorActionPreference = $prevEap }
    if ($ok) { Write-Host ("  Sniffer firmware is on {0}." -f $Port) -ForegroundColor Green }
    else     { Write-Host ("  Could not flash the sniffer on {0} - plug it DIRECTLY into the laptop (no hub), short data cable." -f $Port) -ForegroundColor Red }
    return $ok
}

function Start-SnifferCapture {
    # Starts tools\sniff.py in its OWN window, so its live status line never
    # mixes with the flash/monitor output in this one. Stopped by
    # Stop-SnifferCapture dropping a .stop file next to the capture - a clean
    # stop that writes the .json summary, unlike killing the window.
    # Returns a handle for Stop-SnifferCapture, or $null if it did not start.
    param([string]$Port, [string]$OutPath, [string]$Label, [switch]$Live)
    # PS 5.1 silently DROPS an empty-string argument to a native exe, which
    # would leave --label with no value and argparse would refuse to start.
    if (-not $Label) { $Label = 'run' }
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { Write-Host "  python is not on PATH - run from the ESP-IDF PowerShell." -ForegroundColor Red; return $null }
    $outDir = Split-Path $OutPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $stop = [IO.Path]::ChangeExtension($OutPath, '.stop')
    if (Test-Path $stop) { Remove-Item -Force $stop }

    # -EncodedCommand, not -Command: paths/labels with spaces or quotes survive
    # untouched. The window stays open on an error so the reason can be read.
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $cmd = "`$Host.UI.RawUI.WindowTitle = 'SNIFFER on $Port - recording, do not close'; " +
           "& $(& $q $py.Source) $(& $q (Join-Path $base 'tools\sniff.py')) --port $Port --out $(& $q $OutPath) " +
           "--stop-file $(& $q $stop) --label $(& $q $Label)" + $(if ($Live) { ' --live' } else { '' }) + "; " +
           "`$rc = `$LASTEXITCODE; if (`$rc -ne 0) { Write-Host ''; Read-Host 'Sniffer ended with an error - read it above, then press Enter to close' | Out-Null }; exit `$rc"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-EncodedCommand', $enc) -WorkingDirectory $base -PassThru

    # sniff.py creates the .pcap the moment it has the port open. No file after
    # a few seconds = it could not open the port (busy, wrong COM, no pyserial).
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline -and -not (Test-Path $OutPath) -and -not $proc.HasExited) { Start-Sleep -Milliseconds 300 }
    if (-not (Test-Path $OutPath)) {
        Write-Host ("  The sniffer did not start on {0} - the reason is in the sniffer window." -f $Port) -ForegroundColor Red
        return $null
    }
    Write-Host ("  Sniffer RECORDING in its own window -> {0}" -f $OutPath) -ForegroundColor Green
    Write-Host "  Leave that window open - the wizard stops it after the root's export." -ForegroundColor DarkGray
    return [pscustomobject]@{ Process = $proc; Out = $OutPath; Stop = $stop; Port = $Port }
}

function Confirm-KeepCapture {
    # Asked right after check_pcap's RESULT, while it is still on screen. Yes/keep
    # is the default (Enter); deleting needs an explicit 'n' - the capture is often the only
    # independent record of the run. Removes the .pcap, its .json summary and a
    # check_pcap _fixed copy if one was written. PCAP\ is git-ignored, so this
    # is the ONLY copy: there is no restore.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return }
    $json  = [IO.Path]::ChangeExtension($Path, '.json')
    $fixed = Join-Path (Split-Path $Path -Parent) ([IO.Path]::GetFileNameWithoutExtension($Path) + '_fixed' + [IO.Path]::GetExtension($Path))
    $files = @($Path, $json, $fixed) | Where-Object { Test-Path $_ }
    Write-Host ""
    $ans = Read-Line ("Keep this capture ({0})? [Y/n]  (n = DELETE it permanently) > " -f (Format-ByteSize (Get-Item $Path).Length))
    # Only an explicit n/no deletes - Enter, y, or anything unrecognised keeps it.
    if ($ans -notin @('n', 'N', 'no', 'No', 'NO')) {
        Write-Host ("  Kept: {0}" -f $Path) -ForegroundColor Green
        return
    }
    foreach ($f in $files) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; Write-Host ("  Deleted {0}" -f $f) -ForegroundColor Yellow }
        catch { Write-Host ("  Could not delete {0}: {1}" -f $f, $_.Exception.Message) -ForegroundColor Red }
    }
}

function Stop-SnifferCapture {
    # Stops a capture from Start-SnifferCapture, prints how complete it is (from
    # sniff.py's .json) and runs check_pcap.py on it with the run's board MACs,
    # so a bad capture is known NOW, while the boards are still on the table.
    param($Capture, [string[]]$Macs = @())
    if (-not $Capture) { return }
    Write-Host ""
    Write-Host "Stopping the sniffer capture ..." -ForegroundColor Cyan
    New-Item -ItemType File -Force -Path $Capture.Stop | Out-Null
    if (-not $Capture.Process.WaitForExit(20000)) {
        # It only waits past 20 s if it is sitting on its own error prompt.
        Write-Host "  The sniffer window did not close by itself - closing it (the file is flushed every second)." -ForegroundColor Yellow
        try { Stop-Process -Id $Capture.Process.Id -Force -ErrorAction Stop } catch { }
    }
    Remove-Item -Force $Capture.Stop -ErrorAction SilentlyContinue

    $json = [IO.Path]::ChangeExtension($Capture.Out, '.json')
    if (Test-Path $json) {
        try {
            $s = Get-Content $json -Raw | ConvertFrom-Json
            Write-Host ("  {0} frames ({1} data) over {2}, channel {3}." -f $s.frames_written, $s.frames_by_type.data, (Format-Duration ([int]$s.duration_s)), $s.channel) -ForegroundColor Green
            $lost = [int]$s.loss.usb_link_lost_frames + [int]$s.loss.board_ring_dropped_frames
            if ($lost -gt 0) { Write-Host ("  {0} frame(s) heard but not delivered - recorded in the .json, quote it with any figure from this capture." -f $lost) -ForegroundColor Yellow }
            if ([int]$s.sniffer_reboots -gt 0) { Write-Host ("  The sniffer board rebooted {0} time(s) mid-capture (power/cable) - see the .json." -f $s.sniffer_reboots) -ForegroundColor Yellow }
        } catch {
            Write-Host ("  Could not read {0}: {1}" -f $json, $_.Exception.Message) -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No .json summary (the sniffer was closed, not stopped) - the .pcap is still usable." -ForegroundColor Yellow
    }
    if (Test-Path $Capture.Out) {
        $macArgs = @()
        foreach ($m in $Macs) { if ($m) { $macArgs += @('--mac', $m) } }
        Write-Host ""
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & python (Join-Path $base 'tools\check_pcap.py') $Capture.Out @macArgs }
        finally { $ErrorActionPreference = $prevEap }
        Confirm-KeepCapture -Path $Capture.Out
    }
}

function Get-SnifferPcapPath {
    # PCAP\<attack>\<topology>\<location>\<scenario>\<cell>_r<N>_<time>.pcap - the
    # same folder names as tools\exports\ and run_logs\, so a capture sits beside
    # "its" run on sight.
    param([string]$AttackDir, [string]$TopoDir, [string]$Location, [string]$Scenario, [int]$RepeatNum)
    $sc  = ConvertTo-Scenario $Scenario
    $dir = Join-Path $base ("datasets\PCAP\{0}\{1}\{2}\{3}" -f $AttackDir, $TopoDir, $Location, $sc)
    $head = "{0}-{1}-{2}-{3}_r{4}" -f $TopoDir, $AttackDir, $sc, $Location.ToLower(), $RepeatNum
    return (Get-StampedPath -Dir $dir -Head $head -Ext '.pcap')
}

# NOT CALLED since sep. 26, 2026: Select-PacketCapture, Show-MacCaptureChecklist,
# Start-SnifferCapture and Stop-SnifferCapture were the "packet capture for this
# run?" step of main-menu [1], removed there as a duplicate of the VERIFY
# category's sniffer entries. Kept (never committed anywhere else) so it can be
# re-wired; delete once the team is sure it is not wanted back.
$script:LastCaptureIdx = 0

function Select-PacketCapture {
    # Asked once per run, before anything is flashed. The MacBook is not always
    # there, so the ESP32 board is the no-extra-hardware option; 'none' keeps
    # the run exactly as it was before this existed.
    # Returns @{ Mode = 'none'|'esp32'|'mac'; Port; Live }.
    param([string[]]$Taken = @())
    $chan = Get-MeshChannel
    $idx = Show-Menu -Title 'Packet capture (Wireshark evidence) for this run?' -Options @(
        'None - no packet capture this run',
        "ESP32 sniffer board plugged into THIS laptop (spare board, flashed + recorded automatically into datasets\PCAP\, channel $chan)",
        'MacBook Wireless Diagnostics sniffer (a teammate records it; the wizard tells you when to start and stop)'
    ) -DefaultIndex $script:LastCaptureIdx
    $script:LastCaptureIdx = $idx
    if ($idx -eq 0) { return @{ Mode = 'none' } }
    if ($idx -eq 2) { return @{ Mode = 'mac' } }

    Write-Host ""
    Write-Host "The sniffer must be an EXTRA board - not one of this run's mesh boards. It gets" -ForegroundColor DarkGray
    Write-Host "the sniffer firmware, listens only (never transmits), and stays plugged in here." -ForegroundColor DarkGray
    while ($true) {
        $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
        $port = Select-Port -For 'the SNIFFER board (spare board - gets the sniffer firmware)' -Ports $ports -Taken $Taken
        if ($Taken -contains $port) {
            Write-Host ("  {0} is one of this run's MESH boards - flashing the sniffer there would take it out of the run. Pick the spare board." -f $port) -ForegroundColor Red
            continue
        }
        break
    }
    $live = $false
    if (Find-Wireshark) {
        $ans = Read-Line "  Also show it live in Wireshark on this laptop while it records? [y/N] > "
        $live = ($ans -eq 'y' -or $ans -eq 'Y')
    }
    return @{ Mode = 'esp32'; Port = $port; Live = $live }
}

function Show-MacCaptureChecklist {
    $chan = Get-MeshChannel
    Write-Host ""
    Write-Host "=== MacBook sniffer - set it up now ===" -ForegroundColor Magenta
    Write-Host "  1. Wi-Fi ON but NOT joined to any network (Option-click Wi-Fi -> Disconnect)." -ForegroundColor Magenta
    Write-Host "  2. Option-click Wi-Fi -> Open Wireless Diagnostics -> Window -> Sniffer." -ForegroundColor Magenta
    Write-MacSnifferSettings -Channel $chan
    Write-Host "  4. Mac within 1-2 m of the boards." -ForegroundColor Magenta
    Write-Host "  Untested Mac today? Run the main menu's 'MacBook sniffer test' first - a 0-byte capture" -ForegroundColor DarkGray
    Write-Host "  after an 11-minute run is how sep. 23 was lost." -ForegroundColor DarkGray
}

$script:SniffFiling = @{ Attack = 1; Topology = 0; Location = 0; Scenario = 0; Repeat = 1 }

function Select-SnifferFiling {
    # Where a main-menu capture is saved: the same PCAP\<attack>\<topology>\
    # <location>\<scenario>\ tree a wizard run files its capture in (folder
    # names from Get-RunDirs, so baseline\ and partial_mesh\ match tools\exports\),
    # or PCAP\standalone\ for a plain test. Last answers are this session's
    # defaults, so recording several captures for one cell is Enter-Enter-Enter.
    $f = $script:SniffFiling
    $idx = Show-Menu -Title 'What is this capture for?' -Options @(
        'A run cell - file it under datasets\PCAP\<attack>\<topology>\<location>\<scenario>\ (like the exports)',
        'Just a test - datasets\PCAP\standalone\'
    ) -DefaultIndex 0
    if ($idx -eq 1) { return (Get-StampedPath -Dir (Join-Path $base 'datasets\PCAP\standalone') -Head 'esp32_sniffer' -Ext '.pcap') }

    $f.Attack = Show-Menu -Title 'Attack type:' -Options @('baseline  (no attack)', 'blackhole', 'wormhole') -DefaultIndex $f.Attack
    $f.Topology = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex $f.Topology
    $f.Location = Show-Menu -Title 'Location:' -Options $LOCATIONS -DefaultIndex $f.Location
    $f.Scenario = Show-Menu -Title 'Scenario:' -Options $SCENARIO_LABELS -DefaultIndex $f.Scenario
    while ($true) {
        $raw = Read-Line ("Repeat number (the r<N> of the run it belongs to) > [{0}] " -f $f.Repeat)
        $n = 0
        if (-not $raw) { break }
        if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1) { $f.Repeat = $n; break }
        Write-Host "  Enter a positive whole number." -ForegroundColor Yellow
    }
    $dirs = Get-RunDirs -Attack $ATTACKS[$f.Attack] -Topology $TOPOLOGIES[$f.Topology] -Location $LOCATIONS[$f.Location] -Scenario $SCENARIOS[$f.Scenario]
    return (Get-SnifferPcapPath -AttackDir $dirs.AttackDir -TopoDir $dirs.TopoDir -Location $LOCATIONS[$f.Location] -Scenario $SCENARIOS[$f.Scenario] -RepeatNum $f.Repeat)
}

function Invoke-Esp32SnifferStandalone {
    # Main-menu entry: flash and/or record with the ESP32 sniffer outside a run
    # (a first test, a demo, or a capture while another laptop drives the run).
    # Runs sniff.py in THIS window; Enter stops it. -Live (the WIRESHARK
    # category's "watch LIVE" entry) skips the question and always opens Wireshark.
    param([switch]$Live)
    $chan = Get-MeshChannel
    Write-Host ""
    $title = if ($Live) { "=== ESP32 sniffer board + LIVE Wireshark (no run) ===" } else { "=== ESP32 sniffer board (no run - just record) ===" }
    Write-Host $title -ForegroundColor Cyan
    Write-Host ("Use a SPARE board - it gets the sniffer firmware and listens on channel {0} only." -f $chan) -ForegroundColor DarkGray
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
    $port = Select-Port -For 'the SNIFFER board' -Ports $ports -AllowBack
    if (-not $port -or $port -eq $script:BackSignal) { return }

    $ans = Read-Line "`nFlash the sniffer firmware to $port first? (skip only if it already runs it) [Y/n] > "
    if ($ans -ne 'n' -and $ans -ne 'N') {
        if (-not (Invoke-FlashSniffer -Port $port)) { Read-Host "Press Enter to return to the menu" | Out-Null; return }
        Start-Sleep -Seconds 2   # let it boot past the 115200 banner
    }
    $outPath = Select-SnifferFiling
    # --start-paused: the capture begins PAUSED (nothing saved) so the operator starts it
    # by hand with P at the moment the experiment does - a recording that opens before
    # the run would otherwise fill the file with idle traffic (sep. 26, 2026 request).
    $pyArgs = @((Join-Path $base 'tools\sniff.py'), '--port', $port, '--stop-on-enter', '--start-paused', '--out', $outPath,
                '--label', ((Split-Path (Split-Path $outPath -Parent) -Leaf) + ' ' + [IO.Path]::GetFileNameWithoutExtension($outPath)))
    if (Find-Wireshark) {
        $ans = if ($Live) { 'y' } else { Read-Line "Also show it live in Wireshark? [y/N] > " }
        if ($ans -eq 'y' -or $ans -eq 'Y') {
            # sniff.py opens the live view with the thesis settings folder when it exists.
            Initialize-WiresharkProfile -IoLines (Get-GenericIoLines)
            $pyArgs += '--live'
        }
    } elseif ($Live) {
        Write-Host "  Wireshark was not found on this laptop - recording to the file only." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  >>> It starts PAUSED - press  P  to START recording (and P again to pause/resume). <<<" -ForegroundColor Yellow
    Write-Host "Recording - P = pause/resume, ENTER = stop (it asks: press Y to confirm). Not Ctrl+C: that can close the wizard too." -ForegroundColor Yellow
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & python @pyArgs }
    finally { $ErrorActionPreference = $prevEap }
    $out = $pyArgs[$pyArgs.IndexOf('--out') + 1]
    if (Test-Path $out) {
        Write-Host ""
        $ErrorActionPreference = 'Continue'
        try { & python (Join-Path $base 'tools\check_pcap.py') $out }
        finally { $ErrorActionPreference = $prevEap }
        Confirm-KeepCapture -Path $out
        Request-OpenInWireshark -Path $out
    }
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ------------------------------------------------------- WIRESHARK views ----
# The WIRESHARK category's "open it for me" entries: pick a capture and a view
# and Wireshark opens on it with the columns, filter and I/O-graph lines set.
# All of it lives in its OWN Wireshark settings folder (%APPDATA%\Wireshark-
# ThesisMesh, handed over as WIRESHARK_CONFIG_DIR), so the laptop's normal
# Wireshark - other coursework uses it - is never touched. Not a profile (-C):
# tested sep. 26, 2026, a -C launch made ThesisMesh the "last used profile", so
# the next plain Wireshark start opened in the thesis layout. Board MACs come
# from the capture itself (check_pcap.py --map-json), never from the guide's
# tables: roles rotate per run, and a stale MAC makes a filter silently empty.

$script:WsColors = @('#E6194B', '#4363D8', '#3CB44B', '#F58231', '#911EB4', '#42D4F4', '#F032E6', '#9A6324', '#469990', '#888888')

function Get-WiresharkProfileDir { return (Join-Path $env:APPDATA 'Wireshark-ThesisMesh') }

function Get-GenericIoLines {
    # I/O-graph lines that need no MAC - for the live view and a capture with no
    # mesh boards found.
    return @(
        @{ Name = 'Mesh data frames'; Filter = 'llc.oui == 0x18fe34' },
        @{ Name = 'Retries (802.11 Retry bit)'; Filter = 'wlan.fc.retry == 1' }
    )
}

function Initialize-WiresharkProfile {
    # preferences and the filter buttons are written only when missing, so a
    # column tweak made inside Wireshark survives (delete the profile folder to
    # get these defaults back). io_graphs is rewritten on every launch with the
    # chosen view's lines - that is what "already loaded" means.
    # .NET WriteAllLines = UTF-8 without a BOM; Wireshark reads these as plain text.
    param([object[]]$IoLines = @())
    $dir = Get-WiresharkProfileDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $prefs = Join-Path $dir 'preferences'
    if (-not (Test-Path $prefs)) {
        [IO.File]::WriteAllLines($prefs, [string[]]@(
            '# Written by run_wizard.ps1 (WIRESHARK category). Delete this profile folder to reset it.',
            '# TA = who sent this hop, RA = the next hop (NOT the final target - ESP-MESH is hop-wise).',
            'gui.column.format: ',
            "`t""No."", ""%m"",",
            "`t""Time"", ""%t"",",
            "`t""RSSI"", ""%Cus:radiotap.dbm_antsignal:0:R"",",
            "`t""TA (sender)"", ""%Cus:wlan.ta:0:R"",",
            "`t""RA (next hop)"", ""%Cus:wlan.ra:0:R"",",
            "`t""Seq"", ""%Cus:wlan.seq:0:R"",",
            "`t""Retry"", ""%Cus:wlan.fc.retry:0:U"",",
            "`t""Protocol"", ""%p"",",
            "`t""Length"", ""%L"",",
            "`t""Info"", ""%i""",
            'nameres.mac_name: FALSE'
        ))
    }

    # Window size and column widths live in the 'recent' file; without it this
    # fresh settings folder opens a small window. Wireshark rewrites the file
    # itself on exit, so it is only seeded once.
    $recent = Join-Path $dir 'recent'
    if (-not (Test-Path $recent)) {
        [IO.File]::WriteAllLines($recent, [string[]]@(
            '# Seeded by run_wizard.ps1 (WIRESHARK category): window + packet list column widths.',
            'gui.geometry_main_maximized: TRUE',
            'column.width:',
            "`t%m, 70,",
            "`t%t, 110,",
            "`t""%Cus:radiotap.dbm_antsignal"", 80,",
            "`t""%Cus:wlan.ta"", 170,",
            "`t""%Cus:wlan.ra"", 170,",
            "`t""%Cus:wlan.seq"", 60,",
            "`t""%Cus:wlan.fc.retry"", 55,",
            "`t%p, 70,",
            "`t%L, 60,",
            "`t%i, 900"
        ))
    }

    $buttons = Join-Path $dir 'dfilter_buttons'
    if (-not (Test-Path $buttons)) {
        [IO.File]::WriteAllLines($buttons, [string[]]@(
            '# Written by run_wizard.ps1 (WIRESHARK category): the filter bar buttons.',
            '"TRUE","Mesh data","llc.oui == 0x18fe34","ESP-MESH data frames only"',
            '"TRUE","Retries","wlan.fc.retry == 1","Real 802.11 retransmissions"',
            '"TRUE","Joins/leaves","wlan.fc.type_subtype in {0x00, 0x02, 0x0a, 0x0c}","Association, reassociation, disassociation, deauthentication"',
            '"TRUE","Beacons","wlan.fc.type_subtype == 0x08","Beacons only"',
            '"TRUE","No beacons/ACKs","!(wlan.fc.type_subtype in {0x08, 0x1d})","Hide beacons and ACKs"',
            '"TRUE","Weak signal","radiotap.dbm_antsignal < -80","Frames heard below -80 dBm"'
        ))
    }

    $io = @(
        '# Written by run_wizard.ps1 (WIRESHARK category) for the view it last opened.',
        '#"Enabled","Graph Name","Display Filter","Color","Style","Y Axis","Y Field","SMA Period","Y Axis Factor","Avg over Time"',
        '"Disabled","All Packets","","#2E3436","Line","Packets","","None","1","Disabled"'
    )
    for ($i = 0; $i -lt $IoLines.Count; $i++) {
        $io += ('"Enabled","{0}","{1}","{2}","Line","Packets","","None","1","Disabled"' -f `
                $IoLines[$i].Name, $IoLines[$i].Filter, $script:WsColors[$i % $script:WsColors.Count])
    }
    [IO.File]::WriteAllLines((Join-Path $dir 'io_graphs'), [string[]]$io)
}

function Open-InWireshark {
    # Starts Wireshark on $Path with the thesis settings folder and $Filter applied,
    # and does not wait - the wizard stays usable while it is open. $false when
    # Wireshark is missing (the filter is printed for copy-paste instead).
    param([string]$Path, [string]$Filter, [object[]]$IoLines = @())
    $ws = Find-Wireshark
    if (-not $ws) {
        Write-Host "  Wireshark was not found on this laptop. Open the file by hand and paste this filter:" -ForegroundColor Yellow
        if ($Filter) { Write-Host ("    {0}" -f $Filter) }
        return $false
    }
    # Our filters never hold a double quote; one would break the quoting below.
    if ($Filter -match '"') { throw "Internal: display filter contains a double quote: $Filter" }
    Initialize-WiresharkProfile -IoLines $IoLines
    # ONE pre-quoted string: PS 5.1's Start-Process joins an -ArgumentList array
    # with spaces and does not quote its items, so a path with spaces would split.
    $argLine = '-r "{0}"' -f $Path
    if ($Filter) { $argLine += (' -Y "{0}"' -f $Filter) }
    # PS 5.1's Start-Process has no -Environment: set it here, the child inherits
    # it, then put this window's value back.
    $prevCfg = $env:WIRESHARK_CONFIG_DIR
    $env:WIRESHARK_CONFIG_DIR = Get-WiresharkProfileDir
    try { Start-Process -FilePath $ws -ArgumentList $argLine | Out-Null }
    finally { $env:WIRESHARK_CONFIG_DIR = $prevCfg }
    Write-Host ""
    Write-Host ("  Wireshark is opening {0}" -f (Split-Path $Path -Leaf)) -ForegroundColor Green
    if ($Filter) { Write-Host ("  Filter: {0}" -f $Filter) -ForegroundColor DarkGray }
    Write-Host "  Thesis layout: RSSI / TA / RA / Seq / Retry columns, full MACs, filter buttons right of the filter bar." -ForegroundColor DarkGray
    if ($IoLines.Count -gt 0) {
        Write-Host ("  Statistics -> I/O Graphs: lines already loaded - {0}" -f (($IoLines | ForEach-Object { "'" + $_.Name + "'" }) -join ', ')) -ForegroundColor DarkGray
    }
    return $true
}

function Request-OpenInWireshark {
    # Asked after a capture is checked or recorded. Opens check_pcap's _fixed copy
    # when it wrote one - the original ends in a partial packet Wireshark warns about.
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path) -or -not (Find-Wireshark)) { return }
    $fixed = Join-Path (Split-Path $Path -Parent) ([IO.Path]::GetFileNameWithoutExtension($Path) + '_fixed' + [IO.Path]::GetExtension($Path))
    if (Test-Path -LiteralPath $fixed) { $Path = $fixed }
    Write-Host ""
    $ans = Read-Line "Open it in Wireshark now (overview of all boards of the run)? [Y/n] > "
    if ($ans -in @('n', 'N', 'no', 'No', 'NO')) { return }
    Invoke-WiresharkViews -Path $Path -Overview
}

function Get-PcapMeshMap {
    # check_pcap.py --map-json: every mesh board heard (STA + softAP MAC), whom
    # each sent data up to, and a root guess. $null when the file has no mesh.
    # stderr is left alone on purpose: it shows the file/packet count, or why it failed.
    param([string]$Path)
    Write-Host ""
    Write-Host "Reading the capture for your boards' MACs (a big Mac capture takes ~10 s) ..." -ForegroundColor DarkGray
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $raw = & python (Join-Path $base 'tools\check_pcap.py') --map-json $Path }
    finally { $ErrorActionPreference = $prevEap }
    if (-not $raw) { return $null }
    try { $map = ($raw -join "`n") | ConvertFrom-Json } catch { return $null }
    if (@($map.nodes).Count -eq 0) { return $null }
    return $map
}

function Get-MemberBoardLabels {
    # member_boards.json stores first:last byte ("B0:18") or a full MAC; keyed
    # here on first:last so a capture's full STA MAC finds its nickname.
    $out = @{}
    $p = Join-Path $base 'member_boards.json'
    if (-not (Test-Path $p)) { return $out }
    try { $j = Get-Content $p -Raw | ConvertFrom-Json } catch { return $out }
    foreach ($m in @($j.members)) {
        foreach ($b in @($m.boards)) {
            $parts = @(([string]$b.mac).ToLower() -split '[:-]' | Where-Object { $_ })
            if ($parts.Count -ge 2) { $out[$parts[0] + ':' + $parts[-1]] = ("{0} [{1}]" -f $b.nickname, $m.name) }
        }
    }
    return $out
}

function Get-MemberBoardOwners {
    # Same first:last keying as Get-MemberBoardLabels, but keeps the member and
    # the bare nickname apart - the "whose boards" view groups on the member.
    $out = @{}
    $p = Join-Path $base 'member_boards.json'
    if (-not (Test-Path $p)) { return $out }
    try { $j = Get-Content $p -Raw | ConvertFrom-Json } catch { return $out }
    foreach ($m in @($j.members)) {
        foreach ($b in @($m.boards)) {
            $parts = @(([string]$b.mac).ToLower() -split '[:-]' | Where-Object { $_ })
            if ($parts.Count -ge 2) { $out[$parts[0] + ':' + $parts[-1]] = @{ Member = [string]$m.name; Nick = [string]$b.nickname } }
        }
    }
    return $out
}

function Format-PcapNode {
    param($Node, $Map, [hashtable]$Labels, [string]$Attacker)
    $b = $Node.sta -split ':'
    $label = $Labels[$b[0] + ':' + $b[-1]]
    $txt = $Node.sta
    # "nick:" = member_boards.json's name for the board, NOT its role in this capture.
    if ($label) { $txt += ("  nick: {0}" -f $label) }
    $tags = @()
    if ($Node.sta -eq $Map.root_guess) { $tags += 'ROOT (sends nothing up)' }
    if ($Attacker -and $Node.sta -eq $Attacker) { $tags += 'ATTACKER (mesh_config.h)' }
    $ups = @($Node.parents)
    if ($ups.Count -gt 0) {
        $up = ($ups | ForEach-Object { "{0} ({1} frames)" -f $_.sta, $_.frames }) -join ', '
        $tags += ("up to {0}" -f $up)
    }
    if (-not $Node.beaconed) { $tags += 'not beaconing - seen only as a parent' }
    if ($tags.Count -gt 0) { $txt += ("  - {0}" -f ($tags -join '; ')) }
    return $txt
}

function Select-PcapNode {
    # Returns the chosen node object from the map, or $null on 'b'.
    param($Map, [string]$Title, [hashtable]$Labels, [string]$Attacker, [string]$DefaultSta)
    $nodes = @($Map.nodes)
    $opts = @(); $def = 0
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $opts += (Format-PcapNode -Node $nodes[$i] -Map $Map -Labels $Labels -Attacker $Attacker)
        if ($DefaultSta -and $nodes[$i].sta -eq $DefaultSta) { $def = $i }
    }
    $idx = Show-Menu -Title $Title -Options $opts -DefaultIndex $def -AllowBack
    if ($idx -lt 0) { return $null }
    return $nodes[$idx]
}

function Select-CaptureFile {
    # Every capture under PCAP\, newest first, plus "another file" for a Mac
    # capture copied from elsewhere. -Newest skips the question. $null = back.
    param([switch]$Newest)
    $root = Join-Path $base 'datasets\PCAP'
    $files = @()
    if (Test-Path $root) {
        $files = @(Get-ChildItem -Path $root -Recurse -File -Include *.pcap, *.pcapng -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
    }
    if ($Newest) {
        if ($files.Count -eq 0) { Write-Host "  No captures under datasets\PCAP\ yet - record one first (ESP32 sniffer board)." -ForegroundColor Yellow; return $null }
        return $files[0].FullName
    }
    $shown = @($files | Select-Object -First 15)
    $opts = @()
    foreach ($f in $shown) {
        $age = (Get-Date) - $f.LastWriteTime
        $ageTxt = if ($age.TotalHours -lt 1) { "{0} min ago" -f [int]$age.TotalMinutes }
                  elseif ($age.TotalDays -lt 1) { "{0} h ago" -f [int]$age.TotalHours }
                  else { $f.LastWriteTime.ToString('MMM. dd, yyyy').ToLower() }
        $opts += ("{0}   {1}, {2}" -f $f.FullName.Substring($root.Length + 1), (Format-ByteSize $f.Length), $ageTxt)
    }
    $opts += 'Another file (Mac capture copied from elsewhere - drag it into this window)'
    $idx = Show-Menu -Title 'Which capture? (newest first)' -Options $opts -DefaultIndex 0 -AllowBack
    if ($idx -lt 0) { return $null }
    if ($idx -lt $shown.Count) { return $shown[$idx].FullName }
    $p = Read-Line "Capture file path (drag the file into this window, then Enter) > "
    if (-not $p) { return $null }
    $p = $p.Trim().Trim('"').Trim("'")
    if (-not (Test-Path -LiteralPath $p)) { Write-Host ("  Not found: {0}" -f $p) -ForegroundColor Red; return $null }
    return $p
}

function Get-PcapBoardKey {
    # first:last byte of a STA MAC - what member_boards.json is matched on.
    param([string]$Sta)
    $b = $Sta.ToLower() -split ':'
    return $b[0] + ':' + $b[-1]
}

function Get-PcapMemberNodes {
    # The capture's boards that member_boards.json files under $Member.
    param([object[]]$Nodes, [hashtable]$Owners, [string]$Member)
    return @($Nodes | Where-Object { $o = $Owners[(Get-PcapBoardKey $_.sta)]; $o -and $o.Member -eq $Member })
}

function Select-PcapMember {
    # Whose boards, in roster order (Cal, Bas, Kyle); a name only in the file goes
    # last. '' = back, or nobody's boards are recorded.
    param([object[]]$Nodes, [hashtable]$Owners, [string]$Title = 'Whose boards?')
    $inFile = @($Owners.Values | ForEach-Object { $_.Member } | Select-Object -Unique)
    $names  = @(Get-PresetMemberNames | Where-Object { $inFile -contains $_ }) + @($inFile | Where-Object { (Get-PresetMemberNames) -notcontains $_ })
    if ($names.Count -eq 0) {
        Write-Host "  member_boards.json lists no boards yet - add them from the member board list menu." -ForegroundColor Yellow
        return ''
    }
    $opts = @($names | ForEach-Object { "{0} - {1} board(s) heard in this capture" -f $_, @(Get-PcapMemberNodes -Nodes $Nodes -Owners $Owners -Member $_).Count })
    $i = Show-Menu -Title $Title -Options $opts -DefaultIndex 0 -AllowBack
    if ($i -lt 0) { return '' }
    return $names[$i]
}

function Get-PcapPhaseSegments {
    # baseline/attack/cooldown as (Name, RelStart, RelEnd) in Wireshark's own
    # frame.time_relative convention - seconds since this PCAP's first frame -
    # read from tools/pcap_retry.py's sidecar <name>_retry.json (segments are
    # epoch seconds there; capture_epoch[0] is that same first-frame epoch, so
    # subtracting it lines up exactly with what Wireshark itself will show).
    # $null when the sidecar doesn't exist yet (pcap_retry.py never ran on this
    # capture - menu [27] / --all writes it) - callers fall back silently.
    param([string]$Path)
    $side = Join-Path (Split-Path $Path -Parent) `
                       ([IO.Path]::GetFileNameWithoutExtension($Path) + '_retry.json')
    if (-not (Test-Path -LiteralPath $side)) { return $null }
    try { $j = Get-Content -LiteralPath $side -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $j.segments -or -not $j.capture_epoch) { return $null }
    $zero = [double]$j.capture_epoch[0]
    $order = @('baseline', 'attack', 'cooldown')
    $out = @()
    foreach ($name in $order) {
        $seg = $j.segments.$name
        if (-not $seg -or $seg.Count -lt 2) { continue }
        $out += @{ Name = $name; Start = [double]$seg[0] - $zero; End = [double]$seg[1] - $zero }
    }
    if ($out.Count -eq 0) { return $null }
    return $out
}

function Format-WsTime {
    # Invariant-culture decimal so the filter string is "123.4", never "123,4"
    # on a laptop set to a comma-decimal locale.
    param([double]$Seconds)
    return [Math]::Round($Seconds, 1).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-PcapScopedView {
    # Filter + I/O lines for the views that work on any set of boards: every board
    # of the run (main list, -All) or one member's boards (the MY boards submenu).
    # $Who names the set in the I/O lines. $Path is only needed to find the
    # capture's _retry.json sidecar (phase-split retries); $null = backed out
    # of the board picker.
    param([string]$View, $Map, [object[]]$Scope, [switch]$All, [string]$Who,
          [hashtable]$Labels, [hashtable]$Owners, [string]$Attacker, [string]$Path)
    $macs = ($Scope | ForEach-Object { $_.sta, $_.softap }) -join ', '
    $set  = "wlan.addr in {$macs}"
    # Whole run: every ESP-MESH data frame, even one from a board the map could not place.
    $data = if ($All) { 'llc.oui == 0x18fe34' } else { "llc.oui == 0x18fe34 && $set" }
    switch ($View) {
        'overview' {
            return @{ Filter = $set
                      Io = @(@{ Name = "$Who - all frames"; Filter = $set },
                             @{ Name = "$Who - mesh data frames"; Filter = $data },
                             @{ Name = "$Who - retries"; Filter = "wlan.fc.retry == 1 && $set" }) }
        }
        'one' {
            $sub = [pscustomobject]@{ nodes = $Scope; root_guess = $Map.root_guess }
            $n = Select-PcapNode -Map $sub -Title 'Which board?' -Labels $Labels -Attacker $Attacker
            if (-not $n) { return $null }
            return @{ Filter = "wlan.addr == $($n.sta) || wlan.addr == $($n.softap)"
                      Io = @(@{ Name = "$($n.sta) sends"; Filter = "wlan.ta == $($n.sta) || wlan.ta == $($n.softap)" },
                             @{ Name = "$($n.sta) receives"; Filter = "wlan.ra == $($n.sta) || wlan.ra == $($n.softap)" }) }
        }
        'side' {
            $io = @()
            foreach ($n in $Scope) {
                $o = $Owners[(Get-PcapBoardKey $n.sta)]
                $nm = if ($o -and $o.Nick) { "$($o.Nick) [$($n.sta)]" } else { $n.sta }
                $io += @{ Name = "$nm sends"; Filter = "wlan.ta == $($n.sta) || wlan.ta == $($n.softap)" }
            }
            return @{ Filter = $set; Io = $io }
        }
        'data' {
            return @{ Filter = $data; Io = @(@{ Name = "$Who - mesh data frames"; Filter = $data }) }
        }
        'retry' {
            $f = "wlan.fc.retry == 1 && $set"
            $io = @(@{ Name = "$Who - retries"; Filter = $f },
                    @{ Name = "$Who - mesh data frames"; Filter = $data })
            # Phase-split lines, only when tools/pcap_retry.py has already run on this
            # capture (its _retry.json sidecar has the baseline/attack/cooldown times).
            # Scoped to llc.oui data frames only - the SAME population MacRetryRate /
            # feature_table.csv counts, not the mixed mgmt+data $f line above. Filter
            # bar / packet list stay on $f (the whole run); this only adds Statistics ->
            # I/O Graphs lines so baseline/attack/cooldown are visibly separated there
            # without a manual frame.time_relative edit or a Time Reference click.
            $segs = if ($Path) { Get-PcapPhaseSegments -Path $Path } else { $null }
            if ($segs) {
                foreach ($seg in $segs) {
                    $a = Format-WsTime $seg.Start
                    $z = Format-WsTime $seg.End
                    $pf = "wlan.fc.retry == 1 && $data && frame.time_relative >= $a && frame.time_relative < $z"
                    $io += @{ Name = "$Who - {0} data retries" -f $seg.Name.ToUpper(); Filter = $pf }
                }
            } else {
                Write-Host "  (Phase-split retry lines need tools/pcap_retry.py to have run on this capture first - menu [27] / --all.)" -ForegroundColor DarkGray
            }
            return @{ Filter = $f; Io = $io }
        }
        'topo' {
            return @{ Filter = "wlan.fc.type_subtype in {0x00, 0x02, 0x0a, 0x0c} && $set"
                      Io = @(@{ Name = 'Joins / re-joins'; Filter = "wlan.fc.type_subtype in {0x00, 0x02} && $set" },
                             @{ Name = 'Leaves'; Filter = "wlan.fc.type_subtype in {0x0a, 0x0c} && $set" }) }
        }
        'weak' {
            $f = "radiotap.dbm_antsignal < -80 && wlan.ta in {$macs}"
            return @{ Filter = $f; Io = @(@{ Name = "$Who below -80 dBm"; Filter = $f }) }
        }
    }
    throw "Internal: unknown Wireshark view '$View'"
}

function Invoke-WiresharkMemberViews {
    # The MY boards submenu: the scoped views again, limited to one member's boards.
    # Starts on this laptop's member (my_member.txt) and asks when that is not set.
    # Returns to the main list, whose views cover every board of the run.
    param([string]$Path, $Map, [hashtable]$Owners, [hashtable]$Labels, [string]$Attacker, [string]$Member)
    $nodes = @($Map.nodes)
    if (-not $Member) {
        $Member = Select-MyMember
        if (-not $Member) { $Member = Select-PcapMember -Nodes $nodes -Owners $Owners }
        if (-not $Member) { return }
    }
    $default = 0
    while ($true) {
        $scope = @(Get-PcapMemberNodes -Nodes $nodes -Owners $Owners -Member $Member)
        $who = if ($Member -eq (Get-MyMember)) { "My boards ($Member)" } else { "$Member's boards" }
        $sub = @()
        if ($scope.Count -gt 0) {
            $sub += @{ Key = 'overview'; Text = "Overview - $who only (every frame to or from them)" }
            $sub += @{ Key = 'one';      Text = "One board - one of $who" }
            $sub += @{ Key = 'side';     Text = "$who side by side - one I/O 'sends' line per board" }
            $sub += @{ Key = 'data';     Text = "Mesh data frames to or from $who" }
            $sub += @{ Key = 'retry';    Text = "Real MAC retransmissions on $who (802.11 Retry bit)" }
            $sub += @{ Key = 'topo';     Text = "Topology - joins, re-joins and leaves of $who" }
            $sub += @{ Key = 'weak';     Text = "Weak links - $who heard below -80 dBm" }
        } else {
            Write-Host ("  None of {0} in member_boards.json were heard in this capture (off, other channel, or MACs not recorded)." -f $who) -ForegroundColor Yellow
        }
        $sub += @{ Key = 'member'; Text = 'Another member''s boards instead' }
        $sub += @{ Key = 'back';   Text = 'Back - ALL boards of the run' }
        $title = "{0}: {1} of the {2} boards in this capture. Open which view?" -f $who, $scope.Count, $nodes.Count
        $i = Show-Menu -Title $title -Options @($sub | ForEach-Object { $_.Text }) -DefaultIndex ([Math]::Min($default, $sub.Count - 1)) -AllowBack
        if ($i -lt 0 -or $sub[$i].Key -eq 'back') { return }
        if ($sub[$i].Key -eq 'member') {
            $m = Select-PcapMember -Nodes $nodes -Owners $Owners
            if ($m) { $Member = $m; $default = 0 }
            continue
        }
        $r = Get-PcapScopedView -View $sub[$i].Key -Map $Map -Scope $scope -Who $who -Labels $Labels -Owners $Owners -Attacker $Attacker -Path $Path
        if (-not $r) { continue }
        Open-InWireshark -Path $Path -Filter $r.Filter -IoLines $r.Io | Out-Null
        $default = $sub.Count - 1
    }
}

function Invoke-WiresharkViews {
    # WIRESHARK category: pick a capture (unless -Path), read its boards once,
    # then open as many views of it as wanted. Every view here covers ALL boards
    # heard in the capture; "MY boards" opens the same views limited to one
    # member's boards. -Overview opens the overview straight away and returns
    # (the "newest capture" entry, and after a check).
    param([string]$Path, [switch]$Overview)
    if (-not $Path) { $Path = Select-CaptureFile }
    if (-not $Path) { return }

    $map = Get-PcapMeshMap -Path $Path
    if (-not $map) {
        Write-Host "  No mesh boards found in this capture (wrong channel, too far, or not a mesh capture)." -ForegroundColor Yellow
        Write-Host "  Opening it unfiltered - the filter buttons still work." -ForegroundColor Yellow
        Open-InWireshark -Path $Path -IoLines (Get-GenericIoLines) | Out-Null
        return
    }
    $nodes    = @($map.nodes)
    $labels   = Get-MemberBoardLabels
    $owners   = Get-MemberBoardOwners
    $attacker = Get-ConfiguredAttackerMac
    if ($attacker -and -not ($nodes | Where-Object { $_.sta -eq $attacker })) { $attacker = $null }
    $meshSet  = 'wlan.addr in {' + (($nodes | ForEach-Object { $_.sta, $_.softap }) -join ', ') + '}'

    Write-Host ""
    Write-Host ("Boards in {0} (read from the capture itself):" -f (Split-Path $Path -Leaf)) -ForegroundColor Cyan
    foreach ($n in $nodes) { Write-Host ("  {0}" -f (Format-PcapNode -Node $n -Map $map -Labels $labels -Attacker $attacker)) }
    if (-not $map.root_guess) { Write-Host "  (root unclear from this capture - no single board that only receives)" -ForegroundColor DarkGray }

    # Keyed, not numbered: the switch below cannot drift when an entry is added.
    $views = @(
        @{ Key = 'overview';  Text = 'Overview - ALL boards of the run (every frame to or from them)' },
        @{ Key = 'mine';      Text = '' },
        @{ Key = 'one';       Text = 'One board - everything to or from one board' },
        @{ Key = 'side';      Text = 'All boards side by side - one I/O ''sends'' line per board' },
        @{ Key = 'data';      Text = 'Mesh data frames only - all boards (the real traffic - no beacons, ACKs or other Wi-Fi)' },
        @{ Key = 'retry';     Text = 'Real MAC retransmissions - all boards (802.11 Retry bit)' },
        @{ Key = 'topo';      Text = 'Topology - joins, re-joins and leaves of all boards' },
        @{ Key = 'weak';      Text = 'Weak links - all boards'' frames heard below -80 dBm' },
        @{ Key = 'blackhole'; Text = 'BLACKHOLE proof - attacker -> its parent, with the I/O graph preloaded' },
        @{ Key = 'wormhole';  Text = 'WORMHOLE check - node B''s direct sends vs node A''s uplink, plus joins' },
        @{ Key = 'done';      Text = 'Done - back to the main menu' }
    )
    $doneIdx = $views.Count - 1
    $default = 0
    # Labelled: a bare 'continue' inside the switch below only leaves the switch.
    :views while ($true) {
        # Re-read each time: the submenu may have just set this laptop's member.
        $mine = Get-MyMember
        $views[1].Text = if ($mine) {
            "MY boards ({0}) - {1} of {2} heard - the views above and below, only my boards  >" -f $mine, @(Get-PcapMemberNodes -Nodes $nodes -Owners $owners -Member $mine).Count, $nodes.Count
        } else {
            'MY boards - the views above and below, only my boards (asks whose - not set on this laptop)  >'
        }
        $v = if ($Overview) { 0 } else { Show-Menu -Title 'Open which view in Wireshark? (ALL boards of the run, unless you pick MY boards)' -Options @($views | ForEach-Object { $_.Text }) -DefaultIndex $default -AllowBack }
        if ($v -lt 0 -or $v -eq $doneIdx) { return }
        $filter = $null; $io = @()
        switch ($views[$v].Key) {
            'mine' {
                Invoke-WiresharkMemberViews -Path $Path -Map $map -Owners $owners -Labels $labels -Attacker $attacker -Member $mine
                continue views
            }
            'blackhole' {
                if ($attacker) {
                    Write-Host ("  Attacker from mesh_config.h (BLACKHOLE_ATTACKER_MAC): {0}" -f $attacker) -ForegroundColor DarkGray
                    $a = $nodes | Where-Object { $_.sta -eq $attacker } | Select-Object -First 1
                } else {
                    Write-Host "  mesh_config.h's attacker was not heard in this capture - pick the attacker." -ForegroundColor Yellow
                    $a = Select-PcapNode -Map $map -Title 'Which board is the ATTACKER?' -Labels $labels
                    if (-not $a) { continue views }
                }
                $ups = @($a.parents)
                if ($ups.Count -eq 0) {
                    Write-Host "  The attacker sent no data up in this capture, so its parent is unknown - pick it." -ForegroundColor Yellow
                    $p = Select-PcapNode -Map $map -Title "Which board is the attacker's PARENT?" -Labels $labels -Attacker $attacker -DefaultSta $map.root_guess
                    if (-not $p) { continue views }
                    $parentAp = $p.softap
                } else {
                    $parentAp = $ups[0].softap
                    if ($ups.Count -gt 1) {
                        Write-Host "  The attacker re-parented during this capture - its uplinks:" -ForegroundColor Yellow
                        foreach ($u in $ups) { Write-Host ("    {0} ({1} frames)" -f $u.sta, $u.frames) -ForegroundColor Yellow }
                        Write-Host ("  Using the busiest one, {0}. Filter the others with 'One board' if needed." -f $ups[0].sta) -ForegroundColor Yellow
                    }
                }
                # Hop-wise: wlan.ra is the attacker's parent, never the root (see the quickstart).
                # Data frames only (type 2) - the RTS handshakes to the parent are most of
                # the raw rows and would pad the "forwarded" line.
                $filter = "wlan.fc.type == 2 && wlan.ta == $($a.sta) && wlan.ra == $parentAp"
                $io = @(@{ Name = "Attacker [$($a.sta)] -> parent [$parentAp] (forwarded)"; Filter = $filter },
                        @{ Name = "Into attacker [$($a.sta)] (still receiving)"; Filter = "wlan.fc.type == 2 && wlan.ra == $($a.softap)" },
                        @{ Name = "Attacker [$($a.sta)] - all traffic"; Filter = "wlan.addr == $($a.sta) || wlan.addr == $($a.softap)" })
                Write-Host "  In the I/O graph, 'Attacker -> parent' should fall during the attack window and recover in cooldown," -ForegroundColor DarkGray
                Write-Host "  while 'Into attacker' stays up in every phase." -ForegroundColor DarkGray
            }
            'wormhole' {
                Write-Host "  Wireshark cannot see the wired A<->B tunnel - only its Wi-Fi side effects." -ForegroundColor DarkGray
                $na = Select-PcapNode -Map $map -Title 'Which board is wormhole node A (re-injects)?' -Labels $labels
                if (-not $na) { continue views }
                $nb = Select-PcapNode -Map $map -Title 'Which board is wormhole node B (tunnels its probes away)?' -Labels $labels
                if (-not $nb) { continue views }
                $aUp = @($na.parents)
                $aFilter = if ($aUp.Count -gt 0) { "wlan.fc.type == 2 && wlan.ta == $($na.sta) && wlan.ra == $($aUp[0].softap)" } else { "wlan.fc.type == 2 && wlan.ta == $($na.sta)" }
                $filter = "wlan.fc.type_subtype in {0x00, 0x02} && $meshSet"
                $io = @(@{ Name = "B [$($nb.sta)] direct sends"; Filter = "wlan.fc.type == 2 && wlan.ta == $($nb.sta)" },
                        @{ Name = "A [$($na.sta)] -> its parent"; Filter = $aFilter },
                        @{ Name = 'Joins / re-joins'; Filter = $filter })
                Write-Host "  Expect: B's line drops in the wormhole phase, A's rises, and NO joins appear (topology unchanged)." -ForegroundColor DarkGray
            }
            default {
                $r = Get-PcapScopedView -View $views[$v].Key -Map $map -Scope $nodes -All -Who 'All boards' -Labels $labels -Owners $owners -Attacker $attacker -Path $Path
                if (-not $r) { continue views }
                $filter = $r.Filter; $io = $r.Io
            }
        }
        Open-InWireshark -Path $Path -Filter $filter -IoLines $io | Out-Null
        if ($Overview) { return }
        $default = $doneIdx
    }
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

    # ---- cross-check against the recorded blackhole attacker MAC ------------
    # SEVERITY DOWNGRADED by C7 Option 1 (D-12), sep. 21 2026.
    #
    # BEFORE: BLACKHOLE_ATTACKER_MAC was baked into VICTIM firmware at build time,
    # so if it did not match whichever board was actually wearing the attacker
    # role, every victim probe addressed a MAC nothing in the mesh held -- the
    # whole run logged zero arrivals with no error pointing at why. That cost two
    # full runs (2026-09-15/16, see archive/2026-09-16_bad-attacker-mac/).
    #
    # NOW: victims send to their PARENT hop-by-hop and the attacker drops whatever
    # transits it because of WHERE IT SITS in the tree. It is never addressed by
    # MAC, so a stale value here CANNOT break a capture any more -- it only means
    # the recorded attacker label disagrees with the board actually attacking.
    # Still worth fixing for accurate records, which is why the check stays; but
    # it must NOT read like an alarm. Telling someone their run will be empty when
    # it will not is how a perfectly good capture gets aborted for no reason.
    Write-Host ""
    if (-not $configured) {
        Write-Host "  (Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h -- skipping attacker cross-check.)" -ForegroundColor DarkGray
        return
    }
    Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $configured) -ForegroundColor Cyan
    $readOk  = @($results | Where-Object { $_.Mac })
    $matches = @($readOk | Where-Object { $_.Mac -eq $configured })

    if ($matches.Count -eq 1) {
        Write-Host ("  MATCH -- {0} ({1}) is the recorded attacker." -f $matches[0].Port, $matches[0].Node) -ForegroundColor Green
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

    Write-Host "  NO MATCH." -ForegroundColor Yellow
    Write-Host "  None of the boards just read is the one recorded as attacker ($configured)." -ForegroundColor Yellow
    Write-Host "  LINEAR / TREE / PARTIAL: bookkeeping only - victims send to their parent and the" -ForegroundColor DarkGray
    Write-Host "  attacker drops whatever passes through it, so those captures are fine either way." -ForegroundColor DarkGray
    Write-Host "  STAR + BLACKHOLE: NOT fine - victims join ONLY the attacker's MAC (D-16). A run" -ForegroundColor Red
    Write-Host "  started from the wizard builds the picked attacker's MAC in for you; a board" -ForegroundColor Red
    Write-Host "  flashed any other way uses this mesh_config.h value and never joins if it is wrong." -ForegroundColor Red
    $fixOpts = @($readOk | ForEach-Object { "$($_.Port)  ($($_.Mac))  $($_.Node)" })
    $fixOpts += 'Leave as-is'
    $fixIdx = Show-Menu -Title 'Update the recorded BLACKHOLE_ATTACKER_MAC to one of these boards?' -Options $fixOpts -DefaultIndex ($fixOpts.Count - 1)
    if ($fixIdx -lt $readOk.Count) {
        $target = $readOk[$fixIdx]
        if (Set-ConfiguredAttackerMac -Mac $target.Mac -PortLabel $target.Port) {
            Write-Host ("  Fixed -- mesh_config.h now targets {0} ({1}). The next build will pick it up." -f $target.Mac, $target.Port) -ForegroundColor Green
        } else {
            Write-Host "  Could not write mesh_config.h -- fix it by hand before flashing victims." -ForegroundColor Red
        }
    } else {
        Write-Host "  Left as-is -- fine for linear/tree/partial (only the label is stale). For STAR +" -ForegroundColor DarkGray
        Write-Host "  blackhole, run through the wizard so the picked attacker's MAC is built in." -ForegroundColor DarkGray
    }
}

function Get-CaptureSummary {
    # What preprocess.py/features.py will actually load from ONE folder (both glob
    # *.csv non-recursively). PDR, LatencyHopRatio and TunnelLatency come only from
    # a root's *_arrivals.csv, so a folder without one yields those columns as NaN.
    # Mirrored in menu.ps1 - keep the two in sync.
    param([string]$Dir, $Repeat = $null)
    $names = @(Get-ChildItem -Path $Dir -Filter *.csv -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name } | Where-Object { $_ -like '*_telem.csv' -or $_ -like '*_arrivals.csv' })
    if ($null -ne $Repeat) { $names = @($names | Where-Object { $_ -match "_r${Repeat}_" }) }
    $telem        = @($names | Where-Object { $_ -like '*_telem.csv' })
    $arrivals     = @($names | Where-Object { $_ -like '*_arrivals.csv' })
    # Name stamp, old 20260927_031130 or readable sept27_0311AM[-2] (tools\name_stamp.py).
    $stampRe      = '(\d{8}_\d{6}|[a-z]+\d{2}_\d{4}[AP]M(-\d+)?)'
    $arrivalHeads = @($arrivals | ForEach-Object { $_ -creplace "_${stampRe}_arrivals\.csv$", '' })
    $rootsMissing = @($telem | Where-Object { $_ -like 'root_*' } |
        Where-Object { ($_ -creplace "_${stampRe}_telem\.csv$", '') -notin $arrivalHeads })
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
    param([string]$Export, $Repeat = $null)

    $trimmedDir = Join-Path $Export 'trimmed'
    $raw  = Get-CaptureSummary -Dir $Export -Repeat $Repeat
    $trim = Get-CaptureSummary -Dir $trimmedDir -Repeat $Repeat
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

    $attempt = Select-AnalysisAttempt -ExportDir $dirs.Export -AnalysisDir $dirs.Analysis
    if ($null -eq $attempt) { Write-Host "  Skipped." -ForegroundColor DarkGray; return }
    $rep   = $attempt.Repeat
    $sfx   = if ($null -ne $rep) { "_r$rep" } else { '' }
    $repArgs = @(if ($null -ne $rep) { '--repeat'; [string]$rep })

    $inputDir = Select-AnalysisInput -Export $dirs.Export -Repeat $rep
    if (-not $inputDir) { return }

    # Same two-tier python scan run.ps1's -Analyze uses: prefer a python with the
    # full EDA stack (matplotlib/seaborn/scipy/scikit-learn) so M6+M7+M8 all run;
    # fall back to a pandas/numpy-only one (M6+M7 only, M8 skipped with a hint)
    # rather than failing the whole thing.
    $edaPy = $null
    $featuresPy = $null
    # 'py' is the Windows Python launcher: always on PATH when Python is
    # installed, and it finds the interpreter wherever it actually lives.
    # Replaces a hardcoded C:\Python314\python.exe, which was one
    # machine's install path and matched nothing anywhere else.
    foreach ($cand in @('python', 'python3', 'py')) {
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
    $windowedOut = Join-Path $dirs.Analysis "windowed_dataset$sfx.csv"
    $featOut     = Join-Path $dirs.Analysis "feature_table$sfx.csv"
    $edaOut      = Join-Path $dirs.Analysis "eda_output$sfx"
    $repText     = if ($repArgs.Count) { ' ' + ($repArgs -join ' ') } else { '' }

    Write-Host ""
    Write-Host ("Running: python analysis\preprocess.py {0} -o {1}{2}" -f $inputDir, $windowedOut, $repText) -ForegroundColor DarkGray
    Write-Host ("     ->  python analysis\features.py {0} -o {1}{2}" -f $inputDir, $featOut, $repText) -ForegroundColor DarkGray
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
        & $featuresPy preprocess.py $inputDir -o $windowedOut @repArgs
        if ($LASTEXITCODE -ne 0) { Write-Host "Preprocess failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }

        Write-Host "M7: features.py ..." -ForegroundColor Cyan
        & $featuresPy features.py $inputDir -o $featOut @repArgs
        if ($LASTEXITCODE -ne 0) { Write-Host "Features step failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }

        if ($edaPy) {
            Write-Host "M8: eda.py ..." -ForegroundColor Cyan
            & $edaPy eda.py $featOut -o $edaOut
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("EDA failed (exit $LASTEXITCODE); feature_table$sfx.csv is fine, see the error above.") -ForegroundColor Yellow
            } else {
                Write-Host ("Done -> {0}" -f $edaOut) -ForegroundColor Green
            }
        } else {
            Write-Host "Skipping M8/EDA: $featuresPy lacks matplotlib/seaborn/scipy/scikit-learn." -ForegroundColor Yellow
            Write-Host "  Fix once: pip install -r analysis\requirements.txt" -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
}

function Get-AttemptGroups {
    # Attempt number (the _rN_ in the name) -> that attempt's CSVs in $Dir.
    # Mirrored in menu.ps1 - keep the two in sync.
    param([string]$Dir)
    $groups = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.csv' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.csv' })) {
        if ($f.Name -match '_r(\d+)_') {
            $n = [int]$Matches[1]
            if (-not $groups.ContainsKey($n)) { $groups[$n] = @() }
            $groups[$n] += $f
        }
    }
    return $groups
}

function Select-AnalysisAttempt {
    # Which attempt to analyse. Every run restarts seq_num at 1, so pooling
    # attempts lets one run's arrivals count as another's deliveries (PDR too
    # high) and blanks latency (features.py _arrival_sender_window).
    # One attempt -> feature_table_rN.csv beside the pooled feature_table.csv;
    # the suffix keeps combine_all/feature_separability's **/feature_table.csv
    # glob from counting it twice.
    # Returns @{ Repeat = N }, @{ Repeat = $null } for all, or $null to go back.
    # Mirrored in menu.ps1 - keep the two in sync.
    param([string]$ExportDir, [string]$AnalysisDir)
    $groups = Get-AttemptGroups -Dir $ExportDir
    if ($groups.Count -le 1) {
        if ($groups.Count -eq 1) {
            Write-Host ("`n  Only attempt r{0} in this folder - analysing it into feature_table.csv." -f @($groups.Keys)[0]) -ForegroundColor DarkGray
        }
        return @{ Repeat = $null }
    }

    $reps = @($groups.Keys | Sort-Object)
    $opts = @()
    foreach ($n in $reps) {
        $done  = Test-Path -LiteralPath (Join-Path $AnalysisDir "feature_table_r$n.csv")
        $state = if ($done) { "analysed before -> feature_table_r$n.csv (will be replaced)" } else { "not analysed yet -> feature_table_r$n.csv" }
        $opts += ("r{0}  - {1} file(s), {2}" -f $n, @($groups[$n]).Count, $state)
    }
    $opts += 'all attempts together -> feature_table.csv  (WARNING: PDR too high + latency blank when attempts are pooled)'

    $idx = Show-Menu -Title 'Which attempt (repeat) to analyse?' -Options $opts -DefaultIndex ($reps.Count - 1) -AllowBack
    if ($idx -lt 0) { return $null }
    if ($idx -eq $reps.Count) { return @{ Repeat = $null } }
    return @{ Repeat = $reps[$idx] }
}

function Select-TrimAttempt {
    # Which attempt (the _rN_ in the file name) to trim, so trimming a new repeat
    # doesn't re-trim and overwrite attempts already sitting in trimmed\.
    # Returns @{ Repeat = N } for one attempt, @{ Repeat = $null } for all of
    # them, or $null if the operator backed out.
    # Mirrored in menu.ps1's trim action - keep the two in sync.
    param([string]$ExportDir)
    $trimmedDir = Join-Path $ExportDir 'trimmed'
    $groups = Get-AttemptGroups -Dir $ExportDir
    if ($groups.Count -eq 0) {
        Write-Host "  No _rN_ attempt number in these file names - trimming the whole folder." -ForegroundColor Yellow
        return @{ Repeat = $null }
    }

    $reps = @($groups.Keys | Sort-Object)
    $opts = @()
    $fullyTrimmed = @{}
    $default = -1
    foreach ($n in $reps) {
        $files = @($groups[$n])
        $done  = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $trimmedDir $_.Name) }).Count
        $fullyTrimmed[$n] = ($done -eq $files.Count)
        $state = if ($done -eq 0) { 'not trimmed yet' }
                 elseif ($done -eq $files.Count) { 'already trimmed' }
                 else { "partly trimmed ($done of $($files.Count) in trimmed\)" }
        $opts += ("r{0}  - {1} file(s), {2}" -f $n, $files.Count, $state)
        if (-not $fullyTrimmed[$n]) { $default = $opts.Count - 1 }
    }
    if ($default -lt 0) { $default = $opts.Count - 1 }
    $opts += 'all attempts  (re-trims every one, overwriting their trimmed\ copies)'

    $idx = Show-Menu -Title 'Which attempt (repeat) is this capture?' -Options $opts -DefaultIndex $default -AllowBack
    if ($idx -lt 0) { return $null }
    if ($idx -eq $reps.Count) { return @{ Repeat = $null } }

    $pick = $reps[$idx]
    if ($fullyTrimmed[$pick]) {
        $ans = Read-Line ("  r{0} is already in trimmed\. Trim it again and overwrite those copies? [y/N] > " -f $pick)
        if ($ans -ne 'y' -and $ans -ne 'Y') { return $null }
    }
    return @{ Repeat = $pick }
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
    Write-Host ""
    Write-Host "SMART TRIM (sep. 21, 2026): one exported CSV can hold several boot" -ForegroundColor DarkGray
    Write-Host "sessions - flashing, the real run, and the export power-cycle. It used to" -ForegroundColor DarkGray
    Write-Host "keep the LONGEST one, which silently kept the junk whenever a board was" -ForegroundColor DarkGray
    Write-Host "left plugged in longer than a short or aborted run lasted. It now keeps" -ForegroundColor DarkGray
    Write-Host "the session that actually shows a PHASE PROGRESSION (baseline -> attack ->" -ForegroundColor DarkGray
    Write-Host "cooldown -> terminate); an idle session logs PHASE_ID_UNSET and is rejected" -ForegroundColor DarkGray
    Write-Host "outright. Each session is printed WITH the reasons for its score, so read" -ForegroundColor DarkGray
    Write-Host "the report - it will also warn you if TWO sessions look like real runs." -ForegroundColor DarkGray

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

    $attempt = Select-TrimAttempt -ExportDir $dirs.Export
    if ($null -eq $attempt) { Write-Host "  Skipped." -ForegroundColor DarkGray; return }
    $trimArgs = @($dirs.Export, '--apply')
    if ($null -ne $attempt.Repeat) { $trimArgs += @('--repeat', [string]$attempt.Repeat) }

    $trimmedDir = Join-Path $dirs.Export 'trimmed'
    Write-Host ""
    Write-Host ("Running: python tools\trim_run.py {0}" -f ($trimArgs -join ' ')) -ForegroundColor DarkGray
    Write-Host ("     ->  {0}" -f $trimmedDir) -ForegroundColor DarkGray
    $goAns = Read-Line "`nRun this now? [Y/n] > "
    if ($goAns -eq 'n' -or $goAns -eq 'N') { Write-Host "  Skipped." -ForegroundColor DarkGray; return }

    Push-Location $base
    try {
        python (Join-Path $base 'tools\trim_run.py') @trimArgs
        if ($LASTEXITCODE -ne 0) { Write-Host "Trim failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }
        Write-Host ("`nDone -> {0}" -f $trimmedDir) -ForegroundColor Green
        Write-Host "  'Run analysis only' will offer this trimmed\ folder as its input." -ForegroundColor DarkGray
    } finally { Pop-Location }
}

function Invoke-DataSync {
    # tools\push_data.py does all git work in a private clone, so this folder's
    # code/staged changes/stash are never touched. Mirrors menu.ps1's data-sync
    # actions - keep the two in sync.
    param([ValidateSet('push', 'pull', 'test', 'delete', 'delete-local', 'restore')][string]$Mode,
          [ValidateSet('exports', 'presets', 'analysis', 'logs')][string]$Area = 'exports')
    $py = Join-Path $base 'tools\push_data.py'
    Write-Host ""
    if ($Mode -eq 'delete') {
        Write-Host "Removes ALL of that data or only SOME files (pick folders, then all or some of their files)" -ForegroundColor DarkGray
        Write-Host "from GitHub. Each file shows when it was uploaded: green = last 30 min, yellow = older." -ForegroundColor DarkGray
        Write-Host "A normal commit - GitHub's history keeps the files, so 'Restore deleted data' can undo it;" -ForegroundColor DarkGray
        Write-Host "then offers to delete this laptop's copies too." -ForegroundColor DarkGray
        Write-Host "Teammates are asked on their next pull; their push never re-uploads a deleted file." -ForegroundColor DarkGray
        Write-Host "Asks you to type DELETE before anything goes." -ForegroundColor DarkGray
    } elseif ($Mode -eq 'delete-local') {
        Write-Host "Removes files from THIS LAPTOP only - GitHub is never touched and teammates see nothing." -ForegroundColor DarkGray
        Write-Host "This is the one for clearing out junk: a botched run, a duplicate import, files you" -ForegroundColor DarkGray
        Write-Host "never want to share. Pick ALL or SOME (folders first, then all or some of their files);" -ForegroundColor DarkGray
        Write-Host "each file says whether GitHub has a copy." -ForegroundColor DarkGray
        Write-Host "A file GitHub already has can come back with a pull. A file only this laptop has is GONE" -ForegroundColor DarkGray
        Write-Host "- and if the SD card was cleared on import, that was the last copy, so it is listed by" -ForegroundColor DarkGray
        Write-Host "name before you confirm." -ForegroundColor DarkGray
        Write-Host "Asks you to type DELETE before anything goes. Ledgers (the run registry) and archive" -ForegroundColor DarkGray
        Write-Host "folders are never offered." -ForegroundColor DarkGray
    } elseif ($Mode -eq 'restore') {
        Write-Host "Lists every delete on GitHub (yours or a teammate's), newest first. The files you pick go" -ForegroundColor DarkGray
        Write-Host "back on GitHub exactly as they were, and back on this laptop unless you have a different copy." -ForegroundColor DarkGray
    } elseif ($Mode -eq 'test') {
        Write-Host "Makes 3 dummy CSVs (10 rows: Animal, Sex) under sync_test\<this computer>\ and pushes" -ForegroundColor DarkGray
        Write-Host "them the same way real data is pushed. Run it on a second laptop too (without" -ForegroundColor DarkGray
        Write-Host "pulling first) - both computers' files must end up on GitHub." -ForegroundColor DarkGray
    } elseif ($Area -eq 'logs') {
        if ($Mode -eq 'pull') {
            Write-Host "Copies teammates' saved run logs from GitHub into datasets\run_logs\<attack>\<topology>\<location>\" -ForegroundColor DarkGray
            Write-Host "(never code). Lists them and asks first; a log you already have - or archived - is never" -ForegroundColor DarkGray
            Write-Host "overwritten or brought back. Pushes nothing." -ForegroundColor DarkGray
        } else {
            Write-Host "Pushes your saved run logs (.log console transcripts) under datasets\run_logs\ (never code)." -ForegroundColor DarkGray
            Write-Host "Archived logs (datasets\run_logs\_archive\) stay local. Shows what will go up and asks first." -ForegroundColor DarkGray
        }
    } elseif ($Area -eq 'presets') {
        if ($Mode -eq 'pull') {
            Write-Host "Copies teammates' saved presets from GitHub into presets\<them>\ (never code). Lists them" -ForegroundColor DarkGray
            Write-Host "and asks first; a preset you already have is never overwritten. Pushes nothing." -ForegroundColor DarkGray
        } else {
            Write-Host "Pushes your saved presets under presets\<you>\ (never code, never capture data)." -ForegroundColor DarkGray
            Write-Host "Shows what will go up and asks before pushing, then offers teammates' new presets." -ForegroundColor DarkGray
        }
    } elseif ($Mode -eq 'pull') {
        Write-Host "Copies teammates' capture CSVs from GitHub into datasets\exports\ (never code). Lists them and" -ForegroundColor DarkGray
        Write-Host "asks first; a file you already have is never overwritten. Pushes nothing." -ForegroundColor DarkGray
        Write-Host "Each file shows when it was imported: green = newer than your latest SD import, or a card" -ForegroundColor DarkGray
        Write-Host "from that same run (same folder + repeat, a board you did not import), yellow = older." -ForegroundColor DarkGray
    } elseif ($Area -eq 'analysis') {
        if ($Mode -eq 'pull') {
            Write-Host "Copies teammates' analysis + EDA output from GitHub into analysis\<attack>\<topology>\<site>\" -ForegroundColor DarkGray
            Write-Host "(feature_table.csv, windowed_dataset.csv, eda_output\*.png/.csv). Lists them and asks first;" -ForegroundColor DarkGray
            Write-Host "a file you already have is never overwritten. Pushes nothing." -ForegroundColor DarkGray
        } else {
            Write-Host "Pushes your analysis + EDA RESULTS under analysis\<attack>\<topology>\<site>\ - the plots and" -ForegroundColor DarkGray
            Write-Host "tables a teammate cannot regenerate without your raw data. These are .gitignore'd (they are" -ForegroundColor DarkGray
            Write-Host "rebuilt by -Analyze), so they never reach GitHub any other way." -ForegroundColor DarkGray
            Write-Host "Only .csv/.png/.json/.md at cell depth go up - the pipeline's own .py is never pushed." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "Pushes raw capture CSVs under datasets\exports\ (never code, never trimmed\)." -ForegroundColor DarkGray
        Write-Host "Shows what will go up and asks before pushing, then offers teammates' new files." -ForegroundColor DarkGray
        Write-Host "Each file shows when it was imported: green = your latest SD import (every card up to the" -ForegroundColor DarkGray
        Write-Host "N to 'Import another card?') or newer, yellow = an earlier import." -ForegroundColor DarkGray
    }
    if ($Mode -eq 'push') {
        Write-Host "At the confirm prompt, 'd' deletes unnecessary files from this laptop first - nothing is" -ForegroundColor DarkGray
        Write-Host "pushed until you answer y, so it doubles as a way to prune what the listing shows." -ForegroundColor DarkGray
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
    # Grouped by WHAT is synced, same "-- NAME" style as the main menu; the
    # numbers stay one sequential run, so the headings are purely visual.
    while ($true) {
        switch (Show-Menu -Title 'Data sync (GitHub) - captures, analysis output, run logs and presets. NEVER code:' -Options @(
            "Push my capture data to GitHub - merges with teammates' pushes; green = latest import, yellow = older",
            "Pull teammates' capture data from GitHub - never overwrites your files; green = your latest import's run or newer",
            'Push my analysis + EDA output - feature_table, windowed_dataset, eda_output\ plots',
            "Pull teammates' analysis + EDA output - never overwrites your files",
            'Push my saved run logs - console output of each run, filed by attack\topology\location',
            "Pull teammates' run logs - never overwrites your files",
            "Upload my saved presets to GitHub - shares presets\<you>\*.json, fetches teammates' new ones back too",
            'Test the sync - push 3 dummy animal CSVs to prove two laptops never overwrite each other',
            'Delete data from GitHub (+ this laptop) - all or some files, upload times shown; always undoable',
            'Delete data from THIS LAPTOP only - clear out unnecessary files; GitHub is never touched',
            "Restore deleted data - undo a delete (yours or a teammate's) from GitHub's history",
            'Back to the main menu'
        ) -DefaultIndex 11 -GroupHeaders @{
            0  = '-- CAPTURE DATA'
            2  = '-- ANALYSIS + EDA'
            4  = '-- RUN LOGS'
            6  = '-- PRESETS'
            7  = '-- TEST'
            8  = '-- DELETE / RESTORE'
            11 = ''
        }) {
            0  { Invoke-DataSync -Mode push -Area exports }
            1  { Invoke-DataSync -Mode pull -Area exports }
            2  { Invoke-DataSync -Mode push -Area analysis }
            3  { Invoke-DataSync -Mode pull -Area analysis }
            4  { Invoke-DataSync -Mode push -Area logs }
            5  { Invoke-DataSync -Mode pull -Area logs }
            6  { Invoke-DataSync -Mode push -Area presets }
            7  { Invoke-DataSync -Mode test }
            8  { $a = Select-DataSyncArea -Verb 'Delete';  if ($a) { Invoke-DataSync -Mode delete -Area $a } }
            9  { $a = Select-DataSyncArea -Verb 'Delete from this laptop'
                 if ($a) { Invoke-DataSync -Mode 'delete-local' -Area $a } }
            10 { $a = Select-DataSyncArea -Verb 'Restore'; if ($a) { Invoke-DataSync -Mode restore -Area $a } }
            11 { return }
        }
    }
}

function Select-DataSyncArea {
    # Which kind of data a delete/restore works on - one tools\push_data.py area
    # each. Returns the --area value, or $null for Back.
    param([string]$Verb)
    $areas = @('exports', 'analysis', 'logs', 'presets')
    $idx = Show-Menu -Title "$Verb which kind of data?" -Options @(
        'Capture data (datasets\exports\ CSVs)',
        'Analysis + EDA output (analysis\<attack>\<topology>\<location>\)',
        'Run logs (datasets\run_logs\)',
        'Presets (presets\<member>\*.json)',
        'Back'
    ) -DefaultIndex 4
    if ($idx -ge $areas.Count) { return $null }
    return $areas[$idx]
}

function Get-KnownAttackerMacs {
    # Every attacker MAC this laptop knows of, best evidence first (oct. 1, 2026:
    # a victims-only laptop had to type the remote attacker's MAC from memory).
    #   1. RUNS: boards that actually logged role=blackhole in datasets\exports -
    #      the truth about who attacked, newest run first.
    #   2. PRESETS: attackers named in any member's preset (planned, may be stale).
    #   3. This laptop's mesh_config.h BLACKHOLE_ATTACKER_MAC.
    # Read-only and cheap: only the first data row of each telem CSV is read.
    $found = @{}
    function Add-Hit($mac, $rank, $when, $why) {
        $m = "$mac".Trim().ToLower()
        if ($m -notmatch '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$') { return }
        if (-not $found.ContainsKey($m)) {
            $found[$m] = [pscustomobject]@{ Mac = $m; Rank = $rank; When = $when; Why = $why; Seen = 1 }
        } else {
            $e = $found[$m]; $e.Seen++
            if ($rank -lt $e.Rank -or ($rank -eq $e.Rank -and $when -gt $e.When)) {
                $e.Rank = $rank; $e.When = $when; $e.Why = $why
            }
        }
    }
    $exp = Join-Path $base 'datasets\exports\blackhole'
    if (Test-Path $exp) {
        Get-ChildItem -Path $exp -Recurse -Filter '*_telem.csv' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\trimmed\\' } | ForEach-Object {
                try {
                    $two = @(Get-Content -Path $_.FullName -TotalCount 2)
                    if ($two.Count -lt 2) { return }
                    $cols = $two[0].Split(','); $vals = $two[1].Split(',')
                    $ri = [array]::IndexOf($cols, 'role'); $ni = [array]::IndexOf($cols, 'node_id')
                    if ($ri -lt 0 -or $ni -lt 0 -or $vals[$ri] -ne 'blackhole') { return }
                    $hex = ($vals[$ni] -replace '^NODE_', '')
                    if ($hex -notmatch '^[0-9A-Fa-f]{12}$') { return }
                    $mac = (($hex -split '(..)' | Where-Object { $_ }) -join ':')
                    $cell = (Split-Path (Split-Path $_.FullName -Parent) -NoQualifier) -replace '.*\\exports\\', '' -replace '\\', '/'
                    # Capture time from the file NAME (oct01_1239PM / 20260927_031130),
                    # not LastWriteTime: a git pull rewrites file times.
                    $when = $_.LastWriteTime
                    if ($_.Name -match '_(jan|feb|mar|apr|may|jun|jul|aug|sept|sep|oct|nov|dec)(\d{2})_(\d{2})(\d{2})(AM|PM)_') {
                        $mo = @{jan=1;feb=2;mar=3;apr=4;may=5;jun=6;jul=7;aug=8;sep=9;sept=9;oct=10;nov=11;dec=12}[$Matches[1]]
                        $hh = [int]$Matches[3] % 12; if ($Matches[5] -eq 'PM') { $hh += 12 }
                        try { $when = Get-Date -Year $_.LastWriteTime.Year -Month $mo -Day ([int]$Matches[2]) -Hour $hh -Minute ([int]$Matches[4]) -Second 0 } catch { }
                    }
                    elseif ($_.Name -match '_(\d{8})_(\d{6})_') {
                        try { $when = [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', $null) } catch { }
                    }
                    Add-Hit $mac 1 $when ("attacker in run {0} ({1})" -f $cell, $when.ToString('MMM dd HH:mm'))
                } catch { }
            }
    }
    $pre = Join-Path $base 'presets'
    if (Test-Path $pre) {
        Get-ChildItem -Path $pre -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $cfg = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json
                foreach ($b in @($cfg.boards)) {
                    if ($b.Kind -eq 'attacker' -and $b.Mac) {
                        $name = ($_.FullName -replace '.*\\presets\\', '' -replace '\\', '/')
                        Add-Hit $b.Mac 2 $_.LastWriteTime ("attacker in preset {0}" -f $name)
                    }
                }
            } catch { }
        }
    }
    $cfgMac = Get-ConfiguredAttackerMac
    if ($cfgMac) { Add-Hit $cfgMac 3 ([datetime]::MinValue) "this laptop's mesh_config.h" }

    $nick = Get-BoardNicknames
    foreach ($e in $found.Values) {
        $p = $e.Mac -split ':'
        $e | Add-Member -NotePropertyName Name -NotePropertyValue $nick["$($p[0]):$($p[-1])"] -Force
    }
    return @($found.Values | Sort-Object Rank, @{ Expression = 'When'; Descending = $true })
}

function Get-BoardNicknames {
    # "first:last" byte (lower case) -> "Member nickname", from member_boards.json
    # (it stores first:last byte only).
    $nick = @{}
    $mb = Join-Path $base 'member_boards.json'
    if (Test-Path $mb) {
        try {
            foreach ($m in @((Get-Content -Raw $mb | ConvertFrom-Json).members)) {
                foreach ($bd in @($m.boards)) {
                    $p = "$($bd.mac)".Trim().ToLower() -split ':'
                    if ($p.Count -ge 2) { $nick["$($p[0]):$($p[-1])"] = "$($m.name) $($bd.nickname)" }
                }
            }
        } catch { }
    }
    return $nick
}

function Get-KnownBoardMacs {
    # Every NON-root board this laptop has a full MAC for, newest sighting first -
    # so a fresh board can be picked as the attacker instead of re-using a past
    # one (oct. 1, 2026). Sources: the first data row of every telem CSV in
    # datasets\exports (any attack, any role but root) + every preset board.
    # -Exclude: MACs to leave out (already-listed attackers, this laptop's boards).
    param([string[]]$Exclude = @())
    $skip = @{}; foreach ($x in $Exclude) { if ($x) { $skip["$x".Trim().ToLower()] = $true } }
    $found = @{}
    function Add-Seen($mac, $when, $why) {
        $m = "$mac".Trim().ToLower()
        if ($m -notmatch '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' -or $skip[$m]) { return }
        if (-not $found.ContainsKey($m) -or $when -gt $found[$m].When) {
            $found[$m] = [pscustomobject]@{ Mac = $m; When = $when; Why = $why }
        }
    }
    $roots = @{}
    $exp = Join-Path $base 'datasets\exports'
    if (Test-Path $exp) {
        Get-ChildItem -Path $exp -Recurse -Filter '*_telem.csv' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\trimmed\\' } | ForEach-Object {
                try {
                    $two = @(Get-Content -Path $_.FullName -TotalCount 2)
                    if ($two.Count -lt 2) { return }
                    $cols = $two[0].Split(','); $vals = $two[1].Split(',')
                    $ri = [array]::IndexOf($cols, 'role'); $ni = [array]::IndexOf($cols, 'node_id')
                    if ($ri -lt 0 -or $ni -lt 0) { return }
                    $hex = ($vals[$ni] -replace '^NODE_', '')
                    if ($hex -notmatch '^[0-9A-Fa-f]{12}$') { return }
                    $mac = (($hex -split '(..)' | Where-Object { $_ }) -join ':').ToLower()
                    if ($vals[$ri] -eq 'root') { $roots[$mac] = $true; return }
                    $cell = (Split-Path (Split-Path $_.FullName -Parent) -NoQualifier) -replace '.*\\exports\\', '' -replace '\\', '/'
                    Add-Seen $mac $_.LastWriteTime ("{0} in run {1}" -f $vals[$ri], $cell)
                } catch { }
            }
    }
    $pre = Join-Path $base 'presets'
    if (Test-Path $pre) {
        Get-ChildItem -Path $pre -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $cfg = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json
                $name = ($_.FullName -replace '.*\\presets\\', '' -replace '\\', '/')
                foreach ($b in @($cfg.boards)) {
                    if (-not $b.Mac) { continue }
                    if ($b.Kind -eq 'root') { $roots["$($b.Mac)".Trim().ToLower()] = $true; continue }
                    Add-Seen $b.Mac $_.LastWriteTime ("{0} in preset {1}" -f $b.Kind, $name)
                }
            } catch { }
        }
    }
    $nick = Get-BoardNicknames
    $out = @($found.Values | Where-Object { -not $roots[$_.Mac] })
    foreach ($e in $out) {
        $p = $e.Mac -split ':'
        $e | Add-Member -NotePropertyName Name -NotePropertyValue $nick["$($p[0]):$($p[-1])"] -Force
    }
    return @($out | Sort-Object @{ Expression = 'When'; Descending = $true })
}

function Read-RemoteAttackerMac {
    # Pick-or-paste prompt for an attacker on ANOTHER laptop: lists
    # Get-KnownAttackerMacs so the operator types a number instead of a MAC
    # from memory. Returns the MAC (lower case) or $null for "no attacker".
    # -LocalMacs: boards on THIS laptop (victims here, so never offered).
    param([string]$Who = 'the attacker', [string[]]$LocalMacs = @())
    $loc = @($LocalMacs | Where-Object { $_ } | ForEach-Object { "$_".Trim().ToLower() })
    $attackers = @(Get-KnownAttackerMacs | Where-Object { $loc -notcontains $_.Mac })
    # Second list: every other known board, so a NEW attacker can be picked by
    # number too (oct. 1, 2026: operator wanted a fresh board, not a past one).
    $others = @(Get-KnownBoardMacs -Exclude (@($attackers | ForEach-Object { $_.Mac }) + $loc))
    $list = @($attackers) + @($others)
    if ($attackers.Count -gt 0) {
        Write-Host ""
        Write-Host "Attacker boards this laptop knows of (best evidence first):" -ForegroundColor Cyan
        for ($i = 0; $i -lt $attackers.Count; $i++) {
            $e = $attackers[$i]
            $name = if ($e.Name) { " ($($e.Name))" } else { '' }
            $tag = if ($i -eq 0) { '  <- most likely' } else { '' }
            Write-Host ("  [{0}] {1}{2} - {3}{4}" -f ($i + 1), $e.Mac, $name, $e.Why, $tag)
        }
    }
    if ($others.Count -gt 0) {
        Write-Host ""
        Write-Host "Other known boards (never an attacker yet - pick one for a NEW attacker):" -ForegroundColor Cyan
        for ($j = 0; $j -lt $others.Count; $j++) {
            $e = $others[$j]
            $name = if ($e.Name) { " ($($e.Name))" } else { '' }
            Write-Host ("  [{0}] {1}{2} - last seen as {3} ({4})" -f ($attackers.Count + $j + 1), $e.Mac, $name, $e.Why, $e.When.ToString('MMM dd'))
        }
    }
    if ($list.Count -gt 0) {
        Write-Host "  Confirm with the attacker's laptop (its wizard prints 'Attacker for this run: ...')." -ForegroundColor DarkGray
    }
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) { Write-Host "  No valid answer - continuing without an attacker MAC." -ForegroundColor Yellow; return $null }
        $hint = if ($list.Count -gt 0) { "number 1-$($list.Count), " } else { '' }
        $raw = Read-Line ("`n{0}'s MAC - {1}or paste aa:bb:cc:dd:ee:ff, blank if none > " -f $Who, $hint)
        if (-not $raw) { return $null }
        $raw = $raw.Trim()
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $list.Count) {
            Write-Host ("  Using {0}" -f $list[$n - 1].Mac) -ForegroundColor Green
            return $list[$n - 1].Mac
        }
        if ($raw -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { return $raw.ToLower() }
        Write-Host "  Not a list number or a MAC (expected aa:bb:cc:dd:ee:ff)." -ForegroundColor Yellow
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
    # 'stationary'/'mobility'/'powercycle' builds are untouched.
    $scenario = $Params.Scenario
    if ($scenario -eq 'burst' -and ($role -eq 'root' -or $Params.ScenarioTarget)) { $suffix += '_burst' }
    if ($scenario -eq 'highload') { $suffix += '_highload' }   # root too (oct. 7, 2026)
    if ($scenario -eq 'jitter' -and $role -eq 'root') { $suffix += '_jitter' }
    if ($Params.CommandCenter) { $suffix += '_cc' }
    $portTag = ($Params.Port -replace '[^A-Za-z0-9]', '')
    $proj = if ($role -eq 'root') { 'root_node' } else { 'child_node' }
    return Get-SafeBuildDir -Proj $proj -DirName "build_${suffix}_$portTag"
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

function Format-BoardMacTag {
    # "MAC f4:2d:..." for the pre-build and run headers - the one thing that
    # names the PHYSICAL board (the label is a name, the COM port a USB socket).
    # Reads only what Resolve-BoardMac already stored, never the chip; empty
    # under -SkipMacCheck/-DryRun, and says so rather than printing nothing.
    param($Board)
    if ($Board.PSObject.Properties['Mac'] -and $Board.Mac) { return "MAC $($Board.Mac)" }
    return 'MAC not read'
}

function Format-PickerMacTag {
    # The MAC part of a "which board is ...?" picker line, so the operator can
    # tell physical boards apart. A recorded MAC wins; else this session's
    # identify tag for the port (it already carries the MAC); else 'MAC not read'.
    param($Board)
    $tag = Format-BoardMacTag $Board
    if ($tag -eq 'MAC not read' -and $Board.Port -and $script:IdentifiedPorts.ContainsKey($Board.Port)) {
        return "[$($script:IdentifiedPorts[$Board.Port])]"
    }
    return $tag
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

function Confirm-BoardLocations {
    # ---- LOCATION PRE-FLIGHT (added sep. 22, 2026) ----
    # The board decides which <location> folder its SD mirror writes into, from
    # location.txt on its OWN card - NOT from the answer given in this wizard.
    # When the two disagree the run still "works", and the damage is silent: the
    # USB export lands in exports/<...>/home/ while the card copy lands in
    # <...>/G402/, so one run is split across two SITE folders and location - a
    # RECORDED experimental variable - is wrong for half the data. That is
    # exactly what happened on 2026-09-22.
    #
    # Call this BEFORE flashing: location.txt is read at boot, so a value written
    # here only takes effect on the reboot the flash provides.
    #
    # Shared by BOTH run paths on purpose. It started life inline in the preset
    # "Yes - use it" branch, which left the manual menu flow with no check at all
    # - the identical silent mis-filing was still reachable just by answering the
    # menus instead of picking a preset. One copy, so the two cannot drift.
    param(
        [Parameter(Mandatory)] $Boards,
        [Parameter(Mandatory)] [string] $WantLocation
    )
    $mismatch = @()
    $checked  = 0
    $skipped  = @()
    Write-Host ""
    Write-Host ("Checking each board{0}s location.txt matches {1}{2}{1} ..." -f [char]39, [char]39, $WantLocation) -ForegroundColor DarkGray
    foreach ($b in $Boards) {
        if (-not $b.Port) { $skipped += $b.Label; continue }
        if (-not (Test-PortSafeToTouch -Port $b.Port -Action 'read its location' -Quiet)) { $skipped += $b.Label; continue }
        $checked++
        $cur = Get-SdLocation -TargetPort $b.Port
        if ($cur.State -eq 'OK' -and $cur.Value -eq $WantLocation) { continue }
        $mismatch += [pscustomobject]@{ Label=$b.Label; Port=$b.Port; Current=$cur }
    }
    if ($skipped.Count -gt 0) {
        Write-Host ("  NOT checked (no port here / port unsafe to touch): {0}" -f ($skipped -join ', ')) -ForegroundColor Yellow
    }
    if ($checked -eq 0) {
        # Never print "All boards match" when nothing was read - that green line
        # is exactly what made a skipped ROOT look verified (sep. 25, 2026).
        Write-Host "  No board was read - location.txt is UNVERIFIED on this laptop." -ForegroundColor Yellow
        return
    }
    if ($mismatch.Count -eq 0) {
        Write-Host ("  All {2} board(s) read report {1}{0}{1}." -f $WantLocation, [char]39, $checked) -ForegroundColor Green
        return
    }
    Write-Host ""
    Write-Host ("  {0} board(s) do NOT match {2}{1}{2}:" -f $mismatch.Count, $WantLocation, [char]39) -ForegroundColor Yellow
    foreach ($mm in $mismatch) {
        Write-Host ("    {0,-8} {1,-7} {2}" -f $mm.Label, $mm.Port, (Format-SdLocationState $mm.Current)) -ForegroundColor Yellow
    }
    Write-Host "  Left as-is, this runs SD data is filed under the WRONG site." -ForegroundColor Yellow
    $fixAns = Read-Line ("  Write {1}{0}{1} to them now? [Y/n] > " -f $WantLocation, [char]39)
    if ($fixAns -eq 'n' -or $fixAns -eq 'N') {
        Write-Host "  Proceeding with a KNOWN location mismatch - data will be filed under the boards own value." -ForegroundColor Yellow
        return
    }
    foreach ($mm in $mismatch) {
        Write-Host ("    {0,-8} {1,-7} SET_LOCATION={2} ..." -f $mm.Label, $mm.Port, $WantLocation) -ForegroundColor DarkGray
        $r = Set-SdLocation -TargetPort $mm.Port -Location $WantLocation
        if (-not $r.Ok) {
            # Set-SdLocation returns @{Ok;Lines} - ALWAYS truthy, so this must
            # test .Ok, not the hashtable itself.
            $why = @($r.Lines) -join ' '
            if ($why -match 'LOCATION_STALE_MOUNT') {
                Write-Host "      FAILED: that card was pulled and reinserted while this board kept" -ForegroundColor Red
                Write-Host "      running, so its mount is stale. REBOOT the board, then retry." -ForegroundColor Red
            }
            else {
                Write-Host ("      FAILED: {0}" -f $why) -ForegroundColor Red
            }
        }
    }
    Write-Host "  location.txt takes effect on the NEXT boot - the flash below provides it." -ForegroundColor DarkGray
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
    param($Board, [string]$Attack, [string]$Topology, [string]$Location, [int]$RepeatNum, [string]$Scenario = 'stationary',
          [int]$ExpectedChildren = 0, [string]$AttackerMac = '')

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
        # What runs after the root's export - asked once per run ("after the root's export" block).
        switch ($script:rootPostExport) {
            'trim'  { $h.Trim = $true }
            'none'  { $h.Export = $true }
            default { $h.Analyze = $true }
        }
        # Roster gate: the root will not start Phase 0 until this many children
        # are in the mesh (EXPECTED_CHILDREN in mesh_config.h).
        $h.ExpectedChildren = $ExpectedChildren
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
    # The run's attacker, built into this board's firmware ahead of the laptop's
    # own mesh_config.h (run.ps1 -AttackerMac). Load-bearing for star+blackhole:
    # victims join ONLY that board (D-16).
    if ($h.Attack -eq 'blackhole' -and $AttackerMac) { $h.AttackerMac = $AttackerMac }
    $h.Export = $true
    # Children only (the root returned above): what Ctrl+] does to the export -
    # asked once per run ($script:childExportMode).
    if ($script:childExportMode -eq 'now') { $h.SkipExportNow = $true }
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
    $labels = @($peers | ForEach-Object { "$($_.Label)  ($($_.Port))  $(Format-PickerMacTag $_)" })

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
        $idxA = Show-Menu -Title "WIRED TUNNEL BOARD 1 of 2 (wormhole, labelled Node A) - either cable end is fine: at run start the two boards pick A/B themselves by depth (deeper = B); this choice is only the backup if the cable link fails" -Options $labels -AllowBack
        if ($idxA -ge 0) {
            $idxB = -1
            while ($true) {
                $idxB = Show-Menu -Title "WIRED TUNNEL BOARD 2 of 2 (wormhole, labelled Node B) - the OTHER end of the same UART cable" -Options $labels -AllowBack
                if ($idxB -eq -1 -or $idxB -ne $idxA) { break }
                Write-Host "   Pick the OTHER end of the cable - board 2 must be a different board from board 1." -ForegroundColor Yellow
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
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Ports,
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
                # Enter keeps the current label; the hint names the first free one
                # (gaps first) so renumbering doesn't mean scanning the list by eye.
                $others   = @($Roster | Where-Object { $_ -ne $Board } | ForEach-Object { $_.Label })
                $nextFree = Get-FreeNodeLabel -ForRoot:($Board.Role -eq 'root') -Taken $others
                $new = Read-Line "New label > [$($Board.Label)] (Enter keeps it; first free: $nextFree) "
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
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Ports
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
        # Plain wording for non-members of the team: name who holds the seat now and
        # say that Enter/N keeps it. Y does NOT make the new node the attacker by
        # itself - it opens Set-AttackSubRoles' picker over every board - so the
        # question says "change", not "make this node".
        if ($Attack -eq 'blackhole') {
            $cur = @($updated | Where-Object { $_.Kind -eq 'attacker' } | ForEach-Object { $_.Label }) -join ', '
            if (-not $cur) { $cur = 'nobody yet' }
            Write-Host ("   The attacker (the board that drops traffic) is currently: {0}." -f $cur) -ForegroundColor DarkGray
            $ans = Read-Line "   Change which board is the attacker? Press Enter to keep it as is [y/N] > "
        }
        else {
            $curA = @($updated | Where-Object { $_.Kind -eq 'A' } | ForEach-Object { $_.Label }) -join ', '
            $curB = @($updated | Where-Object { $_.Kind -eq 'B' } | ForEach-Object { $_.Label }) -join ', '
            if (-not $curA) { $curA = 'nobody yet' }
            if (-not $curB) { $curB = 'nobody yet' }
            Write-Host ("   The two wired tunnel boards are currently: {0} (labelled A) and {1} (labelled B)." -f $curA, $curB) -ForegroundColor DarkGray
            Write-Host "   A/B is only a backup label: at run start the boards pick A/B themselves by depth (deeper = B)." -ForegroundColor DarkGray
            $ans = Read-Line "   Change which two boards are the wired tunnel pair? Press Enter to keep them as is [y/N] > "
        }
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
            $tIdx = Show-ScenarioTargetMenu -Title "Which node is now the $Scenario TARGET? (exactly one)" `
                -Scenario $Scenario -Eligible $eligible -Roster $remaining -DefaultIndex 0
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
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario = 'stationary')
    $attackDir = $Attack
    if ($Attack -eq 'none') { $attackDir = 'baseline' }
    $topoDir = switch ($Topology) {
        'star'    { 'star' }
        'tree'    { 'tree' }
        'linear'  { 'linear' }
        'partial' { 'partial_mesh' }
    }
    # Every scenario is a folder, stationary included (sep. 24 2026) - must stay
    # byte-identical to _subdir_for() in tools\export_logs.py. A pre-rename
    # stationary capture has NO scenario folder: use that flat folder only when
    # it holds CSVs and the new stationary folder does not exist yet.
    $Scenario = ConvertTo-Scenario $Scenario
    $scenarioSeg = "\$Scenario"
    if ($Scenario -eq 'stationary') {
        $flat = Join-Path $base "datasets\exports\$attackDir\$topoDir\$Location"
        $new  = Join-Path $flat 'stationary'
        if (-not (Test-Path $new) -and (Get-ChildItem -Path $flat -Filter '*.csv' -File -ErrorAction SilentlyContinue)) {
            $scenarioSeg = ''
        }
    }
    return [pscustomobject]@{
        AttackDir = $attackDir
        TopoDir   = $topoDir
        Export    = (Join-Path $base "datasets\exports\$attackDir\$topoDir\$Location$scenarioSeg")
        Analysis  = (Join-Path $base "datasets\analysis\$attackDir\$topoDir\$Location$scenarioSeg")
    }
}

function Get-PresetCellFileName {
    # A preset's filename spells its experiment cell in the SAME order as the
    # picker's heading: attack / topology / location / scenario, e.g.
    #   -- BLACKHOLE / linear / home / highload -> blackhole-linear-home-highload.json
    # Folder spellings from Get-RunDirs ('none' -> baseline, 'partial' ->
    # partial_mesh). Presets saved before oct. 4, 2026 used topology-attack-
    # scenario-location; the picker reads the cell from the file CONTENTS, so
    # those still load and group correctly, and editing one offers the rename.
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario)
    $dirs = Get-RunDirs -Attack $Attack -Topology $Topology -Location $Location -Scenario $Scenario
    return "{0}-{1}-{2}-{3}.json" -f $dirs.AttackDir, $dirs.TopoDir, $Location.ToLower(), (ConvertTo-Scenario $Scenario)
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
    # presets\Bas\blackhole-linear-g402-stationary.json. The filename already spells
    # the experiment cell (attack-topology-location-scenario), so the ONE thing
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

function Get-MemberNicknameMap {
    # first:last MAC ("20:38") -> nickname from member_boards.json, so the preset
    # picker can name each board the way the whiteboard table does. Same
    # first:last matching as Find-PresetOwnerByMac. Empty map (picker shows '-')
    # when the file or tools\Show-MemberBoards.ps1 is missing or unreadable.
    $map = @{}
    if (-not (Get-Command Read-MemberBoardData -ErrorAction SilentlyContinue)) { return $map }
    $data = $null
    try { $data = Read-MemberBoardData -Path (Join-Path $base 'member_boards.json') } catch { return $map }
    if (-not $data) { return $map }
    foreach ($name in $data.Members.Keys) {
        foreach ($b in $data.Members[$name]) {
            if ($b.mac -and $b.nickname) { $map[(Format-ShortMac ([string]$b.mac))] = [string]$b.nickname }
        }
    }
    return $map
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

function Get-RunLogRoot { return (Join-Path $base 'datasets\run_logs') }

function Get-RunLogDir {
    # Where a run's console log is filed: run_logs\<attack>\<topology>\<location>\<scenario>\
    # - the same folder names tools\exports\ and analysis\ use (Get-RunDirs), so a
    # log sits beside "its" run in every tree. Always includes the scenario: there
    # is no pre-rename flat layout to stay compatible with here.
    param([string]$AttackDir, [string]$TopoDir, [string]$Location, [string]$Scenario)
    return (Join-Path (Get-RunLogRoot) ("{0}\{1}\{2}\{3}" -f $AttackDir, $TopoDir, $Location, (ConvertTo-Scenario $Scenario)))
}

function Get-RunLogEntries {
    # Every *.log under run_logs\ (live) or run_logs\_archive\ (-Archived), each
    # tagged with its folder relative to that root ('blackhole\linear\G402\stationary').
    # '' = a log saved straight into run_logs\ before logs were filed by run.
    param([switch]$Archived)
    $root = [IO.Path]::GetFullPath((Get-RunLogRoot))
    $scan = if ($Archived) { Join-Path $root '_archive' } else { $root }
    if (-not (Test-Path $scan)) { return @() }
    $out = @()
    foreach ($f in @(Get-ChildItem -Path $scan -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue)) {
        $rel = $f.DirectoryName.Substring($scan.Length).Trim('\')
        if (-not $Archived -and ($rel -eq '_archive' -or $rel -like '_archive\*')) { continue }
        $out += [pscustomobject]@{ File = $f; Category = $rel }
    }
    return $out
}

function Remove-EmptyRunLogDirs {
    # After a move/delete, drop the now-empty category folders it leaves behind,
    # walking up but never removing $StopAt itself (run_logs\) - an emptied _archive\ goes too.
    param([string]$Dir, [string]$StopAt)
    $stop = [IO.Path]::GetFullPath($StopAt).TrimEnd('\')
    $d = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
    while ($d.Length -gt $stop.Length -and $d.StartsWith($stop, [StringComparison]::OrdinalIgnoreCase)) {
        if (@(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue).Count -gt 0) { break }
        Remove-Item -LiteralPath $d -Force -ErrorAction SilentlyContinue
        $d = Split-Path $d -Parent
    }
}

function Move-RunLog {
    # Archive (live -> _archive) or restore (_archive -> live), keeping the same
    # attack\topology\location\scenario folders on the other side. Refuses rather
    # than overwrites if a log of that name is already there.
    param($Entry, [string]$FromRoot, [string]$ToRoot)
    $destDir = if ($Entry.Category) { Join-Path $ToRoot $Entry.Category } else { $ToRoot }
    $dest = Join-Path $destDir $Entry.File.Name
    if (Test-Path -LiteralPath $dest) {
        Write-Host "  Not moved - $dest already exists." -ForegroundColor Yellow
        return $false
    }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Move-Item -LiteralPath $Entry.File.FullName -Destination $dest -ErrorAction Stop
    Remove-EmptyRunLogDirs -Dir $Entry.File.DirectoryName -StopAt (Get-RunLogRoot)
    Write-Host "  Moved -> $dest" -ForegroundColor Green
    return $true
}

function Write-RunLogLine {
    # ESP-IDF error lines ("E (1234) tag: ...") and the wizard's own FAILED /
    # ERROR messages in red, so a problem stands out while paging a long run.
    param([string]$Line)
    $clean = Remove-AnsiEscapes $Line
    if ($clean -match '^E \(\d+\)' -or $clean -match '(?i)\b(error|failed|fatal|abort(ed|ing)?)\b') {
        Write-Host $clean -ForegroundColor Red
    } else {
        Write-Host $clean
    }
}

function Show-RunLogPaged {
    # The whole run, first line to last, one screen at a time - "Print the whole
    # file" used to dump thousands of lines at once, so the start of the run
    # scrolled away before it could be read.
    param($Entry)
    $lines = @(Get-Content -LiteralPath $Entry.File.FullName -Encoding UTF8)
    $pageSize = 40
    try { $h = $Host.UI.RawUI.WindowSize.Height; if ($h -gt 12) { $pageSize = $h - 4 } } catch { }
    $where = if ($Entry.Category) { $Entry.Category -replace '\\', ' > ' } else { 'not filed' }
    Write-Host ""
    Write-Host ("=== START OF RUN LOG: {0}  ({1}, {2:N0} lines) ===" -f $Entry.File.Name, $where, $lines.Count) -ForegroundColor Cyan
    $i = 0
    while ($i -lt $lines.Count) {
        $end = [Math]::Min($i + $pageSize, $lines.Count)
        for ($j = $i; $j -lt $end; $j++) { Write-RunLogLine $lines[$j] }
        $i = $end
        if ($i -ge $lines.Count) { break }
        $ans = Read-Line ("-- lines 1-{0} of {1} ({2}%) - Enter next page, 'a' all the rest, 'q' stop here > " -f $i, $lines.Count, [int](100 * $i / $lines.Count))
        $ans = "$ans".Trim().ToLower()
        if ($ans -eq 'q') {
            Write-Host "  (stopped at line $i of $($lines.Count))" -ForegroundColor DarkGray
            return
        }
        if ($ans -eq 'a') { $pageSize = $lines.Count }
    }
    Write-Host ("=== END OF RUN LOG: {0} ===" -f $Entry.File.Name) -ForegroundColor Cyan
}

function Invoke-RunLogActions {
    # One log's menu: view it, then keep / archive / delete it, or push it.
    # Returns once the operator goes back, or the file is moved or deleted.
    param($Entry, [switch]$Archived)
    $root = Get-RunLogRoot
    $archiveRoot = Join-Path $root '_archive'
    $default = 0
    while ($true) {
        $opts = @(
            'View the whole run, beginning to end (page by page)',
            'Show only the last 100 lines (quick look for errors)',
            'Open the full file in Notepad',
            'Keep it here - back to the log list'
        )
        if ($Archived) {
            $opts += 'Restore it - move it back out of the archive into the live list'
        } else {
            $opts += 'Archive it - moves to datasets\run_logs\_archive\<same folders>\ (still viewable, never pushed)'
        }
        $opts += 'Delete it from this laptop - PERMANENT (a pushed copy stays on GitHub: Data sync -> Delete data)'
        $headers = @{ 0 = '-- VIEW'; 3 = '-- KEEP / ARCHIVE / DELETE' }
        if (-not $Archived) {
            $opts += 'Push my run logs to GitHub - lists every log not on GitHub yet and asks first'
            $headers[6] = '-- SHARE'
        }
        $where = if ($Entry.Category) { $Entry.Category -replace '\\', ' > ' } else { 'not filed by run' }
        $tag = if ($Archived) { 'ARCHIVED, ' } else { '' }
        $idx = Show-Menu -Title "$($Entry.File.Name)  ($tag$where) - what do you want to do?" -Options $opts -DefaultIndex $default -GroupHeaders $headers
        switch ($idx) {
            0 { Show-RunLogPaged $Entry; $default = 3 }
            1 {
                Write-Host ""
                Get-Content -LiteralPath $Entry.File.FullName -Tail 100 -Encoding UTF8 |
                    ForEach-Object { Write-RunLogLine $_ }
                $default = 3
            }
            2 { Start-Process notepad.exe $Entry.File.FullName; $default = 3 }
            3 { return }
            4 {
                if ($Archived) { $moved = Move-RunLog -Entry $Entry -FromRoot $archiveRoot -ToRoot $root }
                else { $moved = Move-RunLog -Entry $Entry -FromRoot $root -ToRoot $archiveRoot }
                if ($moved) { return }
            }
            5 {
                $confirm = Read-Line "  PERMANENTLY delete $($Entry.File.Name)? This cannot be undone. [y/N] > "
                if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                    Remove-Item -LiteralPath $Entry.File.FullName -Force
                    Remove-EmptyRunLogDirs -Dir $Entry.File.DirectoryName -StopAt $root
                    Write-Host "  Deleted." -ForegroundColor Green
                    return
                }
                Write-Host "  Kept." -ForegroundColor DarkGray
            }
            6 { Invoke-DataSync -Mode push -Area logs }
        }
    }
}

function Invoke-ViewRunLog {
    # Browses run_logs\ - the console transcripts a run saves when the operator
    # says yes to "Save a full log of this run" (see the -saveRunLog block in the
    # execute section below). Logs are filed under run_logs\<attack>\<topology>\
    # <location>\<scenario>\ (Get-RunLogDir) and listed grouped by that folder;
    # older logs saved flat in run_logs\ show up as "not filed". Filenames keep
    # the preset's base name (or topology-attack-scenario-location) + a timestamp.
    # No board/COM contact.
    $showArchived = $false
    while ($true) {
        $entries = @(Get-RunLogEntries -Archived:$showArchived |
            Sort-Object -Property @{ Expression = 'Category'; Ascending = $true },
                                  @{ Expression = { $_.File.LastWriteTime }; Descending = $true })
        $archivedCount = @(Get-RunLogEntries -Archived).Count

        if ($entries.Count -eq 0) {
            if ($showArchived) {
                Write-Host "`nNo archived run logs." -ForegroundColor Yellow
                $showArchived = $false
                continue
            }
            if ($archivedCount -eq 0) {
                Write-Host "`nNo saved run logs yet - they're saved under datasets\run_logs\<attack>\<topology>\<location>\ when" -ForegroundColor Yellow
                Write-Host "you answer yes to 'Save a full log of this run' before a capture." -ForegroundColor Yellow
                return
            }
        }

        $opts = @()
        $headers = @{}
        $lastCat = $null
        $newest = 0
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $e = $entries[$i]
            if ($e.Category -ne $lastCat) {
                $headers[$i] = if ($e.Category) { '-- ' + ($e.Category -replace '\\', ' > ') } else { '-- NOT FILED (saved before logs were sorted by attack/topology/location)' }
                $lastCat = $e.Category
            }
            if ($e.File.LastWriteTime -gt $entries[$newest].File.LastWriteTime) { $newest = $i }
            $opts += "{0,-55} {1}  ({2:N0} KB)" -f $e.File.Name, $e.File.LastWriteTime.ToString('MMM dd HH:mm'), ($e.File.Length / 1KB)
        }
        $toggleIdx = -1
        if ($showArchived) {
            $toggleIdx = $opts.Count; $opts += 'Back to the live (not archived) logs'
        } elseif ($archivedCount -gt 0) {
            $toggleIdx = $opts.Count; $opts += "Show archived logs ($archivedCount)"
        }
        $backIdx = $opts.Count
        $opts += 'Back to the main menu'
        $headers[$(if ($toggleIdx -ge 0) { $toggleIdx } else { $backIdx })] = ''

        $title = if ($showArchived) { 'ARCHIVED run logs (datasets\run_logs\_archive\) - view which?' } else { 'Saved run logs - view which? (newest is the default)' }
        $default = if ($entries.Count -gt 0) { $newest } else { $backIdx }
        $idx = Show-Menu -Title $title -Options $opts -DefaultIndex $default -GroupHeaders $headers
        if ($idx -eq $backIdx) { return }
        if ($idx -eq $toggleIdx) { $showArchived = -not $showArchived; continue }
        Invoke-RunLogActions -Entry $entries[$idx] -Archived:$showArchived
    }
}

function Read-PresetFile {
    # Get-Content -Raw tolerates the UTF-8 BOM that Set-Content -Encoding UTF8
    # leaves on PS 5.1 - some presets on disk have one, some don't.
    param([string]$Path)
    try { return (Get-Content -Raw -Path $Path | ConvertFrom-Json) }
    catch { return $null }
}

function Get-PresetExpectedChildren {
    # The preset's "expectedChildren": how many CHILDREN (every non-root board, on
    # ALL laptops) the root waits for before Phase 0 - the roster gate, run.ps1
    # -ExpectedChildren. 0 = not set (presets saved before oct. 4, 2026, or
    # cleared): the run asks the operator, as it always did.
    param($Cfg)
    if ($Cfg -and $Cfg.PSObject.Properties['expectedChildren']) {
        $n = 0
        if ([int]::TryParse([string]$Cfg.expectedChildren, [ref]$n) -and $n -gt 0) { return $n }
    }
    return 0
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
    # $ExpectedChildren follows the same rule as $Owner: omitted = keep what the
    # file already has, so the many re-saves that know nothing about it (MAC
    # refresh, port fix, ...) can never wipe it. 0 = not set (left out of the file).
    param([string]$Path, [string]$Attack, [string]$Topology, [string]$Location,
          [int]$RepeatNum, $Roster, [string]$Scenario = 'stationary', [string]$Owner,
          [int]$ExpectedChildren = 0)
    $existing = $null
    if (-not $PSBoundParameters.ContainsKey('Owner') -or -not $PSBoundParameters.ContainsKey('ExpectedChildren')) {
        $existing = Read-PresetFile -Path $Path
    }
    if (-not $PSBoundParameters.ContainsKey('Owner')) {
        $Owner = Get-PresetOwnerFromPath -FullName $Path
        if (-not $Owner -and $existing -and $existing.PSObject.Properties['owner']) { $Owner = [string]$existing.owner }
    }
    if (-not $PSBoundParameters.ContainsKey('ExpectedChildren')) {
        $ExpectedChildren = Get-PresetExpectedChildren $existing
    }
    $fields = [ordered]@{
        attack   = $Attack
        topology = $Topology
        location = $Location
        scenario = $Scenario
        owner    = $Owner
        repeat   = $RepeatNum
    }
    if ($ExpectedChildren -gt 0) { $fields.expectedChildren = $ExpectedChildren }
    $fields.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $fields.boards  = @($Roster | ForEach-Object {
        [pscustomobject]@{
            Label = $_.Label; Port = $_.Port; Role = $_.Role
            Kind  = $_.Kind;  Display = $_.Display; Mac = [string]$_.Mac
            ScenarioTarget = [bool]$_.ScenarioTarget
        }
    })
    [pscustomobject]$fields | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
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

function Show-ScenarioTargetMenu {
    # Every "which node is the <scenario> TARGET?" prompt goes through here, so
    # each board shows whether its port is plugged in RIGHT NOW, and the menu
    # can re-find boards by MAC before you commit. A burst/powercycle/mobility
    # target that isn't connected can't be flashed with the target build -
    # before oct. 1, 2026 'NOT PRESENT' showed only in the preset summary, never
    # at this prompt, so you could pick an unplugged board without noticing.
    # Returns the index into ($Eligible + $ExtraOptions), or -1 for 'b' (only
    # with -AllowBack). Port moves found by Detect are applied to $Roster's
    # board objects in place (the same objects $Eligible holds).
    param(
        [string]$Title,
        [string]$Scenario,
        [object[]]$Eligible,
        [string[]]$ExtraOptions = @(),
        $Roster,
        [int]$DefaultIndex = -1,
        [switch]$AllowBack
    )
    while ($true) {
        $live = @(Get-PortList | Select-Object -ExpandProperty Port)
        $labels = @($Eligible | ForEach-Object {
            $portText = if (-not $_.Port) { 'other laptop' }
                        elseif ($live -contains $_.Port) { "$($_.Port) plugged in" }
                        else { "$($_.Port) NOT PRESENT" }
            "{0}  ({1})  {2}  -  {3}" -f $_.Label, $portText, (Format-PickerMacTag $_), $_.Display
        })
        $labels += $ExtraOptions
        $detectIdx = $labels.Count
        $labels += 'Detect ports - plugged a board in or moved a cable? Find each board by its MAC and redraw this list'

        $idx = if ($AllowBack) { Show-Menu -Title $Title -Options $labels -DefaultIndex $DefaultIndex -AllowBack }
               else            { Show-Menu -Title $Title -Options $labels -DefaultIndex $DefaultIndex }

        if ($idx -eq $detectIdx) {
            if ($DryRun -or $SkipMacCheck) {
                Write-Host ("  Not reading boards ({0}) - can't detect ports. List refreshed from what Windows sees." -f $(if ($DryRun) { 'dry run' } else { '-SkipMacCheck' })) -ForegroundColor Yellow
                continue
            }
            $sync = Sync-RosterPortsByMac -Roster $Roster -Ports @(Get-PortList)
            if ($sync.Unresolved.Count -gt 0) {
                Write-Host ("  Still not found: {0} - plug it in and pick Detect again." -f (($sync.Unresolved | ForEach-Object { $_.Label }) -join ', ')) -ForegroundColor Yellow
            }
            continue
        }
        if ($idx -ge 0 -and $idx -lt $Eligible.Count) {
            $b = $Eligible[$idx]
            if ($b.Port -and $live -notcontains $b.Port) {
                Write-Host ""
                Write-Host ("  {0} is recorded on {1}, which is NOT plugged in right now." -f $b.Label, $b.Port) -ForegroundColor Yellow
                Write-Host ("  The {0} target has to be connected to be flashed with the target build." -f $Scenario) -ForegroundColor Yellow
                Write-Host "  Plug it in and pick 'Detect ports' - its COM number may have changed." -ForegroundColor Yellow
                $ans = Read-Line "  Use it anyway (you'll plug it in before flashing)? [y/N] > "
                if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
            }
        }
        return $idx
    }
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
    Write-Host "  'import_sdcard.py --repeat N' - see docs/operations/2026-09-14_SD-CARD.md." -ForegroundColor DarkGray
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

function Edit-PresetInteractive {
    # "Edit it" from the picker's "Use this preset?" menu: change the experiment
    # cell (attack / topology / location / scenario / repeat) or the roster
    # itself (a node's fields, add a node, remove a node) and write the result
    # back into the SAME file. Before this, changing a saved preset meant either
    # abandoning it and answering every menu from scratch, or loading it and
    # fixing it in the pre-flash "Adjust the plan?" step - which only ever
    # affected THAT run unless the separate write-back prompt at the very end
    # was answered.
    #
    # Edits a CLONE and validates before writing. The preset LOAD path below
    # throws on two roots and on a target-needing scenario with nothing marked
    # as its target, and the run itself depends on "exactly one attacker" /
    # "exactly one A and one B" - so a half-finished edit must never reach the
    # file. A preset that saves but can no longer be loaded is worse than no
    # edit at all. Validation runs at SAVE time, not per field, so an edit can
    # pass through a temporarily broken state (swap the attacker, then fix the
    # burst target) without being blocked halfway.
    #
    # Touches no board: every hardware read stays behind the picker's own
    # entries (Verify MACs / Auto-detect ports / Fix mesh_config.h), same rule
    # as the rest of the wizard. A port change deliberately leaves the recorded
    # MAC alone - the MAC is WHICH board it is, the port is only where it is
    # plugged in today.
    #
    # Returns Saved (did the file change) and Path (the file, which the rename
    # step may have moved - the caller re-resolves its $file from it).
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)]$Roster,
        [object[]]$Ports = @()
    )

    $attack = [string]$Cfg.attack
    if (-not $attack) { $attack = 'none' }
    $topology = [string]$Cfg.topology
    $location = [string]$Cfg.location
    # Same "missing or 'none' means stationary" rule the rest of the picker uses.
    $scenario = ConvertTo-Scenario $(if ($Cfg.PSObject.Properties['scenario']) { [string]$Cfg.scenario })
    $repeat   = [int]$Cfg.repeat
    if ($repeat -lt 1) { $repeat = 1 }
    # How many children the root waits for (all laptops). 0 = not set.
    $expected = Get-PresetExpectedChildren $Cfg

    # Same field set ConvertTo-Roster loads and Save-Preset writes - a CLONE, so
    # "discard" really discards: the caller's own roster is what the picker's
    # other actions and 'Yes - use it' keep using.
    $draft = @($Roster | ForEach-Object {
        [pscustomobject]@{
            Label          = [string]$_.Label
            Port           = [string]$_.Port
            Role           = [string]$_.Role
            Kind           = [string]$_.Kind
            Display        = [string]$_.Display
            Mac            = [string]$_.Mac
            ScenarioTarget = [bool]$_.ScenarioTarget
        }
    })

    # Re-enumerated here (instant, no board contact) instead of reusing the
    # picker's snapshot: a board plugged in since the picker opened should be
    # pickable without leaving this screen. Falls back to the caller's list if
    # nothing is enumerable at all.
    $portList = @(Get-PortList)
    if ($portList.Count -eq 0) { $portList = @($Ports | Where-Object { $_ }) }

    # Children first, root last - the ordering invariant every preset reader
    # downstream assumes, and which a role change or an added node breaks.
    $reorder = { param($R) @(@($R | Where-Object { $_.Role -ne 'root' }) + @($R | Where-Object { $_.Role -eq 'root' })) }

    # Display carries a ' + <SCENARIO> TARGET' suffix on the marked node, and the
    # seat rewrites (Set-AttackSubRoles, an attack change) overwrite Display
    # wholesale - re-stamped every pass so the suffix can neither be lost nor
    # left naming the previous scenario. Skipped when Display already SAYS
    # "TARGET" on its own (the $pickTarget remote escape's own
    # "$scenario TARGET (other laptop)" wording) - otherwise this doubles up
    # into "burst TARGET (other laptop) + BURST TARGET".
    $restamp = {
        foreach ($b in $draft) {
            $b.Display = ($b.Display -replace ' \+ .* TARGET$', '')
            if ($b.ScenarioTarget -and $b.Display -notmatch 'TARGET') { $b.Display += " + $($scenario.ToUpper()) TARGET" }
        }
    }

    $pickTarget = {
        # Exactly one node carries burst / mobility / powercycle - but a preset
        # only ever describes ONE member's boards (see Kyle's own blackhole
        # presets, which never carry an attacker board at all because Kyle's
        # attacker is a DIFFERENT member's board), so "on another laptop" must
        # stay reachable even when nothing local qualifies - same escape the
        # pre-flash "Adjust the plan" step's own scenario menu offers, here
        # reached from Edit-PresetInteractive's own local $draft instead.
        # Returns the (possibly appended) roster - invoked as
        # `$draft = & $pickTarget`, never bare `& $pickTarget`, since the
        # remote branch below has to ADD a board, and a scriptblock run via
        # `&` gets its own child scope: `$draft += ...` in there would rebind
        # only that scope's copy, not this function's.
        $eligible = @($draft | Where-Object { $_.Role -ne 'root' -and ($scenario -ne 'burst' -or (Test-BurstEligible $_)) })
        $escapeIdx = $eligible.Count
        $escapeText = "None of these - the $($scenario.ToUpper()) TARGET is on ANOTHER laptop"
        if ($eligible.Count -eq 0) {
            Write-Host ("   No node here can carry {0} - marking the target as on another laptop." -f $scenario) -ForegroundColor Yellow
            $tIdx = $escapeIdx
        }
        else {
            $tIdx = Show-ScenarioTargetMenu -Title ("Which node is the {0} TARGET? (exactly one)" -f $scenario) `
                -Scenario $scenario -Eligible $eligible -ExtraOptions @($escapeText) -Roster $draft -DefaultIndex 0
        }
        if ($tIdx -lt 0) { return $draft }
        foreach ($b in $draft) { $b.ScenarioTarget = $false }
        if ($tIdx -eq $escapeIdx) {
            $remoteLabel = Get-FreeNodeLabel -Taken @($draft | ForEach-Object { $_.Label })
            $withRemote = @($draft) + [pscustomobject]@{
                Label = $remoteLabel; Port = ''; Role = 'child'; Kind = 'victim'
                Display = "$scenario TARGET (other laptop)"; ScenarioTarget = $true
                Mac = ''
            }
            Write-Host ("   Remote {0} target recorded as '{1}' - tell that laptop's operator to mark their own matching board as the target." -f $scenario, $remoteLabel) -ForegroundColor DarkGray
            return $withRemote
        }
        $eligible[$tIdx].ScenarioTarget = $true
        $eligible[$tIdx].Display += " + $($scenario.ToUpper()) TARGET"
        return $draft
    }

    # ---- Blackhole attacker seat, as its own menu row (oct. 7, 2026) ----
    # Before this the seat was only reachable as a field inside "Edit one node",
    # and a star preset kept naming the old attacker while the run built another
    # board as it (dataset-verification.md #8). In STAR + blackhole the choice is
    # structural, not a label: the attacker is the HUB and every victim joins ONLY
    # its MAC (D-16, mesh_setup.c STAR_HUB_BLACKHOLE; the run builds the preset's
    # attacker MAC into each victim, New-RunParams -AttackerMac), so the row and
    # the picker say so.
    $attackerOf = {
        param($R)
        @($R | Where-Object { $_.Role -ne 'root' -and $_.Kind -eq 'attacker' }) | Select-Object -First 1
    }
    $attackerText = {
        param($R)
        $a = & $attackerOf $R
        if (-not $a) { return 'not set here' }
        $where = if ($a.Port) { $a.Port } else { 'other laptop' }
        $mac = if ($a.Mac) { $a.Mac } else { 'MAC not recorded' }
        "{0} ({1}, {2})" -f $a.Label, $where, $mac
    }
    $setAttacker = {
        # Makes $Chosen the attacker and every other child a victim - the same
        # "exactly one attacker" rewrite Set-AttackSubRoles does. A port-less
        # attacker row (one recorded as "on another laptop") that loses the seat
        # is DROPPED rather than demoted: it only existed to carry the remote
        # attacker's MAC, so keeping it would invent a remote victim.
        param($R, $Chosen)
        $out = @()
        foreach ($b in @($R)) {
            if ($b.Role -eq 'root') { $out += $b; continue }
            if ($b -eq $Chosen) { $b.Kind = 'attacker'; $b.Display = 'blackhole ATTACKER'; $out += $b; continue }
            if (-not $b.Port -and $b.Kind -eq 'attacker') {
                Write-Host ("   Dropped {0} (the old other-laptop attacker entry)." -f $b.Label) -ForegroundColor DarkGray
                continue
            }
            $b.Kind = 'victim'; $b.Display = 'blackhole victim'; $out += $b
        }
        return $out
    }
    $pickAttacker = {
        # Returns the roster (the other-laptop branch adds a row) - invoke as
        # `$draft = & $pickAttacker`, same child-scope reason as $pickTarget.
        $peers = @($draft | Where-Object { $_.Role -ne 'root' })
        Write-Host ""
        if ($topology -eq 'star') {
            Write-Host "STAR + blackhole: the ATTACKER is the HUB." -ForegroundColor Cyan
            Write-Host "  root -> ATTACKER -> every victim. Each victim joins ONLY the attacker's MAC" -ForegroundColor Cyan
            Write-Host "  (the run builds it into their firmware), so the wrong board here = no victim joins." -ForegroundColor Yellow
        }
        else {
            Write-Host "The ATTACKER relays victim probes in baseline, then drops them in the attack phase." -ForegroundColor Cyan
            Write-Host "  It only drops what passes THROUGH it - place it between the victims and the root." -ForegroundColor DarkGray
        }
        Write-Host ("  Now: {0}" -f (& $attackerText $draft)) -ForegroundColor DarkGray
        $cur = & $attackerOf $draft
        $opts = @($peers | ForEach-Object {
            $where = if ($_.Port) { $_.Port } else { 'other laptop' }
            $now = if ($_ -eq $cur) { '   <- attacker now' } else { '' }
            "{0}  ({1})  {2}{3}" -f $_.Label, $where, (Format-PickerMacTag $_), $now
        })
        $remoteIdx = $opts.Count
        $opts += 'The attacker is on ANOTHER laptop (record its MAC here)'
        $def = 0
        for ($i = 0; $i -lt $peers.Count; $i++) { if ($peers[$i] -eq $cur) { $def = $i } }
        $title = if ($topology -eq 'star') { 'Which board is the ATTACKER (the star HUB)?' } else { 'Which board is the BLACKHOLE ATTACKER? (exactly one)' }
        $pick = Show-Menu -Title $title -Options $opts -DefaultIndex $def -AllowBack
        if ($pick -lt 0) { return $draft }

        $out = $draft
        if ($pick -lt $remoteIdx) {
            $out = @(& $setAttacker $draft $peers[$pick])
        }
        else {
            $mac = Read-RemoteAttackerMac -Who 'The attacker' -LocalMacs @($draft | Where-Object { $_.Port -and $_.Mac } | ForEach-Object { $_.Mac })
            if (-not $mac) {
                Write-Host "   No MAC given - attacker unchanged." -ForegroundColor Yellow
                return $draft
            }
            $same = @($peers | Where-Object { $_.Mac -and "$($_.Mac)".Trim().ToLower() -eq $mac }) | Select-Object -First 1
            if ($same) {
                Write-Host ("   {0} is {1} in this preset already - making it the attacker." -f $mac, $same.Label) -ForegroundColor DarkGray
                $out = @(& $setAttacker $draft $same)
            }
            else {
                $remote = [pscustomobject]@{
                    Label = (Get-FreeNodeLabel -Taken @($draft | ForEach-Object { $_.Label }))
                    Port = ''; Role = 'child'; Kind = 'attacker'
                    Display = 'blackhole ATTACKER (other laptop)'; Mac = $mac; ScenarioTarget = $false
                }
                $out = @(& $setAttacker (@($draft) + $remote) $remote)
            }
        }

        $a = & $attackerOf $out
        if ($a) {
            Write-Host ("   Attacker: {0}" -f (& $attackerText $out)) -ForegroundColor Green
            if ($topology -eq 'star') {
                $vict = @($out | Where-Object { $_.Role -ne 'root' -and $_.Kind -eq 'victim' } | ForEach-Object { $_.Label })
                $vText = if ($vict.Count -gt 0) { $vict -join ', ' } else { '(none here)' }
                Write-Host ("   Star layout: root -> {0} (HUB) -> {1}, plus any victims on other laptops." -f $a.Label, $vText) -ForegroundColor Cyan
                if (-not $a.Mac) {
                    Write-Host ("   {0} has no MAC recorded - 'Verify MACs now' on the next screen records it; the victims need it." -f $a.Label) -ForegroundColor Yellow
                }
            }
            $cfgMac = Get-ConfiguredAttackerMac
            if ($a.Mac -and $cfgMac -and $cfgMac -ne "$($a.Mac)".Trim().ToLower()) {
                Write-Host ("   Note: this laptop's mesh_config.h still says {0}. The run builds {1} into the victims anyway;" -f $cfgMac, $a.Mac) -ForegroundColor DarkGray
                Write-Host "   'Fix mesh_config.h attacker MAC now' on the next screen brings the file in line." -ForegroundColor DarkGray
            }
        }
        return $out
    }

    $problemsOf = {
        # $Bad blocks the save outright (the load path or the run itself would
        # break); $Warn is printed but never blocks. A preset only ever holds
        # ONE member's boards - Kyle's own saved blackhole presets never carry
        # an attacker board at all, because Kyle's attacker is a DIFFERENT
        # member's board - so "zero attacker/A/B/target here" is the ordinary
        # multi-laptop case, not a broken file. This mirrors the tolerance the
        # $Preset LOAD path already gives ROOT ("RootCount -gt 1" is the only
        # rejection; 0 is a laptop that doesn't hold the root) and the picker's
        # own "WARNING: blackhole preset with no attacker board" (Show-PresetDetails) -
        # a warning, never a throw. Only an invariant a SINGLE laptop's own
        # roster can actually break (two boards claiming the same seat, two
        # roots, two targets, a baseline run still carrying an attack seat, a
        # duplicate label) is blocking.
        $bad = @()
        $warn = @()
        $boards = @($draft)
        if ($boards.Count -eq 0) { $bad += 'no boards left - a preset needs at least one' }
        $roots = @($boards | Where-Object { $_.Role -eq 'root' })
        if ($roots.Count -gt 1) { $bad += ("{0} boards marked ROOT - a preset may hold at most one (0 is fine - a laptop that doesn't hold the root)" -f $roots.Count) }
        $kids = @($boards | Where-Object { $_.Role -ne 'root' })
        if ($attack -eq 'blackhole') {
            $att = @($kids | Where-Object { $_.Kind -eq 'attacker' })
            if ($att.Count -gt 1) { $bad += ("{0} boards marked ATTACKER - a blackhole run needs at most one" -f $att.Count) }
            elseif ($att.Count -eq 0) {
                $warn += $(if ($topology -eq 'star') {
                    'no ATTACKER recorded - in STAR the attacker is the hub every victim joins, so the run will ask for its MAC; set it with ''Attacker'' (a board here, or one on another laptop)'
                } else {
                    'no ATTACKER board here - fine if another member''s laptop supplies it (their preset holds it, not this one); otherwise set it with ''Attacker'''
                })
            }
            elseif ($topology -eq 'star' -and -not $att[0].Mac) {
                $warn += ("the attacker {0} has no MAC recorded - in STAR every victim joins ONLY that MAC; 'Verify MACs now' on the next screen records it" -f $att[0].Label)
            }
            if (@($kids | Where-Object { $_.Kind -eq 'victim' }).Count -lt 1) { $warn += 'no victim child here - fine if this laptop only holds the attacker/root, otherwise add one' }
        }
        elseif ($attack -eq 'wormhole') {
            foreach ($seat in @('A', 'B')) {
                $n = @($kids | Where-Object { $_.Kind -eq $seat }).Count
                if ($n -gt 1) { $bad += ("{0} boards marked Node {1} - wormhole needs at most one" -f $n, $seat) }
                elseif ($n -eq 0) { $warn += ("no Node {0} here - fine if another member's laptop supplies it" -f $seat) }
            }
        }
        else {
            $left = @($kids | Where-Object { $_.Kind -in @('attacker', 'A', 'B') })
            if ($left.Count -gt 0) { $bad += ("a baseline run still carries attack roles: {0}" -f (($left | ForEach-Object { $_.Label }) -join ', ')) }
        }
        if (Test-ScenarioNeedsTarget $scenario) {
            $tg = @($boards | Where-Object { $_.ScenarioTarget })
            if ($tg.Count -gt 1) { $bad += ("{0} needs exactly one node marked as its TARGET (found {1})" -f $scenario, $tg.Count) }
            elseif ($tg.Count -eq 0) { $warn += ("no {0} TARGET marked here - fine if another laptop's board carries it (use 'Scenario' to re-pick and mark it remote), otherwise this run won't do anything" -f $scenario) }
            elseif ($scenario -eq 'burst' -and -not (Test-BurstEligible $tg[0])) {
                $bad += ("{0} cannot carry burst - only a plain / blackhole-victim / wormhole-control child builds the burst firmware" -f $tg[0].Label)
            }
        }
        # Duplicate PORTS are legal on purpose (swap mode: boards take turns on
        # one socket), duplicate LABELS are not - the label is what names a board
        # in every roster, filename and hand-off summary.
        foreach ($g in @($boards | Group-Object Label | Where-Object { $_.Count -gt 1 })) {
            $bad += ("two boards share the label '{0}'" -f $g.Name)
        }
        # The root would start Phase 0 before boards this preset itself lists.
        if ($expected -gt 0 -and $expected -lt $kids.Count) {
            $bad += ("expected children is {0}, but this preset already lists {1} children - raise it (or 0 = ask each run)" -f $expected, $kids.Count)
        }
        return [pscustomobject]@{ Bad = $bad; Warn = $warn }
    }

    $show = {
        $attackWord = if ($attack -eq 'none') { 'baseline' } else { $attack }
        $live = @($portList | Select-Object -ExpandProperty Port)
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ("  Editing  : {0}{1}" -f (Split-Path -Leaf $Path), $(if ($dirty) { '   << UNSAVED CHANGES' } else { '' })) -ForegroundColor Cyan
        Write-Host ("  Cell     : {0} / {1} / {2} / {3}   (repeat {4})" -f $attackWord, $topology, $location, $scenario, $repeat) -ForegroundColor DarkGray
        Write-Host ("  Expected : {0}" -f $(if ($expected -gt 0) { "root waits for $expected children (all laptops)" } else { 'not set - the run asks how many children' })) -ForegroundColor DarkGray
        if ($attack -eq 'blackhole') {
            $hub = if ($topology -eq 'star') { '   = STAR HUB: root -> attacker -> every victim' } else { '' }
            $col = if (-not (& $attackerOf $draft) -and $topology -eq 'star') { 'Yellow' } else { 'DarkGray' }
            Write-Host ("  Attacker : {0}{1}" -f (& $attackerText $draft), $hub) -ForegroundColor $col
        }
        Write-Host ""
        $n = 0
        foreach ($b in @(& $reorder $draft)) {
            $n++
            $where = if (-not $b.Port) { 'other laptop' } elseif ($live -notcontains $b.Port) { "$($b.Port) NOT PRESENT" } else { $b.Port }
            $role = Get-BoardColorRole $b
            $line = "   [{0}] {1,-8} {2,-30} {3,-16} {4}" -f $n, $b.Label, $b.Display, $where, $(if ($b.Mac) { $b.Mac } else { 'MAC not recorded' })
            Write-Host (Colorize-Role $line.TrimEnd() $role)
        }
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    }

    $dirty = $false
    while ($true) {
        $draft = @(& $reorder $draft)
        & $restamp
        & $show

        $attackWord = if ($attack -eq 'none') { 'baseline' } else { $attack }
        $opts = @(
            "Attack            $attackWord",
            "Topology          $topology",
            "Location          $location",
            "Scenario          $scenario",
            "Repeat            $repeat",
            $(if ($expected -gt 0) { "Expected children $expected   (root waits for all of them, every laptop)" } else { 'Expected children not set   (the run asks each time)' }),
            # Always present (fixed indices below); its text follows the attack.
            $(switch ($attack) {
                'blackhole' {
                    if ($topology -eq 'star') { "Attacker          $(& $attackerText $draft)   = STAR HUB every victim joins" }
                    else                      { "Attacker          $(& $attackerText $draft)" }
                }
                'wormhole' {
                    $na = @($draft | Where-Object { $_.Kind -eq 'A' } | ForEach-Object { $_.Label })
                    $nb = @($draft | Where-Object { $_.Kind -eq 'B' } | ForEach-Object { $_.Label })
                    "Wormhole nodes    A = $(if ($na) { $na -join ',' } else { 'not set' }), B = $(if ($nb) { $nb -join ',' } else { 'not set' })"
                }
                default { 'Attack roles      none (baseline has no attacker)' }
            }),
            'Edit one node      (label / port / which is ROOT / attack role / scenario target)',
            'Replace a node with a different board (new port, forgets the old MAC, keeps its seat)',
            'Add a node',
            'Remove a node',
            $(if ($dirty) { 'SAVE these changes into the preset file' } else { 'Save (nothing changed yet)' }),
            $(if ($dirty) { 'Discard these changes and go back' } else { 'Back (nothing changed)' })
        )
        $idx = Show-Menu -Title 'Edit this preset:' -Options $opts -DefaultIndex $(if ($dirty) { 11 } else { 12 })

        if ($idx -eq 0) {
            $aIdx = Show-Menu -Title 'Attack type:' -Options @(
                'baseline  (no attack - the control run)',
                'blackhole (attacker relays, then drops victim probes)',
                'wormhole  (A<->B tunnel; needs the physical cable)'
            ) -DefaultIndex ([array]::IndexOf($ATTACKS, $attack)) -AllowBack
            if ($aIdx -ge 0 -and $ATTACKS[$aIdx] -ne $attack) {
                $attack = $ATTACKS[$aIdx]
                # Kind/Display ARE the attack (victim/attacker, A/B/control,
                # plain), so every child's seat is void the moment it changes.
                # Reset them all to the uninvolved seat first - no stale
                # 'attacker'/'A' may survive into the new attack - then pick the
                # new seat explicitly. Backing out of that pick leaves the seat
                # unfilled, which the save check below then refuses by name.
                foreach ($b in @($draft | Where-Object { $_.Role -ne 'root' })) {
                    if     ($attack -eq 'blackhole') { $b.Kind = 'victim';  $b.Display = 'blackhole victim' }
                    elseif ($attack -eq 'wormhole')  { $b.Kind = 'control'; $b.Display = 'control (plain firmware)' }
                    else                             { $b.Kind = 'plain';   $b.Display = 'plain child' }
                }
                if ($attack -eq 'blackhole') { $draft = @(& $pickAttacker) }
                elseif ($attack -eq 'wormhole') { Set-AttackSubRoles -Roster $draft -Attack $attack }
                if ($attack -eq 'blackhole') {
                    Write-Host "   Cross-check mesh_config.h BLACKHOLE_ATTACKER_MAC against the new attacker before flashing - the details screen shows both." -ForegroundColor Yellow
                }
                $dirty = $true
            }
        }
        elseif ($idx -eq 1) {
            $tIdx = Show-Menu -Title 'Topology:' -Options $TOPOLOGIES -DefaultIndex ([array]::IndexOf($TOPOLOGIES, $topology)) -AllowBack
            if ($tIdx -ge 0 -and $TOPOLOGIES[$tIdx] -ne $topology) {
                $topology = $TOPOLOGIES[$tIdx]
                $dirty = $true
                if ($topology -eq 'star' -and $attack -eq 'blackhole') {
                    Write-Host ("   STAR + blackhole: the attacker becomes the HUB every victim joins - now {0}." -f (& $attackerText $draft)) -ForegroundColor Cyan
                    Write-Host "   Check it with 'Attacker' below before saving." -ForegroundColor Cyan
                }
            }
        }
        elseif ($idx -eq 2) {
            $lIdx = Show-Menu -Title 'Location (where the run physically happens):' -Options $LOCATIONS -DefaultIndex ([array]::IndexOf($LOCATIONS, $location)) -AllowBack
            if ($lIdx -ge 0 -and $LOCATIONS[$lIdx] -ne $location) {
                $location = $LOCATIONS[$lIdx]
                $dirty = $true
                # The cards carry their own location.txt and the firmware reads
                # THAT, not this preset - changing one without the other files
                # the capture under the old room.
                Write-Host "   Each board's SD card still says the OLD location - use 'Write/update location.txt on all boards' SD cards' on the next screen, or the capture files itself under it." -ForegroundColor Yellow
            }
        }
        elseif ($idx -eq 3) {
            $sIdx = Show-Menu -Title 'Scenario (run-to-run variation the panel asked for):' -Options $SCENARIO_LABELS -DefaultIndex ([array]::IndexOf($SCENARIOS, $scenario)) -AllowBack
            if ($sIdx -ge 0 -and $SCENARIOS[$sIdx] -ne $scenario) {
                $scenario = $SCENARIOS[$sIdx]
                # A target was picked FOR the old scenario - clear it, then ask
                # again when the new one needs one, so no board keeps a
                # 'powercycle TARGET' mark under, say, burst.
                foreach ($b in $draft) { $b.ScenarioTarget = $false }
                if (Test-ScenarioNeedsTarget $scenario) { $draft = & $pickTarget }
                $dirty = $true
            }
        }
        elseif ($idx -eq 4) {
            $r = Read-RepeatNumber -Attack $attack -Topology $topology -DefaultRepeat $repeat -AllowBack
            if ($r -ge 1 -and $r -ne $repeat) { $repeat = $r; $dirty = $true }
        }
        elseif ($idx -eq 5) {
            # Roster gate total: EVERY non-root board of the run, this laptop's and
            # every other laptop's - the root's laptop is where it is used. The
            # floor is the children this preset itself lists.
            $kidsHere = @($draft | Where-Object { $_.Role -ne 'root' }).Count
            Write-Host ""
            Write-Host "How many CHILDREN does the root wait for before it starts the run?" -ForegroundColor Cyan
            Write-Host "  Count every non-root board in the run, on ALL laptops (victims, attacker, controls)." -ForegroundColor DarkGray
            Write-Host ("  This preset lists {0} of them. 0 = not set: the run asks each time." -f $kidsHere) -ForegroundColor DarkGray
            $cur = if ($expected -gt 0) { "$expected" } else { 'not set' }
            $tries = 0
            while ($true) {
                $tries++
                if ($tries -gt $script:MaxPromptTries) { break }
                $ans = Read-Line ("Expected children > [{0}] (Enter keeps it, 'b' back) " -f $cur)
                if (-not $ans -or (Test-BackAnswer $ans)) { break }
                $n = 0
                if ([int]::TryParse($ans.Trim(), [ref]$n) -and ($n -eq 0 -or $n -ge $kidsHere)) {
                    if ($n -ne $expected) { $expected = $n; $dirty = $true }
                    break
                }
                Write-Host ("  Type 0, or a whole number of at least {0}." -f $kidsHere) -ForegroundColor Yellow
            }
        }
        elseif ($idx -eq 6) {
            # Snapshot of every seat, so backing out (or re-picking the same
            # board) does not mark the preset dirty.
            $seats = { (@($draft) | ForEach-Object { "$($_.Label)|$($_.Kind)|$($_.Mac)" }) -join ';' }
            $before = & $seats
            if ($attack -eq 'blackhole') {
                if (@($draft | Where-Object { $_.Role -ne 'root' }).Count -eq 0) {
                    Write-Host "   No child boards in this preset - only 'on ANOTHER laptop' can be picked (or Add a node first)." -ForegroundColor Yellow
                }
                $draft = @(& $pickAttacker)
            }
            elseif ($attack -eq 'wormhole') {
                Set-AttackSubRoles -Roster $draft -Attack 'wormhole'
            }
            else {
                Write-Host "   Baseline has no attacker. Change 'Attack' first to set one." -ForegroundColor Yellow
            }
            if ((& $seats) -ne $before) { $dirty = $true }
        }
        elseif ($idx -eq 7) {
            # $rows holds the SAME objects as $draft (reorder returns references),
            # so editing a row edits the draft.
            $rows = @(& $reorder $draft)
            $pick = Show-Menu -Title 'Which node?' -Options @($rows | ForEach-Object {
                "{0}  ({1}, {2})" -f $_.Label, $(if ($_.Port) { $_.Port } else { 'other laptop' }), $_.Display
            }) -AllowBack
            if ($pick -ge 0) {
                # -HasRemoteAttackRole is deliberately NOT set: a preset holds the
                # WHOLE experiment, including boards on another laptop, so the
                # attacker/A/B seat is reassignable across all of them here.
                Edit-BoardInteractive -Board $rows[$pick] -Roster $draft -Attack $attack -Scenario $scenario -Ports $portList
                $dirty = $true
            }
        }
        elseif ($idx -eq 8) {
            # Swaps which PHYSICAL board fills an EXISTING seat - a dead/borrowed
            # board takes over an attacker, a scenario target, the root, whatever
            # this node already was - without re-answering the attack sub-role or
            # scenario-target questions the way Remove-then-Add would (those
            # reassign the seat among what's LEFT, which for a straight swap is
            # exactly the churn this avoids). Only Port and (optionally) Label
            # change; Role/Kind/Display/ScenarioTarget carry over untouched. The
            # old MAC is CLEARED, not kept - it identified the board that's
            # leaving, and leaving it in place would silently claim the NEW board
            # already matches a MAC it's never been read against.
            $rows = @(& $reorder $draft)
            $pick = Show-Menu -Title 'Replace which node with a different board?' -Options @($rows | ForEach-Object {
                "{0}  ({1}, {2})" -f $_.Label, $(if ($_.Port) { $_.Port } else { 'other laptop' }), $_.Display
            }) -AllowBack
            if ($pick -ge 0) {
                $board = $rows[$pick]
                $taken = @($draft | Where-Object { $_ -ne $board -and $_.Port } | ForEach-Object { $_.Port })
                $newPort = Select-Port -For $board.Label -Ports $portList -AllowBack -Taken $taken
                if ($newPort -and $newPort -ne $script:BackSignal) {
                    $oldPort = if ($board.Port) { $board.Port } else { 'another laptop' }
                    $oldSeat = $board.Display
                    $board.Port = $newPort
                    $board.Mac  = ''
                    $newLabel = Read-Line ("  New label for this seat > [{0}] (Enter to keep) " -f $board.Label)
                    if ($newLabel -and $newLabel -ne $board.Label) {
                        if (@($draft | Where-Object { $_ -ne $board } | ForEach-Object { $_.Label }) -contains $newLabel) {
                            Write-Host ("   '{0}' is already used by another board - keeping '{1}'." -f $newLabel, $board.Label) -ForegroundColor Yellow
                        }
                        else { $board.Label = $newLabel }
                    }
                    Write-Host ("   {0} on {1} now stands in for the {2} seat (was {3}) - MAC cleared; 'Verify MACs now' on the next screen reads it." -f $board.Label, $newPort, $oldSeat, $oldPort) -ForegroundColor Green
                    $dirty = $true
                }
            }
        }
        elseif ($idx -eq 9) {
            $before = @($draft).Count
            $draft = @(Add-BoardInteractive -Roster $draft -Attack $attack -Ports $portList)
            if (@($draft).Count -ne $before) { $dirty = $true }
        }
        elseif ($idx -eq 10) {
            $before = @($draft).Count
            $draft = @(Remove-BoardInteractive -Roster $draft -Attack $attack -Scenario $scenario)
            if (@($draft).Count -ne $before) { $dirty = $true }
        }
        elseif ($idx -eq 11) {
            $checked = & $problemsOf
            if ($checked.Bad.Count -gt 0) {
                Write-Host ""
                Write-Host "  NOT saved - this preset would fail to load, or would run wrong:" -ForegroundColor Red
                foreach ($p in $checked.Bad) { Write-Host ("    - {0}" -f $p) -ForegroundColor Red }
                Write-Host "  Fix the items above, or discard the changes." -ForegroundColor DarkGray
                continue
            }
            if ($checked.Warn.Count -gt 0) {
                Write-Host ""
                Write-Host "  Saving anyway - worth a second look:" -ForegroundColor Yellow
                foreach ($w in $checked.Warn) { Write-Host ("    - {0}" -f $w) -ForegroundColor Yellow }
            }

            # The filename spells the experiment cell
            # (attack-topology-location-scenario, Get-PresetCellFileName). The
            # picker reads the cell from the file CONTENTS, so its grouping stays
            # right either way - but every human reads the name, so a changed
            # cell (or an old-order name) is a file that lies about itself.
            $savePath = $Path
            $want = Get-PresetCellFileName -Attack $attack -Topology $topology -Location $location -Scenario $scenario
            if ($want -ne (Split-Path -Leaf $Path)) {
                Write-Host ""
                Write-Host ("  The filename no longer matches the cell: {0}" -f (Split-Path -Leaf $Path)) -ForegroundColor Yellow
                $ans = Read-Line ("  Rename it to {0}? [Y/n] > " -f $want)
                if ($ans -ne 'n' -and $ans -ne 'N') {
                    $dest = Join-Path (Split-Path -Parent $Path) $want
                    if (Test-Path -LiteralPath $dest) {
                        Write-Host ("  {0} already exists in that folder - keeping the current name." -f $want) -ForegroundColor Yellow
                    }
                    else {
                        try {
                            Move-Item -LiteralPath $Path -Destination $dest -ErrorAction Stop
                            $savePath = $dest
                            Write-Host ("  Renamed -> {0}" -f $want) -ForegroundColor Green
                        }
                        catch {
                            Write-Host ("  Could not rename ({0}) - saving under the current name." -f $_.Exception.Message) -ForegroundColor Yellow
                        }
                    }
                }
            }

            # -Owner omitted on purpose: Save-Preset then keeps the folder's (or
            # the file's own) owner, so an edit can never silently re-attribute
            # someone else's boards.
            Save-Preset -Path $savePath -Attack $attack -Topology $topology `
                -Location $location -RepeatNum $repeat -Roster (& $reorder $draft) -Scenario $scenario `
                -ExpectedChildren $expected
            Write-Host ("  Saved -> {0}" -f $savePath) -ForegroundColor Green
            $noMac = @($draft | Where-Object { $_.Port -and -not $_.Mac })
            if ($noMac.Count -gt 0) {
                Write-Host ("  No MAC recorded for {0} - 'Verify MACs now' on the next screen reads and stores them." -f (($noMac | ForEach-Object { $_.Label }) -join ', ')) -ForegroundColor DarkGray
            }
            return [pscustomobject]@{ Saved = $true; Path = $savePath }
        }
        elseif ($idx -eq 12) {
            if ($dirty) {
                $ans = Read-Line "`n  Discard the changes above? The file stays as it was. [y/N] > "
                if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
                Write-Host "  Discarded - the preset file is unchanged." -ForegroundColor DarkGray
            }
            return [pscustomobject]@{ Saved = $false; Path = $Path }
        }
    }
}

function Show-PresetDetails {
    # The point of the picker: everything the preset implies, before anything is
    # flashed. Ports are checked against what Windows currently enumerates, because
    # COM numbers are assigned per USB SOCKET - a preset saved last week can name a
    # port that is now a different board, or no board at all.
    param($Cfg, [string]$Path, [object[]]$Ports, $Roster)

    # Older presets predate the scenario field - treat a missing one (or 'none', its old name) as 'stationary'.
    $cfgScenario = ConvertTo-Scenario $(if ($Cfg.PSObject.Properties['scenario']) { [string]$Cfg.scenario })
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
        $role = Get-BoardColorRole $b
        if ($miss) { Write-Host $line -ForegroundColor Yellow } else { Write-Host (Colorize-Role $line $role) }
    }

    # Free cross-check (a file read, no board contact): does this preset's attacker
    # match the MAC the victim firmware is compiled to send its probes to? A preset
    # naming a different attacker produces a clean run with no attack signature.
    if ([string]$Cfg.attack -eq 'blackhole') {
        $att = $Roster | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
        # ⚠️ NEW FAILURE MODE SINCE C7 OPTION 1 (D-12) - PLACEMENT, not wiring.
        # The attacker used to intercept traffic because victims were compiled to
        # address its MAC, so where it physically sat was irrelevant. Now it only
        # ever sees traffic that actually TRANSITS it, so an attacker placed at
        # the far end of a chain (or as a leaf) intercepts nothing and the run
        # produces no attack signature - with every board looking perfectly
        # healthy. This cannot be checked from the roster (placement is physical),
        # so it is stated here, before flashing, where it can still be acted on.
        Write-Host ""
        if ([string]$Cfg.topology -eq 'star') {
            # STAR + BLACKHOLE (D-16): victims are firmware-pinned to the attacker's
            # AP, so here the MAC below is load-bearing again - a wrong one means
            # the victims never join and the root holds Phase 0.
            Write-Host "STAR + BLACKHOLE = ATTACKER IS THE HUB (D-16):" -ForegroundColor Cyan
            Write-Host "  Root -> attacker -> every victim. Put the attacker in the middle, the root ~1 m" -ForegroundColor Cyan
            Write-Host "  beside it, victims in a ring around the ATTACKER. Power: root, attacker, victims." -ForegroundColor Cyan
            Write-Host "  Victims ONLY join the MAC below - it MUST be this preset's attacker, or no" -ForegroundColor Yellow
            Write-Host "  victim joins at all (the mismatch warning below is NOT bookkeeping for star)." -ForegroundColor Yellow
            Write-Host "  Check after the run: tools\verify_topology.py ... --expect star" -ForegroundColor DarkGray
        }
        Write-Host "PLACEMENT MATTERS NOW (C7 Option 1):" -ForegroundColor Cyan
        Write-Host "  The attacker only drops traffic that PASSES THROUGH it. Put it BETWEEN the" -ForegroundColor Cyan
        Write-Host "  victims and the root - near the root (hop 1-2) is safest. An attacker at the" -ForegroundColor Cyan
        Write-Host "  far end of a chain, or as a leaf, intercepts nothing and the run will show NO" -ForegroundColor Cyan
        Write-Host "  attack even though every board looks healthy." -ForegroundColor Cyan
        Write-Host "  Check after the run: tools\verify_topology.py ... --structure" -ForegroundColor DarkGray

        $wantMac = Get-ConfiguredAttackerMac
        Write-Host ""
        if (-not $att) {
            Write-Host "  No attacker board on THIS laptop's preset. Fine on a multi-laptop run (the" -ForegroundColor Yellow
            Write-Host "  wizard asks for its MAC before flashing victims); otherwise there is no attack." -ForegroundColor Yellow
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
$script:presetExpectedChildren = 0   # set again when a preset loads (roster gate default)

$attack = ''; $topology = ''; $location = ''; $repeat = 1; $scenario = 'stationary'
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
        if ($modeIdx -eq 29) { Invoke-UartTunnelTest; continue }
        if ($modeIdx -eq 4) { Invoke-ImportSdCard; continue }
        if ($modeIdx -eq 5) { Invoke-VerifyRun; continue }
        if ($modeIdx -eq 6) { Invoke-IdentifyAllBoards; continue }
        if ($modeIdx -eq 7) { Invoke-RunAnalysisOnly; continue }
        if ($modeIdx -eq 10) { Invoke-TrimOnly; continue }
        if ($modeIdx -eq 14) { Invoke-ViewRunLog; continue }
        if ($modeIdx -eq 15) { Invoke-DeleteSdFolder; continue }
        if ($modeIdx -eq 20) { Invoke-ArchiveMenu; continue }
        if ($modeIdx -eq 18) { Invoke-CampaignChecklist; continue }
        if ($modeIdx -eq 19) { Invoke-ShowTopologyStructure; continue }
        if ($modeIdx -eq 21) { Invoke-MacSnifferTest; continue }
        if ($modeIdx -eq 22) { Invoke-CheckSnifferFile; continue }
        if ($modeIdx -eq 23) { Invoke-Esp32SnifferStandalone; continue }
        if ($modeIdx -eq 24) { Invoke-WiresharkViews; continue }
        if ($modeIdx -eq 25) { $newestPcap = Select-CaptureFile -Newest; if ($newestPcap) { Invoke-WiresharkViews -Path $newestPcap -Overview }; Read-Host "Press Enter to return to the menu" | Out-Null; continue }
        if ($modeIdx -eq 26) { Invoke-Esp32SnifferStandalone -Live; continue }
        if ($modeIdx -eq 27) { Invoke-MacRetryReport; continue }
        # Same flow as Data sync -> 'Delete data from THIS LAPTOP only', surfaced
        # on the main menu so junk files can go without hunting in File Explorer.
        if ($modeIdx -eq 28) {
            $a = Select-DataSyncArea -Verb 'Delete from this laptop'
            if ($a) { Invoke-DataSync -Mode 'delete-local' -Area $a }
            continue
        }
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
# Set by the preset branch's pre-flight so the shared check below does not
# ask twice; re-armed here so backing out to the picker re-checks.
$locationPreflightDone = $false
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
            # here and must stay one pick away. WITHIN each member the presets
            # are sorted by experiment cell: attack, then topology, then location,
            # then scenario (the wizard's own list order), then newest. $presetFiles
            # is re-ordered to match what is printed so index N of the menu is
            # index N of the array, the same invariant the flat list relied on.
            $myMember = Get-MyMember
            $cellOf = @{}
            foreach ($pf in $presetFiles) {
                $pc = Read-PresetFile -Path $pf.FullName
                if (-not $pc) { $cellOf[$pf.FullName] = $null; continue }
                $pa = [string]$pc.attack; if (-not $pa) { $pa = 'none' }
                $cellOf[$pf.FullName] = [pscustomobject]@{
                    Attack = $pa; Topology = [string]$pc.topology; Location = [string]$pc.location
                    Scenario = (ConvertTo-Scenario $(if ($pc.PSObject.Properties['scenario']) { [string]$pc.scenario }))
                }
            }
            # Position in the wizard's own option lists (baseline before blackhole,
            # home before G402 ...); anything not listed sorts after them.
            $rank = { param($list, $v) $i = [array]::IndexOf(@($list), $v); if ($i -lt 0) { 99 } else { $i } }
            $byCell = {
                param($items)
                @($items | Sort-Object `
                    @{ Expression = { if ($cellOf[$_.FullName]) { 0 } else { 1 } } }, `
                    @{ Expression = { $c = $cellOf[$_.FullName]; if ($c) { & $rank $ATTACKS $c.Attack } } }, `
                    @{ Expression = { $c = $cellOf[$_.FullName]; if ($c) { & $rank $TOPOLOGIES $c.Topology } } }, `
                    @{ Expression = { $c = $cellOf[$_.FullName]; if ($c) { & $rank $LOCATIONS $c.Location } } }, `
                    @{ Expression = { $c = $cellOf[$_.FullName]; if ($c) { & $rank $SCENARIOS $c.Scenario } } }, `
                    @{ Expression = { $_.LastWriteTime }; Descending = $true })
            }
            $groups = New-Object System.Collections.Specialized.OrderedDictionary
            if ($myMember) {
                $lbl = "-- YOURS ({0})" -f $myMember
                $groups[$lbl] = & $byCell @($presetFiles | Where-Object { $_.Owner -eq $myMember })
            }
            foreach ($m in (Get-PresetMemberNames)) {
                if ($myMember -and $m -eq $myMember) { continue }
                $mine = @($presetFiles | Where-Object { $_.Owner -eq $m })
                if ($mine.Count -gt 0) { $groups["-- $m"] = & $byCell $mine }
            }
            $loose = @($presetFiles | Where-Object { -not $_.Owner })
            if ($loose.Count -gt 0) { $groups['-- UNFILED (not in a member folder yet)'] = & $byCell $loose }

            $presetFiles = @()
            $headers = @{}
            foreach ($key in $groups.Keys) {
                $items = @($groups[$key])
                if ($items.Count -eq 0) { continue }
                # Two levels: the member heading, then an indented sub-heading per
                # cell (attack / topology / location / scenario) - the member heading
                # and its first cell share one header entry, later cells get their own.
                $lastCell = $null
                $firstOfMember = $true
                foreach ($pf in $items) {
                    $c = $cellOf[$pf.FullName]
                    $cellKey = if ($c) { '{0}|{1}|{2}|{3}' -f $c.Attack, $c.Topology, $c.Location, $c.Scenario } else { 'unreadable' }
                    if ($firstOfMember -or $cellKey -ne $lastCell) {
                        $sub = if ($c) {
                            '  ' + (Format-PresetCell -Attack $c.Attack -Topology $c.Topology -Location $c.Location -Scenario $c.Scenario)
                        } else { '  -- UNREADABLE' }
                        $headers[$presetFiles.Count] = if ($firstOfMember) { $key + "`n  " + $sub } else { $sub }   # Show-Menu indents only a header's first line
                        $lastCell = $cellKey
                        $firstOfMember = $false
                    }
                    $presetFiles += $pf
                }
            }

            # Show-Menu takes numbers only - there is no letter escape - so the
            # opt-out has to be the last numbered entry.
            # Each preset lists its boards (role, MAC, member nickname) under the
            # summary line, root last like the run order - "3 board(s)" alone
            # didn't say WHICH boards, so telling two G402 presets apart meant
            # opening each one.
            $nickByMac = Get-MemberNicknameMap
            $opts = @($presetFiles | ForEach-Object {
                $c = Read-PresetFile -Path $_.FullName
                if (-not $c) { "{0,-26} (unreadable)" -f $_.Name }
                else {
                    # attack / topology / location / scenario are the sub-heading above.
                    # Date + time the preset was saved: the file's own savedAt
                    # (Save-Preset), since a git pull resets the file's modified
                    # time to the pull - the file time is only the fallback for
                    # presets saved before savedAt existed.
                    $when = $_.LastWriteTime
                    if ($c.PSObject.Properties['savedAt'] -and $c.savedAt) {
                        $parsed = [datetime]::MinValue
                        if ([datetime]::TryParseExact([string]$c.savedAt, 'yyyy-MM-dd HH:mm',
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::None, [ref]$parsed)) { $when = $parsed }
                    }
                    $head = "{0,-44} {1} board(s), {2}" -f
                        $_.Name, @($c.boards).Count, $when.ToString('MMM dd hh:mm tt', [Globalization.CultureInfo]::InvariantCulture)
                    $boardLines = @((ConvertTo-Roster -Cfg $c).Roster | ForEach-Object {
                        $role = Get-BoardColorRole $_
                        $roleText = switch ($_.Kind) { 'A' { 'Node A' } 'B' { 'Node B' } default { $role } }
                        $mac  = if ($_.Mac) { $_.Mac } else { 'MAC not recorded' }
                        $nick = '-'
                        if ($_.Mac -and $nickByMac.Count -gt 0) {
                            $short = Format-ShortMac $_.Mac
                            if ($nickByMac.ContainsKey($short)) { $nick = $nickByMac[$short] }
                        }
                        "      {0} {1,-17}  {2}" -f (Colorize-Role $roleText.PadRight(8) $role), $mac, $nick
                    })
                    (@($head) + $boardLines) -join "`n"
                }
            })
            # A blank line after each preset's board list so the blocks don't run
            # together - except where a member heading follows, since Show-Menu
            # already prints a blank line above every heading.
            for ($oi = 0; $oi -lt $opts.Count; $oi++) {
                if (-not $headers.ContainsKey($oi + 1)) { $opts[$oi] += "`n" }
            }
            $opts += 'No preset - answer the menus instead'

            $idx = Show-Menu -Title 'Load a saved preset?' -Options $opts -DefaultIndex 0 -GroupHeaders $headers -AllowDelete
            if ($idx -eq -2) {
                # d<N> / d3,5 / d3-5 on the list: delete on the spot, no need to open
                # the preset first. Numbers refer to the list as shown, so the whole
                # set is resolved to files BEFORE anything is removed.
                $delFiles = @()
                $badNums = @()
                foreach ($di in $script:MenuDeleteIndexes) {
                    if ($di -lt 0 -or $di -ge $presetFiles.Count) { $badNums += ($di + 1) }
                    else { $delFiles += $presetFiles[$di] }
                }
                if ($badNums.Count -gt 0) {
                    Write-Host ("  Not a preset number: {0} (pick from 1 to {1}) - nothing deleted." -f ($badNums -join ', '), $presetFiles.Count) -ForegroundColor Yellow
                    continue
                }
                Write-Host ""
                foreach ($df in $delFiles) {
                    Write-Host ("  - {0} ({1})" -f $df.Name, $(if ($df.Owner) { $df.Owner } else { 'unfiled' })) -ForegroundColor Yellow
                }
                $delAns = Read-Line ("Delete {0} permanently? [y/N] > " -f $(if ($delFiles.Count -eq 1) { 'this preset' } else { "these $($delFiles.Count) presets" }))
                if ($delAns -eq 'y' -or $delAns -eq 'Y') {
                    foreach ($df in $delFiles) {
                        try {
                            Remove-Item -LiteralPath $df.FullName -Force -ErrorAction Stop
                            Write-Host ("  Deleted -> {0}" -f $df.Name) -ForegroundColor Green
                        }
                        catch {
                            Write-Host ("  Could not delete {0}: {1}" -f $df.Name, $_.Exception.Message) -ForegroundColor Red
                        }
                    }
                    $presetFiles = @(Get-PresetFiles)
                    if ($presetFiles.Count -eq 0) {
                        Write-Host "  No presets left - continuing with the menus." -ForegroundColor DarkGray
                        break
                    }
                }
                else {
                    Write-Host "  Not deleted." -ForegroundColor DarkGray
                }
                continue
            }
            if ($idx -eq $presetFiles.Count) { break }

            $file = $presetFiles[$idx]
            $cfg  = Read-PresetFile -Path $file.FullName
            if (-not $cfg) {
                Write-Host ("  Could not parse {0} - pick another." -f $file.Name) -ForegroundColor Yellow
                continue
            }
            $preview = (ConvertTo-Roster -Cfg $cfg).Roster
            # Older presets predate the scenario field - treat a missing one (or 'none', its old name) as 'stationary'.
            $cfgScenario = ConvertTo-Scenario $(if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })

            $deciding = $true
            while ($deciding) {
                Show-PresetDetails -Cfg $cfg -Path $file.FullName -Ports $pickPorts -Roster $preview

                switch (Show-Menu -Title 'Use this preset?' -Options @(
                    'Yes - use it',
                    'Edit this preset (attack/topology/location/scenario/repeat, or its boards) and save it',
                    'Verify MACs now (reads each board, ~2s each, briefly resets them)',
                    'Auto-detect ports (finds each board by its recorded MAC; plug in missing ones and rescan)',
                    'Write/update location.txt on all boards'' SD cards (over USB, needs each board already running)',
                    'Fix mesh_config.h attacker MAC now (reads the attacker board, updates the build)',
                    'Copy this preset (same boards/cell as a starting point - then edit the copy, original untouched)',
                    'Show raw preset JSON (just to double-check the file itself, no board access)',
                    'File this preset under a member (move it into presets\<member>\)',
                    'Delete this preset (e.g. an accidental duplicate)',
                    'Pick a different preset',
                    'No preset - answer the menus instead'
                # Purely visual grouping - indices/numbering are unchanged, so
                # nothing below this call needs to know these headers exist.
                ) -DefaultIndex 0 -GroupHeaders @{
                    2 = '-- Board checks (reads/writes hardware over USB)'
                    6 = '-- Preset file management'
                    10 = '-- Not this preset'
                }) {

                    0 {
                        # The location pre-flight is NOT run here any more: $preview still
                        # holds the preset's SAVED ports, so on renumbered COM ports it read
                        # the wrong board, and a port-less board was skipped while it still
                        # printed "All boards already report ...". It runs once, for both
                        # paths, after the port-drift fix below (still before any flash).
                        $Preset = $file.FullName; $presetFromPicker = $true; $deciding = $false; $picking = $false
                    }

                    1 {
                        # Change the PRESET itself - the cell or the roster - and
                        # write it back, instead of the older "load it, then fix it
                        # per-run in Adjust the plan" route that left the file
                        # untouched unless the write-back prompt at the end was
                        # answered. See Edit-PresetInteractive.
                        $edited = Edit-PresetInteractive -Path $file.FullName -Cfg $cfg -Roster $preview -Ports $pickPorts
                        if ($edited.Saved) {
                            # A save may have RENAMED the file to match its new
                            # cell, so $file is re-resolved from the path the edit
                            # reports, and $cfg/$preview/$cfgScenario are re-read
                            # from disk - the details screen above and every other
                            # action here (Verify MACs, Fix mesh_config.h, 'Yes -
                            # use it') all work off those three.
                            $presetFiles = @(Get-PresetFiles)
                            $file = @($presetFiles | Where-Object { $_.FullName -eq $edited.Path }) | Select-Object -First 1
                            $cfg  = if ($file) { Read-PresetFile -Path $file.FullName } else { $null }
                            if (-not $cfg) {
                                Write-Host "  Saved, but that file can't be read back from presets\ - returning to the list." -ForegroundColor Yellow
                                $deciding = $false
                            }
                            else {
                                $preview     = (ConvertTo-Roster -Cfg $cfg).Roster
                                $cfgScenario = ConvertTo-Scenario $(if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })
                            }
                        }
                    }

                    2 {
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
                                    -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -ExpectedChildren (Get-PresetExpectedChildren $cfg)
                                $cfg = Read-PresetFile -Path $file.FullName
                                Write-Host ("  Updated -> {0}" -f $file.Name) -ForegroundColor Green
                            }
                        }
                    }

                    3 {
                        # Dedicated entry for what Verify only offers after it spots drift:
                        # find every board by MAC across whatever is plugged in now. Rescans
                        # so a board plugged in mid-way is picked up; MACs already read this
                        # session are cached, so each rescan only resets the new ports.
                        Write-Host ""
                        if ($DryRun -or $SkipMacCheck) {
                            Write-Host "  Not reading boards ($(if ($DryRun) { 'dry run' } else { '-SkipMacCheck' })) - can't auto-detect." -ForegroundColor Yellow
                            continue
                        }
                        $adChanged = $false
                        while ($true) {
                            $pickPorts = Get-PortList
                            $adSync = Sync-RosterPortsByMac -Roster $preview -Ports $pickPorts
                            if ($adSync.Applied) { $adChanged = $true }
                            $liveNow = @($pickPorts | Select-Object -ExpandProperty Port)
                            $absent = @($preview | Where-Object { $_.Mac -and $_.Port -and
                                (($liveNow -notcontains $_.Port) -or ($adSync.Unresolved -contains $_)) })
                            if ($absent.Count -eq 0) { break }
                            Write-Host ""
                            Write-Host ("  Not found yet: {0}" -f (($absent | ForEach-Object { $_.Label }) -join ', ')) -ForegroundColor Yellow
                            $again = Read-Line "  Plug them in, then press Enter to rescan (or type s to stop) > "
                            if ($again -eq 's' -or $again -eq 'S') { break }
                        }
                        if ($adChanged) {
                            $ans = Read-Line "`n  Write these ports back into the preset? [y/N] > "
                            if ($ans -eq 'y' -or $ans -eq 'Y') {
                                Save-Preset -Path $file.FullName -Attack ([string]$cfg.attack) `
                                    -Topology ([string]$cfg.topology) -Location ([string]$cfg.location) `
                                    -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -ExpectedChildren (Get-PresetExpectedChildren $cfg)
                                $cfg = Read-PresetFile -Path $file.FullName
                                Write-Host ("  Updated -> {0}" -f $file.Name) -ForegroundColor Green
                            }
                        }
                    }

                    4 {
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

                    5 {
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
                                                        -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -ExpectedChildren (Get-PresetExpectedChildren $cfg)
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

                    6 {
                        # Duplicate this preset as the starting point for a new one -
                        # the same boards for another scenario/location, or another
                        # member's preset copied into your own folder - instead of
                        # answering every menu from scratch. Written with Save-Preset,
                        # not Copy-Item, so the owner recorded INSIDE the file matches
                        # the folder it lands in. The edit screen then opens on the
                        # COPY; the original file is never touched.
                        $copyOwner = Select-PresetOwner -Roster $preview `
                            -Title ("Copy '{0}' into which member's folder?" -f $file.Name)
                        $copyDir = if ($copyOwner) { Join-Path (Get-PresetRoot) $copyOwner } else { Get-PresetRoot }
                        if (-not (Test-Path $copyDir)) { New-Item -ItemType Directory -Force -Path $copyDir | Out-Null }
                        # Same name when the target folder doesn't have it yet (copying
                        # another member's preset into yours); otherwise -copy, -copy2 ...
                        # The edit step's save offers the proper cell name once the cell
                        # has been changed.
                        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
                        $copyPath = [IO.Path]::GetFullPath((Join-Path $copyDir $file.Name))
                        $n = 1
                        while (Test-Path -LiteralPath $copyPath) {
                            $sfx = if ($n -eq 1) { '-copy' } else { "-copy$n" }
                            $copyPath = [IO.Path]::GetFullPath((Join-Path $copyDir ("{0}{1}.json" -f $stem, $sfx)))
                            $n++
                        }
                        $copied = $false
                        try {
                            Save-Preset -Path $copyPath -Attack ([string]$cfg.attack) `
                                -Topology ([string]$cfg.topology) -Location ([string]$cfg.location) `
                                -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -ExpectedChildren (Get-PresetExpectedChildren $cfg) -Owner $copyOwner
                            $copied = $true
                        }
                        catch {
                            Write-Host ("  Could not write the copy: {0}" -f $_.Exception.Message) -ForegroundColor Red
                        }
                        if ($copied) {
                            Write-Host ("  Copied -> presets\{0}{1}" -f $(if ($copyOwner) { "$copyOwner\" } else { '' }), (Split-Path -Leaf $copyPath)) -ForegroundColor Green
                            Write-Host "  Now editing the COPY - change only what differs. The original is untouched." -ForegroundColor DarkGray
                            $copyCfg = Read-PresetFile -Path $copyPath
                            $edited = Edit-PresetInteractive -Path $copyPath -Cfg $copyCfg `
                                -Roster (ConvertTo-Roster -Cfg $copyCfg).Roster -Ports $pickPorts
                            $finalPath = $edited.Path
                            # An unedited copy in the SAME folder is a pure duplicate - clutter
                            # that would sit next to the original under a -copy name. One in
                            # another member's folder is the point of copying, so it stays.
                            if (-not $edited.Saved -and $copyOwner -eq $file.Owner) {
                                $keep = Read-Line "`n  The copy is identical to the original, in the same folder - keep it anyway? [y/N] > "
                                if ($keep -ne 'y' -and $keep -ne 'Y') {
                                    Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
                                    Write-Host "  Removed the unchanged copy - still on the original." -ForegroundColor DarkGray
                                    $finalPath = $null
                                }
                            }
                            $presetFiles = @(Get-PresetFiles)
                            if ($finalPath) {
                                # Switch this screen to the copy, same re-resolve as the Edit
                                # entry above, so 'Yes - use it' runs from the new preset.
                                $file = @($presetFiles | Where-Object { $_.FullName -eq $finalPath }) | Select-Object -First 1
                                $cfg  = if ($file) { Read-PresetFile -Path $file.FullName } else { $null }
                                if (-not $cfg) {
                                    Write-Host "  Copy saved, but it can't be read back from presets\ - returning to the list." -ForegroundColor Yellow
                                    $deciding = $false
                                }
                                else {
                                    $preview     = (ConvertTo-Roster -Cfg $cfg).Roster
                                    $cfgScenario = ConvertTo-Scenario $(if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })
                                    Write-Host ("  Now showing the copy ({0}) - 'Yes - use it' runs from it." -f $file.Name) -ForegroundColor Green
                                }
                            }
                        }
                    }

                    7 {
                        Write-Host ""
                        Write-Host ("--- {0} (raw file contents) ---" -f $file.Name) -ForegroundColor Cyan
                        Get-Content -Path $file.FullName -Raw | Write-Host
                        Write-Host "--- end of file ---" -ForegroundColor Cyan
                    }

                    8 {
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
                                    -RepeatNum ([int]$cfg.repeat) -Roster $preview -Scenario $cfgScenario -ExpectedChildren (Get-PresetExpectedChildren $cfg) -Owner $newOwner
                                Write-Host ("  Moved -> presets\{0}\{1}" -f $newOwner, $file.Name) -ForegroundColor Green
                                $presetFiles = @(Get-PresetFiles)
                                $deciding = $false
                            }
                        }
                    }

                    9 {
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

                    10 { $deciding = $false }
                    11 { $deciding = $false; $picking = $false }
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
    # Roster-gate total saved with the preset (0 = not set) - the default at the
    # "children on other laptops" question further down.
    $script:presetExpectedChildren = Get-PresetExpectedChildren $cfg
    # Older presets predate the scenario field - treat a missing one (or 'none', its old name) as 'stationary'
    # so a pre-scenario preset still loads unchanged.
    $scenario = ConvertTo-Scenario $(if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })

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
    # Multi-laptop split presets (oct. 1, 2026): a laptop holding only the root,
    # or only plain victims, legitimately has no target - it is on another
    # laptop. Throwing here killed the wizard for every such laptop, so ask.
    if ((Test-ScenarioNeedsTarget $scenario) -and -not ($roster | Where-Object { $_.ScenarioTarget })) {
        Write-Host ""
        Write-Host ("No board in this preset is marked as the '{0}' TARGET." -f $scenario) -ForegroundColor Yellow
        Write-Host "  Fine on a multi-laptop run if the target board is flashed on ANOTHER laptop." -ForegroundColor DarkGray
        Write-Host "  On a single-laptop run it means nobody carries out the scenario - edit the preset." -ForegroundColor DarkGray
        $ans = Read-Line ("Is the {0} target on another laptop? [y/N] > " -f $scenario)
        if ($ans -ne 'y' -and $ans -ne 'Y') {
            throw "Preset's scenario is '$scenario' but no board is marked as the ScenarioTarget - mark one (Edit this preset) or answer y if it is on another laptop."
        }
        Write-Host ("  OK - the {0} target runs on another laptop." -f $scenario) -ForegroundColor Green
    }
    # A burst TARGET mark left on the attacker (e.g. the old target was later
    # picked as attacker - that picker keeps the mark) builds no burst code at all:
    # blackhole_victim.c has none, so the run silently becomes stationary.
    $burstTgt = @($roster | Where-Object { $_.ScenarioTarget }) | Select-Object -First 1
    if ($scenario -eq 'burst' -and $burstTgt -and -not (Test-BurstEligible $burstTgt)) {
        throw ("This preset's burst TARGET is {0}, the {1} - that firmware has no burst code, so NOTHING would burst. Edit the preset and mark a VICTIM as the burst target." -f $burstTgt.Label, $burstTgt.Kind)
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
    # A board saved with NO port is one the preset records as on ANOTHER laptop
    # (multi-laptop split) - it is not "unplugged", and the MAC match and the
    # re-pick below both skip port-less boards. Listing it under "not plugged in"
    # and then silently dropping it left a ROOT that WAS plugged in here filed
    # as remote, with nothing flashed and no question asked (sep. 25, 2026).
    $remapped    = $false
    $remoteHere = @($roster | Where-Object { -not $_.Port })
    if ($remoteHere.Count -gt 0) {
        Write-Host ""
        Write-Host "This preset records these boards as on ANOTHER laptop (no COM port saved):" -ForegroundColor Yellow
        foreach ($r in $remoteHere) {
            $lbl = if ($r.Label) { $r.Label } else { '(no label)' }
            Write-Host ("  {0,-10} {1}" -f $lbl, $r.Display) -ForegroundColor Yellow
        }
        foreach ($r in $remoteHere) {
            $lbl = if ($r.Label) { $r.Label } else { '(no label)' }
            # Default NO: a genuine split preset must not walk the operator into a
            # port picker (and a flash) for a board that really is elsewhere.
            $hereAns = Read-Line "  Is $lbl ($($r.Display)) plugged into THIS laptop? [y/N] > "
            if ($hereAns -ne 'y' -and $hereAns -ne 'Y') { continue }
            $p = Select-Port -For "$lbl ($($r.Display))" -Ports $livePorts `
                -Taken @($roster | Where-Object { $_.Port } | ForEach-Object { $_.Port })
            if (-not $p) { continue }
            $r.Port = $p
            if (-not $r.Label) { $r.Label = Get-FreeNodeLabel -ForRoot:($r.Role -eq 'root') -Taken @($roster | ForEach-Object { $_.Label }) }
            # Same rule as the re-pick below: keep a MAC only if one was read on
            # this port this session; otherwise leave it blank, never a stale one.
            $r.Mac = ''
            if ($script:IdentifiedPorts.ContainsKey($p)) {
                $c = ($script:IdentifiedPorts[$p] -split ' -> ')[0].Trim()
                if ($c -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { $r.Mac = $c.ToLower() }
            }
            $remapped = $true
        }
    }
    $missing     = @($roster | Where-Object { $_.Port -and $liveNames -notcontains $_.Port })
    $haveMacs    = @($roster | Where-Object { $_.Mac }).Count -gt 0
    $canReadMacs = $haveMacs -and -not ($DryRun -or $SkipMacCheck)
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
                        Write-Host ""
                        Write-Host "-> Root is on ANOTHER laptop, so this is now a MULTI-LAPTOP split. The next" -ForegroundColor Cyan
                        Write-Host "   questions cover the FULL experiment (every board, on every laptop) - you'll" -ForegroundColor Cyan
                        Write-Host "   say which of THOSE are physically here in a moment." -ForegroundColor Cyan
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
                    Write-Host "  MULTI-LAPTOP: this is the FULL experiment's children, ACROSS every laptop" -ForegroundColor Yellow
                    Write-Host "  combined - not just what's plugged in here. Example: your laptop has 2" -ForegroundColor Yellow
                    Write-Host "  boards, a teammate's has 2 more -> enter 4 (the total, same on both laptops)." -ForegroundColor Yellow
                    Write-Host "  Right after this you'll name each of those 4 one at a time, and for EACH" -ForegroundColor Yellow
                    Write-Host "  one say whether IT is physically at your desk - that's how the wizard sorts" -ForegroundColor Yellow
                    Write-Host "  out which ones are yours to flash." -ForegroundColor Yellow
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
                # This count only means something when every board in the roster is
                # local: in a multi-laptop split, $childCount is the FULL experiment's
                # children (see step 6's own note above) and the root may be remote
                # (step 5) - neither is knowable as "needs a port on THIS laptop" until
                # Select-PortOrRemote asks per-board in step 7. Showing "N need ports"
                # against the whole roster here is what said "5 boards need ports" to
                # an operator who had JUST said the root was on another laptop.
                if (-not $multiLaptop) {
                    $localNeeded = $childCount + 1   # root is always local outside a split
                    if ($localNeeded -gt $ports.Count) {
                        Write-Host ""
                        Write-Host ("{0} boards need ports but only {1} are plugged in right now." -f $localNeeded, $ports.Count) -ForegroundColor Yellow
                        Write-Host "When you reach a board that isn't plugged in yet, pick 'a' at the port prompt -" -ForegroundColor Yellow
                        Write-Host "swap it onto a free USB port and the wizard will find it for you." -ForegroundColor Yellow
                    }
                }

                if ($multiLaptop -and $childCount -gt 0) {
                    Write-Host ""
                    Write-Host ("Now naming all {0} children one at a time. For EACH one, after its label," -f $childCount) -ForegroundColor Cyan
                    Write-Host "you'll be asked 'Is it plugged into THIS laptop?' - say Y only for a board" -ForegroundColor Cyan
                    Write-Host "physically at your desk right now; say N for anything on another laptop" -ForegroundColor Cyan
                    Write-Host "(it gets recorded as remote and skipped - no port question for it)." -ForegroundColor Cyan
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

                $suggested = Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label)
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
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)  $(Format-PickerMacTag $_)"
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
                        # Same RosterAlias rule as the wormhole escape: a remote child
                        # already listed is the attacker, so the placeholder (still
                        # needed for the MAC prompt) is not counted a second time.
                        $alias = @($children | Where-Object { -not $_.Port }).Count -ge 1
                        $remoteLabel = if ($alias) { 'remote-attacker' } else { Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label) }
                        $children += [pscustomobject]@{
                            Label          = $remoteLabel
                            Port           = $null
                            Role           = 'child'
                            Kind           = 'attacker'
                            Display        = $(if ($alias) { 'blackhole ATTACKER (one of the remote boards above)' } else { 'blackhole ATTACKER (other laptop)' })
                            ScenarioTarget = $false
                            Mac            = ''   # same field set as every other board - see the child above
                            Synthetic      = $true
                            RosterAlias    = $alias
                        }
                        foreach ($c in $children) {
                            if ($c.Synthetic) { continue }
                            $c.Kind = 'victim'
                            $c.Display = if (-not $c.Port -and $alias) { 'blackhole victim - or the attacker (set on its own laptop)' } else { 'blackhole victim' }
                        }
                        Write-Host ""
                        if ($alias) {
                            Write-Host "  The attacker is one of the remote boards already listed - not counted again." -ForegroundColor DarkGray
                        }
                        else {
                            Write-Host ("  Remote attacker recorded as '{0}' - tell that laptop's operator to use the" -f $remoteLabel) -ForegroundColor DarkGray
                            Write-Host "  same label." -ForegroundColor DarkGray
                        }
                        Write-Host "  You'll be asked for its MAC before anything is flashed." -ForegroundColor DarkGray
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
                        $portText = if ($_.Port) { $_.Port } else { 'remote - not on this laptop' }
                        "$($_.Label)  ($portText)  $(Format-PickerMacTag $_)"
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

                    $idxA = Show-Menu -Title 'WIRED TUNNEL BOARD 1 of 2 (wormhole, labelled Node A) - either cable end is fine: at run start the two boards pick A/B themselves by depth (deeper = B); this choice is only the backup if the cable link fails' -Options $menuLabels -AllowBack
                    if ($idxA -eq -1) { Undo-LastChild; $step = 7; continue flow }

                    if ($multiLaptop -and $idxA -eq $bothRemoteIdx) {
                        # The step-7 roster is the FULL experiment's, so when it already
                        # holds 2+ remote children the tunnel ends are among them. The
                        # placeholders then stand in for those boards (RosterAlias) and
                        # are not counted again - counting them asked for "at least 9"
                        # after 7 children were entered. Real extra boards only when
                        # the roster is short.
                        $alias = @($children | Where-Object { -not $_.Port }).Count -ge 2
                        if ($alias) {
                            $labelA = 'remote-A'; $labelB = 'remote-B'
                            $dispA  = 'wormhole Node A (one of the remote boards above)'
                            $dispB  = 'wormhole Node B (one of the remote boards above)'
                        }
                        else {
                            $taken  = @($children | Select-Object -ExpandProperty Label)
                            $labelA = Get-FreeNodeLabel -Taken $taken
                            $labelB = Get-FreeNodeLabel -Taken (@($taken) + $labelA)
                            $dispA  = 'wormhole Node A (other laptop)'
                            $dispB  = 'wormhole Node B (other laptop)'
                        }
                        $children += [pscustomobject]@{
                            Label = $labelA; Port = $null; Role = 'child'; Kind = 'A'
                            Display = $dispA; ScenarioTarget = $false
                            Mac = ''; Synthetic = $true; RosterAlias = $alias
                        }
                        $children += [pscustomobject]@{
                            Label = $labelB; Port = $null; Role = 'child'; Kind = 'B'
                            Display = $dispB; ScenarioTarget = $false
                            Mac = ''; Synthetic = $true; RosterAlias = $alias
                        }
                        # Keyed on Synthetic, not Kind: a real board picked as A/B on an
                        # earlier visit to this step must not keep that role.
                        foreach ($c in $children) {
                            if ($c.Synthetic) { continue }
                            $c.Kind = 'control'
                            $c.Display = if (-not $c.Port -and $alias) { 'control - or a tunnel end (set on its own laptop)' } else { 'control (plain firmware)' }
                        }
                        Write-Host ""
                        if ($alias) {
                            Write-Host "  Both tunnel ends are among the remote boards already listed - not counted again." -ForegroundColor DarkGray
                            Write-Host "  That laptop's operator picks which two are Node A and Node B." -ForegroundColor DarkGray
                        }
                        else {
                            Write-Host ("  Remote tunnel ends recorded as '{0}' (A) and '{1}' (B) - the cable and both" -f $labelA, $labelB) -ForegroundColor DarkGray
                            Write-Host "  boards live on that laptop; nothing is flashed for them here." -ForegroundColor DarkGray
                        }
                        $step = if (Test-ScenarioNeedsTarget $scenario) { 9 } else { 10 }
                        continue flow
                    }

                    # Node B is picked from the REAL boards only - the combined escape
                    # above already covers "not here", and offering it again would let
                    # A be local while B is remote.
                    $idxB = -1
                    while ($true) {
                        $idxB = Show-Menu -Title 'WIRED TUNNEL BOARD 2 of 2 (wormhole, labelled Node B) - the OTHER end of the same UART cable' -Options $labels -AllowBack
                        if ($idxB -eq -1) { continue flow }   # re-ask Node A (step 8 re-entry strips synthetics)
                        if ($idxB -eq $idxA) {
                            Write-Host "  Pick the OTHER end of the cable - board 2 must be a different board from board 1." -ForegroundColor Yellow
                            continue
                        }
                        if ([bool]$children[$idxA].Port -ne [bool]$children[$idxB].Port) {
                            Write-Host "  Node A and Node B share one cable - both must be on this laptop, or both remote." -ForegroundColor Yellow
                            continue
                        }
                        break
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
                $labels = @()
                # MULTI-LAPTOP SPLIT: same reasoning as the attacker/wormhole escapes
                # above - the scenario target may be a board on a teammate's laptop,
                # never listed here at all. Without this, "which child is the target?"
                # forced picking one of YOUR boards even when the real target is
                # elsewhere. Always offered when multiLaptop, so this menu is never
                # the one place in the wizard that can't say "not here".
                $escapeIdx = -1
                if ($multiLaptop) {
                    $escapeIdx = $eligible.Count
                    $labels += "None of these - the $($scenario.ToUpper()) TARGET is on ANOTHER laptop"
                }
                $idx = Show-ScenarioTargetMenu -Title "Which child is the $scenario TARGET? (exactly one)" `
                    -Scenario $scenario -Eligible $eligible -ExtraOptions $labels -Roster $children -AllowBack
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
                    # RosterAlias: see the wormhole escape in step 8.
                    $alias = @($eligible | Where-Object { -not $_.Port }).Count -ge 1
                    $remoteLabel = if ($alias) { 'remote-target' } else { Get-FreeNodeLabel -Taken @($children | Select-Object -ExpandProperty Label) }
                    $children += [pscustomobject]@{
                        Label = $remoteLabel; Port = $null; Role = 'child'; Kind = 'victim'
                        Display = $(if ($alias) { "$scenario TARGET (one of the remote boards above)" } else { "$scenario TARGET (other laptop)" })
                        ScenarioTarget = $true
                        Mac = ''; Synthetic = $true; RemoteTargetSynthetic = $true; RosterAlias = $alias
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
                    $rootLabel = Get-FreeNodeLabel -ForRoot -Taken @($children | Select-Object -ExpandProperty Label)
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

# LOCATION PRE-FLIGHT for the MANUAL flow (added sep. 22, 2026). Both paths
# converge here with a final roster and $location, but the preset branch has
# already asked by now - hence the flag. Answering the menus instead of using
# a preset used to skip this check entirely and silently file the run's SD
# data under whatever each card already said. Still before any flash.
if (-not $locationPreflightDone -and $runRoster.Count -gt 0) {
    Confirm-BoardLocations -Boards $runRoster -WantLocation $location
    $locationPreflightDone = $true
}

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

# Cleared here so a value from an earlier pass (preset loop) cannot leak into
# this run's attacker MAC below.
$gotMac = $null
$typedMac = $null

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
            $typedMac = Read-RemoteAttackerMac -Who $remoteAttacker.Label -LocalMacs @($roster | Where-Object { $_.Port -and $_.Mac } | ForEach-Object { $_.Mac })

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
            # A split preset often records no attacker at all (e.g. a laptop with
            # only victims). Its victims still need the attacker's MAC built in -
            # load-bearing for STAR (D-16): without it they fall back to this
            # laptop's mesh_config.h and, if stale, never join (oct. 1, 2026).
            Write-Host ""
            Write-Host "No attacker board is recorded in this roster, but it has local victim(s)." -ForegroundColor Yellow
            Write-Host "  If the attacker is on ANOTHER laptop, type its MAC (printed by that laptop's" -ForegroundColor DarkGray
            Write-Host "  wizard) so it is built into the victims here. Blank = there is no attacker." -ForegroundColor DarkGray
            if ($SkipMacCheck -or $DryRun) {
                Write-Host "  (not asking - dry run / -SkipMacCheck)" -ForegroundColor DarkGray
            }
            else {
                $typedMac = Read-RemoteAttackerMac -Who 'Attacker' -LocalMacs @($roster | Where-Object { $_.Port -and $_.Mac } | ForEach-Object { $_.Mac })
            }
            if (-not $typedMac) {
                Write-Host "WARNING: no attacker - no node will drop transiting traffic, so there is no" -ForegroundColor Red
                Write-Host "blackhole to observe and the capture carries no attack signature." -ForegroundColor Red
            }
        }
    }
    else {
        if ($victimCount -eq 0) {
            Write-Host ""
            Write-Host "WARNING: this roster has an attacker but NO victims." -ForegroundColor Red
            Write-Host "No probes will be generated, so nothing transits the attacker and there is" -ForegroundColor Red
            Write-Host "no blackhole to observe - the capture carries no attack signature." -ForegroundColor Red
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
        Write-Host "  $($na.Label) and $($nb.Label), and that uart_link_test passed" -ForegroundColor Yellow
        Write-Host "  (main menu > MAINTENANCE > Wormhole UART tunnel test)." -ForegroundColor Yellow
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

# ------------------------------------------------------------ roster gate ----
# The root is built to WAIT until every child of the run is in the mesh before
# Phase 0 (run.ps1 -ExpectedChildren). On sep. 24, 2026 it started on a fixed
# 60 s timer while five of seven children were being moved onto powerbanks and
# never came back - a "clean" run with two children.
#
# Children on THIS laptop are counted live from $runRoster (so an add/remove
# edit below is followed). Children on OTHER laptops are only partly known: the
# roster records a remote board only when it has a job (attacker, tunnel end,
# scenario target) - a plain child flashed elsewhere is not in it at all. So on
# a multi-laptop run the operator confirms that number once.
# RosterAlias placeholders stand in for a remote board already counted, so skip them.
$script:remoteChildCount = @($fullRoster | Where-Object { -not $_.Port -and $_.Role -ne 'root' -and -not $_.RosterAlias }).Count
$rootIsLocal = @($runRoster | Where-Object { $_.Role -eq 'root' }).Count -gt 0
$localKids   = @($runRoster | Where-Object { $_.Role -ne 'root' }).Count
# Total saved in the preset ('Expected children' in Edit preset; 0 = not set /
# no preset). A total above this laptop's own children means other laptops
# hold the rest, so the question below is asked even without -multiLaptop.
$presetTotal = [int]$script:presetExpectedChildren
$script:gateTotal = 0   # set below only when the question is asked; the end-of-run preset save stores it
if ($rootIsLocal -and (($multiLaptop -eq $true) -or $script:remoteChildCount -gt 0 -or $presetTotal -gt $localKids)) {
    # No GUESSED Enter-default here (oct. 1, 2026): the known count only covers
    # remote boards with a JOB, so accepting it left plain victims on other
    # laptops out of the gate and the root started Phase 0 with 2 of its
    # victims. The known count is the floor; the operator must type the real
    # number. The one exception is a total the operator SAVED in the preset
    # (oct. 4, 2026) - that is their own answer, not a guess.
    $known = $script:remoteChildCount
    $defRemote = -1
    if ($presetTotal -gt 0) {
        if ($presetTotal -ge ($localKids + $known)) { $defRemote = $presetTotal - $localKids }
        else {
            Write-Host ("`n  The preset expects {0} children, but this run already has {1} - ignoring the preset's number." -f $presetTotal, ($localKids + $known)) -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "The root will NOT start the run until every child is in the mesh." -ForegroundColor Cyan
    Write-Host "  Count EVERY non-root board flashed on another laptop - victims included, not just" -ForegroundColor DarkGray
    Write-Host ("  the {0} already in this roster. Ask the other laptops if unsure." -f $known) -ForegroundColor DarkGray
    if ($defRemote -ge 0) {
        Write-Host ("  The preset says {0} children in total: {1} on this laptop + {2} on other laptops." -f $presetTotal, $localKids, $defRemote) -ForegroundColor DarkGray
    }
    $tries = 0
    while ($true) {
        $tries++
        if ($tries -gt $script:MaxPromptTries) {
            $fallback = if ($defRemote -ge 0) { $defRemote } else { $known }
            $script:remoteChildCount = $fallback
            Write-Host ("  No valid number - using {0}; the root may start before everyone joins." -f $fallback) -ForegroundColor Yellow
            break
        }
        $prompt = if ($defRemote -ge 0) { "How many children run on OTHER laptops? Enter = {0} (from the preset), or type another number (at least {1}) > " -f $defRemote, $known }
                  else { "How many children run on OTHER laptops? (at least {0}) > " -f $known }
        $ans = Read-Line $prompt
        if (-not $ans -and $defRemote -ge 0) { $script:remoteChildCount = $defRemote; break }
        $n = 0
        if ($ans -and [int]::TryParse($ans.Trim(), [ref]$n) -and $n -ge $known) { $script:remoteChildCount = $n; break }
        Write-Host ("  Type a whole number, {0} or more." -f $known) -ForegroundColor Yellow
    }
    Write-Host ("  Root waits for {0} children: {1} on this laptop + {2} on other laptops." -f ($localKids + $script:remoteChildCount), $localKids, $script:remoteChildCount) -ForegroundColor Green
    $script:gateTotal = $localKids + $script:remoteChildCount
}

# ---------------------------------------------- after the root's export ----
# The root always exports (it is the last board); what runs AFTER that is the
# operator's call (user request, sep. 26, 2026). Trim + M6-M8 on the root only
# makes sense when every child's CSV is already in tools\exports\ - over USB
# they are, with the SD-card workflow they arrive later. run.ps1 also refuses
# M6-M8 when no child telemetry is present, so a wrong answer cannot overwrite
# a complete analysis with a root-only one.
$script:rootPostExport = 'analyze'
if ($rootIsLocal) {
    Write-Host ""
    Write-Host "After the ROOT exports, what should run?" -ForegroundColor Cyan
    Write-Host "   [1] Auto-trim + analyze (M6-M8)   - children's CSVs already exported over USB"
    Write-Host "   [2] Auto-trim only                - children come in later from SD cards; run analyze.ps1 then"
    Write-Host "   [3] Neither - export only"
    $ans = Read-Line "Choice [1] > "
    switch ("$ans".Trim()) {
        '2'     { $script:rootPostExport = 'trim' }
        '3'     { $script:rootPostExport = 'none' }
        default { $script:rootPostExport = 'analyze' }
    }
}

# ------------------------------------------- children: skip export by default ----
# Every child is flashed with -Export, and closing its monitor (Ctrl+]) used to
# EXPORT after 5 s unless 'n' was pressed. On an SD-card run Ctrl+] on a child
# usually just means "on to the next board", and one missed 'n' started a USB
# export nobody wanted (oct. 4, 2026). Asked once per run; the ROOT is never
# affected - it always keeps the export-by-default window (run.ps1 ignores the
# flag for it). Skipping loses nothing: the data stays on the board's card.
# $script:childExportMode: 'now' = skip at once (run.ps1 -SkipExportNow),
# 'export' = the old 5 s window, export unless 'n' (no extra switch).
$script:childExportMode = 'export'
if (@($runRoster | Where-Object { $_.Role -ne 'root' }).Count -gt 0) {
    # Default is SKIP INSTANTLY (user request, oct. 4, 2026) - skipping loses
    # nothing, while an unwanted USB export is what led to the Ctrl+C mid-read crash.
    $sxIdx = Show-Menu -Title "When you close a CHILD's monitor (Ctrl+]), what happens to its export?" -Options @(
        "SKIP instantly    - no wait, straight on to the next board (best for SD-card runs: children come in from their cards later)",
        "EXPORT over USB   - after 5 s; press 'n' to skip it (the old behaviour; use when children export over USB)"
    ) -DefaultIndex 0
    $script:childExportMode = if ($sxIdx -eq 0) { 'now' } else { 'export' }
    $sxText = if ($script:childExportMode -eq 'now') { 'export SKIPPED instantly' } else { "export over USB unless you press 'n' within 5 s" }
    Write-Host ("  Children: {0}. The ROOT always exports." -f $sxText) -ForegroundColor DarkGray
}

# --------------------------------------------------------- confirmation ----

# Wrapped as a scriptblock (not just run inline) so the edit-a-node loop just
# below can rebuild $plan (Params comes from New-RunParams, a snapshot -- it
# does NOT auto-follow a later edit to the Board it was built from) and
# reprint the box after each change, instead of the operator having to trust
# an edit "took" with no visible confirmation.
# ------------------------------------------------- this run's attacker MAC ----
# Built into every blackhole child's firmware (run.ps1 -AttackerMac), ahead of
# this laptop's mesh_config.h, so a stale per-laptop value can never point
# victims at the wrong board (oct. 1, 2026: star+blackhole victims flashed from
# a laptop holding GitHub's old MAC never joined - D-16). Best source first: the
# MAC just read off the attacker, the one typed for a remote attacker, then the
# roster's recorded MAC. Nothing known -> mesh_config.h as before.
$script:runAttackerMac = ''
if ($attack -eq 'blackhole') {
    $attBoard = $fullRoster | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
    $cands = @($gotMac, $typedMac, $(if ($attBoard) { $attBoard.Mac }))
    $pick = $cands | Where-Object { $_ -and "$_".Trim() -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$' } | Select-Object -First 1
    if ($pick) { $script:runAttackerMac = "$pick".Trim().ToLower() }

    Write-Host ""
    if ($script:runAttackerMac) {
        Write-Host ("Attacker for this run: {0} - built into every blackhole board flashed here" -f $script:runAttackerMac) -ForegroundColor Cyan
        Write-Host "  (this laptop's mesh_config.h no longer decides it)." -ForegroundColor DarkGray
    }
    elseif ($topology -eq 'star') {
        Write-Host "WARNING: the attacker's MAC is unknown on this laptop, so victims fall back to" -ForegroundColor Red
        Write-Host ("  mesh_config.h ({0}). In STAR + blackhole victims join ONLY that board -" -f (Get-ConfiguredAttackerMac)) -ForegroundColor Red
        Write-Host "  if it is not this run's attacker, no victim joins. Abort at the plan and fix the MAC." -ForegroundColor Red
    }
}

$buildAndPrintPlan = {
    $script:plan = @()
    $script:expectedChildren = @($runRoster | Where-Object { $_.Role -ne 'root' }).Count + $script:remoteChildCount
    foreach ($b in $runRoster) {
        $script:plan += [pscustomobject]@{
            Board  = $b
            Params = (New-RunParams -Board $b -Attack $attack -Topology $topology -Location $location -RepeatNum $repeat -Scenario $scenario -ExpectedChildren $script:expectedChildren -AttackerMac $script:runAttackerMac)
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
        $what = if ($scenario -eq 'powercycle') { 'unplug ~10 s, then plug back in' } else { 'move it from spot 1 to spot 2' }
        $when = if ($attack -eq 'none') { '2:30 after the root prints PHASE 0 - BASELINE (halfway through baseline)' }
                else { '5:10 after the root prints PHASE 0 - BASELINE (just inside the attack)' }
        Write-Host "  NOTE     : this is a $scenario run - board $tgtLbl must be handled DURING it:" -ForegroundColor Magenta
        Write-Host "             WHAT: $what - ONCE, then leave it powered." -ForegroundColor Magenta
        Write-Host "             WHEN: $when - start a phone timer at that banner." -ForegroundColor Magenta
        Write-Host "             Write down the exact time you did it. run.ps1 repeats this before each board boots." -ForegroundColor Magenta
    }
    elseif ($scenario -eq 'burst') {
        # oct. 1, 2026: two burst runs had NO sender because every laptop assumed
        # another one had it. Say plainly who sends it - or that nobody here does.
        $tgt = $plan | Where-Object { $_.Board.ScenarioTarget } | Select-Object -First 1
        $remoteTgt = $fullRoster | Where-Object { $_.ScenarioTarget -and -not $_.Port } | Select-Object -First 1
        if ($tgt) {
            Write-Host ("  BURST    : {0} on THIS laptop is the burst sender - no other laptop may mark one." -f $tgt.Board.Label) -ForegroundColor Magenta
        }
        elseif ($remoteTgt) {
            Write-Host ("  BURST    : sender {0} is on another laptop - CHECK its plan shows '<< burst TARGET'." -f $remoteTgt.Label) -ForegroundColor Magenta
        }
        else {
            Write-Host "  BURST    : NO burst sender on this laptop. Exactly ONE other laptop's plan must" -ForegroundColor Red
            Write-Host "             show a victim with '<< burst TARGET' - if none does, nothing bursts." -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "  Order (root is always last):"
    $step = 0
    foreach ($p in $plan) {
        $step++
        $tail = if ($script:childExportMode -eq 'now') { 'no export (instant skip)' } else { '-Export' }
        if ($p.Board.Role -eq 'root') {
            $tail = switch ($script:rootPostExport) { 'trim' { '-Trim' } 'none' { '-Export' } default { '-Analyze' } }
        }
        if ($p.Board.ScenarioTarget) { $tail = "$tail  << $scenario TARGET" }
        $mac = Resolve-BoardMac -Board $p.Board -SkipLiveRead:($SkipMacCheck -or $DryRun)
        $macDisp = if ($mac) { $mac } else { '(unread)' }
        $line = ("   [{0}] {1,-8} {2,-27} {3,-7} {4,-17} {5}" -f $step, $p.Board.Label, $p.Board.Display, $p.Board.Port, $macDisp, $tail)
        $role = Get-BoardColorRole $p.Board
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
                    $labels = @($eligible | ForEach-Object { "$($_.Label)  ($($_.Port))  $(Format-PickerMacTag $_)  -  $($_.Display)" })
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
        # The children total confirmed at this run's roster-gate question becomes
        # the preset's default next time; no question this run = keep the file's.
        $gateSave = @{}
        if ($script:gateTotal -gt 0) { $gateSave.ExpectedChildren = $script:gateTotal }
        Save-Preset -Path $Preset -Attack $attack -Topology $topology `
            -Location $location -RepeatNum $repeat -Roster $runRoster -Scenario $scenario @gateSave
        Write-Host ("  Updated -> {0}" -f $Preset) -ForegroundColor Green
    }
}

if (-not $Preset) {
    $saveAns = if ($Ask) { Read-Line "`nSave this roster as a preset for the next repeat? [y/N] > " } else { 'y' }
    if ($saveAns -eq 'y' -or $saveAns -eq 'Y') {
        # Whose boards this roster is, asked BEFORE the filename: it decides the
        # folder, which is what lets two members keep the same plain cell name
        # (blackhole-linear-g402-stationary.json) instead of one having to be
        # hand-renamed. Pre-answered from the MACs, so flashing an absent
        # member's boards files itself under THEM without you remembering to say so.
        $presetOwner = Select-PresetOwner -Roster $runRoster
        $presetDir = if ($presetOwner) { Join-Path (Get-PresetRoot) $presetOwner } else { Get-PresetRoot }
        if (-not (Test-Path $presetDir)) { New-Item -ItemType Directory -Force -Path $presetDir | Out-Null }
        $suggested = Get-PresetCellFileName -Attack $attack -Topology $topology -Location $location -Scenario $scenario
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

        $gateSave = @{}
        if ($script:gateTotal -gt 0) { $gateSave.ExpectedChildren = $script:gateTotal }
        Save-Preset -Path $presetPath -Attack $attack -Topology $topology `
            -Location $location -RepeatNum $repeat -Roster $runRoster -Scenario $scenario -Owner $presetOwner @gateSave
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
            Write-Host "Removing build_* under $buildRoot and $shortBuildRoot ..." -ForegroundColor Yellow
            foreach ($r in @($buildRoot, $shortBuildRoot)) {
                Remove-Item -Recurse -Force (Join-Path $r 'child_node\build_*') -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force (Join-Path $r 'root_node\build_*')  -ErrorAction SilentlyContinue
            }
            $cleanBuild = $false
        }

        $buildPlan = @()
        $seenDirs  = @{}
        # Build dir -> every board it will be flashed onto. Boards sharing a
        # port share one build, so the header names ALL of them, not just the
        # one that happened to be first.
        $buildUsers = @{}
        foreach ($p in $plan) {
            $bd = Get-BoardBuildDir -Params $p.Params
            if (-not $seenDirs.ContainsKey($bd)) { $seenDirs[$bd] = $true; $buildPlan += $p; $buildUsers[$bd] = @() }
            $buildUsers[$bd] += $p.Board
        }

        $failed = @()
        $nBuilt = 0; $nSkipped = 0
        $bi = 0
        $buildWatch = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($p in $buildPlan) {
            $bi++
            Write-Host ""
            Write-Host ("=== Pre-build [{0}/{1}] {2} - {3} on {4} ({5}) ===" -f $bi, $buildPlan.Count, $p.Board.Label, $p.Board.Display, $p.Board.Port, (Format-BoardMacTag $p.Board)) -ForegroundColor Cyan
            foreach ($other in @($buildUsers[(Get-BoardBuildDir -Params $p.Params)] | Where-Object { $_ -ne $p.Board })) {
                Write-Host ("    same firmware also goes to {0} - {1} ({2})" -f $other.Label, $other.Display, (Format-BoardMacTag $other)) -ForegroundColor DarkGray
            }
            $buildParams = [ordered]@{}
            foreach ($k in $p.Params.Keys) { $buildParams[$k] = $p.Params[$k] }
            $buildParams.BuildOnly = $true
            if ($p.Board.PSObject.Properties['Mac'] -and $p.Board.Mac) { $buildParams['Mac'] = [string]$p.Board.Mac }
            $global:LASTEXITCODE = 0
            $global:PrebuildResult = $null
            & (Join-Path $base 'run.ps1') @buildParams
            if ($LASTEXITCODE -ne 0) { $failed += $p.Board.Label }
            elseif ($global:PrebuildResult -eq 'skipped') { $nSkipped++ }
            else { $nBuilt++ }
        }
        $buildWatch.Stop()

        if ($failed.Count -gt 0) {
            Write-Host ""
            Write-Host ("BUILD FAILED for: {0}" -f ($failed -join ', ')) -ForegroundColor Red
            Write-Host "Nothing was flashed. Fix the compile error above and re-run the wizard." -ForegroundColor Red
            return
        }
        Write-Host ""
        Write-Host ("All {0} variant(s) ready in {1} - {2} compiled, {3} already up to date, 0 errors." -f $buildPlan.Count, (Format-Duration ([int]$buildWatch.Elapsed.TotalSeconds)), $nBuilt, $nSkipped) -ForegroundColor Green
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
        Write-Host "  (would first remove build_* under $buildRoot and $shortBuildRoot)" -ForegroundColor DarkGray
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
# sight: <preset-base-name>_r<N>_<timestamp>.log, or <topology>-<attack>-<scenario>-
# <location>_r<N>_<timestamp>.log when no preset is involved. Filed by run under
# run_logs\<attack>\<topology>\<location>\<scenario>\ (Get-RunLogDir), like the
# exports. Reviewable later from the wizard's DATA menu ("View a saved run log"
# -> Invoke-ViewRunLog); offered for a GitHub push once it is closed off.
# No packet-capture question here (removed sep. 26, 2026, user's call): the
# VERIFY category's sniffer entries (MacBook sniffer test, ESP32 sniffer board,
# Check a sniffer capture file) already cover it, and asking again on every run
# was a duplicate.

$saveLogAns = Read-Line "`nSave a full log of this run (console output incl. any errors, viewable later from the wizard)? [Y/n] > "
$saveRunLog = ($saveLogAns -ne 'n' -and $saveLogAns -ne 'N')
$runLogPath = $null
$transcriptStarted = $false
if ($saveRunLog) {
    $runLogDir = Get-RunLogDir -AttackDir $attackDir -TopoDir $topoDir -Location $location -Scenario $scenario
    if (-not (Test-Path $runLogDir)) { New-Item -ItemType Directory -Force -Path $runLogDir | Out-Null }
    $logBaseName = if ($Preset) { [IO.Path]::GetFileNameWithoutExtension($Preset) } else { "$topoDir-$attackDir-$scenario-$($location.ToLower())" }
    # _r<N> like the exports/PCAP names, so r1/r2/r3 of one cell tell apart on sight.
    $logBaseName = "{0}_r{1}" -f $logBaseName, $repeat
    $runLogPath = Get-StampedPath -Dir $runLogDir -Head $logBaseName -Ext '.log'
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
    Write-Host "Removing build_* under $buildRoot and $shortBuildRoot ..." -ForegroundColor Yellow
    # BLACKHOLE_ATTACKER_MAC lives in the shared mesh_common header, which BOTH
    # projects compile against - so both build trees have to go, not just child_node.
    # Both roots: Get-SafeBuildDir puts over-long build dirs under the short one.
    foreach ($r in @($buildRoot, $shortBuildRoot)) {
        Remove-Item -Recurse -Force (Join-Path $r 'child_node\build_*') -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force (Join-Path $r 'root_node\build_*')  -ErrorAction SilentlyContinue
    }
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

# SILENCE THE OLD ROOT BEFORE ANY CHILD BOOTS. The root is flashed LAST, so
# until its turn it is still running whatever it ran before - often the
# previous 11-min experiment. When that one ends it broadcasts TERMINATE, and a
# freshly flashed child (seq counter at 0) accepts it: the child stops logging
# and heartbeating before the NEW root has even started, and the new root's
# topology table then shows only itself (sep. 23 2026 blackhole/linear/home -
# child got phase_id=4 root_ts=667 s at its own uptime 116 s).
#
# PARKED, NOT ERASED: esptool --after no_reset leaves the chip sitting in its
# ROM bootloader - no Wi-Fi, no firmware running, flash untouched. It is woken
# (hard reset) right before its own run.ps1 call below, so run.ps1's
# SET_TIME -> erase -> flash sequence finds live firmware exactly as before.
# Erasing here instead would kill SET_TIME (an erased board cannot answer it),
# and setting the clock early would date the root by the moment it was parked,
# minutes stale by the time it boots. The park is VERIFIED by a second esptool
# call that must sync WITHOUT resetting - that only succeeds if the chip really
# is still in the bootloader.
$rootParked = $false
$rootStep = $plan | Where-Object { $_.Board.Role -eq 'root' } | Select-Object -First 1
if ($rootStep -and $plan[0].Board.Role -ne 'root' -and -not $DryRun) {
    $rp = $rootStep.Board.Port
    Write-Host ""
    Write-Host ("Parking the root on {0} (bootloader, firmware kept) - its OLD firmware would otherwise" -f $rp) -ForegroundColor Yellow
    Write-Host "send a stale TERMINATE that stops the children before the new root even starts." -ForegroundColor Yellow
    & esptool.py --chip esp32 --port $rp --after no_reset read_mac | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & esptool.py --chip esp32 --port $rp --before no_reset --after no_reset read_mac | Out-Null
    }
    if ($LASTEXITCODE -eq 0) {
        $rootParked = $true
        Write-Host ("  {0} parked - silent until its turn." -f $rp) -ForegroundColor Green
    } else {
        Write-Host ("  Could not park {0}. UNPLUG THE ROOT now and plug it back in only at its turn," -f $rp) -ForegroundColor Red
        Write-Host "  or the old run may terminate the children. Press Enter once it is unplugged." -ForegroundColor Red
        [void](Read-Line "  > ")
    }
}

$total = $plan.Count
$step = 0
$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$boardElapsed = [ordered]@{}   # Label -> seconds, for the "it took N min" summary
foreach ($p in $plan) {
    $step++
    $b = $p.Board

    Write-Host ""
    Write-Host ("=== [{0}/{1}] {2} - {3} on {4} ({5}) ===" -f $step, $total, $b.Label, $b.Display, $b.Port, (Format-BoardMacTag $b)) -ForegroundColor Cyan

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
        if ($p.Params.ExpectedChildren -gt 0) {
            Write-Host ""
            Write-Host ("  ROSTER GATE: this root WAITS until all {0} children are in the mesh before Phase 0." -f $p.Params.ExpectedChildren) -ForegroundColor Yellow
            Write-Host "  Every child must already be on its FINAL power (powerbank/charger) - a board moved" -ForegroundColor Yellow
            Write-Host "  after this point cuts its own capture. The monitor prints 'WAITING: n/N' every 10 s;" -ForegroundColor Yellow
            Write-Host "  if a child is truly gone, type START_ANYWAY + Enter there (the run is then SHORT)." -ForegroundColor Yellow
        }

        if ($rootParked) {
            # Wake it into its OLD firmware so run.ps1's SET_TIME has something
            # to answer. That firmware restarts from stabilise (60 s before any
            # phase broadcast), and run.ps1 erases it within seconds. The wait
            # covers boot -> SD mount -> serial command task (~7 s on the root).
            Write-Host ""
            Write-Host "  Waking the parked root so run.ps1 can set its clock ..." -ForegroundColor DarkGray
            & esptool.py --chip esp32 --port $b.Port --before no_reset --after hard_reset read_mac | Out-Null
            if ($LASTEXITCODE -eq 0) { Start-Sleep -Seconds 10 }
            else { Write-Host "  Wake failed - the root keeps a build-time clock this run; the capture itself is unaffected." -ForegroundColor Yellow }
        }
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

    # Display-only (run.ps1 echoes it on its "Board:" line). Set HERE, after any
    # port change above, and only when known - an empty -Mac would print nothing.
    if ($b.PSObject.Properties['Mac'] -and $b.Mac) { $p.Params['Mac'] = [string]$b.Mac }
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
        # Offered AFTER Stop-Transcript so the push's own output is not in the
        # log. Also reached on the FAILED-child `exit 1` path - a failed run's
        # log is exactly the one a teammate needs to see. push_data.py lists
        # what goes up and asks again before anything is sent.
        try {
            $pushLogAns = Read-Line "  Push this run log to GitHub now? (shows every run log not on GitHub yet, asks before sending) [y/N] > "
            if ($pushLogAns -eq 'y' -or $pushLogAns -eq 'Y') { Invoke-DataSync -Mode push -Area logs }
            else { Write-Host "  Not pushed - later: main menu -> Sync data with GitHub -> RUN LOGS." -ForegroundColor DarkGray }
        } catch {
            Write-Host ("  Run log push skipped ({0}) - the log itself is saved." -f $_.Exception.Message) -ForegroundColor Yellow
        }
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
