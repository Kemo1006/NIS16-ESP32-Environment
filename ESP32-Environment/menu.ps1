<#
  Combined ESP-WIFI-MESH launcher
  ---------------------------------------------------------------------------
  No more long flag strings. Run:   .\menu.ps1
  Pick options from menus; it builds and runs the right run.ps1 / tool command
  for you, and SHOWS you the equivalent long command before it runs. Run from
  the "ESP-IDF 5.3 PowerShell" window.

  Covers: baseline / blackhole / wormhole runs (flash, wipe, export, analyze)
  for ONE board or MULTIPLE boards at once (opens one ESP-IDF window per
  board, root exported last), export-only, wipe/erase a board, identify-a-
  board (MAC/node), writing/updating location.txt on an already-running board
  over USB, running the M6->M8 analysis pipeline standalone on
  already-exported CSVs, and verifying a captured attack against the
  published 3-sigma signature. Thin wrapper over run.ps1 + tools\*.py, so
  nothing about the dataset or firmware changes.
  For saved rosters/presets or MAC-drift checks across repeats, see
  run_wizard.ps1 instead.
  ASCII-only on purpose (Windows PowerShell 5.1 misreads non-ASCII in .ps1).
#>
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$run  = Join-Path $base 'run.ps1'

# Build output goes OUTSIDE OneDrive -- same tag formula as run.ps1/run_wizard.ps1
# (keep these three in sync so they all resolve the SAME build dir for the same
# board/variant and share ccache-warm output). Used by the multi-board pre-build
# flow below to predict/build the exact dir run.ps1 will use.
$repoTag   = (Split-Path (Split-Path $base -Parent) -Leaf) + '_' + ([math]::Abs($base.GetHashCode())).ToString('x8')
$buildRoot = Join-Path $env:LOCALAPPDATA "esp32_builds\$repoTag"

# Same navigation contract as run_wizard.ps1 (identical mechanism, kept in sync):
# EVERY prompt goes through Read-Line, so 'm' (back to the main menu) works
# everywhere by construction -- no prompt you can get stuck on needing Ctrl+C.
# 'b' (back one question) stays opt-in per call site via -AllowBack, since it
# only means something where there is a previous question to return to.
$script:MainMenuSignal = 'MENU-RETURN-TO-MAIN-MENU'
$script:BackSignal     = 'MENU-GO-BACK'
$script:NavLocked      = $false

# Ports identified this session via Invoke-Identify (COM -> "MAC -> name"), so a
# port read once shows what it is everywhere else in this run - port list, role
# menus - without re-reading it. Same cache/shape as run_wizard.ps1's identical
# one; kept in sync so the identify feature looks and behaves the same in both.
$script:IdentifiedPorts = @{}

function Test-MainMenuAnswer {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('m', 'menu', 'main')))
}

function Test-BackAnswer {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('b', 'back')))
}

function Test-ClearScreenAnswer {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -eq 'cls'))
}

function Request-MainMenu {
    # Thrown, not returned: prompts sit several helpers deep (Select-Port inside
    # a per-board loop inside an action block), and threading a sentinel back up
    # through every one of those returns would mean touching every call site.
    # try/finally still unwinds normally. Caught once, at the :menu loop below.
    if ($script:NavLocked) {
        Write-Host ""
        Write-Host "  'm' is disabled once flashing/writing has started - continue answering, or" -ForegroundColor Yellow
        Write-Host "  Ctrl+C if you really must stop mid-run." -ForegroundColor Yellow
        return
    }
    throw $script:MainMenuSignal
}

function Read-Line {
    # EVERY raw prompt in this file goes through here (not just Read-Choice/
    # Read-YesNo below) so 'm' - and 'cls' - are available with no
    # exceptions, on any prompt, instead of needing Ctrl+C to get a clean
    # terminal back.
    # -Redraw lets a menu function (Read-Choice, Show-MainMenu, ...) hand back
    # the scriptblock that printed its title/options, so 'cls' can replay it
    # after Clear-Host instead of leaving a blank screen with only the one-line
    # prompt on it - Clear-Host wipes everything Read-Line itself has no memory of.
    #
    # -Default / -AllowBack put a free-text prompt on the same footing as
    # Read-Choice and Read-YesNo: blank returns the default, 'b' returns
    # $script:BackSignal, and the prompt SAYS so. Both are opt-in so the
    # nested one-off prompts ("Which listed port number?") that already sit
    # under a menu keep rendering exactly as before instead of growing a
    # second, redundant nav hint.
    param(
        [string]$Prompt,
        [scriptblock]$Redraw,
        [string]$Default,
        [switch]$AllowBack
    )
    $bits = @()
    if ($PSBoundParameters.ContainsKey('Default') -and $Default -ne '') { $bits += "default $Default" }
    if ($AllowBack) { $bits += "'b' back" }
    $suffix = if ($bits.Count -gt 0) { " [{0}]" -f ($bits -join ', ') } else { '' }
    # The prompt text already ends in its own ': ' / '> ' - splice the hint in
    # ahead of that rather than tacking it on after, so the cursor still sits
    # at the end of the line where the operator types.
    $shown = $Prompt
    if ($suffix) {
        if ($Prompt -match '^(.*?)(\s*[:>]\s*)$') { $shown = $Matches[1] + $suffix + $Matches[2] }
        else { $shown = $Prompt + $suffix }
    }
    while ($true) {
        Write-Host -NoNewline $shown
        $raw = Read-Host
        if (Test-ClearScreenAnswer $raw) {
            Clear-Host
            if ($Redraw) { & $Redraw }
            continue
        }
        if (Test-MainMenuAnswer $raw) { Request-MainMenu }
        if ($AllowBack -and (Test-BackAnswer $raw)) { return $script:BackSignal }
        if ([string]::IsNullOrWhiteSpace($raw) -and $PSBoundParameters.ContainsKey('Default')) { return $Default }
        return $raw
    }
}

function Read-Choice {
    # Highlights the default option in green with a "<- default (press Enter)"
    # tag, same convention as run_wizard.ps1's Show-Menu -- kept in sync so a
    # sub-menu (Topology, Attack, Scenario, Location, ...) looks the same
    # whichever launcher it's answered from.
    param([string]$Title, [string[]]$Options, [int]$Default = 1, [switch]$AllowBack)
    # Captured as a scriptblock (not just run inline) so it can be handed to
    # Read-Line as -Redraw: 'cls' Clear-Hosts the whole screen, and this is the
    # only place that knows how to put the title/options back afterward.
    $draw = {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if (($i + 1) -eq $Default) {
                Write-Host ("   [{0}] {1}  <- default (press Enter)" -f ($i + 1), $Options[$i]) -ForegroundColor Green
            } else {
                Write-Host ("   [{0}] {1}" -f ($i + 1), $Options[$i])
            }
        }
    }
    & $draw
    $navHint = if ($AllowBack) { ", 'b' back, 'm' main menu, 'cls' clear" } else { ", 'm' main menu, 'cls' clear" }
    while ($true) {
        $ans = Read-Line ("Choice [default {0}]{1}: " -f $Default, $navHint) -Redraw $draw
        if ($AllowBack -and (Test-BackAnswer $ans)) { return $script:BackSignal }
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $Options.Count) { return [int]$ans }
        Write-Host ("   Enter a number 1..{0}." -f $Options.Count) -ForegroundColor Yellow
    }
}

function Read-YesNo {
    # Returns $true/$false normally, or $script:BackSignal when -AllowBack is
    # set and the operator typed 'b' - callers that opt in must check for that
    # sentinel before using the result as a bool.
    param([string]$Question, [bool]$Default = $true, [switch]$AllowBack)
    # Spells the default out ("default Y") instead of leaving it encoded in
    # which letter is capitalised -- Read-Choice announces "[default 1]" right
    # next to it, and two prompts in the same flow disagreeing about how loudly
    # they state their default is exactly the inconsistency this removes.
    if ($Default) { $hint = 'Y/n, default Y' } else { $hint = 'y/N, default N' }
    $navHint = if ($AllowBack) { ", 'b' back, 'm' main menu, 'cls' clear" } else { ", 'm' main menu, 'cls' clear" }
    while ($true) {
        $ans = Read-Line ("{0} [{1}]{2}: " -f $Question, $hint, $navHint)
        if ($AllowBack -and (Test-BackAnswer $ans)) { return $script:BackSignal }
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        $a = $ans.Trim().ToLower()
        if ($a -like 'y*') { return $true }
        if ($a -like 'n*') { return $false }
        Write-Host "   Please answer y or n." -ForegroundColor Yellow
    }
}

# Bright role colors for a black console background -- root/child/attacker at a
# glance in board summaries. Raw ANSI 24-bit escapes (named ConsoleColor values
# used elsewhere in this file can't express these exact hex values); Windows
# 10/11's default console and Windows Terminal both render them. Keep this block
# in sync with run_wizard.ps1's identical one.
$script:RoleAnsi = @{
    root     = "$([char]27)[38;2;254;189;23m"   # #FEBD17
    child    = "$([char]27)[38;2;27;192;186m"   # #1BC0BA
    attacker = "$([char]27)[38;2;253;184;217m"  # #FDB8D9
}
$script:AnsiReset = "$([char]27)[0m"

function Colorize-Role {
    param([string]$Text, [string]$Role)
    $key = if ($Role -eq 'root') { 'root' } elseif ($Role -eq 'attacker') { 'attacker' } else { 'child' }
    return "$($script:RoleAnsi[$key])$Text$script:AnsiReset"
}

function Invoke-Identify {
    # Reads the board's MAC via tools\board_check.py and names the node against
    # the project's known-board roster (same tool run_wizard.ps1 uses for its
    # own "identify a port" - kept in sync so both launchers report the same
    # MAC/name tag). Resets the chip to read the MAC, same as any other
    # port-touching action.
    param([string]$TargetPort)
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

function Select-Port {
    # Loops (rather than returning right away) so picking "identify" shows the
    # MAC/name tag and comes straight back to the same port list instead of
    # ending selection - same identify workflow as run_wizard.ps1's Select-Port,
    # kept in sync so the UI matches between launchers. Uses Get-PortList (not
    # raw GetPortNames) so a BLOCKED device (Bluetooth, a mouse receiver, ...)
    # is never even listed, and an UNKNOWN one has to be confirmed by typing
    # its own port name back before it's returned - see Test-PortSafeToTouch.
    param([switch]$AllowBack, [string]$Action = 'talk to this port')
    while ($true) {
        $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
        if ($ports.Count -eq 0) {
            Write-Host "   (No usable COM ports detected. Is the board plugged in?)" -ForegroundColor Yellow
            $manual = Read-Line "Enter COM port (e.g. COM8): "
            if ($manual -and -not (Test-PortSafeToTouch -Port $manual -Action $Action)) { continue }
            return $manual
        }

        $opts = @($ports | ForEach-Object {
            $macTag  = if ($script:IdentifiedPorts.ContainsKey($_.Port)) { "  [{0}]" -f $script:IdentifiedPorts[$_.Port] } else { '' }
            $kindTag = if ($_.Kind -eq 'UNKNOWN') { ' [UNKNOWN - confirm this is really the board]' } else { '' }
            "$($_.Port)  ($($_.Description))$macTag$kindTag"
        })
        $identifyOneIdx = $ports.Count + 1
        $identifyAllIdx = $ports.Count + 2
        $manualIdx      = $ports.Count + 3
        $opts += 'identify a port (reads its MAC)'
        $opts += 'identify ALL listed ports (reads each one in turn, takes a while)'
        $opts += 'Type it manually'

        $idx = Read-Choice -Title "Which COM port (board)?" -Options $opts -Default 1 -AllowBack:$AllowBack
        if ($idx -eq $script:BackSignal) { return $script:BackSignal }

        if ($idx -eq $identifyOneIdx) {
            $which = Read-Line "  Which listed port number? "
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $ports.Count) {
                Invoke-Identify -TargetPort $ports[$wn - 1].Port
            } else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }
        if ($idx -eq $identifyAllIdx) {
            foreach ($p in $ports) {
                Write-Host ("Identifying {0} ..." -f $p.Port) -ForegroundColor DarkGray
                Invoke-Identify -TargetPort $p.Port
            }
            continue
        }
        if ($idx -eq $manualIdx) {
            $manual = (Read-Line "Enter COM port (e.g. COM8): ").Trim().ToUpper()
            if ($manual -and -not (Test-PortSafeToTouch -Port $manual -Action $Action)) { continue }
            return $manual
        }
        if (-not (Test-PortSafeToTouch -Port $ports[$idx - 1].Port -Action $Action)) { continue }
        return $ports[$idx - 1].Port
    }
}

function Get-LocationList {
    # The one list of sites, so Select-Location (export folder) and the
    # write-location-to-a-board flow further down can never offer different
    # sets. Keep in sync with run.ps1's -Location ValidateSet and with
    # run_wizard.ps1's $LOCATIONS.
    return ,@('home', 'G402', 'DLSU_Library', 'Goks')
}

function Select-Location {
    # run.ps1 requires -Location whenever -Export/-Clean/-Analyze is used, so
    # any flow that can export asks this. Keep the ValidateSet in run.ps1 in sync.
    # -Current is the previously-picked value, so a step machine re-asking this
    # after a 'b' offers what was already chosen rather than resetting to home.
    param([string]$Current, [switch]$AllowBack)
    $locs = Get-LocationList
    $def  = [array]::IndexOf($locs, $Current) + 1
    if ($def -lt 1) { $def = 1 }
    $idx  = Read-Choice -Title "Where was this run captured?" -Options $locs -Default $def -AllowBack:$AllowBack
    if ($script:BackSignal -eq $idx) { return $script:BackSignal }
    return $locs[$idx - 1]
}

function Select-Scenario {
    # Run-to-run variation the panel asked for. 'none' is byte-identical to the
    # old behaviour. Keep this option list in sync with run.ps1's ValidateSet.
    param([string]$Current, [switch]$AllowBack)
    $opts = @(
        'none        (today''s behaviour -- no variation)',
        'burst       (CODE: one child fires 100 probes back-to-back in the attack window)',
        'highload    (CODE: every child probes 4x faster for the whole run)',
        'mobility    (HUMAN: you move one child from spot A to spot B -- checklist only)',
        'powercycle  (HUMAN: you unplug/replug one child -- checklist only)'
    )
    $vals = @('none', 'burst', 'highload', 'mobility', 'powercycle')
    $def  = [array]::IndexOf($vals, $Current) + 1
    if ($def -lt 1) { $def = 1 }
    $idx = Read-Choice -Title "Scenario for this run (every board in the run gets the SAME one)?" -Options $opts -Default $def -AllowBack:$AllowBack
    if ($script:BackSignal -eq $idx) { return $script:BackSignal }
    return $vals[$idx - 1]
}

function Test-ScenarioNeedsTarget {
    # burst/mobility/powercycle need exactly ONE child picked as the subject
    # (the sender / the node moved / the node power-cycled). highload applies
    # to every child automatically; none needs nothing.
    param([string]$Scenario)
    return $Scenario -in @('burst', 'mobility', 'powercycle')
}

function Select-SdCard {
    # A pulled card mirrors the exports tree (<attack>/<topology>/<location>/),
    # so a drive whose ROOT holds any of these folders is almost certainly one of
    # ours. Same rule as run_wizard.ps1's Get-SdCardCandidates -- keep in sync.
    param([switch]$AllowBack)
    $markers = @('baseline', 'blackhole', 'wormhole')
    $opts  = @()
    $roots = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $root = "$($d.Name):\"
        if (-not (Test-Path $root)) { continue }
        $looks = @($markers | Where-Object { Test-Path (Join-Path $root $_) }).Count -gt 0
        $roots += $root
        if ($looks) { $opts += ("{0}  <- looks like a card ({1} folder present)" -f $root, ($markers -join '/')) }
        else        { $opts += $root }
    }
    $opts += 'Type a path manually'

    $idx = Read-Choice -Title "Which card? (insert it first)" -Options $opts -Default 1 -AllowBack:$AllowBack
    if ($script:BackSignal -eq $idx) { return $script:BackSignal }
    if ($idx -eq $opts.Count) { return (Read-Line "Card path (e.g. E:\): " -AllowBack:$AllowBack) }
    return $roots[$idx - 1]
}

function Show-And-Confirm {
    # Single choke point every action in this file funnels through before it
    # touches a board or writes a file - locking 'm' out HERE, once, on a "yes",
    # covers all of them instead of needing a lock line at each call site.
    param([string]$CommandText)
    Write-Host ""
    Write-Host "Equivalent command:" -ForegroundColor DarkGray
    Write-Host ("   " + $CommandText) -ForegroundColor White
    $go = Read-YesNo -Question "Run this now?" -Default $true
    if ($go) { $script:NavLocked = $true }
    return $go
}

# ---- blackhole attacker-MAC pre-flight (ported from run_wizard.ps1) ---------
# BLACKHOLE_ATTACKER_MAC is baked into the VICTIM firmware at BUILD time. If it
# doesn't match whichever physical board is actually wearing the "attacker"
# role right now (boards get swapped between COM ports/roles across sessions),
# every victim probe gets addressed to a MAC nothing in the mesh holds -- it
# never routes anywhere, so the ROOT logs ZERO arrivals for the ENTIRE run
# (baseline included, not just the attack phase) and every blackhole feature
# (ForwardingRatio/PDR/ConsistencyScore) comes out all-NaN with no error to
# point at why. This check catches that BEFORE any flashing happens.

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

