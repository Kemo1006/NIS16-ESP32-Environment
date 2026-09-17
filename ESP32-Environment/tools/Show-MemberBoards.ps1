# Who owns which ESP32, printed at the top of run_wizard.ps1 and menu.ps1 so the
# list doesn't have to live on the whiteboard. Data: member_boards.json at the
# repo root. Dot-sourced by both launchers; relies on their Colorize-Role and
# Read-Line.
# ASCII-only on purpose (Windows PowerShell 5.1 misreads non-ASCII in .ps1).

$script:BoardMembers = @('Cal', 'Bas', 'Kyle')
$script:ScenarioTagAnsi = "$([char]27)[38;2;255;170;60m"   # amber - the scenario-job tag, distinct from the role colors

function Format-ShortMac {
    # "F4:2D:C9:73:E6:18" -> "F4:18". Already-short "20:38" passes through.
    param([string]$Mac)
    $parts = @($Mac -split '[:\-\s]' | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $Mac.ToUpper() }
    return ("{0}:{1}" -f $parts[0], $parts[$parts.Count - 1]).ToUpper()
}

function Show-MemberBoardsTable {
    # Core renderer, split out from Show-MemberBoards so a saved snapshot can be
    # PREVIEWED (Manage-MemberBoardSnapshots below) from its own parsed object
    # without writing it over the live file first. $Cfg is whatever ConvertFrom-Json
    # produced - either member_boards.json's own content or a snapshot's.
    param($Cfg, [string]$Title = 'Boards by member')

    $columns = @()
    foreach ($name in $script:BoardMembers) {
        $entry  = @($Cfg.members) | Where-Object { [string]$_.name -eq $name } | Select-Object -First 1
        $boards = if ($entry) { @($entry.boards) } else { @() }
        $rows = @($boards | Where-Object { $_ } | ForEach-Object {
            $nick = [string]$_.nickname
            [pscustomobject]@{
                Nick     = if ($nick) { $nick } else { '-' }
                Mac      = Format-ShortMac ([string]$_.mac)
                Role     = [string]$_.role
                Scenario = [string]$_.scenario
            }
        })
        $columns += [pscustomobject]@{ Name = $name; Rows = $rows }
    }

    # $tagW reserves room for the widest scenario-job tag actually in use (0 if
    # none), so every row in a column pads to the SAME width whether or not it
    # has a tag - a variable-width tag on an EARLIER row would otherwise make
    # `$colW - $v.Plain.Length` go negative on the padding below and crash.
    $nickW = 4; $roleW = 4; $tagW = 0
    foreach ($c in $columns) {
        foreach ($r in $c.Rows) {
            if ($r.Nick.Length -gt $nickW) { $nickW = $r.Nick.Length }
            if ($r.Role.Length -gt $roleW) { $roleW = $r.Role.Length }
            if ($r.Scenario) {
                $tlen = "  << $($r.Scenario.ToUpper()) TARGET".Length
                if ($tlen -gt $tagW) { $tagW = $tlen }
            }
        }
    }
    $macW = 5
    $colW = $nickW + 3 + $macW + 3 + $roleW + $tagW
    $gap  = '    '

    # Each cell is kept as plain text (for padding) plus its colored form; ANSI
    # codes have no width on screen but would count toward PadRight.
    $cell = {
        param($c, $i)
        if ($i -eq 0) { return @{ Plain = $c.Name; Color = $c.Name } }
        if ($i -eq 1) { $u = '-' * $colW; return @{ Plain = $u; Color = $u } }
        if ($c.Rows.Count -eq 0 -and $i -eq 2) { $t = '(no boards yet)'; return @{ Plain = $t; Color = $t } }
        $ri = $i - 2
        if ($ri -ge $c.Rows.Count) { return @{ Plain = ''; Color = '' } }
        $r    = $c.Rows[$ri]
        $head = "{0} | {1} | " -f $r.Nick.PadRight($nickW), $r.Mac.PadRight($macW)
        $role = $r.Role.PadRight($roleW)
        $key  = switch -Regex ($r.Role) { '^root$' { 'root' } '^(attacker|blackhole|black)$' { 'attacker' } '^(child|victim)$' { 'child' } default { '' } }
        $roleTxt = if ($key) { Colorize-Role $role $key } else { $role }
        $tag = if ($r.Scenario) { "  << $($r.Scenario.ToUpper()) TARGET" } else { '' }
        $tagPad = ' ' * ($tagW - $tag.Length)
        $tagTxt = if ($tag) { "$script:ScenarioTagAnsi$tag$script:AnsiReset$tagPad" } else { $tagPad }
        return @{ Plain = $head + $role + $tag + $tagPad; Color = $head + $roleTxt + $tagTxt }
    }

    $height = 2 + (($columns | ForEach-Object { [math]::Max(1, $_.Rows.Count) }) | Measure-Object -Maximum).Maximum
    $width  = 80
    try { $width = $Host.UI.RawUI.WindowSize.Width } catch { }
    if ($width -le 0) { $width = 80 }
    $sideBySide = (($colW * $columns.Count) + ($gap.Length * ($columns.Count - 1))) -lt $width

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    if ($sideBySide) {
        for ($i = 0; $i -lt $height; $i++) {
            $line = ''
            for ($ci = 0; $ci -lt $columns.Count; $ci++) {
                $v = & $cell $columns[$ci] $i
                $pad = if ($ci -lt $columns.Count - 1) { (' ' * ($colW - $v.Plain.Length)) + $gap } else { '' }
                $line += $v.Color + $pad
            }
            if ($i -eq 0) { Write-Host $line -ForegroundColor Cyan } else { Write-Host $line }
        }
    }
    else {
        foreach ($c in $columns) {
            $h = 2 + [math]::Max(1, $c.Rows.Count)
            for ($i = 0; $i -lt $h; $i++) {
                $v = & $cell $c $i
                if ($i -eq 0) { Write-Host $v.Color -ForegroundColor Cyan } else { Write-Host $v.Color }
            }
            Write-Host ""
        }
    }
}

