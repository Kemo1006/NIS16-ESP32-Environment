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
  board (MAC/node), running the M6->M8 analysis pipeline standalone on
  already-exported CSVs, and verifying a captured attack against the
  published 3-sigma signature. Thin wrapper over run.ps1 + tools\*.py, so
  nothing about the dataset or firmware changes.
  For saved rosters/presets, MAC-drift checks across repeats, or bulk
  set-location on many boards, see run_wizard.ps1 instead.
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
    if ($Default) { $hint = 'Y/n' } else { $hint = 'y/N' }
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

function Select-Location {
    # run.ps1 requires -Location whenever -Export/-Clean/-Analyze is used, so
    # any flow that can export asks this. Keep the ValidateSet in run.ps1 in sync.
    $locs = @('home', 'G402', 'DLSU_Library', 'Goks')
    $idx  = Read-Choice -Title "Where was this run captured?" -Options $locs -Default 1
    return $locs[$idx - 1]
}

function Select-Scenario {
    # Run-to-run variation the panel asked for. 'none' is byte-identical to the
    # old behaviour. Keep this option list in sync with run.ps1's ValidateSet.
    $opts = @(
        'none        (today''s behaviour -- no variation)',
        'burst       (CODE: one child fires 100 probes back-to-back in the attack window)',
        'highload    (CODE: every child probes 4x faster for the whole run)',
        'mobility    (HUMAN: you move one child from spot A to spot B -- checklist only)',
        'powercycle  (HUMAN: you unplug/replug one child -- checklist only)'
    )
    $idx = Read-Choice -Title "Scenario for this run (every board in the run gets the SAME one)?" -Options $opts -Default 1
    return @('none', 'burst', 'highload', 'mobility', 'powercycle')[$idx - 1]
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

    $idx = Read-Choice -Title "Which card? (insert it first)" -Options $opts -Default 1
    if ($idx -eq $opts.Count) { return (Read-Line "Card path (e.g. E:\): ") }
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

function Confirm-BlackholeAttackerMac {
    # Cross-checks mesh_config.h's compiled BLACKHOLE_ATTACKER_MAC against the
    # ATTACKER board's ACTUAL live MAC (read over serial, no custom firmware
    # needed), before any build/flash happens. Offers to auto-fix the header
    # right here so the very next build picks up the correction.
    param([string]$AttackerPort, [string]$AttackerLabel = $null)

    $want = Get-ConfiguredAttackerMac
    Write-Host ""
    Write-Host "Checking BLACKHOLE_ATTACKER_MAC against $AttackerPort's live MAC ..." -ForegroundColor DarkGray
    if (-not $want) {
        Write-Host "   Could not read BLACKHOLE_ATTACKER_MAC from mesh_config.h -- skipping check." -ForegroundColor Yellow
        return
    }
    $live = Get-LiveBoardMac -TargetPort $AttackerPort
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

    $topoIdx = Read-Choice -Title "Topology (every board, same)?" -Options @(
        'tree     (default self-organising)',
        'star     (all direct children of root)',
        'linear   (forced chain)',
        'partial  (physical placement)'
    ) -Default 1
    $topo = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]

    $attkIdx = Read-Choice -Title "Attack for this run (every board, same)?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
    $attack  = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]

    $scenario = Select-Scenario

    $flash  = Read-YesNo -Question "Flash firmware on every board first?" -Default $true
    $wipe   = Read-YesNo -Question "Wipe/erase every board BEFORE this run?" -Default $true
    $export = Read-YesNo -Question "Export CSVs from every board when its monitor is exited?" -Default $true
    $clean  = $false
    $loc    = $null
    if ($export) {
        $loc   = Select-Location
        $clean = Read-YesNo -Question "Wipe each board AFTER a good export?" -Default $false
    }

    if ($attack -eq 'wormhole') {
        Write-Host ""
        Write-Host "REMINDER (wormhole): wire the UART tunnel BEFORE powering on -" -ForegroundColor Yellow
        Write-Host "   Node A GPIO17(TX) -> Node B GPIO16(RX), Node A GPIO16(RX) -> Node B GPIO17(TX), shared GND." -ForegroundColor Yellow
    }

    # ---- add boards one at a time --------------------------------------------
    $boards = @()
    $haveRoot = $false
    $haveScenarioTarget = $false
    while ($true) {
        Write-Host ""
        Write-Host ("--- Board {0} " -f ($boards.Count + 1)) -ForegroundColor Cyan
        $taken = @($boards | ForEach-Object { $_.Port })
        $port  = Select-BoardPort -Taken $taken

        $roleOpts = if ($haveRoot) { @('child / victim') } else { @('root', 'child / victim') }
        $roleIdx  = Read-Choice -Title "Mesh role of THIS board?" -Options $roleOpts -Default 1
        $role = if (-not $haveRoot -and $roleIdx -eq 1) { 'root' } else { 'child' }
        if ($role -eq 'root') { $haveRoot = $true }

        $bhRole = 'attacker'
        $wEnd   = 'B'
        if ($attack -eq 'blackhole' -and $role -ne 'root') {
            $i = Read-Choice -Title "Blackhole role of THIS board?" -Options @(
                'attacker  (relay that forwards then drops victim probes)',
                'victim    (sends its probes to the attacker MAC)'
            ) -Default 1
            if ($i -eq 2) { $bhRole = 'victim' } else { $bhRole = 'attacker' }
        }
        if ($attack -eq 'wormhole' -and $role -ne 'root') {
            $i = Read-Choice -Title "Wormhole tunnel end of THIS board?" -Options @(
                'A  (exit / root-side: re-injects to root)',
                'B  (entry / leaf-side: captures + tunnels)'
            ) -Default 2
            if ($i -eq 1) { $wEnd = 'A' } else { $wEnd = 'B' }
        }

        # Scenario target: exactly one child. Burst also needs a plain send path
        # (not the attacker relay / a wormhole tunnel end) since only
        # victim_main.c carries the burst logic -- so a blackhole ATTACKER or a
        # wormhole A/B board is not offered the question.
        $isScenarioTarget = $false
        if ($role -ne 'root' -and (Test-ScenarioNeedsTarget $scenario) -and -not $haveScenarioTarget) {
            $burstEligible = -not (($attack -eq 'blackhole' -and $bhRole -eq 'attacker') -or $attack -eq 'wormhole')
            if ($scenario -ne 'burst' -or $burstEligible) {
                $isScenarioTarget = Read-YesNo -Question "Is THIS board the $scenario TARGET (the one that bursts / is moved / is power-cycled)?" -Default $false
                if ($isScenarioTarget) { $haveScenarioTarget = $true }
            }
        }

        $label = Read-Line "Board label / node id (e.g. node5), blank to skip: "

        $p = @{ Port = $port; Role = $role; Topology = $topo; Attack = $attack; Scenario = $scenario }
        $cmdText = ".\run.ps1 -Port $port -Role $role -Topology $topo -Attack $attack -Scenario $scenario"
        if (-not [string]::IsNullOrWhiteSpace($label)) {
            if ($label -notmatch '^[A-Za-z0-9_\-]+$') {
                Write-Host "   Label must be letters/digits/_/- only -- skipping label for this board." -ForegroundColor Yellow
            } else {
                $p['Label'] = $label; $cmdText += " -Label $label"
            }
        }
        if ($attack -eq 'blackhole' -and $role -ne 'root') { $p['BlackholeRole'] = $bhRole; $cmdText += " -BlackholeRole $bhRole" }
        if ($attack -eq 'wormhole'  -and $role -ne 'root') { $p['WormholeEnd']   = $wEnd;   $cmdText += " -WormholeEnd $wEnd" }
        if ($isScenarioTarget) { $p['ScenarioTarget'] = $true; $cmdText += ' -ScenarioTarget' }
        if ($wipe)  { $p['Wipe']  = $true; $cmdText += ' -Wipe' }
        if ($flash) { $p['Flash'] = $true; $cmdText += ' -Flash' }
        if ($export) { $p['Export'] = $true; $p['Location'] = $loc; $cmdText += " -Export -Location $loc" }
        if ($clean) { $p['Clean'] = $true; $cmdText += ' -Clean' }
        # -Analyze is assigned to the root ONLY, once the full plan is known
        # (below) -- never asked per board, since it must land on the LAST
        # board exported (the root) so arrivals.csv covers the whole run.

        $boards += [pscustomobject]@{ Port = $port; Role = $role; Label = $label; Params = $p; CmdText = $cmdText; Kind = ((Get-PortList | Where-Object { $_.Port -eq $port } | Select-Object -First 1).Kind) }

        if (-not (Read-YesNo -Question "Add another board?" -Default $true)) { break }
    }

    if ($boards.Count -eq 0) { Write-Host "No boards added." -ForegroundColor Yellow; continue menu }

    # Sanity warnings (non-fatal)
    if (-not $haveRoot) { Write-Host "`nWARNING: no ROOT board in this plan -- a mesh needs exactly one." -ForegroundColor Yellow }
    if ($attack -eq 'wormhole') {
        $aCount = ($boards | Where-Object { $_.Params.WormholeEnd -eq 'A' }).Count
        $bCount = ($boards | Where-Object { $_.Params.WormholeEnd -eq 'B' }).Count
        if ($aCount -ne 1 -or $bCount -ne 1) { Write-Host "`nWARNING: wormhole needs exactly one A and one B tunnel end (found A=$aCount B=$bCount)." -ForegroundColor Yellow }
    }
    if ($attack -eq 'blackhole') {
        $atkBoard = $boards | Where-Object { $_.Params.BlackholeRole -eq 'attacker' } | Select-Object -First 1
        $atkCount = ($boards | Where-Object { $_.Params.BlackholeRole -eq 'attacker' }).Count
        if ($atkCount -ne 1) {
            Write-Host "`nWARNING: blackhole normally wants exactly one attacker board (found $atkCount)." -ForegroundColor Yellow
        } else {
            $atkLbl = if ($atkBoard.Label) { $atkBoard.Label } else { $atkBoard.Port }
            Confirm-BlackholeAttackerMac -AttackerPort $atkBoard.Port -AttackerLabel $atkLbl
        }
    }
    if ((Test-ScenarioNeedsTarget $scenario) -and -not $haveScenarioTarget) {
        Write-Host "`nWARNING: -Scenario $scenario needs exactly one board marked as the target (none was) -- go back and add one, or the scenario won't do anything." -ForegroundColor Yellow
    }

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
    # matter what order it was added in.
    $children  = @($boards | Where-Object { $_.Role -ne 'root' })
    $rootBoard = $boards | Where-Object { $_.Role -eq 'root' } | Select-Object -First 1
    $boards = @($children)
    if ($rootBoard) { $boards += $rootBoard }

    # ---- plan table + per-board confirm (no blind apply-to-all) -------------
    Write-Host ""
    Write-Host "Plan:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $boards.Count; $i++) {
        $b = $boards[$i]
        Write-Host ("  [{0}] {1,-6} {2,-5} {3}" -f ($i + 1), $b.Port, $b.Role, $b.CmdText) -ForegroundColor White
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
    $attkIdx = Read-Choice -Title "Which attack to verify?" -Options @('auto-detect', 'blackhole', 'wormhole') -Default 1
    $attack  = @('auto', 'blackhole', 'wormhole')[$attkIdx - 1]
    $topoIdx = Read-Choice -Title "Topology?" -Options @('tree', 'star', 'linear', 'partial') -Default 1
    $topo    = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $loc     = Select-Location
    $table   = Join-Path $base "analysis\$attack\$topo\$loc\feature_table.csv"
    if ($attack -eq 'auto') { $table = Join-Path $base "analysis\blackhole\$topo\$loc\feature_table.csv" }
    $typed   = Read-Line ("feature_table.csv path [default: {0}]: " -f $table)
    if (-not [string]::IsNullOrWhiteSpace($typed)) { $table = $typed }
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
    $port = Select-Port -Action 'erase it'
    $roleIdx = Read-Choice -Title "Board role (only matters if you also re-flash)?" -Options @('child / victim', 'root') -Default 1
    if ($roleIdx -eq 2) { $role = 'root' } else { $role = 'child' }
    $full = Read-YesNo -Question "FULL chip erase + re-flash? (fixes 'storage full' / crash-loops)" -Default $false
    $p = @{ Port = $port; Role = $role; Wipe = $true }
    $cmdText = ".\run.ps1 -Port $port -Role $role -Wipe"
    if ($full) { $p['Flash'] = $true; $cmdText += ' -Flash' }
    if (Show-And-Confirm $cmdText) { & $run @p }
    continue menu
}

