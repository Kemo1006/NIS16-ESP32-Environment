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
  board (MAC/node), and verifying a captured attack against the published
  3-sigma signature. Thin wrapper over run.ps1 + tools\*.py, so nothing
  about the dataset or firmware changes.
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

function Read-Choice {
    param([string]$Title, [string[]]$Options, [int]$Default = 1)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("   [{0}] {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $ans = Read-Host ("Choice [default {0}]" -f $Default)
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $Options.Count) { return [int]$ans }
        Write-Host ("   Enter a number 1..{0}." -f $Options.Count) -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $true)
    if ($Default) { $hint = 'Y/n' } else { $hint = 'y/N' }
    while ($true) {
        $ans = Read-Host ("{0} [{1}]" -f $Question, $hint)
        if ([string]::IsNullOrWhiteSpace($ans)) { return $Default }
        $a = $ans.Trim().ToLower()
        if ($a -like 'y*') { return $true }
        if ($a -like 'n*') { return $false }
        Write-Host "   Please answer y or n." -ForegroundColor Yellow
    }
}

function Select-Port {
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)
    if ($ports.Count -gt 0) {
        $opts = @($ports + @('Type it manually'))
        $idx  = Read-Choice -Title "Which COM port (board)?" -Options $opts -Default 1
        if ($idx -le $ports.Count) { return $ports[$idx - 1] }
    } else {
        Write-Host "   (No COM ports detected. Is the board plugged in?)" -ForegroundColor Yellow
    }
    return (Read-Host "Enter COM port (e.g. COM8)")
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
    if ($idx -eq $opts.Count) { return (Read-Host "Card path (e.g. E:\)") }
    return $roots[$idx - 1]
}