function Show-MemberBoards {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host ("  (member board list not found: {0})" -f (Split-Path -Leaf $Path)) -ForegroundColor DarkGray
        return
    }
    try { $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json }
    catch {
        Write-Host ("  (member board list {0} is not valid JSON - fix it to see the list)" -f (Split-Path -Leaf $Path)) -ForegroundColor Yellow
        return
    }
    Show-MemberBoardsTable -Cfg $cfg -Title 'Boards by member'
}

# ------------------------------------------------------------------ editing ----
# Reached from the "Edit the member board list" option in both launchers' main
# menus. Uses only Read-Line (both launchers define it with the same positional
# prompt), so 'm' and 'cls' behave like every other prompt. Every change is
# written to the file as soon as it is confirmed, so 'm' never loses one.

function Read-MemberBoardData {
    # Returns @{ Help; Members = [ordered] name -> ArrayList of boards }, or $null
    # when the file exists but is not valid JSON (never overwrite a file that
    # couldn't be read - that would wipe whatever someone was fixing by hand).
    param([string]$Path)
    $help = 'Shown at the top of run_wizard.ps1 and menu.ps1. Member names are fixed (Cal, Bas, Kyle). mac can be the full MAC or just first:last byte - only first:last is displayed. role: root, child, attacker (anything else is shown uncolored). scenario: "" (none), burst, mobility, or powercycle - at most one board holds a given job.'
    $cfg = $null
    if (Test-Path $Path) {
        try { $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json }
        catch { return $null }
        if ($cfg.PSObject.Properties['_help']) { $help = [string]$cfg._help }
    }
    $members = [ordered]@{}
    foreach ($name in $script:BoardMembers) {
        $list  = New-Object System.Collections.ArrayList
        $entry = $null
        if ($cfg) { $entry = @($cfg.members) | Where-Object { [string]$_.name -eq $name } | Select-Object -First 1 }
        if ($entry) {
            foreach ($b in @($entry.boards)) {
                if (-not $b) { continue }
                [void]$list.Add([pscustomobject]@{
                    nickname = [string]$b.nickname; mac = [string]$b.mac; role = [string]$b.role; scenario = [string]$b.scenario
                })
            }
        }
        $members[$name] = $list
    }
    return @{ Help = $help; Members = $members }
}