function Get-LiveBoardMac {
    # Reads the chip's eFuse MAC over serial via tools\Get-EspMac.ps1 (wraps
    # esptool read_mac) -- no flashing, works even on a blank/factory board.
    # NOTE: param is deliberately NOT called $Port -- dot-sourcing the tool
    # runs its own param([string]$Port,...) block in THIS scope and would
    # blank out a variable of that name before we got to use it.
    param([string]$TargetPort)
    $tool = Join-Path $base 'tools\Get-EspMac.ps1'
    if (-not (Test-Path $tool)) { return $null }
    try {
        . $tool                              # dot-source: loads the function, runs nothing
        $r = Get-EspMac -Port $TargetPort
        if ($r -and $r.MAC) { return ([string]$r.MAC).ToLower() }
    }
    catch { return $null }
    return $null
}

function Resolve-BoardMac {
    # Best-effort MAC for the plan table: prefer what's already known (this
    # session's Invoke-Identify cache, or a board this flow already read, e.g.
    # the blackhole attacker via Confirm-BlackholeAttackerMac -Board) over
    # reading the chip again - Get-LiveBoardMac/Invoke-Identify briefly reset
    # the board, and every board here is about to be flashed anyway so a fresh
    # read is harmless, but a cached value is free. Caches a fresh read back
    # onto $Board.Mac so it isn't re-read later in the same flow.
    param($Board)
    if ($Board.Mac) { return $Board.Mac }
    if ($script:IdentifiedPorts.ContainsKey($Board.Port)) {
        $cached = $script:IdentifiedPorts[$Board.Port]
        $mac = ($cached -split ' -> ')[0].Trim()
        if ($mac -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$') { return $mac.ToLower() }
    }
    $mac = Get-LiveBoardMac -TargetPort $Board.Port
    if ($mac) { $Board.Mac = $mac }
    return $mac
}

function Confirm-BlackholeAttackerMac {
    # Cross-checks mesh_config.h's compiled BLACKHOLE_ATTACKER_MAC against the
    # ATTACKER board's ACTUAL live MAC (read over serial, no custom firmware
    # needed), before any build/flash happens. Offers to auto-fix the header
    # right here so the very next build picks up the correction.
    # -Board is optional: when the caller has the board object (the multi-board
    # flow does), the live MAC read here is cached onto it via Resolve-BoardMac
    # so the plan table's MAC column doesn't read the chip a second time.
    param([string]$AttackerPort, [string]$AttackerLabel = $null, $Board = $null)

    $want = Get-ConfiguredAttackerMac
    Write-Host ""
    Write-Host "Checking BLACKHOLE_ATTACKER_MAC against $AttackerPort's live MAC ..." -ForegroundColor DarkGray
    if (-not $want) {
        Write-Host "   Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h -- skipping check." -ForegroundColor Yellow
        return
    }
    $live = Get-LiveBoardMac -TargetPort $AttackerPort
    if ($live -and $Board) { $Board.Mac = $live }
    if (-not $live) {
        Write-Host "   Could not read $AttackerPort's live MAC (port busy / board unplugged?) -- skipping check." -ForegroundColor Yellow
        Write-Host "   mesh_config.h currently targets: $want -- double-check by eye before flashing victims." -ForegroundColor Yellow
        return
    }
    if ($live -eq $want) {
        Write-Host "   OK -- $AttackerPort ($live) matches mesh_config.h. Victims will reach this board." -ForegroundColor Green
        return
    }

    $lbl = if ($AttackerLabel) { $AttackerLabel } else { $AttackerPort }
    Write-Host ""
    Write-Host "   MISMATCH: mesh_config.h BLACKHOLE_ATTACKER_MAC = $want" -ForegroundColor Red
    Write-Host "              but $AttackerPort's actual live MAC  = $live" -ForegroundColor Red
    Write-Host "   Victim probes are compiled to target $want. With nothing in the mesh at that" -ForegroundColor Red
    Write-Host "   address they get 'no route found' and vanish for the WHOLE run (baseline" -ForegroundColor Red
    Write-Host "   included, not just the attack phase) -- root logs zero arrivals and every" -ForegroundColor Red
    Write-Host "   blackhole feature comes out all-NaN, with nothing to point at why." -ForegroundColor Red
    if (Read-YesNo -Question "   Fix mesh_config.h now (point BLACKHOLE_ATTACKER_MAC at $live)?" -Default $true) {
        if (Set-ConfiguredAttackerMac -Mac $live -PortLabel $lbl) {
            Write-Host "   Fixed -- mesh_config.h now targets $live. The next build will pick it up." -ForegroundColor Green
        } else {
            Write-Host "   Could not write mesh_config.h -- fix it by hand before flashing the victim(s)." -ForegroundColor Red
        }
    } else {
        Write-Host "   Left as-is -- victim boards will still target the wrong MAC until this is fixed." -ForegroundColor Yellow
    }
}

# ---- multi-board helpers (ported/trimmed from run_wizard.ps1) ---------------

function Get-RunDirs {
    # The attack/topology folder names the whole pipeline agrees on. 'none' files
    # under baseline\ and 'partial' under partial_mesh\ - these MUST stay
    # byte-identical to _subdir_for()/_TOPOLOGY_DIR in tools\export_logs.py and to
    # s_attack_dirs/s_topo_dirs in components\mesh_common\src\sd_status.c. Kept in
    # sync with run_wizard.ps1's identical function.
    param([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario = 'none')
    $attackDir = $Attack
    if ($Attack -eq 'none') { $attackDir = 'baseline' }
    $topoDir = switch ($Topology) {
        'star'    { 'star' }
        'tree'    { 'tree' }
        'linear'  { 'linear' }
        'partial' { 'partial_mesh' }
    }
    $scenarioSeg = if ($Scenario -and $Scenario -ne 'none') { "\$Scenario" } else { '' }
    return [pscustomobject]@{
        AttackDir = $attackDir
        TopoDir   = $topoDir
        Export    = (Join-Path $base "tools\exports\$attackDir\$topoDir\$Location$scenarioSeg")
        Analysis  = (Join-Path $base "analysis\$attackDir\$topoDir\$Location$scenarioSeg")
    }
}

function Get-PortKind {
    # Classifies a COM device by its driver description so a batch of boards
    # never includes something that isn't an ESP32 (this machine shows
    # Bluetooth on COM4/COM5) -- esptool's first move is to yank DTR/RTS and
    # shove the device into a bootloader handshake it was never designed for.
    # Trimmed straight from run_wizard.ps1's Get-PortKind; keep the deny-
    # before-allow order if this ever needs to change.
    param([string]$Description)
    $d = [string]$Description
    $deny = @(
        'bluetooth', 'logitech', 'logi ', 'unifying', 'lightspeed',
        'printer', 'modem', 'fax', 'scanner',
        'mouse', 'keyboard', 'gamepad', 'joystick', 'headset', 'audio', 'webcam', 'camera',
        'hub', 'smartcard', 'smart card', 'fingerprint',
        'intel(r) active management', 'amt ', 'virtual machine', 'vmware', 'hyper-v'
    )
    foreach ($k in $deny) { if ($d -like "*$k*") { return 'BLOCKED' } }
    $allow = @(
        'cp210', 'cp 210', 'silicon labs',
        'ch340', 'ch341', 'ch910', 'wch',
        'ftdi', 'ft232', 'ft231', 'future technology',
        'prolific', 'pl2303',
        'usb-serial', 'usb serial', 'usb to uart', 'usb-to-uart', 'usb-enhanced-serial'
    )
    foreach ($k in $allow) { if ($d -like "*$k*") { return 'BRIDGE' } }
    return 'UNKNOWN'
}

function Get-PortList {
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

function Test-PortSafeToTouch {
    # The single gate in front of anything that opens or resets a port (esptool
    # erase/MAC read, export_logs GET/SET_LOCATION) - ported from run_wizard.ps1's
    # identical function, kept in sync so a device gets the same protection
    # whichever launcher touches it. Returns $true only if it's safe, or the
    # operator has explicitly vouched for an unrecognised port by typing its
    # name back.
    param([string]$Port, [string]$Action = 'talk to this port')
    $known = @(Get-PortList | Where-Object { $_.Port -eq $Port }) | Select-Object -First 1
    $kind  = if ($known) { $known.Kind } else { 'UNKNOWN' }
    $desc  = if ($known) { $known.Description } else { 'not currently enumerated' }

    if ($kind -eq 'BRIDGE') { return $true }

    if ($kind -eq 'BLOCKED') {
        Write-Host ""
        Write-Host ("REFUSED: {0} is '{1}'." -f $Port, $desc) -ForegroundColor Red
        Write-Host ("That is not an ESP32, so this will not {0}." -f $Action) -ForegroundColor Red
        Write-Host "esptool resets a port by pulling DTR/RTS, which other USB hardware is" -ForegroundColor Red
        Write-Host "not built to survive. Unplug it or pick a real board instead." -ForegroundColor Red
        return $false
    }

    Write-Host ""
    Write-Host ("{0} is '{1}' -- not a recognised USB-to-UART bridge." -f $Port, $desc) -ForegroundColor Yellow
    Write-Host ("If it is NOT one of your ESP32s, this could {0} the wrong device." -f $Action) -ForegroundColor Yellow
    $ans = Read-Line ("  Type the port name ({0}) to confirm it IS your board, anything else to skip: " -f $Port)
    if ($ans.Trim().ToUpper() -eq $Port.ToUpper()) { return $true }

    Write-Host ("  Skipped {0} -- not confirmed." -f $Port) -ForegroundColor DarkGray
    return $false
}

function Select-BoardPort {
    # Like Select-Port, but filters to ESP32-shaped bridges (BLOCKED never
    # shown) and refuses a port already claimed by an earlier board in this
    # same multi-board plan. Same identify workflow as Select-Port above /
    # run_wizard.ps1's Select-Port - loops so "identify" comes back to the
    # same list with the MAC/name tag now showing, instead of ending selection.
    # An UNKNOWN pick (numbered or typed manually) still has to clear
    # Test-PortSafeToTouch before it's returned.
    param([string[]]$Taken = @(), [switch]$AllowBack, [string]$Action = 'flash it')
    while ($true) {
        $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' -and ($Taken -notcontains $_.Port) })
        if ($ports.Count -eq 0) {
            Write-Host "   (No usable COM ports detected -- plugged in? already used by another board in this plan?)" -ForegroundColor Yellow
            $manual = (Read-Line "Enter COM port (e.g. COM8): ").Trim().ToUpper()
            if ($manual -and -not (Test-PortSafeToTouch -Port $manual -Action $Action)) { continue }
            return $manual
        }
        $opts = @($ports | ForEach-Object {
            $macTag  = if ($script:IdentifiedPorts.ContainsKey($_.Port)) { "  [{0}]" -f $script:IdentifiedPorts[$_.Port] } else { '' }
            $kindTag = if ($_.Kind -eq 'UNKNOWN') { ' [UNKNOWN - confirm this is really the board]' } else { '' }
            "$($_.Port)  ($($_.Description))$macTag$kindTag"
        })
        $identifyOneIdx = $ports.Count + 1
        $identifyAllIdx = $ports.Count + 2
        $manualIdx      = $ports.Count + 3
        $opts += 'identify a port (reads its MAC)'
        $opts += 'identify ALL listed ports (reads each one in turn, takes a while)'
        $opts += 'Type it manually'

        $idx = Read-Choice -Title "Which COM port (board)?" -Options $opts -Default 1 -AllowBack:$AllowBack
        if ($idx -eq $script:BackSignal) { return $script:BackSignal }

        if ($idx -eq $identifyOneIdx) {
            $which = Read-Line "  Which listed port number? "
            $wn = 0
            if ([int]::TryParse($which, [ref]$wn) -and $wn -ge 1 -and $wn -le $ports.Count) {
                Invoke-Identify -TargetPort $ports[$wn - 1].Port
            } else { Write-Host "  Invalid number." -ForegroundColor Yellow }
            continue
        }
        if ($idx -eq $identifyAllIdx) {
            foreach ($p in $ports) {
                Write-Host ("Identifying {0} ..." -f $p.Port) -ForegroundColor DarkGray
                Invoke-Identify -TargetPort $p.Port
            }
            continue
        }
        if ($idx -eq $manualIdx) {
            $manual = (Read-Line "Enter COM port (e.g. COM8): ").Trim().ToUpper()
            if ($manual -and -not (Test-PortSafeToTouch -Port $manual -Action $Action)) { continue }
            return $manual
        }
        if (-not (Test-PortSafeToTouch -Port $ports[$idx - 1].Port -Action $Action)) { continue }
        return $ports[$idx - 1].Port
    }
}

function Format-BoardCmdText {
    # Single source of truth for a board's run.ps1 command line, rebuilt from
    # its Params hashtable. Used by Edit-BoardInteractive so CmdText can never
    # drift out of sync with what will actually run after a field changes.
    # Field order matches the add-board loop in the multi-board flow above --
    # keep both in sync.
    param([hashtable]$Params)
    $cmd = ".\run.ps1 -Port $($Params.Port) -Role $($Params.Role) -Topology $($Params.Topology) -Attack $($Params.Attack) -Scenario $($Params.Scenario)"
    if ($Params.ContainsKey('Label') -and $Params.Label) { $cmd += " -Label $($Params.Label)" }
    if ($Params.ContainsKey('BlackholeRole'))             { $cmd += " -BlackholeRole $($Params.BlackholeRole)" }
    if ($Params.ContainsKey('WormholeEnd'))               { $cmd += " -WormholeEnd $($Params.WormholeEnd)" }
    if ($Params.ContainsKey('ScenarioTarget'))            { $cmd += ' -ScenarioTarget' }
    if ($Params.ContainsKey('Wipe'))                      { $cmd += ' -Wipe' }
    if ($Params.ContainsKey('Flash'))                     { $cmd += ' -Flash' }
    if ($Params.ContainsKey('Export'))                    { $cmd += " -Export -Location $($Params.Location)" }
    if ($Params.ContainsKey('Clean'))                     { $cmd += ' -Clean' }
    if ($Params.ContainsKey('Analyze'))                   { $cmd += ' -Analyze' }
    return $cmd
}

function Get-ReorderedBoards {
    # Children first, root last. Re-run this any time Role could have
    # changed (a root-swap edit), not just once after the add-board loop --
    # everything downstream (the printed plan, per-board confirm, pre-build,
    # spawn) reads whatever order $boards is in.
    param($Boards)
    $children  = @($Boards | Where-Object { $_.Role -ne 'root' })
    $rootBoard = $Boards | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1
    $ordered = @($children)
    if ($rootBoard) { $ordered += $rootBoard }
    # Comma operator, not a bare return: `return $ordered` UNROLLS a
    # one-element array into a scalar PSCustomObject, and a caller that then
    # does `$boards += $new` (adding a board from the plan-adjust menu) dies
    # with "does not contain a method named 'op_Addition'" -- while
    # $boards.Count silently reads as $null, mislabelling the next board.
    return ,$ordered
}

function Show-PlanWarnings {
    # Sanity warnings (non-fatal), factored out so both the initial plan and
    # every post-edit reprint show the same checks against current reality --
    # including re-confirming BLACKHOLE_ATTACKER_MAC if the attacker board
    # changed, the exact failure mode that cost a full run twice (see
    # Confirm-BlackholeAttackerMac above).
    param($Boards, [string]$Attack, [string]$Scenario)
    $haveRootLocal = (@($Boards | Where-Object { $_.Role -eq 'root' })).Count -gt 0
    if (-not $haveRootLocal) { Write-Host "`nWARNING: no ROOT board in this plan -- a mesh needs exactly one." -ForegroundColor Yellow }
    if ($Attack -eq 'wormhole') {
        $aCount = (@($Boards | Where-Object { $_.Params.WormholeEnd -eq 'A' })).Count
        $bCount = (@($Boards | Where-Object { $_.Params.WormholeEnd -eq 'B' })).Count
        if ($aCount -ne 1 -or $bCount -ne 1) { Write-Host "`nWARNING: wormhole needs exactly one A and one B tunnel end (found A=$aCount B=$bCount)." -ForegroundColor Yellow }
    }
    if ($Attack -eq 'blackhole') {
        $atkBoard = $Boards | Where-Object { $_.Params.BlackholeRole -eq 'attacker' } | Select-Object -First 1
        $atkCount = (@($Boards | Where-Object { $_.Params.BlackholeRole -eq 'attacker' })).Count
        if ($atkCount -ne 1) {
            Write-Host "`nWARNING: blackhole normally wants exactly one attacker board (found $atkCount)." -ForegroundColor Yellow
        } else {
            $atkLbl = if ($atkBoard.Label) { $atkBoard.Label } else { $atkBoard.Port }
            Confirm-BlackholeAttackerMac -AttackerPort $atkBoard.Port -AttackerLabel $atkLbl -Board $atkBoard
        }
    }
    $haveTargetLocal = (@($Boards | Where-Object { $_.Params.ScenarioTarget })).Count -gt 0
    if ((Test-ScenarioNeedsTarget $Scenario) -and -not $haveTargetLocal) {
        Write-Host "`nWARNING: -Scenario $Scenario needs exactly one board marked as the target (none was) -- go back and add one, or the scenario won't do anything." -ForegroundColor Yellow
    }
}

function Edit-BoardInteractive {
    # Per-node edit reached from the pre-flash plan summary. Always operates on
    # ONE board the operator picked by number (never a blind apply-to-all --
    # same hardware-safety convention as the rest of this file); every change
    # is applied immediately and the field list redraws showing the new value,
    # then the caller reprints the whole plan so the effect is visible before
    # anything is confirmed/touched.
    param(
        [Parameter(Mandatory)][pscustomobject]$Board,
        [Parameter(Mandatory)]$Boards,
        [Parameter(Mandatory)][string]$Attack,
        [Parameter(Mandatory)][string]$Scenario
    )

    while ($true) {
        $lbl = if ($Board.Label) { $Board.Label } else { $Board.Port }
        Write-Host ""
        Write-Host ("Editing node: {0}  ({1}, {2})" -f $lbl, $Board.Port, $Board.Role) -ForegroundColor Cyan

        $fields = @()
        $fields += @{ Key = 'Role';  Text = "Role               $($Board.Role)" }
        $fields += @{ Key = 'Port';  Text = "Port               $($Board.Port)" }
        $fields += @{ Key = 'Label'; Text = "Label              $(if ($Board.Label) { $Board.Label } else { '(none)' })" }
        if ($Attack -eq 'blackhole' -and $Board.Role -ne 'root') {
            $fields += @{ Key = 'BlackholeRole'; Text = "Blackhole role     $($Board.Params.BlackholeRole)" }
        }
        if ($Attack -eq 'wormhole' -and $Board.Role -ne 'root') {
            $fields += @{ Key = 'WormholeEnd'; Text = "Wormhole end       $($Board.Params.WormholeEnd)" }
        }
        if ((Test-ScenarioNeedsTarget $Scenario) -and $Board.Role -ne 'root') {
            $onOff = if ($Board.Params.ContainsKey('ScenarioTarget')) { 'Yes' } else { 'No' }
            $fields += @{ Key = 'ScenarioTarget'; Text = "Scenario target    $onOff" }
        }
        $wipeOnOff   = if ($Board.Params.ContainsKey('Wipe'))   { 'Yes' } else { 'No' }
        $flashOnOff  = if ($Board.Params.ContainsKey('Flash'))  { 'Yes' } else { 'No' }
        $exportOnOff = if ($Board.Params.ContainsKey('Export')) { "Yes (-> $($Board.Params.Location))" } else { 'No' }
        $cleanOnOff  = if ($Board.Params.ContainsKey('Clean'))  { 'Yes' } else { 'No' }
        $fields += @{ Key = 'Wipe';   Text = "Wipe               $wipeOnOff" }
        $fields += @{ Key = 'Flash';  Text = "Flash              $flashOnOff" }
        $fields += @{ Key = 'Export'; Text = "Export             $exportOnOff" }
        $fields += @{ Key = 'Clean';  Text = "Wipe after export  $cleanOnOff" }

        $opts = @($fields | ForEach-Object { $_.Text })
        $opts += 'Done editing this node'
        $idx = Read-Choice -Title "Which field?" -Options $opts -Default $opts.Count
        if ($idx -eq $opts.Count) { break }

        switch ($fields[$idx - 1].Key) {
            'Role' {
                # Exactly one root, always -- so "change this board's role" is
                # really "pick which board should be root": promoting one
                # implicitly demotes whichever board holds it now. Mirrors the
                # add-board loop's own root/child question, just re-run here.
                $opts2 = @($Boards | ForEach-Object {
                    $lbl2 = if ($_.Label) { $_.Label } else { $_.Port }
                    $tag  = if ($_.Role -eq 'root') { '  (current root)' } else { '' }
                    "$lbl2  ($($_.Port))$tag"
                })
                $curRootIdx = 1
                for ($ri = 0; $ri -lt $Boards.Count; $ri++) { if ($Boards[$ri].Role -eq 'root') { $curRootIdx = $ri + 1 } }
                $newRootIdx = Read-Choice -Title "Which board should be ROOT?" -Options $opts2 -Default $curRootIdx
                $newRoot = $Boards[$newRootIdx - 1]

                if ($newRoot.Role -eq 'root') {
                    Write-Host "   Already root -- unchanged." -ForegroundColor Yellow
                } else {
                    $oldRoot = $Boards | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1

                    if ($oldRoot) {
                        $oldRoot.Role = 'child'
                        $oldRoot.Params['Role'] = 'child'
                        $oldRoot.Params.Remove('Analyze') | Out-Null
                        # Demoted board needs an attack sub-role if this run has
                        # one -- default to the harmless side; editable afterward
                        # via this same menu's BlackholeRole/WormholeEnd field.
                        if ($Attack -eq 'blackhole' -and -not $oldRoot.Params.ContainsKey('BlackholeRole')) {
                            $oldRoot.Params['BlackholeRole'] = 'victim'
                        }
                        if ($Attack -eq 'wormhole' -and -not $oldRoot.Params.ContainsKey('WormholeEnd')) {
                            $oldRoot.Params['WormholeEnd'] = 'B'
                        }
                        $oldRoot.CmdText = Format-BoardCmdText -Params $oldRoot.Params
                    }

                    $newRoot.Role = 'root'
                    $newRoot.Params['Role'] = 'root'
                    $newRoot.Params.Remove('BlackholeRole')  | Out-Null
                    $newRoot.Params.Remove('WormholeEnd')    | Out-Null
                    $newRoot.Params.Remove('ScenarioTarget') | Out-Null
                    if ($newRoot.Params.ContainsKey('Export')) { $newRoot.Params['Analyze'] = $true }
                    $newRoot.CmdText = Format-BoardCmdText -Params $newRoot.Params

                    $oldLbl = if ($oldRoot) { if ($oldRoot.Label) { $oldRoot.Label } else { $oldRoot.Port } } else { '(none)' }
                    $newLbl = if ($newRoot.Label) { $newRoot.Label } else { $newRoot.Port }
                    Write-Host ("   {0} is now ROOT; {1} is now a child." -f $newLbl, $oldLbl) -ForegroundColor Green
                }
                # $Board itself may have just been demoted/promoted -- its Role
                # in the "Editing node: ..." header above updates next loop turn.
            }
            'Port' {
                $taken = @($Boards | Where-Object { $_ -ne $Board } | ForEach-Object { $_.Port })
                $new = Select-BoardPort -Taken $taken
                if ($new) {
                    $Board.Port = $new
                    $Board.Params['Port'] = $new
                    $Board.Kind = (Get-PortList | Where-Object { $_.Port -eq $new } | Select-Object -First 1).Kind
                }
            }
            'Label' {
                $new = Read-Line "New label (blank to clear): "
                if ($new -and $new -notmatch '^[A-Za-z0-9_\-]+$') {
                    Write-Host "   Label must be letters/digits/_/- only -- unchanged." -ForegroundColor Yellow
                } elseif ($new) {
                    $Board.Label = $new; $Board.Params['Label'] = $new
                } else {
                    $Board.Label = $null; $Board.Params.Remove('Label') | Out-Null
                }
            }
            'BlackholeRole' {
                $bhDefault = if ($Board.Params.BlackholeRole -eq 'victim') { 2 } else { 1 }
                $i = Read-Choice -Title "Blackhole role of THIS board?" -Options @(
                    'attacker  (relay that forwards then drops victim probes)',
                    'victim    (sends its probes to the attacker MAC)'
                ) -Default $bhDefault
                $Board.Params['BlackholeRole'] = if ($i -eq 2) { 'victim' } else { 'attacker' }
            }
            'WormholeEnd' {
                $wDefault = if ($Board.Params.WormholeEnd -eq 'A') { 1 } else { 2 }
                $i = Read-Choice -Title "Wormhole tunnel end of THIS board?" -Options @(
                    'A  (exit / root-side: re-injects to root)',
                    'B  (entry / leaf-side: captures + tunnels)'
                ) -Default $wDefault
                $Board.Params['WormholeEnd'] = if ($i -eq 1) { 'A' } else { 'B' }
            }
            'ScenarioTarget' {
                if ($Board.Params.ContainsKey('ScenarioTarget')) {
                    $Board.Params.Remove('ScenarioTarget') | Out-Null
                } else {
                    $already = $Boards | Where-Object { $_ -ne $Board -and $_.Params.ContainsKey('ScenarioTarget') } | Select-Object -First 1
                    if ($already) {
                        $aLbl = if ($already.Label) { $already.Label } else { $already.Port }
                        Write-Host ("   {0} is already the $Scenario target -- edit it first to clear that." -f $aLbl) -ForegroundColor Yellow
                    } else {
                        $Board.Params['ScenarioTarget'] = $true
                    }
                }
            }
            'Wipe' {
                if ($Board.Params.ContainsKey('Wipe')) { $Board.Params.Remove('Wipe') | Out-Null } else { $Board.Params['Wipe'] = $true }
            }
            'Flash' {
                if ($Board.Params.ContainsKey('Flash')) { $Board.Params.Remove('Flash') | Out-Null } else { $Board.Params['Flash'] = $true }
            }
            'Export' {
                if ($Board.Params.ContainsKey('Export')) {
                    $Board.Params.Remove('Export') | Out-Null
                    $Board.Params.Remove('Location') | Out-Null
                    $Board.Params.Remove('Clean') | Out-Null
                    if ($Board.Role -eq 'root' -and $Board.Params.ContainsKey('Analyze')) {
                        Write-Host "   Export off -- also dropping -Analyze (needs exported CSVs)." -ForegroundColor Yellow
                        $Board.Params.Remove('Analyze') | Out-Null
                    }
                } else {
                    $Board.Params['Export'] = $true
                    $Board.Params['Location'] = Select-Location
                    if ($Board.Role -eq 'root') { $Board.Params['Analyze'] = $true }
                }
            }
            'Clean' {
                if (-not $Board.Params.ContainsKey('Export')) {
                    Write-Host "   Turn Export on first -- wipe-after-export needs something to export." -ForegroundColor Yellow
                } elseif ($Board.Params.ContainsKey('Clean')) {
                    $Board.Params.Remove('Clean') | Out-Null
                } else {
                    $Board.Params['Clean'] = $true
                }
            }
        }
        $Board.CmdText = Format-BoardCmdText -Params $Board.Params
    }
}

function Add-BoardInteractive {
    # Collects ONE new board for the multi-board plan (port/role/attack
    # sub-role/scenario-target/label) -- Wipe/Flash/Export/Clean are run-wide
    # toggles the caller already asked once, so they're applied by the caller
    # afterward via Format-BoardCmdText, same as Edit-BoardInteractive does.
    # Used both by the initial "add boards one at a time" loop and by the
    # post-summary "Add another board" adjustment, so a board added late goes
    # through the exact same Qs.
    #
    # -AllowBack threads through every sub-prompt: hitting 'b' at ANY of them
    # abandons just THIS board (nothing is appended to $Boards) and returns
    # $script:BackSignal, instead of the only escape being 'm' (which nukes
    # every board collected so far). haveRoot/haveScenarioTarget are derived
    # fresh from $Boards each call rather than tracked as running state, so an
    # abandoned board never leaves a phantom "root already taken" behind.
    param(
        [Parameter(Mandatory)][string]$Topo,
        [Parameter(Mandatory)][string]$Attack,
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)]$Boards,
        [switch]$AllowBack
    )

    # Normalised up front: a caller can hand us a single board that PowerShell
    # already unrolled to a scalar, whose .Count reads as $null and would
    # label the next board "Board 1" on top of an existing one.
    $existing           = @($Boards)
    $haveRoot           = [bool]@($existing | Where-Object { $_.Role -eq 'root' }).Count
    $haveScenarioTarget = [bool]@($existing | Where-Object { $_.Params.ContainsKey('ScenarioTarget') }).Count

    Write-Host ""
    Write-Host ("--- Board {0} " -f ($existing.Count + 1)) -ForegroundColor Cyan
    $taken = @($existing | ForEach-Object { $_.Port })
    $port  = Select-BoardPort -Taken $taken -AllowBack:$AllowBack
    if ($port -eq $script:BackSignal) { return $script:BackSignal }

    $roleOpts = if ($haveRoot) { @('child / victim') } else { @('root', 'child / victim') }
    $roleIdx  = Read-Choice -Title "Mesh role of THIS board?" -Options $roleOpts -Default 1 -AllowBack:$AllowBack
    if ($roleIdx -eq $script:BackSignal) { return $script:BackSignal }
    $role = if (-not $haveRoot -and $roleIdx -eq 1) { 'root' } else { 'child' }

    $bhRole = 'attacker'
    $wEnd   = 'B'
    if ($Attack -eq 'blackhole' -and $role -ne 'root') {
        $i = Read-Choice -Title "Blackhole role of THIS board?" -Options @(
            'attacker  (relay that forwards then drops victim probes)',
            'victim    (sends its probes to the attacker MAC)'
        ) -Default 1 -AllowBack:$AllowBack
        if ($i -eq $script:BackSignal) { return $script:BackSignal }
        if ($i -eq 2) { $bhRole = 'victim' } else { $bhRole = 'attacker' }
    }
    if ($Attack -eq 'wormhole' -and $role -ne 'root') {
        $i = Read-Choice -Title "Wormhole tunnel end of THIS board?" -Options @(
            'A  (exit / root-side: re-injects to root)',
            'B  (entry / leaf-side: captures + tunnels)'
        ) -Default 2 -AllowBack:$AllowBack
        if ($i -eq $script:BackSignal) { return $script:BackSignal }
        if ($i -eq 1) { $wEnd = 'A' } else { $wEnd = 'B' }
    }

    # Scenario target: exactly one child. Burst also needs a plain send path
    # (not the attacker relay / a wormhole tunnel end) since only
    # victim_main.c carries the burst logic -- so a blackhole ATTACKER or a
    # wormhole A/B board is not offered the question.
    $isScenarioTarget = $false
    if ($role -ne 'root' -and (Test-ScenarioNeedsTarget $Scenario) -and -not $haveScenarioTarget) {
        $burstEligible = -not (($Attack -eq 'blackhole' -and $bhRole -eq 'attacker') -or $Attack -eq 'wormhole')
        if ($Scenario -ne 'burst' -or $burstEligible) {
            $tgt = Read-YesNo -Question "Is THIS board the $Scenario TARGET (the one that bursts / is moved / is power-cycled)?" -Default $false -AllowBack:$AllowBack
            # BackSignal (a string) must be the LEFT operand: a bare `$tgt -eq
            # $script:BackSignal` coerces the string to bool when $tgt is a
            # real $true answer, comparing $true -eq $true and misfiring as a
            # false "back" on a legitimate "yes".
            if ($script:BackSignal -eq $tgt) { return $script:BackSignal }
            $isScenarioTarget = $tgt
        }
    }

    $labelPrompt = if ($AllowBack) {
        "Board label / node id (e.g. node5), blank to skip ('b' cancels this board, 'm' main menu, 'cls' clear): "
    } else {
        "Board label / node id (e.g. node5), blank to skip: "
    }
    $label = Read-Line $labelPrompt
    if ($AllowBack -and (Test-BackAnswer $label)) { return $script:BackSignal }

    $p = @{ Port = $port; Role = $role; Topology = $Topo; Attack = $Attack; Scenario = $Scenario }
    if (-not [string]::IsNullOrWhiteSpace($label)) {
        if ($label -notmatch '^[A-Za-z0-9_\-]+$') {
            Write-Host "   Label must be letters/digits/_/- only -- skipping label for this board." -ForegroundColor Yellow
            $label = ''
        } else {
            $p['Label'] = $label
        }
    }
    if ($Attack -eq 'blackhole' -and $role -ne 'root') { $p['BlackholeRole'] = $bhRole }
    if ($Attack -eq 'wormhole'  -and $role -ne 'root') { $p['WormholeEnd']   = $wEnd }
    if ($isScenarioTarget) { $p['ScenarioTarget'] = $true }

    return [pscustomobject]@{
        Port = $port; Role = $role; Label = $label; Params = $p
        CmdText = (Format-BoardCmdText -Params $p)
        Mac = $null; Kind = ((Get-PortList | Where-Object { $_.Port -eq $port } | Select-Object -First 1).Kind)
    }
}

function Select-MultiplePorts {
    # Ported/trimmed from run_wizard.ps1's Select-MultiplePorts; the per-port
    # vetting below now calls the shared Test-PortSafeToTouch above instead of
    # carrying its own copy of the same check. Picks several boards at once
    # ('all' or comma/space-separated numbers) for a bulk read (identify),
    # never a blind "apply to all enumerated ports" -- a BLOCKED port
    # (Bluetooth, a mouse receiver, ...) is never even listed, and an UNKNOWN
    # one only gets touched after typing its own port name back to prove it
    # really is a board someone means to read.
    param([object[]]$Ports, [string]$Action = 'read it')

    $usable = @($Ports | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($usable.Count -eq 0) { return @() }
    $bridges = @($usable | Where-Object { $_.Kind -eq 'BRIDGE' })

    Write-Host ""
    if ($bridges.Count -gt 0) {
        Write-Host ("Type 'all' for the {0} detected ESP32 board(s): {1}" -f $bridges.Count, (($bridges | ForEach-Object { $_.Port }) -join ', ')) -ForegroundColor DarkGray
    }
    $which = Read-Line "Which port numbers? ('all', or comma/space separated e.g. 1,3,5): "
    $picked = @()
    if ($which.Trim() -in @('all', 'ALL', 'All', 'a', 'A')) {
        if ($bridges.Count -eq 0) {
            Write-Host "  No recognised ESP32 boards detected -- pick numbers by hand instead." -ForegroundColor Yellow
            return @()
        }
        $picked = @($bridges)
        Write-Host ("  Selected all {0} detected ESP32 board(s)." -f $picked.Count) -ForegroundColor Green
    } else {
        foreach ($tok in ($which -split '[,\s]+' | Where-Object { $_ })) {
            $wn = 0
            if ([int]::TryParse($tok, [ref]$wn) -and $wn -ge 1 -and $wn -le $usable.Count) {
                $picked += $usable[$wn - 1]
            } else {
                Write-Host ("  Ignoring invalid entry '{0}'." -f $tok) -ForegroundColor Yellow
            }
        }
    }

    $seen = @{}; $unique = @()
    foreach ($p in $picked) { if (-not $seen.ContainsKey($p.Port)) { $seen[$p.Port] = $true; $unique += $p } }
    $picked = @($unique)
    if ($picked.Count -eq 0) { Write-Host "  Nothing valid selected." -ForegroundColor Yellow; return @() }

    # Make each unrecognised port earn its place individually -- a bulk pick is
    # exactly where a stray number ends up aimed at something that isn't a board.
    $vetted = @()
    foreach ($p in $picked) {
        if ($p.Kind -eq 'BRIDGE') { $vetted += $p; continue }
        if (Test-PortSafeToTouch -Port $p.Port -Action $Action) { $vetted += $p }
    }
    return @($vetted)
}

# ---- location.txt on a RUNNING board (ported from run_wizard.ps1) -----------
# Both helpers below go through tools\export_logs.py's serial dispatcher (see
# csv_logger.c), which only answers once the board has booted, joined the mesh
# and reached csv_logger_init(). Unlike the esptool paths above (Get-LiveBoardMac,
# erase_flash) they do NOT work on a board that hasn't been flashed/booted yet --
# for that, write location.txt onto the card directly with a reader.
# Kept byte-for-byte in step with run_wizard.ps1's identical functions.

function Get-SdLocation {
    # Reads a running board's location.txt WITHOUT changing it, so a write can be
    # shown as "Goks -> G402" instead of a blind overwrite, and skipped entirely
    # when it would be a no-op.
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
    # Sends SET_LOCATION=<value> to an ALREADY-RUNNING board. Fixes a card an
    # already-running board found broken (SD_STATUS_NO_LOCATION_FILE/BAD_LOCATION
    # in its own boot log), not one that's about to be freshly flashed. Takes
    # effect on THAT board's next boot, not this session.
    param([string]$TargetPort, [string]$Location)
    Push-Location (Join-Path $base 'tools')
    try {
        $out = & python export_logs.py --port $TargetPort --set-location $Location 2>&1
        return @{ Ok = ($LASTEXITCODE -eq 0); Lines = @($out) }
    }
    catch { return @{ Ok = $false; Lines = @($_.Exception.Message) } }
    finally { Pop-Location }
}

function Select-WriteLocation {
    # Location picker for a WRITE, deliberately not Select-Location: there the
    # default is harmless (it only names an export folder), here hitting Enter
    # without meaning to would overwrite a card that was already correct, with
    # no undo. So "cancel" IS the default, and the only way to write is to type
    # a number. Same reasoning as run_wizard.ps1's -DefaultIndex -1 on this
    # prompt; expressed through Read-Choice so the menu still looks like every
    # other menu in this file.
    param([string]$Title)
    $locs = Get-LocationList
    $opts = @($locs) + @('Cancel - write nothing')
    $idx  = Read-Choice -Title $Title -Options $opts -Default $opts.Count
    if ($idx -eq $opts.Count) { return $null }
    return $locs[$idx - 1]
}

function Get-BuildDirSpec {
    # Mirrors run.ps1's OWN build-dir naming and -D flag selection (run.ps1's
    # $buildSuffix/$buildDir block and its $attackFlags/$topologyFlag block) so
    # the pre-build loop below compiles EXACTLY what run.ps1 will later ask
    # idf.py to flash -- read-only prediction; run.ps1 still computes its own
    # dir itself when it actually runs.
    param($Params)
    $role = $Params.Role
    $attack = $Params.Attack
    $topology = $Params.Topology
    $proj = if ($role -eq 'root') { 'root_node' } else { 'child_node' }

    $suffix = "${role}_${attack}_${topology}"
    if ($attack -eq 'wormhole' -and $role -ne 'root' -and $Params.WormholeEnd) { $suffix += "_$($Params.WormholeEnd)" }
    if ($attack -eq 'blackhole' -and $role -ne 'root' -and $Params.BlackholeRole) { $suffix += "_$($Params.BlackholeRole)" }
    # SCENARIO TAG RULE (kept identical in run.ps1 and run_wizard.ps1's
    # Get-BoardBuildDir): only a board that actually gets -DTRAFFIC_PROFILE
    # takes a suffix/flag, so 'none'/'mobility'/'powercycle' builds are untouched.
    $scenario = $Params.Scenario
    if ($scenario -eq 'burst' -and ($role -eq 'root' -or $Params.ScenarioTarget)) { $suffix += '_burst' }
    if ($scenario -eq 'highload' -and $role -ne 'root') { $suffix += '_highload' }
    $portTag = ($Params.Port -replace '[^A-Za-z0-9]', '')
    $buildDir = Join-Path $buildRoot "$proj\build_${suffix}_$portTag"

    $flags = @()
    switch ($attack) {
        'blackhole' {
            $flags += '-DACTIVE_ATTACK=1'
            if ($role -ne 'root') {
                $bhNum = if ($Params.BlackholeRole -eq 'victim') { 1 } else { 0 }
                $flags += "-DBLACKHOLE_ROLE=$bhNum"
            }
        }
        'wormhole' {
            $flags += '-DACTIVE_ATTACK=2'
            if ($role -ne 'root') {
                $endNum = if ($Params.WormholeEnd -eq 'A') { 0 } else { 1 }
                $flags += "-DWORMHOLE_END=$endNum"
            }
        }
        default { $flags += '-DACTIVE_ATTACK=255' }
    }
    $topologyNum = switch ($topology) { 'star' {0}; 'tree' {1}; 'linear' {2}; 'partial' {3} }
    $flags += "-DMESH_TOPOLOGY=$topologyNum"

    if ($scenario -eq 'burst' -and ($role -eq 'root' -or $Params.ScenarioTarget)) { $flags += '-DTRAFFIC_PROFILE=1' }
    if ($scenario -eq 'highload' -and $role -ne 'root') { $flags += '-DTRAFFIC_PROFILE=2' }

    return [pscustomobject]@{ Proj = $proj; BuildDir = $buildDir; Flags = $flags }
}

function Get-PhaseDurations {
    # Parses the four PHASE_*_S constants out of mesh_config.h (seconds) --
    # ported from run_wizard.ps1 -- so the estimate moves when a campaign
    # retunes phase lengths instead of silently going stale.
    # Returns @{ Stabilise=; Baseline=; Attack=; Cooldown=; Total=; Ok= }.
    # Ok=$false means the header couldn't be read/parsed and Total is the
    # hardcoded fallback -- callers MUST show that as a guess, never as fact.
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
        # Fallback matches Table 4.1 as of this writing -- only used if the
        # header is missing/renamed, and always flagged, never presented as
        # measured fact (see the call sites below).
        $vals = @{ Stabilise = 60; Baseline = 300; Attack = 180; Cooldown = 120 }
    }
    $vals.Total = $vals.Stabilise + $vals.Baseline + $vals.Attack + $vals.Cooldown
    $vals.Ok = $ok
    return $vals
}

function Format-Duration {
    # Seconds -> "11 min" / "1 hr 5 min" / "43 sec", for estimate lines.
    param([int]$Seconds)
    if ($Seconds -lt 60) { return "$Seconds sec" }
    $h = [math]::Floor($Seconds / 3600)
    $m = [math]::Floor(($Seconds % 3600) / 60)
    $s = $Seconds % 60
    if ($h -gt 0) { return "{0} hr {1} min" -f $h, $m }
    if ($s -eq 0) { return "$m min" }
    return "{0} min {1:D2} sec" -f $m, $s
}

function Get-EspIdfActivation {
    # Finds the REAL "ESP-IDF 5.3 PowerShell" Start Menu shortcut and reads its
    # exact launch arguments, so New-BoardWindow can reproduce it byte-for-byte
    # instead of guessing. Omitting -IdfId and letting Initialize-Idf.ps1 fall
    # back to $env:IDF_PATH was tried and FAILED: idf-env's `--idf-path` lookup
    # doesn't match by directory the way `--idf-id` does, so it silently prints
    # the literal string "null" for $PythonCommand instead of erroring, and
    # every step downstream (Get-Item, &$PythonCommand --version, ...) breaks on
    # that "null" string. The shortcut's own -IdfId is the one value proven to
    # resolve correctly (it's what "open ESP-IDF 5.3 PowerShell manually" uses),
    # so read it from the shortcut itself -- never hardcode it, an ESP-IDF Tools
    # reinstall changes this GUID-like id.
    # Returns $null if no matching shortcut is found (falls back to a plain
    # Initialize-Idf.ps1 call with no -IdfId, which at least matches whatever
    # ESP-IDF install $env:IDF_PATH already points at, even if the lookup above
    # can fail for it too).
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    )
    $lnk = $null
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $lnk = Get-ChildItem -Path $root -Filter '*ESP-IDF*PowerShell*.lnk' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) { break }
    }
    if (-not $lnk) { return $null }

    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk.FullName)
    $script = $null
    $idfId  = $null
    if ($sc.Arguments -match '-File\s+"([^"]+)"') { $script = $Matches[1] }
    if ($sc.Arguments -match '-IdfId\s+(\S+)')    { $idfId  = $Matches[1] }
    if (-not $script) { return $null }
    return [pscustomobject]@{ Script = $script; IdfId = $idfId }
}