# ---- Export only ------------------------------------------------------------
if ($action -eq 3) {
    $port = Select-Port -Action 'export logs from it'
    $roleIdx = Read-Choice -Title "Board role?" -Options @('child / victim', 'root') -Default 1
    if ($roleIdx -eq 2) { $role = 'root' } else { $role = 'child' }
    $topoIdx  = Read-Choice -Title "Topology this run used?" -Options @('tree', 'star', 'linear', 'partial') -Default 1
    $topo     = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $attkIdx  = Read-Choice -Title "Attack this run used?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
    $attack   = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
    $scenario = Select-Scenario
    $loc      = Select-Location
    $label    = Read-Line "Board label / node id (e.g. node5), blank to skip: "
    $repeat   = Read-Line "Repeat number (r1/r2/r3 -> 1/2/3) [default 1]: "
    if ([string]::IsNullOrWhiteSpace($repeat)) { $repeat = '1' }
    $delete   = Read-YesNo -Question "Wipe the board AFTER a good download?" -Default $false

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

    $attkIdx = Read-Choice -Title "Which attack?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
    $attack  = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]

    $topoIdx = Read-Choice -Title "Topology?" -Options @(
        'tree     (default self-organising)',
        'star     (all direct children of root)',
        'linear   (forced chain)',
        'partial  (physical placement)'
    ) -Default 1
    $topo    = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $topoDir = if ($topo -eq 'partial') { 'partial_mesh' } else { $topo }

    $scenario = Select-Scenario
    $loc      = Select-Location

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

    $attkIdx = Read-Choice -Title "What attack was this capture?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
    $attack  = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]

    $topoIdx = Read-Choice -Title "Topology?" -Options @(
        'tree     (default self-organising)',
        'star     (all direct children of root)',
        'linear   (forced chain)',
        'partial  (physical placement)'
    ) -Default 1
    $topo = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]

    $scenario = Select-Scenario
    $loc = Select-Location

    Write-Host ""
    Write-Host "Every card imported with this number is filed under it, whatever each board's" -ForegroundColor DarkGray
    Write-Host "OWN on-device run counter says -- that is what keeps one run's boards on one" -ForegroundColor DarkGray
    Write-Host "r-number instead of root=r1 while a child lands on r21." -ForegroundColor DarkGray
    $repeat = Read-Line "Repeat number for this card (r1/r2/r3 -> 1/2/3) [default 1]: "
    if ([string]::IsNullOrWhiteSpace($repeat)) { $repeat = '1' }

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
$port = Select-Port -Action 'flash it'
$roleIdx = Read-Choice -Title "Mesh role of THIS board?" -Options @('root', 'child / victim') -Default 2
if ($roleIdx -eq 1) { $role = 'root' } else { $role = 'child' }