function Save-MemberBoardData {
    param([string]$Path, $Data)
    $out = [pscustomobject]@{
        _help   = $Data.Help
        members = @($script:BoardMembers | ForEach-Object {
            [pscustomobject]@{ name = $_; boards = @($Data.Members[$_].ToArray()) }
        })
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6
    # No BOM: Set-Content -Encoding UTF8 on PS 5.1 adds one.
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Test-MemberBoardBack {
    param([string]$Raw)
    return [bool]($Raw -and ($Raw.Trim().ToLower() -in @('b', 'back')))
}

function Read-MemberName {
    param([string]$Current)
    Write-Host ""
    for ($i = 0; $i -lt $script:BoardMembers.Count; $i++) {
        $mark = if ($script:BoardMembers[$i] -eq $Current) { '  <- current (press Enter)' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $script:BoardMembers[$i], $mark)
    }
    # Adding a board asks whose it is; editing one already has an owner, so the
    # question is really "keep it here or transfer it" - same menu, different
    # wording so picking [3] on an edit doesn't read as "reassign this board?"
    # when it's actually "stay put".
    $prompt = if ($Current) { "Transfer to which member? (Enter keeps $Current, number to move, 'b' cancel) > " }
              else { "Whose board? (number, 'b' cancel) > " }
    while ($true) {
        $raw = Read-Line $prompt
        if (Test-MemberBoardBack $raw) { return $null }
        if (-not $raw -and $Current) { return $Current }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $script:BoardMembers.Count) { return $script:BoardMembers[$n - 1] }
        Write-Host ("  Enter 1-{0}." -f $script:BoardMembers.Count) -ForegroundColor Yellow
    }
}

function Read-MemberBoardMac {
    # Full MAC (aa:bb:cc:dd:ee:ff, ':' or '-') or just first:last. Stored upper-
    # case with ':'. Asks before accepting one that displays the same first:last
    # as a board already in the list.
    param($Data, [string]$Current, $Self)
    while ($true) {
        $hint = if ($Current) { " [$Current]" } else { '' }
        $raw  = Read-Line "MAC - full, or just first:last like F4:18$hint ('b' cancel) > "
        if (Test-MemberBoardBack $raw) { return $null }
        if (-not $raw -and $Current) { return $Current }
        $mac = ([string]$raw).Trim().ToUpper() -replace '-', ':'
        if ($mac -notmatch '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$' -and $mac -notmatch '^[0-9A-F]{2}:[0-9A-F]{2}$') {
            Write-Host "  Not a MAC. Use 6 pairs (F4:2D:C9:73:E6:18) or first:last (F4:18)." -ForegroundColor Yellow
            continue
        }
        $short = Format-ShortMac $mac
        $clash = $null
        foreach ($name in $script:BoardMembers) {
            foreach ($b in $Data.Members[$name]) {
                if ($b -ne $Self -and (Format-ShortMac $b.mac) -eq $short) { $clash = "$name's board $($b.mac)" }
            }
        }
        if ($clash) {
            $ans = Read-Line "  $clash already shows as $short - use it anyway? [y/N] > "
            if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
        }
        return $mac
    }
}

function Read-MemberBoardRole {
    param([string]$Current)
    $roles = @('root', 'child', 'attacker', '?')
    $texts = @('root', 'child', 'attacker', "unknown (shows '?')")
    Write-Host ""
    for ($i = 0; $i -lt $roles.Count; $i++) {
        $mark = if ($roles[$i] -eq $Current) { '  <- current (press Enter)' } else { '' }
        $line = "  [{0}] {1}{2}" -f ($i + 1), $texts[$i], $mark
        if ($i -lt 3) { Write-Host (Colorize-Role $line $roles[$i]) } else { Write-Host $line }
    }
    while ($true) {
        $raw = Read-Line "Role? (number, 'b' cancel) > "
        if (Test-MemberBoardBack $raw) { return $null }
        if (-not $raw -and $Current) { return $Current }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $roles.Count) { return $roles[$n - 1] }
        Write-Host ("  Enter 1-{0}." -f $roles.Count) -ForegroundColor Yellow
    }
}