function New-BoardWindow {
    # Opens an actual "ESP-IDF 5.3 PowerShell" window per board -- NOT a plain
    # powershell.exe. The real shortcut (Start Menu > ESP-IDF > ESP-IDF 5.3
    # PowerShell) runs `Initialize-Idf.ps1 -IdfId <id>`, which defines idf.py/
    # esptool.py/etc. as POWERSHELL FUNCTIONS (Initialize-Idf.ps1:48), not real
    # .exe/.py files on PATH. Functions never survive into a child process --
    # only environment variables do -- so a plain spawned powershell.exe
    # inherits PATH/IDF_PATH fine but still fails with "idf.py is not
    # recognized" because the FUNCTION itself was never redefined there. Fix:
    # dot-source that same script with that same -IdfId (via $Activation, from
    # Get-EspIdfActivation) in the new window -- exactly what the shortcut runs.
    # -NoProfile stays so a profile script can't clobber any of this afterward.
    param([pscustomobject]$Activation, [string]$RunScript, [string]$WorkDir, [string]$ArgText, [string]$Title, [string]$Banner, [string]$Color)
    $rq = $RunScript -replace "'", "''"
    $initScript = if ($Activation -and $Activation.Script) { $Activation.Script } elseif ($env:IDF_TOOLS_PATH) { Join-Path $env:IDF_TOOLS_PATH 'Initialize-Idf.ps1' } else { 'C:\Espressif\Initialize-Idf.ps1' }
    $initq = $initScript -replace "'", "''"
    $initCall = ". '$initq'"
    if ($Activation -and $Activation.IdfId) {
        $idq = $Activation.IdfId -replace "'", "''"
        $initCall += " -IdfId '$idq'"
    }
    $inner = "`$Host.UI.RawUI.WindowTitle = '$Title'; " +
             "$initCall; " +
             "Write-Host '$Banner' -ForegroundColor $Color; " +
             "& '$rq' $ArgText"
    $argLine = "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$inner`""
    Start-Process powershell.exe -ArgumentList $argLine -WorkingDirectory $WorkDir | Out-Null
}