$topoIdx = Read-Choice -Title "Topology (flash EVERY board in the run the SAME)?" -Options @(
    'tree     (default self-organising)',
    'star     (all direct children of root)',
    'linear   (forced chain)',
    'partial  (physical placement)'
) -Default 1
$topo = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]

$attkIdx = Read-Choice -Title "Attack for this run?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
$attack  = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]

$scenario = Select-Scenario

$bhRole = 'attacker'
$wEnd   = 'B'
if ($attack -eq 'blackhole' -and $role -ne 'root') {
    $i = Read-Choice -Title "Blackhole role of THIS board?" -Options @(
        'attacker  (relay that forwards then drops victim probes)',
        'victim    (sends its probes to the attacker MAC)'
    ) -Default 1
    if ($i -eq 2) { $bhRole = 'victim' } else { $bhRole = 'attacker' }

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
}
if ($attack -eq 'wormhole' -and $role -ne 'root') {
    $i = Read-Choice -Title "Wormhole tunnel end of THIS board? (UART cable A<->B required)" -Options @(
        'A  (exit / root-side: re-injects to root)',
        'B  (entry / leaf-side: captures + tunnels)'
    ) -Default 2
    if ($i -eq 1) { $wEnd = 'A' } else { $wEnd = 'B' }
}