function Read-MemberBoardScenario {
    # Which human task (if any) THIS board is currently doing - mirrors
    # run_wizard's scenario targets (burst/mobility/powercycle each need
    # exactly ONE board across the whole roster; highload applies to every
    # child automatically and 'none' names nobody, so neither is offered here
    # as a per-board job - same set Test-ScenarioNeedsTarget flags in
    # run_wizard.ps1). Picking a job another board already holds asks to move
    # it here instead, same pattern as Read-MemberBoardMac's clash check.
    param($Data, [string]$Current, $Self)
    $jobs  = @('', 'burst', 'mobility', 'powercycle')
    $texts = @(
        'none        (not doing a scenario job right now)',
        'burst       (will fire the probe burst)',
        'mobility    (will be physically moved)',
        'powercycle  (will be unplugged/replugged)'
    )
    Write-Host ""
    for ($i = 0; $i -lt $jobs.Count; $i++) {
        $isCurrent = ($jobs[$i] -eq $Current) -or ((-not $Current) -and ($jobs[$i] -eq ''))
        $mark = if ($isCurrent) { '  <- current (press Enter)' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $texts[$i], $mark)
    }
    while ($true) {
        $raw = Read-Line "Scenario job? (number, 'b' cancel) > "
        if (Test-MemberBoardBack $raw) { return $null }
        if (-not $raw) { if ($Current) { return $Current }; return '' }
        $n = 0
        if (-not ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $jobs.Count)) {
            Write-Host ("  Enter 1-{0}." -f $jobs.Count) -ForegroundColor Yellow
            continue
        }
        $picked = $jobs[$n - 1]
        if ($picked) {
            $holder = $null
            foreach ($name in $script:BoardMembers) {
                foreach ($b in $Data.Members[$name]) {
                    if ($b -ne $Self -and [string]$b.scenario -eq $picked) { $holder = "$name's board ($(Format-ShortMac $b.mac))" }
                }
            }
            if ($holder) {
                $ans = Read-Line "  $holder already holds $picked - give this board the job instead? [y/N] > "
                if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
                foreach ($name in $script:BoardMembers) {
                    foreach ($b in $Data.Members[$name]) {
                        if ($b -ne $Self -and [string]$b.scenario -eq $picked) { $b.scenario = '' }
                    }
                }
            }
        }
        return $picked
    }
}

function Select-MemberBoard {
    # Numbered list of every board across all members; returns @{Member; Board} or $null.
    param($Data, [string]$Title)
    $all = @()
    foreach ($name in $script:BoardMembers) {
        foreach ($b in $Data.Members[$name]) { $all += @{ Member = $name; Board = $b } }
    }
    if ($all.Count -eq 0) {
        Write-Host "  There are no boards in the list yet - add one first." -ForegroundColor Yellow
        return $null
    }
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $all.Count; $i++) {
        $b = $all[$i].Board
        $nick = if ($b.nickname) { $b.nickname } else { '-' }
        $tag  = if ($b.scenario) { "  << $(([string]$b.scenario).ToUpper())" } else { '' }
        Write-Host ("  [{0}] {1,-5} {2} | {3} | {4}{5}" -f ($i + 1), $all[$i].Member, $nick, (Format-ShortMac $b.mac), $b.role, $tag)
    }
    while ($true) {
        $raw = Read-Line "Which board? (number, 'b' cancel) > "
        if (Test-MemberBoardBack $raw) { return $null }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $all.Count) { return $all[$n - 1] }
        Write-Host ("  Enter 1-{0}." -f $all.Count) -ForegroundColor Yellow
    }
}