# ---- main menu --------------------------------------------------------------

function Show-MainMenu {
    # Grouped by what the action actually touches, not the order they were added
    # in - a flat 1-9 list reads as one undifferentiated wall once there are this
    # many options. Each item carries its REAL action id (what every
    # `if ($action -eq N)` check elsewhere in the file expects back), but the
    # NUMBER PRINTED ON SCREEN is a separate, always-sequential 1..9 position
    # in display order - $order/$display below is the lookup between the two,
    # so picking "[3]" always means "the 3rd line on screen" even though DATA's
    # first item is action 3 and MAINTENANCE's is action 4.
    $categories = @(
        @{ Name = 'CAPTURE'; Items = @(
            @{ Action = 1; Text = 'Run a board  (baseline / blackhole / wormhole; plus a run scenario)' }
            @{ Action = 2; Text = 'Run MULTIPLE boards in parallel  (one window per board, pre-built)' }
        ) }
        @{ Name = 'DATA'; Items = @(
            @{ Action = 3; Text = 'Export a board only  (it already ran; just pull CSVs)' }
            @{ Action = 8; Text = 'Import CSVs from a pulled SD card  (no board/COM contact)' }
            @{ Action = 7; Text = 'Run analysis only  (M6->M8 on already-exported CSVs, no board contact)' }
        ) }
        @{ Name = 'MAINTENANCE'; Items = @(
            @{ Action = 4; Text = 'Wipe / full-erase a board  (start empty)' }
            @{ Action = 5; Text = 'Identify a board  (read its MAC / node number)' }
            @{ Action = 10; Text = 'Write/update location.txt on an already-running board  (over USB)' }
        ) }
        @{ Name = 'VERIFY'; Items = @(
            @{ Action = 6; Text = 'Verify a run  (paper-backed 3-sigma attack check)' }
        ) }
    )
    $quitAction = 9

    $order = @()
    foreach ($cat in $categories) { foreach ($item in $cat.Items) { $order += $item.Action } }
    $order += $quitAction   # always last on screen
    $display = @{}   # real action id -> number printed on screen
    for ($i = 0; $i -lt $order.Count; $i++) { $display[$order[$i]] = $i + 1 }

    # Captured as a scriptblock (not just run inline) so it can be handed to
    # Read-Line as -Redraw: 'cls' Clear-Hosts the whole screen, and this is the
    # only place that knows how to put the banner/listing back afterward.
    $draw = {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "   Combined ESP-WIFI-MESH launcher" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        foreach ($cat in $categories) {
            Write-Host ""
            Write-Host ("-- {0}" -f $cat.Name) -ForegroundColor DarkCyan
            foreach ($item in $cat.Items) {
                $num = $display[$item.Action]
                if ($item.Action -eq 1) {
                    Write-Host ("   [{0}] {1}  <- default (press Enter)" -f $num, $item.Text) -ForegroundColor Green
                } else {
                    Write-Host ("   [{0}] {1}" -f $num, $item.Text)
                }
            }
        }
        Write-Host ""
        Write-Host ("   [{0}] Quit" -f $display[$quitAction])
    }
    & $draw

    while ($true) {
        $ans = Read-Line "`nChoice [default 1], 'm' redraws this menu, 'cls' clears it: " -Redraw $draw
        if ([string]::IsNullOrWhiteSpace($ans)) { return 1 }
        if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $order.Count) { return $order[[int]$ans - 1] }
        Write-Host ("   Enter a number 1..{0}." -f $order.Count) -ForegroundColor Yellow
    }
}