# This flow flashes ONE board per run, so there's no roster to check "exactly
# one target" against -- just ask whether THIS board is it. Burst also needs a
# plain send path (not the attacker relay / a wormhole tunnel end), since only
# victim_main.c carries the burst logic.
$isScenarioTarget = $false
if ($role -ne 'root' -and (Test-ScenarioNeedsTarget $scenario)) {
    $burstEligible = -not (($attack -eq 'blackhole' -and $bhRole -eq 'attacker') -or $attack -eq 'wormhole')
    if ($scenario -ne 'burst' -or $burstEligible) {
        $isScenarioTarget = Read-YesNo -Question "Is THIS board the $scenario TARGET (the one that bursts / is moved / is power-cycled)?" -Default $true
    } else {
        Write-Host "   NOTE: an attacker/wormhole board can't carry the burst -- pick a plain victim as the target instead." -ForegroundColor Yellow
    }
}

$label   = Read-Line "Board label / node id (e.g. node5), blank to skip: "
$flash   = Read-YesNo -Question "Flash the firmware first? (needed to apply topology/attack)" -Default $true
$wipe    = Read-YesNo -Question "Wipe/erase board BEFORE this run (fresh, unstacked run)?" -Default $true
$export  = Read-YesNo -Question "Export the CSVs when you exit the monitor?" -Default $true
$analyze = $false
$clean   = $false
$loc     = $null
if ($export) {
    $loc = Select-Location
    if ($role -eq 'root') {
        $analyze = Read-YesNo -Question "Auto-run analysis (M6+M7+M8) after export? (do this on the ROOT, exported LAST)" -Default $false
    }
    $clean = Read-YesNo -Question "Wipe the board AFTER a good export?" -Default $false
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