function Edit-MemberBoards {
    param([string]$Path)
    while ($true) {
        $data = Read-MemberBoardData -Path $Path
        if (-not $data) {
            Write-Host ""
            Write-Host ("{0} is not valid JSON - fix or delete it by hand first; not overwriting it." -f $Path) -ForegroundColor Yellow
            return
        }
        Show-MemberBoards -Path $Path
        Write-Host ""
        Write-Host "Edit the member board list:" -ForegroundColor Cyan
        Write-Host "  [1] Add a board"
        Write-Host "  [2] Edit a board (nickname / MAC / role / owner / scenario job)"
        Write-Host "  [3] Remove a board"
        Write-Host "  [4] Done - back to the main menu  <- default (press Enter)" -ForegroundColor Green
        $raw = Read-Line "> "
        if (-not $raw -or $raw -eq '4' -or (Test-MemberBoardBack $raw)) { return }

        if ($raw -eq '1') {
            $member = Read-MemberName
            if (-not $member) { continue }
            $nick = Read-Line "Nickname (blank for none, 'b' cancel) > "
            if (Test-MemberBoardBack $nick) { continue }
            $mac = Read-MemberBoardMac -Data $data
            if (-not $mac) { continue }
            $role = Read-MemberBoardRole
            if (-not $role) { continue }
            $newBoard = [pscustomobject]@{ nickname = ([string]$nick).Trim(); mac = $mac; role = $role; scenario = '' }
            $scenario = Read-MemberBoardScenario -Data $data -Self $newBoard
            if ($null -eq $scenario) { continue }
            $newBoard.scenario = $scenario
            [void]$data.Members[$member].Add($newBoard)
            Save-MemberBoardData -Path $Path -Data $data
            Write-Host ("  Added to {0} and saved." -f $member) -ForegroundColor Green
        }
        elseif ($raw -eq '2') {
            $pick = Select-MemberBoard -Data $data -Title 'Edit which board?'
            if (-not $pick) { continue }
            $b = $pick.Board
            $member = Read-MemberName -Current $pick.Member
            if (-not $member) { continue }
            $nickHint = if ($b.nickname) { " [$($b.nickname)]" } else { '' }
            $nick = Read-Line "Nickname$nickHint (Enter keeps it, '-' clears it, 'b' cancel) > "
            if (Test-MemberBoardBack $nick) { continue }
            $newNick = if (-not $nick) { $b.nickname } elseif ($nick.Trim() -eq '-') { '' } else { $nick.Trim() }
            $mac = Read-MemberBoardMac -Data $data -Current $b.mac -Self $b
            if (-not $mac) { continue }
            $role = Read-MemberBoardRole -Current $b.role
            if (-not $role) { continue }
            $scenario = Read-MemberBoardScenario -Data $data -Current $b.scenario -Self $b
            if ($null -eq $scenario) { continue }
            $b.nickname = $newNick; $b.mac = $mac; $b.role = $role; $b.scenario = $scenario
            if ($member -ne $pick.Member) {
                $data.Members[$pick.Member].Remove($b)
                [void]$data.Members[$member].Add($b)
            }
            Save-MemberBoardData -Path $Path -Data $data
            Write-Host "  Saved." -ForegroundColor Green
        }
        elseif ($raw -eq '3') {
            $pick = Select-MemberBoard -Data $data -Title 'Remove which board?'
            if (-not $pick) { continue }
            $ans = Read-Line ("  Remove {0}'s {1} from the list? [y/N] > " -f $pick.Member, (Format-ShortMac $pick.Board.mac))
            if ($ans -ne 'y' -and $ans -ne 'Y') { continue }
            $data.Members[$pick.Member].Remove($pick.Board)
            Save-MemberBoardData -Path $Path -Data $data
            Write-Host "  Removed and saved." -ForegroundColor Green
        }
        else {
            Write-Host "  Enter 1-4." -ForegroundColor Yellow
        }
    }
}