# Everything from here to end-of-file is wrapped in one loop so choosing an
# action returns to the main menu afterward, instead of ending the script (the
# original behaviour: pick one thing, script exits, run .\menu.ps1 again for
# anything else). 'm' at any prompt below (Read-Line throws $script:MainMenuSignal)
# also lands back here from any depth. The body keeps its original indentation
# on purpose - re-indenting ~800 lines would bury the real change in whitespace
# noise, and PowerShell does not care either way.
:menu while ($true) {
try {

$script:NavLocked = $false
$action = Show-MainMenu

if ($action -eq 9) { Write-Host ""; Write-Host "Bye." -ForegroundColor DarkGray; break menu }

# ---- Run MULTIPLE boards in parallel -----------------------------------------
if ($action -eq 2) {
    if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "idf.py is not on PATH - run this from the 'ESP-IDF 5.3 PowerShell' window." -ForegroundColor Red
        continue menu
    }

    Write-Host ""
    Write-Host "Settings below apply to EVERY board in this run (flash every board in a" -ForegroundColor DarkGray
    Write-Host "run with the SAME topology and SAME attack, or the shaping is wrong)." -ForegroundColor DarkGray

    # Run-wide settings as a step machine (see the "Run a board" flow at the
    # bottom of this file for the pattern and why $dir exists): 'b' walks back
    # one question at a time, and every question re-offers the answer already
    # given rather than its factory default.
    $topoIdx  = 1
    $attkIdx  = 1
    $scenario = 'none'
    $flash    = $true
    $wipe     = $true
    $export   = $true
    $clean    = $false
    $loc      = $null
    $topo     = 'tree'
    $attack   = 'none'

    $step = 0
    $dir  = 1
    :settings while ($step -le 7) {
        switch ($step) {

            0 {
                $r = Read-Choice -Title "Topology (every board, same)?" -Options @(
                    'tree     (default self-organising)',
                    'star     (all direct children of root)',
                    'linear   (forced chain)',
                    'partial  (physical placement)'
                ) -Default $topoIdx -AllowBack
                if ($script:BackSignal -eq $r) { continue menu }
                $topoIdx = $r
                $topo = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
                $step = 1; $dir = 1; continue settings
            }

            1 {
                $r = Read-Choice -Title "Attack for this run (every board, same)?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 0; $dir = -1; continue settings }
                $attkIdx = $r
                $attack = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
                $step = 2; $dir = 1; continue settings
            }

            2 {
                $r = Select-Scenario -Current $scenario -AllowBack
                if ($script:BackSignal -eq $r) { $step = 1; $dir = -1; continue settings }
                $scenario = $r
                $step = 3; $dir = 1; continue settings
            }

            3 {
                $r = Read-YesNo -Question "Flash firmware on every board first?" -Default $flash -AllowBack
                if ($script:BackSignal -eq $r) { $step = 2; $dir = -1; continue settings }
                $flash = $r
                $step = 4; $dir = 1; continue settings
            }

            4 {
                $r = Read-YesNo -Question "Wipe/erase every board BEFORE this run?" -Default $wipe -AllowBack
                if ($script:BackSignal -eq $r) { $step = 3; $dir = -1; continue settings }
                $wipe = $r
                $step = 5; $dir = 1; continue settings
            }

            5 {
                $r = Read-YesNo -Question "Export CSVs from every board when its monitor is exited?" -Default $export -AllowBack
                if ($script:BackSignal -eq $r) { $step = 4; $dir = -1; continue settings }
                $export = $r
                if (-not $export) { $loc = $null; $clean = $false }
                $step = 6; $dir = 1; continue settings
            }

            6 {
                if (-not $export) { $step += $dir; continue settings }
                $r = Select-Location -Current $loc -AllowBack
                if ($script:BackSignal -eq $r) { $step = 5; $dir = -1; continue settings }
                $loc = $r
                $step = 7; $dir = 1; continue settings
            }

            7 {
                if (-not $export) { $step += $dir; continue settings }
                $r = Read-YesNo -Question "Wipe each board AFTER a good export?" -Default $clean -AllowBack
                if ($script:BackSignal -eq $r) { $step = 6; $dir = -1; continue settings }
                $clean = $r
                $step = 8; $dir = 1; continue settings
            }
        }
    }

    if ($attack -eq 'wormhole') {
        Write-Host ""
        Write-Host "REMINDER (wormhole): wire the UART tunnel BEFORE powering on -" -ForegroundColor Yellow
        Write-Host "   Node A GPIO17(TX) -> Node B GPIO16(RX), Node A GPIO16(RX) -> Node B GPIO17(TX), shared GND." -ForegroundColor Yellow
    }

    # ---- add boards one at a time --------------------------------------------
    # -Analyze is assigned to the root ONLY, once the full plan is known
    # (below) -- never asked per board, since it must land on the LAST
    # board exported (the root) so arrivals.csv covers the whole run.
    $boards = @()
    while ($true) {
        # 'b' is only offered once there's an already-added board to fall back
        # to -- cancelling board #1 has nowhere useful to land, so that case
        # still goes through 'm' like everything else in this file.
        $new = Add-BoardInteractive -Topo $topo -Attack $attack -Scenario $scenario -Boards $boards -AllowBack:($boards.Count -gt 0)
        if ($script:BackSignal -eq $new) { break }

        if ($wipe)   { $new.Params['Wipe']   = $true }
        if ($flash)  { $new.Params['Flash']  = $true }
        if ($export) { $new.Params['Export'] = $true; $new.Params['Location'] = $loc }
        if ($clean)  { $new.Params['Clean']  = $true }
        $new.CmdText = Format-BoardCmdText -Params $new.Params

        $boards += $new

        if (-not (Read-YesNo -Question "Add another board?" -Default $true)) { break }
    }

    if ($boards.Count -eq 0) { Write-Host "No boards added." -ForegroundColor Yellow; continue menu }

    # Sanity warnings (non-fatal) -- also re-run after any edit below that
    # could change role/attack-sub-role/scenario-target assignments, not just
    # once here, so a stale "exactly one attacker" warning (or its absence)
    # never survives an edit that changed who holds that role.
    Show-PlanWarnings -Boards $boards -Attack $attack -Scenario $scenario

    # -Analyze on the root, only if exporting -- and only now that we know
    # every board that was added (root must be exported LAST to see the run).
    if ($export) {
        foreach ($b in $boards) {
            if ($b.Role -eq 'root') {
                $b.Params['Analyze'] = $true
                $b.CmdText += ' -Analyze'
            }
        }
    }

    # Reorder to children-first, root-last HERE -- regardless of what order
    # boards were picked in above (root chosen first is fine; no need to restart
    # the menu to fix it). Everything below (the printed plan, the per-board
    # confirm, the pre-build progress, and the final spawn) reads from this same
    # $boards list, so root visibly builds/confirms/opens last, consistently, no
    # matter what order it was added in. Also re-run after a root-swap edit
    # below, so a newly-promoted root still sorts last.
    $boards = Get-ReorderedBoards -Boards $boards

    # ---- plan table + per-board confirm (no blind apply-to-all) -------------
    # Boxed summary ported from run_wizard.ps1's pre-flash confirm (same
    # Attack/Topology/Scenario header, "Order (root is always last)" table,
    # Exports/Analysis footer) so both front-ends show the same thing before
    # committing to a flash. menu.ps1 has no Repeat/swap-mode concept, so those
    # two header lines are omitted rather than faked.
    # Wrapped as a scriptblock (not just printed inline) so the edit-a-node
    # loop just below can reprint it after each change, instead of the
    # operator having to trust an edit "took" with no visible confirmation.
    $printPlan = {
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Green
        Write-Host ("  Attack   : {0}" -f $attack)
        Write-Host ("  Topology : {0}" -f $topo)
        Write-Host ("  Scenario : {0}" -f $scenario)
        if ($export) { Write-Host ("  Location : {0}" -f $loc) }
        Write-Host ""
        Write-Host "  Order (root is always last):"
        $step = 0
        foreach ($b in $boards) {
            $step++
            $lbl = if ($b.Label) { $b.Label } else { $b.Port }
            if ($b.Role -eq 'root') {
                $display = 'root'
            } elseif ($attack -eq 'blackhole' -and $b.Params.BlackholeRole) {
                $display = "blackhole $($b.Params.BlackholeRole)"
            } elseif ($attack -eq 'wormhole' -and $b.Params.WormholeEnd) {
                $display = "wormhole end $($b.Params.WormholeEnd)"
            } else {
                $display = "$attack child"
            }
            $tail = @()
            if ($b.Params.Export)  { $tail += '-Export' }
            if ($b.Params.Analyze) { $tail += '-Analyze' }
            $tailText = $tail -join ' '
            if ($b.Params.ScenarioTarget) { $tailText = "$tailText  << $scenario TARGET" }
            $mac = Resolve-BoardMac -Board $b
            $macDisp = if ($mac) { $mac } else { '(unread)' }
            $role = if ($b.Role -eq 'root') { 'root' } elseif ($b.Params.BlackholeRole -eq 'attacker') { 'attacker' } else { 'child' }
            $line = ("   [{0}] {1,-8} {2,-27} {3,-7} {4,-17} {5}" -f $step, $lbl, $display, $b.Port, $macDisp, $tailText)
            Write-Host (Colorize-Role $line $role)
        }
        if ($export) {
            $dirs = Get-RunDirs -Attack $attack -Topology $topo -Location $loc -Scenario $scenario
            Write-Host ""
            Write-Host "  Exports  -> $($dirs.Export)"
            Write-Host "  Analysis -> $($dirs.Analysis)"
        }
        Write-Host "------------------------------------------------------------" -ForegroundColor Green
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $boards.Count; $i++) {
            $b = $boards[$i]
            Write-Host ("  [{0}] {1,-6} {2}" -f ($i + 1), $b.Port, $b.CmdText) -ForegroundColor DarkGray
        }
    }
    & $printPlan

    # ---- optional adjustments, right after the summary (no blind apply-to-all
    # -- see [[thesis_cc_wizard_hardware_safety]]: any node change is on ONE
    # node the operator picked by number; a topology change is explicit and
    # global by nature. The plan (and its warnings) is rebuilt+reprinted after
    # every change, and nothing is touched until the per-board CONFIRM loop
    # below runs). --------------------------------------------------------------
    :adjustLoop while ($true) {
        $adjIdx = Read-Choice -Title "Adjust the plan before confirming?" -Options @(
            'Edit a specific node (port/label/role/toggles/attack sub-role)',
            'Add another board',
            'Remove a node (added it by mistake)',
            'Change topology for this run',
            'Nothing more -- continue to confirm'
        ) -Default 5
        if ($adjIdx -eq 5) { break adjustLoop }

        if ($adjIdx -eq 1) {
            for ($i = 0; $i -lt $boards.Count; $i++) {
                $b = $boards[$i]
                $lbl = if ($b.Label) { $b.Label } else { $b.Port }
                Write-Host ("   [{0}] {1}  ({2}, {3})" -f ($i + 1), $lbl, $b.Port, $b.Role)
            }
            $pickIdx = Read-Choice -Title "Which node?" -Options ($boards | ForEach-Object {
                $lbl = if ($_.Label) { $_.Label } else { $_.Port }
                "$lbl  ($($_.Port), $($_.Role))"
            }) -Default 1 -AllowBack
            if ($script:BackSignal -ne $pickIdx) {
                Edit-BoardInteractive -Board $boards[$pickIdx - 1] -Boards $boards -Attack $attack -Scenario $scenario
            }
        }
        elseif ($adjIdx -eq 2) {
            $new = Add-BoardInteractive -Topo $topo -Attack $attack -Scenario $scenario -Boards $boards -AllowBack
            if ($script:BackSignal -eq $new) {
                Write-Host "   Cancelled -- no board added." -ForegroundColor DarkGray
            } else {
                if ($wipe)   { $new.Params['Wipe']   = $true }
                if ($flash)  { $new.Params['Flash']  = $true }
                if ($export) { $new.Params['Export'] = $true; $new.Params['Location'] = $loc }
                if ($clean)  { $new.Params['Clean']  = $true }
                $new.CmdText = Format-BoardCmdText -Params $new.Params
                $boards += $new
            }
        }
        elseif ($adjIdx -eq 3) {
            $rmOpts = @($boards | ForEach-Object {
                $lbl = if ($_.Label) { $_.Label } else { $_.Port }
                "$lbl  ($($_.Port), $($_.Role))"
            })
            $rmOpts += 'Never mind -- keep every node'
            $rmIdx = Read-Choice -Title "Remove which node?" -Options $rmOpts -Default $rmOpts.Count
            if ($rmIdx -le $boards.Count) {
                $victim = $boards[$rmIdx - 1]
                $vLbl = if ($victim.Label) { $victim.Label } else { $victim.Port }
                if (Read-YesNo -Question "Remove $vLbl ($($victim.Port), $($victim.Role)) from this plan?" -Default $false) {
                    $boards = @($boards | Where-Object { $_ -ne $victim })
                    Write-Host "   Removed." -ForegroundColor Green
                    if ($boards.Count -eq 0) { Write-Host "No boards left in the plan." -ForegroundColor Yellow; continue menu }
                }
            }
        }
        elseif ($adjIdx -eq 4) {
            $topoOpts = @('tree', 'star', 'linear', 'partial')
            $topoIdx2 = Read-Choice -Title "Topology (every board, same)?" -Options @(
                'tree     (default self-organising)',
                'star     (all direct children of root)',
                'linear   (forced chain)',
                'partial  (physical placement)'
            ) -Default ([array]::IndexOf($topoOpts, $topo) + 1)
            $topo = $topoOpts[$topoIdx2 - 1]
            foreach ($b in $boards) {
                $b.Params['Topology'] = $topo
                $b.CmdText = Format-BoardCmdText -Params $b.Params
            }
        }

        # A node's Role or the run's Topology may have just changed -- re-sort
        # (root-last) and re-check invariants before showing the effect.
        $boards = Get-ReorderedBoards -Boards $boards
        & $printPlan
        Show-PlanWarnings -Boards $boards -Attack $attack -Scenario $scenario
    }

    $confirmed = @()
    foreach ($b in $boards) {
        $lbl = if ($b.Label) { $b.Label } else { $b.Role }
        if (Read-YesNo -Question ("CONFIRM flash/run {0} ({1})?" -f $b.Port, $lbl) -Default $false) {
            $confirmed += $b
        } else {
            Write-Host ("   Dropped {0} from this run." -f $b.Port) -ForegroundColor DarkGray
        }
    }
    if ($confirmed.Count -eq 0) { Write-Host "`nNothing confirmed -- nothing to do." -ForegroundColor Yellow; continue menu }
    # $boards was already children-first/root-last before this loop ran, and
    # filtering-by-confirm preserves that relative order, so $confirmed still is.
    $boards = $confirmed

    # ---- estimated time (ported from run_wizard.ps1) -------------------------
    # So you can set a phone alarm and walk away instead of watching the
    # terminal. Only the root's phase timing is genuinely known (a firmware
    # constant, not a guess); build/flash time depends on your machine and is
    # shown as a labelled approximation, never blended into the firm number so
    # one bad guess can't quietly poison the whole estimate.
    $durations    = Get-PhaseDurations
    $estRootBoard = $boards | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1
    $childCount   = ($boards | Where-Object { $_.Role -ne 'root' }).Count
    $warmBuildMin = 2
    $coldBuildMin = 4
    $flashBoards  = @($boards | Where-Object { $_.Params.Flash })
    $coldCount    = 0
    foreach ($b in $flashBoards) {
        $spec = Get-BuildDirSpec -Params $b.Params
        if (-not (Test-Path $spec.BuildDir)) { $coldCount++ }
    }
    $warmCount    = $flashBoards.Count - $coldCount
    $buildSec     = (($warmCount * $warmBuildMin) + ($coldCount * $coldBuildMin)) * 60
    $attentionSec = $childCount * 60   # ~1 min/child: watch for the banner, press Ctrl+]
    $rootSec      = if ($estRootBoard) { [int]$durations.Total } else { 0 }
    $totalSec     = $buildSec + $attentionSec + $rootSec
    $finishAt     = (Get-Date).AddSeconds($totalSec)

    Write-Host ""
    Write-Host "  Estimated time" -ForegroundColor Cyan
    if ($rootSec -gt 0) {
        $phaseNote = "$($durations.Stabilise)s stabilise + $($durations.Baseline)s baseline + $($durations.Attack)s attack + $($durations.Cooldown)s cooldown"
        if ($durations.Ok) {
            Write-Host ("    Root experiment   {0,-8} ({1})" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor DarkGray
        } else {
            Write-Host ("    Root experiment   ~{0,-7} ({1}) -- mesh_config.h unreadable, this is a HARDCODED FALLBACK, not measured" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor Yellow
        }
    }
    if ($flashBoards.Count -gt 0) {
        Write-Host ("    Build + flash     ~{0}          ({1} warm, {2} cold @ ~{3}min/~{4}min per board - varies with your machine)" -f (Format-Duration $buildSec), $warmCount, $coldCount, $warmBuildMin, $coldBuildMin) -ForegroundColor DarkGray
    }
    if ($childCount -gt 0) {
        Write-Host ("    Your attention    ~{0}          (press Ctrl+] at each child's banner, then it's hands-off)" -f (Format-Duration $attentionSec)) -ForegroundColor DarkGray
    }
    Write-Host "    ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("    Total            ~{0}, finishing around {1}" -f (Format-Duration $totalSec), $finishAt.ToString('HH:mm')) -ForegroundColor Cyan
    if ($rootSec -gt 0) {
        Write-Host ("    Of that, {0} is a single unattended block during the root's run - that's the part worth an alarm." -f (Format-Duration $rootSec)) -ForegroundColor DarkGray
    }

    if (-not (Read-YesNo -Question ("Proceed with {0} board(s)?" -f $boards.Count) -Default $true)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        continue menu
    }
    # Past here boards start getting pre-built/flashed - see Request-MainMenu.
    $script:NavLocked = $true

    # ---- optional sequential pre-build (children first, root last -- see above) ----
    $doPreBuild = Read-YesNo -Question "Pre-build all variants first? (recommended - avoids several cold builds racing each other)" -Default $true
    $badBuildDirs = @{}
    if ($doPreBuild) {
        $env:CCACHE_BASEDIR    = $base
        $env:CCACHE_SLOPPINESS = 'pch_defines,time_macros,include_file_mtime'

        $specs = @()
        $seen  = @{}
        foreach ($b in ($boards | Where-Object { $_.Params.Flash })) {
            $spec = Get-BuildDirSpec -Params $b.Params
            $key  = "$($spec.Proj)|$($spec.BuildDir)"
            if (-not $seen.Contains($key)) { $seen[$key] = $true; $specs += $spec }
        }

        $i = 0
        foreach ($spec in $specs) {
            $i++
            Write-Host ("`n[{0}/{1}] Pre-building {2} ..." -f $i, $specs.Count, $spec.BuildDir) -ForegroundColor Cyan
            Push-Location (Join-Path $base $spec.Proj)
            try {
                # Splat via a plain variable -- `@($spec.Flags)` is an array SUBEXPRESSION,
                # not a splat (see build_all_variants.ps1:47-53 for the exact failure this
                # caused there: both -D flags got merged into ONE argument,
                # -DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=2", and the second define vanished).
                $flags = $spec.Flags
                idf.py -B $spec.BuildDir @flags build
            } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("BUILD FAILED for {0} -- boards using this variant will be skipped." -f $spec.BuildDir) -ForegroundColor Red
                $badBuildDirs[$spec.BuildDir] = $true
            }
        }

        if ($badBuildDirs.Count -gt 0) {
            $before = $boards.Count
            $boards = @($boards | Where-Object {
                $s = Get-BuildDirSpec -Params $_.Params
                -not $badBuildDirs.Contains($s.BuildDir)
            })
            Write-Host ("`n{0} board(s) dropped due to a failed pre-build; {1} remain." -f ($before - $boards.Count), $boards.Count) -ForegroundColor Yellow
            if ($boards.Count -eq 0) { continue menu }
            if (-not (Read-YesNo -Question "Continue with the remaining boards?" -Default $true)) { continue menu }
        }
    }

    # ---- spawn: children first, root LAST ------------------------------------
    # $boards has been in that order since right after the add-board loop (see
    # the Reorder comment above) -- just recheck root is still present in case a
    # failed pre-build dropped it.
    $ordered = $boards
    $rootBoard = $boards | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1

    $activation = Get-EspIdfActivation
    if (-not $activation) {
        Write-Host ""
        Write-Host "WARNING: couldn't find the 'ESP-IDF 5.3 PowerShell' shortcut -- spawned" -ForegroundColor Yellow
        Write-Host "windows may not have idf.py available. See README.md for the shortcut location." -ForegroundColor Yellow
    }

    if ($scenario -in @('mobility', 'powercycle')) {
        $targetBoard = $boards | Where-Object { $_.Params.ScenarioTarget } | Select-Object -First 1
        $tgtLbl = if ($targetBoard) { if ($targetBoard.Label) { $targetBoard.Label } else { $targetBoard.Port } } else { '(none picked!)' }
        $verb = if ($scenario -eq 'mobility') { 'move' } else { 'unplug/replug' }
        Write-Host ""
        Write-Host "REMINDER: this is a $scenario run -- YOU must $verb board $tgtLbl during the run. run.ps1 will print the full checklist again right before its console starts." -ForegroundColor Magenta
    }

    Write-Host ""
    Write-Host "Opening one window per board. Exit each monitor with Ctrl+] -- NOT Ctrl+C." -ForegroundColor Yellow
    if ($rootBoard) { Write-Host "Press Ctrl+] in every CHILD window FIRST, then the ROOT window LAST." -ForegroundColor Yellow }

    $liveNow = @(Get-PortList | Select-Object -ExpandProperty Port)
    $opened = 0
    $step = 0
    $total = $ordered.Count
    foreach ($b in $ordered) {
        $step++
        if ($liveNow -notcontains $b.Port) {
            Write-Host ("SKIPPING {0}: no longer detected on this port." -f $b.Port) -ForegroundColor Red
            continue
        }
        $lbl = if ($b.Label) { $b.Label } else { $b.Port }
        $argText = ($b.CmdText -replace '^\.\\run\.ps1 ', '')
        if ($b.Role -eq 'root') {
            $title  = "ROOT $($b.Port) $lbl"
            $banner = "ROOT $($b.Port) $lbl -- exit LAST (Ctrl+]) - exports arrivals.csv and runs analysis"
            $color  = 'Red'
            Start-Sleep -Seconds 15
        } else {
            $title  = "CHILD $step/$total $($b.Port) $lbl"
            $banner = "CHILD $step/$total $($b.Port) $lbl -- Ctrl+] BEFORE the ROOT window"
            $color  = 'Yellow'
        }
        New-BoardWindow -Activation $activation -RunScript $run -WorkDir $base -ArgText $argText -Title $title -Banner $banner -Color $color
        $opened++
        Start-Sleep -Milliseconds 1500
    }

    Write-Host ""
    Write-Host ("Opened {0}/{1} board window(s)." -f $opened, $ordered.Count) -ForegroundColor Green
    Write-Host "Exit order: every CHILD window (Ctrl+]) first, ROOT window LAST." -ForegroundColor Cyan
    continue menu
}

# ---- Verify a run (paper-backed 3-sigma) ------------------------------------
if ($action -eq 6) {
    $attkIdx = 1
    $topoIdx = 1
    $loc     = $null
    $table   = ''
    $step = 0
    :verify while ($step -le 3) {
        switch ($step) {
            0 {
                $r = Read-Choice -Title "Which attack to verify?" -Options @('auto-detect', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
                if ($script:BackSignal -eq $r) { continue menu }
                $attkIdx = $r; $step = 1; continue verify
            }
            1 {
                $r = Read-Choice -Title "Topology?" -Options @('tree', 'star', 'linear', 'partial') -Default $topoIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 0; continue verify }
                $topoIdx = $r; $step = 2; continue verify
            }
            2 {
                $r = Select-Location -Current $loc -AllowBack
                if ($script:BackSignal -eq $r) { $step = 1; continue verify }
                $loc = $r; $step = 3; continue verify
            }
            3 {
                $attack = @('auto', 'blackhole', 'wormhole')[$attkIdx - 1]
                $topo   = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
                $guess  = if ($attack -eq 'auto') { Join-Path $base "analysis\blackhole\$topo\$loc\feature_table.csv" }
                          else                    { Join-Path $base "analysis\$attack\$topo\$loc\feature_table.csv" }
                $r = Read-Line "feature_table.csv path: " -Default $guess -AllowBack
                if ($script:BackSignal -eq $r) { $step = 2; continue verify }
                $table = if ([string]::IsNullOrWhiteSpace($r)) { $guess } else { $r }
                $step = 4; continue verify
            }
        }
    }
    $attack = @('auto', 'blackhole', 'wormhole')[$attkIdx - 1]
    $vaArgs  = @($table)
    $cmdText = "python tools\verify_attack.py $table"
    if ($attack -ne 'auto') { $vaArgs += @('--attack', $attack); $cmdText += " --attack $attack" }
    if (Show-And-Confirm $cmdText) {
        Push-Location $base
        try { python (Join-Path $base 'tools\verify_attack.py') @vaArgs } finally { Pop-Location }
    }
    continue menu
}

# ---- Identify a board -------------------------------------------------------
if ($action -eq 5) {
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($ports.Count -eq 0) {
        Write-Host ""
        Write-Host "   (No usable COM ports detected. Is anything plugged in?)" -ForegroundColor Yellow
        continue menu
    }
    Write-Host ""
    Write-Host "Detected ports:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $ports.Count; $i++) {
        $tag = if ($ports[$i].Kind -eq 'UNKNOWN') { '  [UNKNOWN - confirm this is really a board]' } else { '' }
        Write-Host ("   [{0}] {1,-7} ({2}){3}" -f ($i + 1), $ports[$i].Port, $ports[$i].Description, $tag)
    }

    $multi = Read-YesNo -Question "Identify MULTIPLE boards at once (like run_wizard.ps1)?" -Default $true
    $picked = @()
    if ($multi) {
        $picked = @(Select-MultiplePorts -Ports $ports -Action 'reset it to read a MAC')
    } else {
        $opts = @($ports | ForEach-Object {
            $tag = if ($_.Kind -eq 'UNKNOWN') { ' [UNKNOWN - confirm this is really the board]' } else { '' }
            "$($_.Port)  ($($_.Description))$tag"
        })
        $opts += 'Type it manually'
        $idx = Read-Choice -Title "Which port?" -Options $opts -Default 1
        if ($idx -le $ports.Count) {
            $pick = $ports[$idx - 1]
            if (Test-PortSafeToTouch -Port $pick.Port -Action 'reset it to read a MAC') { $picked = @($pick) }
        } else {
            $manual = (Read-Line "Enter COM port (e.g. COM8): ").Trim().ToUpper()
            if ($manual -and (Test-PortSafeToTouch -Port $manual -Action 'reset it to read a MAC')) {
                $picked = @([pscustomobject]@{ Port = $manual; Description = 'manual entry'; Kind = 'UNKNOWN' })
            }
        }
    }
    if ($picked.Count -eq 0) { Write-Host "Nothing to identify." -ForegroundColor Yellow; continue menu }

    # Fast read (--wait 1, same as run_wizard.ps1's Invoke-Identify): enough for
    # esptool's bootloader MAC read, without sitting through the full runtime
    # listen board_check.py otherwise does for a single-board health check.
    Write-Host ""
    Write-Host ("Reading {0} board(s) -- MAC + node number ..." -f $picked.Count) -ForegroundColor DarkGray
    $results = @()
    Push-Location (Join-Path $base 'tools')
    try {
        foreach ($p in $picked) {
            Write-Host ("  {0} ..." -f $p.Port) -ForegroundColor DarkGray
            $out = & python board_check.py --port $p.Port --wait 1
            $hit = $out | Select-String -Pattern 'MAC\s+([0-9a-fA-F:]{17})\s+->\s+(.+)$' | Select-Object -First 1
            if ($hit) {
                $mac  = $hit.Matches[0].Groups[1].Value.ToLower()
                $node = $hit.Matches[0].Groups[2].Value
                Write-Host ("    MAC {0}  ->  {1}" -f $mac, $node) -ForegroundColor Green
            } else {
                $mac  = $null
                $node = 'could not identify (no MAC read)'
                Write-Host ("    Could not read a MAC from {0} -- unplugged, port busy, or esptool unavailable." -f $p.Port) -ForegroundColor Yellow
            }
            $results += [pscustomobject]@{ Port = $p.Port; Mac = $mac; Node = $node }
        }
    } finally { Pop-Location }

    # Read once here so root/attacker rows below can be colored on the spot,
    # same as run_wizard.ps1's Invoke-IdentifyAllBoards.
    $configured = Get-ConfiguredAttackerMac

    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    foreach ($r in $results) {
        $macDisp = if ($r.Mac) { $r.Mac } else { '(unread)' }
        $role = if ($r.Node -match '\(ROOT\)') { 'root' } elseif ($configured -and $r.Mac -eq $configured) { 'attacker' } else { 'child' }
        Write-Host (Colorize-Role ("   {0,-7} {1,-17} {2}" -f $r.Port, $macDisp, $r.Node) $role)
    }

    # ---- cross-check against the compiled blackhole attacker MAC ------------
    # BLACKHOLE_ATTACKER_MAC is baked into VICTIM firmware at BUILD time (see
    # Confirm-BlackholeAttackerMac above) -- if it doesn't match whichever board
    # is actually wearing the attacker role right now, every victim probe
    # addresses a MAC nothing in the mesh holds and the whole run logs zero
    # arrivals with no error pointing at why. This reads the boards you just
    # identified against that compiled value so you can catch it here, before
    # any flashing happens.
    $configured = Get-ConfiguredAttackerMac
    Write-Host ""
    if (-not $configured) {
        Write-Host "   (Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h -- skipping attacker cross-check.)" -ForegroundColor DarkGray
        continue menu
    }
    Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $configured) -ForegroundColor Cyan
    $readOk  = @($results | Where-Object { $_.Mac })
    $matches = @($readOk | Where-Object { $_.Mac -eq $configured })

    if ($matches.Count -eq 1) {
        Write-Host ("   MATCH -- {0} ({1}) is the configured attacker. Victim boards will reach it." -f $matches[0].Port, $matches[0].Node) -ForegroundColor Green
        continue menu
    }
    if ($matches.Count -gt 1) {
        Write-Host ("   WARNING: {0} of the boards just read all report this SAME MAC -- that should not happen (duplicate/cloned MAC?)." -f $matches.Count) -ForegroundColor Red
        continue menu
    }
    if ($readOk.Count -eq 0) {
        Write-Host "   Could not confirm -- no MAC was successfully read from any board above." -ForegroundColor Yellow
        continue menu
    }

    Write-Host "   NO MATCH among the board(s) just read -- none of these is the configured attacker." -ForegroundColor Red
    Write-Host "   Victim probes targeting $configured will find nothing in the mesh and vanish for the" -ForegroundColor Red
    Write-Host "   WHOLE run (baseline included), with every blackhole feature coming out all-NaN." -ForegroundColor Red
    $fixOpts = @($readOk | ForEach-Object { "$($_.Port)  ($($_.Mac))  $($_.Node)" })
    $fixOpts += 'Leave as-is'
    $fixIdx = Read-Choice -Title "Point BLACKHOLE_ATTACKER_MAC at one of the boards just read instead?" -Options $fixOpts -Default $fixOpts.Count
    if ($fixIdx -le $readOk.Count) {
        $target = $readOk[$fixIdx - 1]
        if (Set-ConfiguredAttackerMac -Mac $target.Mac -PortLabel $target.Port) {
            Write-Host ("   Fixed -- mesh_config.h now targets {0} ({1}). The next build will pick it up." -f $target.Mac, $target.Port) -ForegroundColor Green
        } else {
            Write-Host "   Could not write mesh_config.h -- fix it by hand before flashing victims." -ForegroundColor Red
        }
    } else {
        Write-Host "   Left as-is -- victim boards will still target the wrong MAC until this is fixed." -ForegroundColor Yellow
    }
    continue menu
}