function Show-And-Confirm {
    param([string]$CommandText)
    Write-Host ""
    Write-Host "Equivalent command:" -ForegroundColor DarkGray
    Write-Host ("   " + $CommandText) -ForegroundColor White
    return (Read-YesNo -Question "Run this now?" -Default $true)
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

function Select-BoardPort {
    # Like Select-Port, but filters to ESP32-shaped bridges (BLOCKED never
    # shown) and refuses a port already claimed by an earlier board in this
    # same multi-board plan.
    param([string[]]$Taken = @())
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' -and ($Taken -notcontains $_.Port) })
    if ($ports.Count -eq 0) {
        Write-Host "   (No usable COM ports detected -- plugged in? already used by another board in this plan?)" -ForegroundColor Yellow
        return (Read-Host "Enter COM port (e.g. COM8)").Trim().ToUpper()
    }
    $opts = @($ports | ForEach-Object {
        $tag = if ($_.Kind -eq 'UNKNOWN') { ' [UNKNOWN - confirm this is really the board]' } else { '' }
        "$($_.Port)  ($($_.Description))$tag"
    })
    $opts += 'Type it manually'
    $idx = Read-Choice -Title "Which COM port (board)?" -Options $opts -Default 1
    if ($idx -le $ports.Count) { return $ports[$idx - 1].Port }
    return (Read-Host "Enter COM port (e.g. COM8)").Trim().ToUpper()
}

function Select-MultiplePorts {
    # Ported/trimmed from run_wizard.ps1's Select-MultiplePorts + Test-PortSafeToTouch:
    # picks several boards at once ('all' or comma/space-separated numbers) for a
    # bulk read (identify), never a blind "apply to all enumerated ports" -- a
    # BLOCKED port (Bluetooth, a mouse receiver, ...) is never even listed, and an
    # UNKNOWN one only gets touched after typing its own port name back to prove
    # it really is a board someone means to read.
    param([object[]]$Ports, [string]$Action = 'read it')

    $usable = @($Ports | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($usable.Count -eq 0) { return @() }
    $bridges = @($usable | Where-Object { $_.Kind -eq 'BRIDGE' })

    Write-Host ""
    if ($bridges.Count -gt 0) {
        Write-Host ("Type 'all' for the {0} detected ESP32 board(s): {1}" -f $bridges.Count, (($bridges | ForEach-Object { $_.Port }) -join ', ')) -ForegroundColor DarkGray
    }
    $which = Read-Host "Which port numbers? ('all', or comma/space separated e.g. 1,3,5)"
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
        Write-Host ""
        Write-Host ("{0} is '{1}' -- not a recognised USB-to-UART bridge." -f $p.Port, $p.Description) -ForegroundColor Yellow
        Write-Host ("If it is NOT one of your ESP32s, this could {0} the wrong device." -f $Action) -ForegroundColor Yellow
        $ans = Read-Host ("  Type the port name ({0}) to confirm it IS your board, anything else to skip" -f $p.Port)
        if ($ans.Trim().ToUpper() -eq $p.Port.ToUpper()) { $vetted += $p }
        else { Write-Host ("  Skipped {0} -- not confirmed." -f $p.Port) -ForegroundColor DarkGray }
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
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   Combined ESP-WIFI-MESH launcher" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

$action = Read-Choice -Title "What do you want to do?" -Options @(
    'Run a board  (baseline / blackhole / wormhole; plus a run scenario)',
    'Run MULTIPLE boards in parallel  (one window per board, pre-built)',
    'Export a board only  (it already ran; just pull CSVs)',
    'Wipe / full-erase a board  (start empty)',
    'Identify a board  (read its MAC / node number)',
    'Verify a run  (paper-backed 3-sigma attack check)',
    'Import CSVs from a pulled SD card  (no board/COM contact)',
    'Quit'
) -Default 1

if ($action -eq 8) { return }

# ---- Run MULTIPLE boards in parallel -----------------------------------------
if ($action -eq 2) {
    if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "idf.py is not on PATH - run this from the 'ESP-IDF 5.3 PowerShell' window." -ForegroundColor Red
        return
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

        $label = Read-Host "Board label / node id (e.g. node5), blank to skip"

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

    if ($boards.Count -eq 0) { Write-Host "No boards added." -ForegroundColor Yellow; return }

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
    if ($confirmed.Count -eq 0) { Write-Host "`nNothing confirmed -- nothing to do." -ForegroundColor Yellow; return }
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
        return
    }

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
            if ($boards.Count -eq 0) { return }
            if (-not (Read-YesNo -Question "Continue with the remaining boards?" -Default $true)) { return }
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
    return
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
    $typed   = Read-Host ("feature_table.csv path [default: {0}]" -f $table)
    if (-not [string]::IsNullOrWhiteSpace($typed)) { $table = $typed }
    $vaArgs  = @($table)
    $cmdText = "python tools\verify_attack.py $table"
    if ($attack -ne 'auto') { $vaArgs += @('--attack', $attack); $cmdText += " --attack $attack" }
    if (Show-And-Confirm $cmdText) {
        Push-Location $base
        try { python (Join-Path $base 'tools\verify_attack.py') @vaArgs } finally { Pop-Location }
    }
    return
}

# ---- Identify a board -------------------------------------------------------
if ($action -eq 5) {
    $ports = @(Get-PortList | Where-Object { $_.Kind -ne 'BLOCKED' })
    if ($ports.Count -eq 0) {
        Write-Host ""
        Write-Host "   (No usable COM ports detected. Is anything plugged in?)" -ForegroundColor Yellow
        return
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
            $picked = @($ports[$idx - 1])
        } else {
            $manual = (Read-Host "Enter COM port (e.g. COM8)").Trim().ToUpper()
            if ($manual) { $picked = @([pscustomobject]@{ Port = $manual; Description = 'manual entry'; Kind = 'UNKNOWN' }) }
        }
    }
    if ($picked.Count -eq 0) { Write-Host "Nothing to identify." -ForegroundColor Yellow; return }

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

    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    foreach ($r in $results) {
        $macDisp = if ($r.Mac) { $r.Mac } else { '(unread)' }
        Write-Host ("   {0,-7} {1,-17} {2}" -f $r.Port, $macDisp, $r.Node)
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
        return
    }
    Write-Host ("mesh_config.h BLACKHOLE_ATTACKER_MAC = {0}" -f $configured) -ForegroundColor Cyan
    $readOk  = @($results | Where-Object { $_.Mac })
    $matches = @($readOk | Where-Object { $_.Mac -eq $configured })

    if ($matches.Count -eq 1) {
        Write-Host ("   MATCH -- {0} ({1}) is the configured attacker. Victim boards will reach it." -f $matches[0].Port, $matches[0].Node) -ForegroundColor Green
        return
    }
    if ($matches.Count -gt 1) {
        Write-Host ("   WARNING: {0} of the boards just read all report this SAME MAC -- that should not happen (duplicate/cloned MAC?)." -f $matches.Count) -ForegroundColor Red
        return
    }
    if ($readOk.Count -eq 0) {
        Write-Host "   Could not confirm -- no MAC was successfully read from any board above." -ForegroundColor Yellow
        return
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
    return
}

# ---- Wipe / erase a board ---------------------------------------------------
if ($action -eq 4) {
    $port = Select-Port
    $roleIdx = Read-Choice -Title "Board role (only matters if you also re-flash)?" -Options @('child / victim', 'root') -Default 1
    if ($roleIdx -eq 2) { $role = 'root' } else { $role = 'child' }
    $full = Read-YesNo -Question "FULL chip erase + re-flash? (fixes 'storage full' / crash-loops)" -Default $false
    $p = @{ Port = $port; Role = $role; Wipe = $true }
    $cmdText = ".\run.ps1 -Port $port -Role $role -Wipe"
    if ($full) { $p['Flash'] = $true; $cmdText += ' -Flash' }
    if (Show-And-Confirm $cmdText) { & $run @p }
    return
}

# ---- Export only ------------------------------------------------------------
if ($action -eq 3) {
    $port = Select-Port
    $roleIdx = Read-Choice -Title "Board role?" -Options @('child / victim', 'root') -Default 1
    if ($roleIdx -eq 2) { $role = 'root' } else { $role = 'child' }
    $topoIdx  = Read-Choice -Title "Topology this run used?" -Options @('tree', 'star', 'linear', 'partial') -Default 1
    $topo     = @('tree', 'star', 'linear', 'partial')[$topoIdx - 1]
    $attkIdx  = Read-Choice -Title "Attack this run used?" -Options @('none (baseline)', 'blackhole', 'wormhole') -Default 1
    $attack   = @('none', 'blackhole', 'wormhole')[$attkIdx - 1]
    $scenario = Select-Scenario
    $loc      = Select-Location
    $label    = Read-Host "Board label / node id (e.g. node5), blank to skip"
    $repeat   = Read-Host "Repeat number (r1/r2/r3 -> 1/2/3) [default 1]"
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
    return
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
if ($action -eq 7) {
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
    $repeat = Read-Host "Repeat number for this card (r1/r2/r3 -> 1/2/3) [default 1]"
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
        return
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
    return
}

# ---- Run a board (the main flow) --------------------------------------------
$port = Select-Port
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

$label   = Read-Host "Board label / node id (e.g. node5), blank to skip"
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