function Open-MemberBoardsFile {
    # Faster path for someone who'd rather hand-edit the JSON than go through
    # Edit-MemberBoards' prompts. If the file doesn't exist yet, seed it with the
    # same empty structure Edit-MemberBoards would (via the shared read/save
    # helpers) so there's a valid file to open instead of a launch error.
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        $data = Read-MemberBoardData -Path $Path
        if ($data) {
            Save-MemberBoardData -Path $Path -Data $data
            Write-Host ("  {0} didn't exist - created it with an empty list." -f (Split-Path -Leaf $Path)) -ForegroundColor DarkGray
        }
    }

    $editor = $null
    if ($env:EDITOR) { $editor = $env:EDITOR }
    elseif (Get-Command code -ErrorAction SilentlyContinue) { $editor = 'code' }

    Write-Host ""
    try {
        if ($editor) {
            Write-Host ("Opening {0} in {1} ..." -f (Split-Path -Leaf $Path), $editor) -ForegroundColor DarkGray
            & $editor $Path
        }
        else {
            Write-Host ("Opening {0} in Notepad (set `$env:EDITOR for something else) ..." -f (Split-Path -Leaf $Path)) -ForegroundColor DarkGray
            Start-Process notepad.exe $Path
        }
    }
    catch {
        Write-Host ("  Could not launch an editor - open it yourself: {0}" -f $Path) -ForegroundColor Yellow
    }
    Write-Host "  Keep the member names (Cal/Bas/Kyle) and each board's nickname/mac/role fields -" -ForegroundColor DarkGray
    Write-Host "  the table above re-reads this file every time it's shown, and won't display a" -ForegroundColor DarkGray
    Write-Host "  board whose fields don't match that shape. Save the file when you're done." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- snapshots ----
# Named saves of the WHOLE board list, including each board's scenario job -
# same idea as run_wizard's presets (attack/topology/location), so a specific
# run's board assignment ("who had which board, who was doing the burst") can
# be looked up later instead of retyped. Snapshots live in their own sibling
# folder next to member_boards.json - never inside the live file itself.
# Loading one OVERWRITES the live file (with a confirm); it never merges.

$script:MemberSnapshotAttacks    = @('none', 'blackhole', 'wormhole')
$script:MemberSnapshotTopologies = @('linear', 'tree', 'star', 'partial')
$script:MemberSnapshotLocations  = @('home', 'G402', 'DLSU_Library', 'Goks')

function Get-MemberBoardSnapshotDir {
    param([string]$LivePath)
    return Join-Path (Split-Path $LivePath -Parent) 'member_boards'
}

function Read-MemberBoardChoice {
    # Small generic numbered picker for the attack/topology/location prompts
    # below only - Read-MemberName/Read-MemberBoardRole/Read-MemberBoardScenario
    # stay their own purpose-built prompts since they're already tested and this
    # would just add risk for no benefit.
    param([string]$Title, [string[]]$Options)
    Write-Host ""
    if ($Title) { Write-Host $Title -ForegroundColor Cyan }
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i]) }
    while ($true) {
        $raw = Read-Line "(number, 'b' cancel) > "
        if (Test-MemberBoardBack $raw) { return $null }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $Options[$n - 1] }
        Write-Host ("  Enter 1-{0}." -f $Options.Count) -ForegroundColor Yellow
    }
}

function Get-MemberBoardSnapshots {
    # Newest first - the snapshot just saved is almost always the one wanted next.
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return @() }
    return @(Get-ChildItem -Path $Dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}