# ---- Wipe / erase a board ---------------------------------------------------
if ($action -eq 4) {
    # Role only feeds a REFLASH (which project's firmware to flash back on) --
    # a bare erase has nothing to reflash, so it's asked below only once $full
    # says a reflash is actually happening, same split run_wizard.ps1 makes.
    $modeIdx = Read-Choice -Title "Wipe how many boards?" -Options @('one board', 'SEVERAL boards at once (faster than one by one)') -Default 1 -AllowBack
    if ($script:BackSignal -eq $modeIdx) { continue menu }

    if ($modeIdx -eq 2) {
        # Ported from run_wizard.ps1's Invoke-WipeBoards "wipe SEVERAL boards"
        # path: bare esptool erase_flash, no role, no reflash -- a bulk wipe is
        # for clearing boards back to blank before they go back into rotation,
        # not for re-provisioning them.
        $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
        if ($ports.Count -eq 0) {
            Write-Host ""
            Write-Host "   (No usable COM ports detected. Is anything plugged in?)" -ForegroundColor Yellow
            continue menu
        }
        $picked = @(Select-MultiplePorts -Ports $ports -Action 'erase it')
        if ($picked.Count -eq 0) { continue menu }

        Write-Host ""
        Write-Host ("This PERMANENTLY erases everything on the {0} board(s) below -- firmware," -f $picked.Count) -ForegroundColor Yellow
        Write-Host "SD-status cache, all of it. There is no undo; each board must be reflashed" -ForegroundColor Yellow
        Write-Host "afterward to do anything." -ForegroundColor Yellow
        foreach ($p in $picked) { Write-Host ("   {0,-7} - {1}" -f $p.Port, $p.Description) }

        $cmdText = "esptool.py --chip esp32 --port <port> erase_flash   (for each of: {0})" -f (($picked | ForEach-Object { $_.Port }) -join ', ')
        if (-not (Show-And-Confirm $cmdText)) { continue menu }

        foreach ($p in $picked) {
            Write-Host ("`nErasing $($p.Port) (takes ~10-15s) ...") -ForegroundColor Yellow
            & esptool.py --chip esp32 --port $p.Port erase_flash
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("   {0} wiped clean." -f $p.Port) -ForegroundColor Green
                $script:IdentifiedPorts.Remove($p.Port) | Out-Null
            } else {
                Write-Host ("   erase_flash failed on {0} (exit {1}) -- port busy, board unplugged, or esptool not on PATH." -f $p.Port, $LASTEXITCODE) -ForegroundColor Red
            }
        }
        continue menu
    }

    $port = Select-Port -Action 'erase it' -AllowBack
    if ($script:BackSignal -eq $port) { continue menu }
    $full = Read-YesNo -Question "FULL chip erase + re-flash afterward? (fixes 'storage full' / crash-loops)" -Default $false -AllowBack
    if ($script:BackSignal -eq $full) { continue menu }

    if ($full) {
        $roleIdx = Read-Choice -Title "Board role (for the re-flash)?" -Options @('child / victim', 'root') -Default 1 -AllowBack
        if ($script:BackSignal -eq $roleIdx) { continue menu }
        if ($roleIdx -eq 2) { $role = 'root' } else { $role = 'child' }
        $p = @{ Port = $port; Role = $role; Wipe = $true; Flash = $true }
        $cmdText = ".\run.ps1 -Port $port -Role $role -Wipe -Flash"
        if (Show-And-Confirm $cmdText) { & $run @p }
        continue menu
    }

    # Bare wipe, no reflash: go straight at the chip instead of routing through
    # run.ps1 -- run.ps1 always ends a no-Flash invocation in an interactive
    # `idf.py monitor`, which nobody wants for a plain "make it blank" wipe.
    Write-Host ""
    Write-Host "This PERMANENTLY erases everything on $port -- firmware, SD-status cache, all" -ForegroundColor Yellow
    Write-Host "of it. There is no undo; the board must be reflashed afterward to do anything." -ForegroundColor Yellow
    $cmdText = "esptool.py --chip esp32 --port $port erase_flash"
    if (Show-And-Confirm $cmdText) {
        Write-Host ("`nErasing $port (takes ~10-15s) ...") -ForegroundColor Yellow
        & esptool.py --chip esp32 --port $port erase_flash
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("   {0} wiped clean." -f $port) -ForegroundColor Green
            $script:IdentifiedPorts.Remove($port) | Out-Null
        } else {
            Write-Host ("   erase_flash failed on {0} (exit {1}) -- port busy, board unplugged, or esptool not on PATH." -f $port, $LASTEXITCODE) -ForegroundColor Red
        }
    }
    continue menu
}

# ---- Write/update location.txt on an already-running board -------------------
# Ported from run_wizard.ps1's Invoke-SetLocationBoards (its MAINTENANCE [5]),
# which menu.ps1 had no equivalent of at all -- the only way to fix a board's
# site from here was to pull the card, or to switch launchers mid-session.
#
# A board whose card has no valid location.txt mirrors NOTHING to the card
# (csv_logger.c), and it says so only in its own boot log, so this is normally
# run the moment a board reports SD ENV trouble -- with the board already
# booted, which is exactly when the pull-the-card fix is most annoying.
#
# Every write path here READS the card first and shows "<was> -> <now>",
# skipping boards already sitting at the chosen site, rather than overwriting
# blind. And the pick is always a port someone named: no "apply to all
# enumerated ports" (see Select-MultiplePorts / Test-PortSafeToTouch).
if ($action -eq 10) {
    Write-Host ""
    Write-Host "This talks to the firmware ALREADY RUNNING on the board (GET/SET_LOCATION over" -ForegroundColor DarkGray
    Write-Host "USB), so the board must have booted and reached csv_logger_init(). It does NOT" -ForegroundColor DarkGray
    Write-Host "help a board that was never flashed -- write location.txt onto that card with a" -ForegroundColor DarkGray
    Write-Host "reader instead. The change takes effect on the board's NEXT boot." -ForegroundColor DarkGray

    $modeIdx = Read-Choice -Title "Write a location to how many boards?" -Options @(
        'one board',
        'SEVERAL boards at once (same location to each -- faster than one by one)'
    ) -Default 1 -AllowBack
    if ($script:BackSignal -eq $modeIdx) { continue menu }

    if ($modeIdx -eq 2) {
        $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
        if ($ports.Count -eq 0) {
            Write-Host ""
            Write-Host "   (No usable COM ports detected -- a charge-only USB cable creates no port.)" -ForegroundColor Yellow
            continue menu
        }
        Write-Host ""
        Write-Host "Detected ports:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $ports.Count; $i++) {
            $macTag  = if ($script:IdentifiedPorts.ContainsKey($ports[$i].Port)) { "  [{0}]" -f $script:IdentifiedPorts[$ports[$i].Port] } else { '' }
            $kindTag = if ($ports[$i].Kind -eq 'UNKNOWN') { '  [UNKNOWN - confirm this is really a board]' } else { '' }
            Write-Host ("   [{0}] {1,-7} ({2}){3}{4}" -f ($i + 1), $ports[$i].Port, $ports[$i].Description, $macTag, $kindTag)
        }

        $picked = @(Select-MultiplePorts -Ports $ports -Action 'write a location to it')
        if ($picked.Count -eq 0) { continue menu }

        $loc = Select-WriteLocation -Title "Write which location to the boards you picked?"
        if (-not $loc) { Write-Host "   Cancelled -- nothing written." -ForegroundColor DarkGray; continue menu }

        # Read each board FIRST, so the confirmation shows what is actually on
        # the card and what it would become. A board already sitting at $loc is
        # left alone entirely -- rewriting it is a pointless card write, and
        # listing it as "-> G402" hides that nothing needed doing.
        Write-Host ""
        Write-Host ("Reading each board's current location.txt ({0} board(s), a few seconds each) ..." -f $picked.Count) -ForegroundColor DarkGray
        $plan = @()
        foreach ($p in $picked) {
            $cur = Get-SdLocation -TargetPort $p.Port
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
            $tag = if ($script:IdentifiedPorts.ContainsKey($row.Port)) { "  [{0}]" -f $script:IdentifiedPorts[$row.Port] } else { '' }
            $was = Format-SdLocationState $row.Current
            if ($row.Skip) {
                Write-Host ("   {0,-7} {1,-38} already set - leaving alone{2}" -f $row.Port, $was, $tag) -ForegroundColor DarkGray
            } else {
                Write-Host ("   {0,-7} {1,-38} -> {2}{3}" -f $row.Port, $was, $loc, $tag)
            }
        }
        if ($blind.Count -gt 0) {
            Write-Host ""
            Write-Host ("{0} board(s) above could not be read -- for those this is still a BLIND" -f $blind.Count) -ForegroundColor Yellow
            Write-Host "overwrite of whatever the card holds. A board that has not booted yet, or" -ForegroundColor Yellow
            Write-Host "is running firmware from before GET_LOCATION, cannot report its location." -ForegroundColor Yellow
        }
        if ($toWrite.Count -eq 0) {
            Write-Host ""
            Write-Host "   Every board picked is already set to $loc -- nothing to write." -ForegroundColor Green
            continue menu
        }

        $cmdText = "python tools\export_logs.py --port <port> --set-location $loc   (for each of: {0})" -f (($toWrite | ForEach-Object { $_.Port }) -join ', ')
        if (-not (Show-And-Confirm $cmdText)) { Write-Host "   Skipped -- nothing written." -ForegroundColor DarkGray; continue menu }

        foreach ($row in $toWrite) {
            Write-Host ("`n  {0} SET_LOCATION=$loc ..." -f $row.Port) -ForegroundColor DarkGray
            $r = Set-SdLocation -TargetPort $row.Port -Location $loc
            $color = if ($r.Ok) { 'Green' } else { 'Yellow' }
            foreach ($line in $r.Lines) { Write-Host ("    " + $line) -ForegroundColor $color }
        }
        Write-Host ""
        Write-Host "Reboot or reflash each board above to confirm 'SD ENV: OK' before relying on it." -ForegroundColor DarkGray
        continue menu
    }

    $target = Select-Port -Action 'write a location to it' -AllowBack
    if ($script:BackSignal -eq $target) { continue menu }
    if (-not $target) { continue menu }

    # Check the card BEFORE offering the menu, so the choice is made knowing
    # what is already there. A board whose card reads NONE/INVALID is the one
    # actually losing data (csv_logger.c mirrors nothing without a valid
    # location), which is worth saying out loud at the moment of the fix.
    Write-Host ""
    Write-Host ("Reading {0}'s current location.txt (a few seconds) ..." -f $target) -ForegroundColor DarkGray
    $cur = Get-SdLocation -TargetPort $target
    Write-Host ""
    switch ($cur.State) {
        'OK'      { Write-Host ("{0} currently records to: {1}" -f $target, $cur.Value) -ForegroundColor Green }
        'NONE'    { Write-Host ("{0} has NO location.txt -- it is writing nothing to its SD card." -f $target) -ForegroundColor Yellow }
        'INVALID' { Write-Host ("{0} holds an unrecognised location '{1}' -- it is writing nothing to its SD card." -f $target, $cur.Value) -ForegroundColor Yellow }
        default   { Write-Host ("{0}'s current location.txt could not be read -- anything below is a BLIND overwrite." -f $target) -ForegroundColor Yellow }
    }

    $loc = Select-WriteLocation -Title "Set $target's location to:"
    if (-not $loc) { Write-Host "   Cancelled -- nothing written." -ForegroundColor DarkGray; continue menu }

    if ($cur.State -eq 'OK' -and $cur.Value -eq $loc) {
        Write-Host ("   {0} already records to {1} -- nothing to write." -f $target, $loc) -ForegroundColor Green
        continue menu
    }

    # Confirm before sending rather than after, since there is no undo.
    Write-Host ""
    Write-Host ("   {0}: {1} -> {2}" -f $target, (Format-SdLocationState $cur), $loc) -ForegroundColor Yellow
    $cmdText = "python tools\export_logs.py --port $target --set-location $loc"
    if (-not (Show-And-Confirm $cmdText)) { Write-Host "   Skipped -- nothing written." -ForegroundColor DarkGray; continue menu }

    Write-Host ("`n  {0} SET_LOCATION=$loc ..." -f $target) -ForegroundColor DarkGray
    $r = Set-SdLocation -TargetPort $target -Location $loc
    $color = if ($r.Ok) { 'Green' } else { 'Yellow' }
    foreach ($line in $r.Lines) { Write-Host ("    " + $line) -ForegroundColor $color }
    Write-Host "  Reboot or reflash this board to confirm 'SD ENV: OK' before relying on it." -ForegroundColor DarkGray
    continue menu
}

# ---- Export only ------------------------------------------------------------
if ($action -eq 3) {
    $port     = $null
    $roleIdx  = 1
    $topoIdx  = 1
    $attkIdx  = 1
    $scenario = 'none'
    $loc      = $null
    $label    = ''
    $repeat   = '1'
    $delete   = $false

    $step = 0
    :exportOnly while ($step -le 8) {
        switch ($step) {
            0 {
                $r = Select-Port -Action 'export logs from it' -AllowBack
                if ($script:BackSignal -eq $r) { continue menu }
                $port = $r; $step = 1; continue exportOnly
            }
            1 {
                $r = Read-Choice -Title "Board role?" -Options @('child / victim', 'root') -Default $roleIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 0; continue exportOnly }
                $roleIdx = $r; $step = 2; continue exportOnly
            }
            2 {
                $r = Read-Choice -Title "Topology this run used?" -Options @('tree', 'star', 'linear', 'partial') -Default $topoIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 1; continue exportOnly }
                $topoIdx = $r; $step = 3; continue exportOnly
            }
            3 {
                $r = Read-Choice -Title "Attack this run used?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 2; continue exportOnly }
                $attkIdx = $r; $step = 4; continue exportOnly
            }
            4 {
                $r = Select-Scenario -Current $scenario -AllowBack
                if ($script:BackSignal -eq $r) { $step = 3; continue exportOnly }
                $scenario = $r; $step = 5; continue exportOnly
            }
            5 {
                $r = Select-Location -Current $loc -AllowBack
                if ($script:BackSignal -eq $r) { $step = 4; continue exportOnly }
                $loc = $r; $step = 6; continue exportOnly
            }
            6 {
                $r = Read-Line "Board label / node id (e.g. node5), blank to skip: " -Default $label -AllowBack
                if ($script:BackSignal -eq $r) { $step = 5; continue exportOnly }
                $label = $r; $step = 7; continue exportOnly
            }
            7 {
                $r = Read-Line "Repeat number (r1/r2/r3 -> 1/2/3): " -Default $repeat -AllowBack
                if ($script:BackSignal -eq $r) { $step = 6; continue exportOnly }
                $repeat = if ([string]::IsNullOrWhiteSpace($r)) { '1' } else { $r }
                $step = 8; continue exportOnly
            }
            8 {
                $r = Read-YesNo -Question "Wipe the board AFTER a good download?" -Default $delete -AllowBack
                if ($script:BackSignal -eq $r) { $step = 7; continue exportOnly }
                $delete = $r; $step = 9; continue exportOnly
            }
        }
    }
    $role   = if ($roleIdx -eq 2) { 'root' } else { 'child' }
    $topo   = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $attack = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]

    $exArgs  = @('export_logs.py', '--port', $port, '--role', $role, '--topology', $topo, '--location', $loc, '--attack', $attack, '--repeat', $repeat, '--scenario', $scenario)
    $cmdText = "python tools\export_logs.py --port $port --role $role --topology $topo --location $loc --attack $attack --repeat $repeat --scenario $scenario"
    if (-not [string]::IsNullOrWhiteSpace($label)) { $exArgs += @('--label', $label); $cmdText += " --label $label" }
    if ($delete) { $exArgs += '--delete'; $cmdText += ' --delete' }
    if (Show-And-Confirm $cmdText) {
        Push-Location (Join-Path $base 'tools')
        try { python @exArgs } finally { Pop-Location }
    }
    continue menu
}

# ---- Run analysis only (M6->M8, no board contact) ---------------------------
# Same three-stage pipeline run.ps1's -Analyze switch drives automatically after
# a root export (preprocess.py -> features.py -> eda.py), exposed here standalone
# so an already-exported (or SD-imported) folder can be (re-)analyzed without
# touching a board -- e.g. after fixing a preprocessing bug, or analyzing a
# topology this laptop never itself flashed. Mirrors run_wizard.ps1's
# Invoke-RunAnalysisOnly - keep the two in sync.
if ($action -eq 7) {
    Write-Host ""
    Write-Host "Nothing here touches a board or a COM port -- runs the M6->M8 pipeline" -ForegroundColor DarkGray
    Write-Host "(preprocess.py -> features.py -> eda.py) over an already-exported folder." -ForegroundColor DarkGray

    $attkIdx  = 1
    $topoIdx  = 1
    $scenario = 'none'
    $loc      = $null

    $step = 0
    :analysisOnly while ($step -le 3) {
        switch ($step) {
            0 {
                $r = Read-Choice -Title "Which attack?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
                if ($script:BackSignal -eq $r) { continue menu }
                $attkIdx = $r; $step = 1; continue analysisOnly
            }
            1 {
                $r = Read-Choice -Title "Topology?" -Options @(
                    'tree     (default self-organising)',
                    'star     (all direct children of root)',
                    'linear   (forced chain)',
                    'partial  (physical placement)'
                ) -Default $topoIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 0; continue analysisOnly }
                $topoIdx = $r; $step = 2; continue analysisOnly
            }
            2 {
                $r = Select-Scenario -Current $scenario -AllowBack
                if ($script:BackSignal -eq $r) { $step = 1; continue analysisOnly }
                $scenario = $r; $step = 3; continue analysisOnly
            }
            3 {
                $r = Select-Location -Current $loc -AllowBack
                if ($script:BackSignal -eq $r) { $step = 2; continue analysisOnly }
                $loc = $r; $step = 4; continue analysisOnly
            }
        }
    }
    $attack  = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
    $topo    = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $topoDir = if ($topo -eq 'partial') { 'partial_mesh' } else { $topo }

    $attackDir   = if ($attack -eq 'none') { 'baseline' } else { $attack }
    $scenarioSeg = if ($scenario -and $scenario -ne 'none') { "\$scenario" } else { '' }
    $exportSub   = Join-Path $base "tools\exports\$attackDir\$topoDir\$loc$scenarioSeg"
    $analysisSub = Join-Path $base "analysis\$attackDir\$topoDir\$loc$scenarioSeg"

    if (-not (Test-Path $exportSub)) {
        Write-Host ""
        Write-Host ("No exported CSVs in {0} -- export a board or import a card for this run first." -f $exportSub) -ForegroundColor Yellow
        continue menu
    }

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
        Write-Host ""
        Write-Host "No python with pandas/numpy found -- pip install -r analysis\requirements.txt first." -ForegroundColor Yellow
        continue menu
    }

    if (-not (Test-Path $analysisSub)) { New-Item -ItemType Directory -Force -Path $analysisSub | Out-Null }
    $windowedOut = Join-Path $analysisSub 'windowed_dataset.csv'
    $featOut     = Join-Path $analysisSub 'feature_table.csv'
    $edaOut      = Join-Path $analysisSub 'eda_output'

    $cmdText = "python analysis\preprocess.py $exportSub -o $windowedOut`n   python analysis\features.py $exportSub -o $featOut"
    $cmdText += if ($edaPy) { "`n   python analysis\eda.py $featOut -o $edaOut" } else { "`n   (EDA/M8 skipped -- $featuresPy lacks matplotlib/seaborn/scipy/scikit-learn)" }
    if (-not (Show-And-Confirm $cmdText)) { continue menu }

    Push-Location (Join-Path $base 'analysis')
    try {
        Write-Host "`nM6: preprocess.py ..." -ForegroundColor Cyan
        & $featuresPy preprocess.py $exportSub -o $windowedOut
        if ($LASTEXITCODE -ne 0) { Write-Host "Preprocess failed (exit $LASTEXITCODE)." -ForegroundColor Red; continue menu }

        Write-Host "M7: features.py ..." -ForegroundColor Cyan
        & $featuresPy features.py $exportSub -o $featOut
        if ($LASTEXITCODE -ne 0) { Write-Host "Features step failed (exit $LASTEXITCODE)." -ForegroundColor Red; continue menu }

        if ($edaPy) {
            Write-Host "M8: eda.py ..." -ForegroundColor Cyan
            & $edaPy eda.py $featOut -o $edaOut
            if ($LASTEXITCODE -ne 0) {
                Write-Host "EDA failed (exit $LASTEXITCODE); feature_table.csv is fine, see the error above." -ForegroundColor Yellow
            } else {
                Write-Host ("Done -> analysis\$attackDir\$topoDir\$loc$scenarioSeg\eda_output\") -ForegroundColor Green
            }
        } else {
            Write-Host "Skipping M8/EDA: $featuresPy lacks matplotlib/seaborn/scipy/scikit-learn." -ForegroundColor Yellow
            Write-Host "  Fix once: pip install -r analysis\requirements.txt" -ForegroundColor DarkGray
        }
    } finally { Pop-Location }
    continue menu
}