function Save-MemberBoardSnapshot {
    # Saves the CURRENT live list (including each board's scenario job) under a
    # name, so it can be pulled back up later instead of retyped. Doesn't touch
    # the live file - a snapshot is a copy, taken at this moment.
    param([string]$LivePath)
    $data = Read-MemberBoardData -Path $LivePath
    if (-not $data) {
        Write-Host ("  {0} is not valid JSON - fix it first." -f (Split-Path -Leaf $LivePath)) -ForegroundColor Yellow
        return
    }
    $total = ($script:BoardMembers | ForEach-Object { $data.Members[$_].Count } | Measure-Object -Sum).Sum
    if ($total -eq 0) {
        Write-Host "  The list is empty - nothing to save yet." -ForegroundColor Yellow
        return
    }

    $attack = Read-MemberBoardChoice -Title 'Attack for this snapshot?' -Options $script:MemberSnapshotAttacks
    if (-not $attack) { return }
    $topology = Read-MemberBoardChoice -Title 'Topology for this snapshot?' -Options $script:MemberSnapshotTopologies
    if (-not $topology) { return }
    $location = Read-MemberBoardChoice -Title 'Location for this snapshot?' -Options $script:MemberSnapshotLocations
    if (-not $location) { return }

    $dir = Get-MemberBoardSnapshotDir -LivePath $LivePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $suggested = "$topology-$attack-$location.json"
    $name = Read-Line "Filename > [$suggested] ('b' cancel) "
    if (Test-MemberBoardBack $name) { return }
    if (-not $name) { $name = $suggested }
    if ($name -notmatch '\.json$') { $name = "$name.json" }
    $path = Join-Path $dir $name

    if (Test-Path $path) {
        $ans = Read-Line "  '$name' already exists - overwrite it? [y/N] > "
        if ($ans -ne 'y' -and $ans -ne 'Y') { Write-Host "  Not saved." -ForegroundColor DarkGray; return }
    }

    $out = [pscustomobject]@{
        _help    = 'A saved member board list - same shape as member_boards.json, plus attack/topology/location/savedAt. Load it from the snapshot menu; it OVERWRITES member_boards.json.'
        attack   = $attack
        topology = $topology
        location = $location
        savedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        members  = @($script:BoardMembers | ForEach-Object {
            [pscustomobject]@{ name = $_; boards = @($data.Members[$_].ToArray()) }
        })
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
    Write-Host ("  Saved -> {0}" -f $path) -ForegroundColor Green
}

function Show-MemberBoardSnapshotSummary {
    param($Cfg, [string]$Name)
    $attack = [string]$Cfg.attack
    if ($attack -eq 'none') { $attack = 'baseline' }
    return "{0,-26} {1,-10} {2,-8} {3,-13} {4}" -f $Name, $attack, [string]$Cfg.topology, [string]$Cfg.location, [string]$Cfg.savedAt
}

function Restore-MemberBoardSnapshot {
    # Overwrites member_boards.json with a snapshot's members. Keeps the LIVE
    # file's own _help line (falling back to the standard one if the live file
    # didn't exist/parse), rather than the snapshot's - _help should always
    # describe member_boards.json, not the snapshot it came from.
    param([string]$LivePath, $Cfg)
    $live = Read-MemberBoardData -Path $LivePath
    $help = if ($live) { $live.Help } else {
        'Shown at the top of run_wizard.ps1 and menu.ps1. Member names are fixed (Cal, Bas, Kyle). mac can be the full MAC or just first:last byte - only first:last is displayed. role: root, child, attacker (anything else is shown uncolored). scenario: "" (none), burst, mobility, or powercycle - at most one board holds a given job.'
    }
    $out = [pscustomobject]@{
        _help   = $help
        members = @($script:BoardMembers | ForEach-Object {
            $name   = $_
            $entry  = @($Cfg.members) | Where-Object { [string]$_.name -eq $name } | Select-Object -First 1
            $boards = if ($entry) {
                @($entry.boards | Where-Object { $_ } | ForEach-Object {
                    [pscustomobject]@{ nickname = [string]$_.nickname; mac = [string]$_.mac; role = [string]$_.role; scenario = [string]$_.scenario }
                })
            } else { @() }
            [pscustomobject]@{ name = $name; boards = $boards }
        })
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6
    [System.IO.File]::WriteAllText($LivePath, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Manage-MemberBoardSnapshots {
    param([string]$LivePath)
    $dir = Get-MemberBoardSnapshotDir -LivePath $LivePath
    while ($true) {
        Write-Host ""
        Write-Host "Board-list snapshots (like a preset, for the Cal/Bas/Kyle list):" -ForegroundColor Cyan
        Write-Host "  [1] Save the CURRENT list as a new snapshot"
        Write-Host "  [2] Look at / load a saved snapshot"
        Write-Host "  [3] Delete a saved snapshot"
        Write-Host "  [4] Back  <- default (press Enter)" -ForegroundColor Green
        $raw = Read-Line "> "
        if (-not $raw -or $raw -eq '4' -or (Test-MemberBoardBack $raw)) { return }

        if ($raw -eq '1') { Save-MemberBoardSnapshot -LivePath $LivePath; continue }
        if ($raw -notin @('2', '3')) { Write-Host "  Enter 1-4." -ForegroundColor Yellow; continue }

        $files = Get-MemberBoardSnapshots -Dir $dir
        if ($files.Count -eq 0) {
            Write-Host "  No saved snapshots yet - save one first." -ForegroundColor Yellow
            continue
        }
        $title = if ($raw -eq '2') { 'Look at / load which snapshot?' } else { 'Delete which snapshot?' }
        Write-Host ""
        Write-Host $title -ForegroundColor Cyan
        for ($i = 0; $i -lt $files.Count; $i++) {
            $c = $null
            try { $c = Get-Content -Raw -Path $files[$i].FullName | ConvertFrom-Json } catch { }
            $line = if ($c) { Show-MemberBoardSnapshotSummary -Cfg $c -Name $files[$i].Name } else { "$($files[$i].Name)  (unreadable)" }
            Write-Host ("  [{0}] {1}" -f ($i + 1), $line)
        }
        $fIdx = -1
        while ($true) {
            $raw2 = Read-Line "(number, 'b' cancel) > "
            if (Test-MemberBoardBack $raw2) { break }
            $n = 0
            if ([int]::TryParse($raw2, [ref]$n) -and $n -ge 1 -and $n -le $files.Count) { $fIdx = $n - 1; break }
            Write-Host ("  Enter 1-{0}." -f $files.Count) -ForegroundColor Yellow
        }
        if ($fIdx -eq -1) { continue }
        $file = $files[$fIdx]

        if ($raw -eq '3') {
            $ans = Read-Line ("  Delete '{0}' permanently? [y/N] > " -f $file.Name)
            if ($ans -eq 'y' -or $ans -eq 'Y') {
                Remove-Item -Path $file.FullName -Force
                Write-Host "  Deleted." -ForegroundColor Green
            }
            continue
        }

        $cfg = $null
        try { $cfg = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json } catch { }
        if (-not $cfg) {
            Write-Host ("  Could not read {0} - it may be corrupted." -f $file.Name) -ForegroundColor Yellow
            continue
        }
        Show-MemberBoardsTable -Cfg $cfg -Title ("Snapshot: {0}  (saved {1})" -f $file.Name, [string]$cfg.savedAt)
        $useAns = Read-Line "`n  Load this into the live list? This OVERWRITES the current Cal/Bas/Kyle table. [y/N] > "
        if ($useAns -eq 'y' -or $useAns -eq 'Y') {
            Restore-MemberBoardSnapshot -LivePath $LivePath -Cfg $cfg
            Write-Host "  Loaded." -ForegroundColor Green
        }
        else {
            Write-Host "  Not loaded - just looked." -ForegroundColor DarkGray
        }
    }
}