# ---- Import CSVs from a pulled SD card ---------------------------------------
# The no-laptop counterpart to option 3 above: a board that ran on a wall
# charger/powerbank has no CSVs to pull over serial, only what csv_logger.c
# mirrored onto its card. Same tools\import_sdcard.py run_wizard.ps1 drives, so
# the two front-ends can't produce differently-named data for the same card.
#
# Asks the same attack/topology/location question the main "Run a board" flow
# below already asks, then a repeat number - roster and delete-on-verify are
# no longer separate questions. --delete-source is always on (that's the
# whole point: it frees the card so an old capture can't be dragged into an
# exports folder months later), which means a card normally holds exactly one
# un-imported file per board by the time it's pulled, and the roster is
# auto-matched from a saved preset for this exact attack/topology/location
# (a preset already lists the boards THAT run used). Mirrors
# run_wizard.ps1's Invoke-ImportSdCard - keep the two in sync.
if ($action -eq 8) {
    Write-Host ""
    Write-Host "Pop the card out of the board and read it with a card reader on THIS laptop." -ForegroundColor DarkGray
    Write-Host "Nothing here touches a board or a COM port." -ForegroundColor DarkGray

    $attkIdx  = 1
    $topoIdx  = 1
    $scenario = 'none'
    $loc      = $null
    $repeat   = '1'

    $step = 0
    :importCard while ($step -le 4) {
        switch ($step) {
            0 {
                $r = Read-Choice -Title "What attack was this capture?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
                if ($script:BackSignal -eq $r) { continue menu }
                $attkIdx = $r; $step = 1; continue importCard
            }
            1 {
                $r = Read-Choice -Title "Topology?" -Options @(
                    'tree     (default self-organising)',
                    'star     (all direct children of root)',
                    'linear   (forced chain)',
                    'partial  (physical placement)'
                ) -Default $topoIdx -AllowBack
                if ($script:BackSignal -eq $r) { $step = 0; continue importCard }
                $topoIdx = $r; $step = 2; continue importCard
            }
            2 {
                $r = Select-Scenario -Current $scenario -AllowBack
                if ($script:BackSignal -eq $r) { $step = 1; continue importCard }
                $scenario = $r; $step = 3; continue importCard
            }
            3 {
                $r = Select-Location -Current $loc -AllowBack
                if ($script:BackSignal -eq $r) { $step = 2; continue importCard }
                $loc = $r; $step = 4; continue importCard
            }
            4 {
                Write-Host ""
                Write-Host "Every card imported with this number is filed under it, whatever each board's" -ForegroundColor DarkGray
                Write-Host "OWN on-device run counter says -- that is what keeps one run's boards on one" -ForegroundColor DarkGray
                Write-Host "r-number instead of root=r1 while a child lands on r21." -ForegroundColor DarkGray
                $r = Read-Line "Repeat number for this card (r1/r2/r3 -> 1/2/3): " -Default $repeat -AllowBack
                if ($script:BackSignal -eq $r) { $step = 3; continue importCard }
                $repeat = if ([string]::IsNullOrWhiteSpace($r)) { '1' } else { $r }
                $step = 5; continue importCard
            }
        }
    }
    $attack = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
    $topo   = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]

    # Roster: auto-match a saved preset for this exact attack/topology/location -
    # that preset already lists the boards THIS run used (matched by MAC), so an
    # imported file is named exactly as a USB export of that same board would be
    # (child_node2_linear_blackhole_r1_...), not victim_NODE_<MAC>_.... Falls
    # back to the card's own naming (never an error) when nothing matches.
    $roster    = ''
    $presetDir = Join-Path $base 'presets'
    if (Test-Path $presetDir) {
        $presetMatches = @(Get-ChildItem -Path $presetDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                try { $cfg = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json } catch { $cfg = $null }
                # Older presets predate the scenario field -- treat a missing one as 'none'.
                $cfgScenario = if ($cfg -and $cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario } else { 'none' }
                if ($cfg -and [string]$cfg.attack -eq $attack -and [string]$cfg.topology -eq $topo -and [string]$cfg.location -eq $loc -and $cfgScenario -eq $scenario) {
                    [pscustomobject]@{ File = $_; Cfg = $cfg }
                }
            })
        if ($presetMatches.Count -eq 1) {
            $roster = $presetMatches[0].File.FullName
            Write-Host ("   Naming from preset {0} (matches {1}/{2}/{3}/{4})." -f $presetMatches[0].File.Name, $attack, $topo, $scenario, $loc) -ForegroundColor DarkGray
        }
        elseif ($presetMatches.Count -gt 1) {
            $rOpts = @($presetMatches | ForEach-Object { $_.File.Name })
            $rOpts += "No roster - keep the card's own victim_NODE_<MAC> naming"
            $rIdx  = Read-Choice -Title "Several saved presets match this attack/topology/scenario/location - name from which?" -Options $rOpts -Default 1
            if ($rIdx -le $presetMatches.Count) { $roster = $presetMatches[$rIdx - 1].File.FullName }
        }
        else {
            Write-Host "   No saved preset matches this attack/topology/scenario/location - files keep the card's own victim_NODE_<MAC> naming." -ForegroundColor DarkGray
        }
    }

    # Card: auto-pick when exactly one mounted drive has the attack-folder
    # shape (same "looks like ours" rule as Select-SdCard); only ask when
    # that's ambiguous (no card found yet, or several readers at once).
    $markers    = @('baseline', 'blackhole', 'wormhole')
    $cardLooks  = @{}
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $root = "$($d.Name):\"
        if (-not (Test-Path $root)) { continue }
        $cardLooks[$root] = [bool](@($markers | Where-Object { Test-Path (Join-Path $root $_) }).Count -gt 0)
    }
    $cardCandidates = @($cardLooks.Keys | Where-Object { $cardLooks[$_] })
    if ($cardCandidates.Count -eq 1) {
        $card = $cardCandidates[0]
        Write-Host ("   Using {0} (only drive with a baseline/blackhole/wormhole folder tree)." -f $card) -ForegroundColor DarkGray
    }
    else {
        $card = Select-SdCard
    }
    if ([string]::IsNullOrWhiteSpace($card)) {
        Write-Host "   No card path given -- nothing to import." -ForegroundColor Yellow
        continue menu
    }

    $imArgs  = @('import_sdcard.py', '--card', $card, '--repeat', $repeat, '--scenario', $scenario, '--delete-source')
    $cmdText = "python tools\import_sdcard.py --card `"$card`" --repeat $repeat --scenario $scenario --delete-source"
    if ($roster) { $imArgs += @('--roster', $roster); $cmdText += " --roster `"$roster`"" }

    # Preview before confirming, unlike the other actions here: with
    # --delete-source this is the step that releases the card's only copy, so
    # what it matched has to be visible BEFORE it runs, not after.
    Write-Host ""
    Write-Host "Preview (dry run -- nothing copied, nothing deleted):" -ForegroundColor Cyan
    Push-Location (Join-Path $base 'tools')
    try { python @imArgs --dry-run } finally { Pop-Location }

    if (Show-And-Confirm $cmdText) {
        Push-Location (Join-Path $base 'tools')
        try { python @imArgs } finally { Pop-Location }
    }
    continue menu
}

# ---- Run a board (the main flow) --------------------------------------------
# Step machine, same shape as run_wizard.ps1's :flow loop: every answer lives
# in a variable initialised BEFORE the loop, each step passes that variable
# back as its own -Default, and 'b' rewinds $step instead of unwinding the
# whole action. So going back and forward again re-offers what you already
# picked rather than resetting to the factory default.
#
# $dir is what makes SKIPPED steps work in both directions: a step that
# doesn't apply (no attack sub-role on a root board, no location when you're
# not exporting) does `$step += $dir` rather than jumping forward, so
# travelling backwards through it keeps going backwards instead of bouncing
# forward again on the step it just skipped.
$roleIdx  = 2
$topoIdx  = 1
$attkIdx  = 1
$scenario = 'none'
$bhIdx    = 1
$wIdx     = 2
$isScenarioTarget = $true
$label    = ''
$flash    = $true
$wipe     = $true
$export   = $true
$analyze  = $false
$clean    = $false
$loc      = $null
$port     = $null
$role     = 'child'
$topo     = 'tree'
$attack   = 'none'
$bhRole   = 'attacker'
$wEnd     = 'B'

$step = 0
$dir  = 1
:flow while ($step -le 14) {
    switch ($step) {

        0 {
            # Nothing earlier to land on -- 'b' here backs out of the action
            # entirely, the same place 'm' would go.
            $r = Select-Port -Action 'flash it' -AllowBack
            if ($script:BackSignal -eq $r) { continue menu }
            $port = $r
            $step = 1; $dir = 1; continue flow
        }

        1 {
            $r = Read-Choice -Title "Mesh role of THIS board?" -Options @('root', 'child / victim') -Default $roleIdx -AllowBack
            if ($script:BackSignal -eq $r) { $step = 0; $dir = -1; continue flow }
            $roleIdx = $r
            $role = if ($roleIdx -eq 1) { 'root' } else { 'child' }
            $step = 2; $dir = 1; continue flow
        }

        2 {
            $r = Read-Choice -Title "Topology (flash EVERY board in the run the SAME)?" -Options @(
                'tree     (default self-organising)',
                'star     (all direct children of root)',
                'linear   (forced chain)',
                'partial  (physical placement)'
            ) -Default $topoIdx -AllowBack
            if ($script:BackSignal -eq $r) { $step = 1; $dir = -1; continue flow }
            $topoIdx = $r
            $topo = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
            $step = 3; $dir = 1; continue flow
        }

        3 {
            $r = Read-Choice -Title "Attack for this run?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default $attkIdx -AllowBack
            if ($script:BackSignal -eq $r) { $step = 2; $dir = -1; continue flow }
            $attkIdx = $r
            $attack = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
            $step = 4; $dir = 1; continue flow
        }

        4 {
            $r = Select-Scenario -Current $scenario -AllowBack
            if ($script:BackSignal -eq $r) { $step = 3; $dir = -1; continue flow }
            $scenario = $r
            $step = 5; $dir = 1; continue flow
        }

        5 {
            if (-not ($attack -eq 'blackhole' -and $role -ne 'root')) { $step += $dir; continue flow }
            $r = Read-Choice -Title "Blackhole role of THIS board?" -Options @(
                'attacker  (relay that forwards then drops victim probes)',
                'victim    (sends its probes to the attacker MAC)'
            ) -Default $bhIdx -AllowBack
            if ($script:BackSignal -eq $r) { $step = 4; $dir = -1; continue flow }
            $bhIdx  = $r
            $bhRole = if ($bhIdx -eq 2) { 'victim' } else { 'attacker' }

            if ($bhRole -eq 'attacker') {
                Confirm-BlackholeAttackerMac -AttackerPort $port -AttackerLabel $port
            } else {
                $configuredMac = Get-ConfiguredAttackerMac
                if ($configuredMac) {
                    Write-Host ""
                    Write-Host "   FYI: mesh_config.h BLACKHOLE_ATTACKER_MAC = $configuredMac -- this victim's" -ForegroundColor DarkGray
                    Write-Host "   probes go to that MAC. Confirm it's actually the attacker board's live MAC" -ForegroundColor DarkGray
                    Write-Host "   (menu -> Identify a board, or flash the attacker with this same menu first)." -ForegroundColor DarkGray
                }
            }
            $step = 6; $dir = 1; continue flow
        }

        6 {
            if (-not ($attack -eq 'wormhole' -and $role -ne 'root')) { $step += $dir; continue flow }
            $r = Read-Choice -Title "Wormhole tunnel end of THIS board? (UART cable A<->B required)" -Options @(
                'A  (exit / root-side: re-injects to root)',
                'B  (entry / leaf-side: captures + tunnels)'
            ) -Default $wIdx -AllowBack
            if ($script:BackSignal -eq $r) { $step = 5; $dir = -1; continue flow }
            $wIdx = $r
            $wEnd = if ($wIdx -eq 1) { 'A' } else { 'B' }
            $step = 7; $dir = 1; continue flow
        }

        7 {
            # This flow flashes ONE board per run, so there's no roster to check
            # "exactly one target" against -- just ask whether THIS board is it.
            # Burst also needs a plain send path (not the attacker relay / a
            # wormhole tunnel end), since only victim_main.c carries the burst logic.
            if (-not ($role -ne 'root' -and (Test-ScenarioNeedsTarget $scenario))) {
                $isScenarioTarget = $false
                $step += $dir; continue flow
            }
            $burstEligible = -not (($attack -eq 'blackhole' -and $bhRole -eq 'attacker') -or $attack -eq 'wormhole')
            if ($scenario -eq 'burst' -and -not $burstEligible) {
                Write-Host "   NOTE: an attacker/wormhole board can't carry the burst -- pick a plain victim as the target instead." -ForegroundColor Yellow
                $isScenarioTarget = $false
                $step += $dir; continue flow
            }
            $r = Read-YesNo -Question "Is THIS board the $scenario TARGET (the one that bursts / is moved / is power-cycled)?" -Default $isScenarioTarget -AllowBack
            if ($script:BackSignal -eq $r) { $step = 6; $dir = -1; continue flow }
            $isScenarioTarget = $r
            $step = 8; $dir = 1; continue flow
        }

        8 {
            $r = Read-Line "Board label / node id (e.g. node5), blank to skip: " -Default $label -AllowBack
            if ($script:BackSignal -eq $r) { $step = 7; $dir = -1; continue flow }
            $label = $r
            $step = 9; $dir = 1; continue flow
        }

        9 {
            $r = Read-YesNo -Question "Flash the firmware first? (needed to apply topology/attack)" -Default $flash -AllowBack
            if ($script:BackSignal -eq $r) { $step = 8; $dir = -1; continue flow }
            $flash = $r
            $step = 10; $dir = 1; continue flow
        }

        10 {
            $r = Read-YesNo -Question "Wipe/erase board BEFORE this run (fresh, unstacked run)?" -Default $wipe -AllowBack
            if ($script:BackSignal -eq $r) { $step = 9; $dir = -1; continue flow }
            $wipe = $r
            $step = 11; $dir = 1; continue flow
        }

        11 {
            $r = Read-YesNo -Question "Export the CSVs when you exit the monitor?" -Default $export -AllowBack
            if ($script:BackSignal -eq $r) { $step = 10; $dir = -1; continue flow }
            $export = $r
            # Answering "no" here retires every export-only answer, so a
            # forward pass can't smuggle a stale location/analyze/clean from
            # an earlier "yes" into the command line.
            if (-not $export) { $loc = $null; $analyze = $false; $clean = $false }
            $step = 12; $dir = 1; continue flow
        }

        12 {
            if (-not $export) { $step += $dir; continue flow }
            $r = Select-Location -Current $loc -AllowBack
            if ($script:BackSignal -eq $r) { $step = 11; $dir = -1; continue flow }
            $loc = $r
            $step = 13; $dir = 1; continue flow
        }

        13 {
            if (-not ($export -and $role -eq 'root')) { $step += $dir; continue flow }
            $r = Read-YesNo -Question "Auto-run analysis (M6+M7+M8) after export? (do this on the ROOT, exported LAST)" -Default $analyze -AllowBack
            if ($script:BackSignal -eq $r) { $step = 12; $dir = -1; continue flow }
            $analyze = $r
            $step = 14; $dir = 1; continue flow
        }

        14 {
            if (-not $export) { $step += $dir; continue flow }
            $r = Read-YesNo -Question "Wipe the board AFTER a good export?" -Default $clean -AllowBack
            if ($script:BackSignal -eq $r) { $step = 13; $dir = -1; continue flow }
            $clean = $r
            $step = 15; $dir = 1; continue flow
        }
    }
}

$p = @{ Port = $port; Role = $role; Topology = $topo; Attack = $attack; Scenario = $scenario }
$cmdText = ".\run.ps1 -Port $port -Role $role -Topology $topo -Attack $attack -Scenario $scenario"
if (-not [string]::IsNullOrWhiteSpace($label)) { $p['Label'] = $label; $cmdText += " -Label $label" }
if ($attack -eq 'blackhole' -and $role -ne 'root') { $p['BlackholeRole'] = $bhRole; $cmdText += " -BlackholeRole $bhRole" }
if ($attack -eq 'wormhole'  -and $role -ne 'root') { $p['WormholeEnd']   = $wEnd;   $cmdText += " -WormholeEnd $wEnd" }
if ($isScenarioTarget) { $p['ScenarioTarget'] = $true; $cmdText += ' -ScenarioTarget' }
if ($wipe)    { $p['Wipe']    = $true; $cmdText += ' -Wipe' }
if ($flash)   { $p['Flash']   = $true; $cmdText += ' -Flash' }
if ($export)  { $p['Export']  = $true; $p['Location'] = $loc; $cmdText += " -Export -Location $loc" }
if ($clean)   { $p['Clean']   = $true; $cmdText += ' -Clean' }
if ($analyze) { $p['Analyze'] = $true; $cmdText += ' -Analyze' }

if ($attack -eq 'wormhole') {
    Write-Host ""
    Write-Host "REMINDER (wormhole): wire the UART tunnel BEFORE powering on -" -ForegroundColor Yellow
    Write-Host "   Node A GPIO17(TX) -> Node B GPIO16(RX), Node A GPIO16(RX) -> Node B GPIO17(TX), shared GND." -ForegroundColor Yellow
    Write-Host "   Run all THREE boards (root + A + B) with the same Attack=wormhole and Flash." -ForegroundColor Yellow
}

# ---- estimated time (ported from run_wizard.ps1) ----------------------------
$durations    = Get-PhaseDurations
$warmBuildMin = 2
$coldBuildMin = 4
$buildSec     = 0
$buildIsCold  = $false
if ($flash) {
    $spec = Get-BuildDirSpec -Params $p
    $buildIsCold = -not (Test-Path $spec.BuildDir)
    $buildSec = ($(if ($buildIsCold) { $coldBuildMin } else { $warmBuildMin })) * 60
}
$rootSec  = if ($role -eq 'root' -and $export) { [int]$durations.Total } else { 0 }
$totalSec = $buildSec + $rootSec
if ($buildSec -gt 0 -or $rootSec -gt 0) {
    $finishAt = (Get-Date).AddSeconds($totalSec)
    Write-Host ""
    Write-Host "  Estimated time" -ForegroundColor Cyan
    if ($buildSec -gt 0) {
        $tag = if ($buildIsCold) { "cold build @ ~$coldBuildMin min" } else { "warm build @ ~$warmBuildMin min" }
        Write-Host ("    Build + flash     ~{0}          ({1} - varies with your machine)" -f (Format-Duration $buildSec), $tag) -ForegroundColor DarkGray
    }
    if ($rootSec -gt 0) {
        $phaseNote = "$($durations.Stabilise)s stabilise + $($durations.Baseline)s baseline + $($durations.Attack)s attack + $($durations.Cooldown)s cooldown"
        if ($durations.Ok) {
            Write-Host ("    Root experiment   {0,-8} ({1})" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor DarkGray
        } else {
            Write-Host ("    Root experiment   ~{0,-7} ({1}) -- mesh_config.h unreadable, this is a HARDCODED FALLBACK, not measured" -f (Format-Duration $rootSec), $phaseNote) -ForegroundColor Yellow
        }
        Write-Host "    (this board sits here through the whole experiment before Ctrl+] exports it)" -ForegroundColor DarkGray
    }
    Write-Host "    ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("    Total            ~{0}, finishing around {1}" -f (Format-Duration $totalSec), $finishAt.ToString('HH:mm')) -ForegroundColor Cyan
}

if (Show-And-Confirm $cmdText) { & $run @p }

}
catch {
    # Only the 'm' escape is handled here; every real failure keeps its original
    # behaviour (message, stack, non-zero exit) by being rethrown untouched.
    if ($_.Exception.Message -ne $script:MainMenuSignal) { throw }
    Write-Host ""
    Write-Host "Back to the main menu - nothing else was touched." -ForegroundColor Cyan
    continue menu
}
}
