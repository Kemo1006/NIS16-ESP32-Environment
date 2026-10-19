# gui\VerdictDesign.ps1 - the verdict on the Analyse / Verify page, designed (oct. 19 2026,
# user: "add more design in result verdicts in the verify and analysis page").
#   * the coloured verdict banner gets the CONFIDENCE grade as a badge and the
#     at-a-glance lights per area, under its text
#   * the Result tab opens with four headline tiles: SIGNATURE (n/m primaries + a
#     segmented bar), SETUP (failed / warnings), VICTIMS CUT OFF (n/m + bar),
#     CONFIDENCE (the grade)
# Everything is read from the report text Show-AnaReport already parsed - no extra
# file, no Python, a few dozen elements. Dot-sourced by run_gui.ps1. ASCII only.

# one colour per kind of '~' line, everywhere a report is shown (Verify card, Campaign notes):
#   MAJOR GAP (affects the result) = orange, MINOR GAP (result not affected) = yellow,
#   a plain note for the report = dim with an info mark
function Get-IncompleteHex([string]$Text) {
    if ($Text -match '^\s*MAJOR GAP') { return $Pal.Orange }
    if ($Text -match '^\s*MINOR GAP') { return $Pal.Amber }
    return $Pal.Dim
}
function Get-IncompleteGlyph([string]$Text) {
    if ($Text -match '^\s*(MAJOR|MINOR) GAP') { return [string][char]0x26A0 }
    return [string][char]0x2139
}

function Get-GradeLook([string]$Grade) {
    switch ($Grade) {
        'STRONG'          { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A'; G = [char]0x2714; Say = 'all data present, nothing to note' } }
        'GOOD'            { @{ Fg = $Pal.Green; Bg = '#16352B'; Bd = '#1F5E4A'; G = [char]0x2714; Say = 'all data present, notes for the report' } }
        'MINOR GAPS' { @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320'; G = [char]0x26A0; Say = 'some data missing - not data the result uses (result not affected)' } }
        'MAJOR GAPS' { @{ Fg = $Pal.Orange; Bg = '#35200F'; Bd = '#7C3F1A'; G = [char]0x26A0; Say = 'attack confirmed, but data it relies on is missing - recapture required' } }
        { $_ -in 'FAILED', 'NOT CONFIRMED' } { @{ Fg = $Pal.Red;   Bg = '#33192A'; Bd = '#6B2A3F'; G = [char]0x2716; Say = 'the attack cannot be confirmed - see why below' } }
        { $_ -in 'SOUND', 'WITH NOTES', 'QUALIFIED', '-' } { @{ Fg = $Pal.Amber; Bg = '#2E2716'; Bd = '#6B5320'; G = [char]0x2026; Say = 'older report - press Verify' } }
        default     { @{ Fg = $Pal.Dim;   Bg = '#232742'; Bd = $Pal.Line; G = [char]0x2026; Say = 'no grade (older report - press Verify)' } }
    }
}

function New-SegBar([int]$Have, [int]$Of, [string]$Hex) {
    # n of m as m small segments, the first n filled
    $wp = New-Object Windows.Controls.Primitives.UniformGrid; $wp.Rows = 1; $wp.Margin = '0,6,0,0'
    $n = [Math]::Max(1, [Math]::Min($Of, 12))
    for ($i = 0; $i -lt $n; $i++) {
        $s = New-Object Windows.Controls.Border; $s.Height = 7; $s.CornerRadius = 3; $s.Margin = '0,0,3,0'
        $s.Background = Get-Brush $(if ($i -lt $Have) { $Hex } else { '#2F3352' })
        [void]$wp.Children.Add($s)
    }
    return $wp
}

function New-HeadTile([string]$Label, [string]$Big, [string]$Sub, [string]$Hex, $Extra) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '14,10'; $b.Margin = '0,0,10,10'
    $b.Background = Get-Brush $Pal.Card; $b.BorderBrush = Get-Brush $Hex; $b.BorderThickness = '0,3,0,0'
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text $Label 10 $Pal.Faint 'SemiBold'))
    $t = New-Text $Big 22 $Hex 'Bold'; $t.Margin = '0,2,0,0'; [void]$sp.Children.Add($t)
    if ($Sub) { $s = New-Text $Sub 11 $Pal.Dim; $s.TextWrapping = 'Wrap'; [void]$sp.Children.Add($s) }
    if ($Extra) { [void]$sp.Children.Add($Extra) }
    $b.Child = $sp
    return $b
}

function Add-ResultHeadline([string[]]$Lines, $Checks, $Nodes) {
    # four tiles at the TOP of the Result tab (after the gate pills, if any)
    $vl = [string](@($Lines | Where-Object { $_ -match '^\s*VERDICT\s*:' } | Select-Object -Last 1))
    if (-not $vl) { return }
    $grade = ''; $cl = @($Lines | Where-Object { $_ -match '^\s*CONFIDENCE\s*:' } | Select-Object -Last 1)
    if ($cl -and [string]$cl -match '^\s*CONFIDENCE\s*:\s*(STRONG|GOOD|MINOR GAPS|MAJOR GAPS|FAILED|NOT CONFIRMED|SOUND|WITH NOTES|QUALIFIED|-)') { $grade = $Matches[1] }
    $wp = New-Object Windows.Controls.Primitives.UniformGrid; $wp.Rows = 1; $wp.Margin = '0,0,-10,4'   # tiles share the row evenly
    # SIGNATURE n/m primaries
    if ($vl -match '\((\d+)/(\d+) primary') {
        $h = [int]$Matches[1]; $o = [int]$Matches[2]
        $hex = if ($o -and $h -eq $o) { $Pal.Green } elseif ($h) { $Pal.Amber } else { $Pal.Red }
        [void]$wp.Children.Add((New-HeadTile 'SIGNATURE' "$h / $o" 'primary signatures beyond 3-sigma' $hex (New-SegBar $h $o $hex)))
    } elseif ($vl -match 'NOT CONFIRMED') {
        [void]$wp.Children.Add((New-HeadTile 'SIGNATURE' '0' 'no primary signature beyond 3-sigma' $Pal.Red $null))
    }
    # SETUP failed / warnings
    $items = @($Checks | Where-Object { $_[0] -ne 'H' })
    $f = @($items | Where-Object { $_[0] -eq 'FAIL' }).Count; $w = @($items | Where-Object { $_[0] -eq 'WARN' }).Count
    if ($items.Count) {
        $hex = if ($f) { $Pal.Red } elseif ($w) { $Pal.Amber } else { $Pal.Green }
        $big = if ($f) { "$f failed" } elseif ($w) { "$w to note" } else { 'all OK' }
        [void]$wp.Children.Add((New-HeadTile 'SETUP' $big ('{0} checks, {1} warning(s)' -f $items.Count, $w) $hex $null))
    }
    # VICTIMS cut off (attack PDR <= 0.1) out of the boards behind the attacker
    $vic = @($Nodes | Where-Object { [string]$_[2] -match 'VICTIM' })
    if ($vic.Count) {
        $cut = @($vic | Where-Object { $v = 0.0; [double]::TryParse([string]$_[5], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -le 0.1 }).Count
        $hex = if ($cut -eq $vic.Count) { $Pal.Green } elseif ($cut) { $Pal.Amber } else { $Pal.Red }
        [void]$wp.Children.Add((New-HeadTile 'VICTIMS CUT OFF' "$cut / $($vic.Count)" 'boards behind the attacker that stopped delivering' $hex (New-SegBar $cut $vic.Count $hex)))
    }
    # CONFIDENCE
    $gl = Get-GradeLook $grade
    [void]$wp.Children.Add((New-HeadTile 'CONFIDENCE' $(if ($grade -in 'SOUND', 'WITH NOTES', 'QUALIFIED', '-') { 'OLD REPORT' } elseif ($grade) { $grade } else { '?' }) $gl.Say $gl.Fg $null))
    $at = 0
    if ($ui.AnaResult.Children.Count -and $ui.AnaResult.Children[0] -is [Windows.Controls.WrapPanel]) { $at = 1 }   # after the gate pills
    if ($ui.AnaResult.Children.Count -gt $at -and $ui.AnaResult.Children[$at] -is [Windows.Controls.Border] -and $ui.AnaResult.Children[$at].Child -is [Windows.Controls.TextBlock]) { $at++ }   # after an "older report" note
    $ui.AnaResult.Children.Insert($at, $wp)
}

function Set-VerdictGradeLook {
    # the banner title + colour from the run's grade (set by Set-VerdictExtras); called
    # again by Set-VerdictBanner, which draws the plain verdict after the report
    $look = $script:VerdictGradeLook; if (-not $look) { return }
    $ui.VerdictTitle.Text = $look[0]
    try { $ui.Verdict.Background = $(if ($look[1] -like '#*') { Get-Brush $look[1] } else { $win.FindResource($look[1]) }) } catch { }
}

function Set-VerdictExtras([string[]]$Lines) {
    # the grade badge + area lights INSIDE the coloured verdict banner, under its text
    $host_ = $ui.VerdictText.Parent; if (-not ($host_ -is [Windows.Controls.Panel])) { return }
    if (-not $script:VerdictExtras) {
        $script:VerdictExtras = New-Object Windows.Controls.WrapPanel; $script:VerdictExtras.Margin = '0,6,0,0'
        [void]$host_.Children.Add($script:VerdictExtras)
    }
    $x = $script:VerdictExtras; $x.Children.Clear()
    # oct. 19 2026: the banner speaks the same words / colours as the Campaign page
    $gm = @($Lines | Where-Object { $_ -match '^\s*CONFIDENCE\s*:\s*(STRONG|GOOD|MINOR GAPS|MAJOR GAPS|FAILED|NOT CONFIRMED)' } | Select-Object -Last 1)
    if ($gm -and [string]$gm -match 'CONFIDENCE\s*:\s*(STRONG|GOOD|MINOR GAPS|MAJOR GAPS|FAILED|NOT CONFIRMED)') {
        $look = switch ($Matches[1]) {
            { $_ -in 'STRONG', 'GOOD' } { @('DONE - attack confirmed', 'GradGood') }
            'MINOR GAPS' { @('DONE - RECAPTURE ADVISED - minor gaps, result not affected', '#A16207') }
            'MAJOR GAPS' { @('RECAPTURE REQUIRED - major gaps, the result relies on what is missing', '#C2410C') }
            default           { @('REDO - FAILED: the attack cannot be confirmed', '#BE123C') } }
        # the campaign status can be stricter (a checklist / completeness recapture): it wins
        try {
            $cc = Get-Cell
            if ($cc) {
                $k = (Get-RunStatus $(if ($cc.Attack -in 'none', 'baseline') { 'baseline' } else { $cc.Attack }) ($cc.Topology -replace '^partial$', 'partial_mesh') $cc.Location $cc.Scenario $cc.Look).K
                if ($k -eq 'required') { $look = @('RECAPTURE REQUIRED - attack confirmed, the dataset must be captured again', '#C2410C') }
                elseif ($k -eq 'redo') { $look = @('REDO - FAILED: the attack cannot be confirmed', '#BE123C') }
            }
        } catch { }
        $script:VerdictGradeLook = $look
        Set-VerdictGradeLook
    } else { $script:VerdictGradeLook = $null }
    # the run's CAMPAIGN status (the redo list can ask for a recapture even when the attack
    # is confirmed - e.g. a checklist row: 7 of 8 boards) - shown so the two never look contradictory
    try {
        $cc = Get-Cell
        if ($cc) {
            $cs = Get-RunStatus $(if ($cc.Attack -in 'none', 'baseline') { 'baseline' } else { $cc.Attack }) ($cc.Topology -replace '^partial$', 'partial_mesh') $cc.Location $cc.Scenario $cc.Look
            $pb = New-Object Windows.Controls.Border; $pb.CornerRadius = 9; $pb.Padding = '10,3'; $pb.Margin = '0,0,8,4'; $pb.Background = Get-Brush '#33000000'
            $pb.Child = (New-Text ('CAMPAIGN: ' + $cs.T) 11.5 '#FFFFFF' 'Bold')
            $pb.ToolTip = 'The status this run has on the Campaign page (the redo list) - the same words and colours there'
            [void]$x.Children.Add($pb)
        }
    } catch { }
    $cl = @($Lines | Where-Object { $_ -match '^\s*CONFIDENCE\s*:' } | Select-Object -Last 1)
    if ($cl -and [string]$cl -match '^\s*CONFIDENCE\s*:\s*(STRONG|GOOD|MINOR GAPS|MAJOR GAPS|FAILED|NOT CONFIRMED|SOUND|WITH NOTES|QUALIFIED|-)') {
        $g = $Matches[1]; $lk = Get-GradeLook $g
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 9; $b.Padding = '10,3'; $b.Margin = '0,0,8,4'; $b.Background = Get-Brush '#33000000'
        $t = New-Text ('{0}  CONFIDENCE: {1}' -f [string]$lk.G, $(if ($g -in 'SOUND', 'WITH NOTES', 'QUALIFIED', '-') { 'old report' } else { $g })) 11.5 '#FFFFFF' 'Bold'; $b.Child = $t
        [void]$x.Children.Add($b)
    }
    $gl = @($Lines | Where-Object { $_ -match '^\s*AT A GLANCE:' } | Select-Object -Last 1)
    if ($gl) {
        foreach ($m in [regex]::Matches([string]$gl, '([A-Z][A-Z-]+) \[\s*(OK|WARN|FAIL|--)\s*\]')) {
            $g = switch ($m.Groups[2].Value) { 'FAIL' { [char]0x2716 } 'WARN' { [char]0x26A0 } 'OK' { [char]0x2714 } default { [char]0x2026 } }
            $b = New-Object Windows.Controls.Border; $b.CornerRadius = 9; $b.Padding = '8,2'; $b.Margin = '0,0,6,4'; $b.Background = Get-Brush '#26000000'
            $t = New-Text ('{0} {1}' -f [string]$g, $m.Groups[1].Value) 10.5 '#F1F5FF' 'SemiBold'; $b.Child = $t
            [void]$x.Children.Add($b)
        }
    }
    $x.Visibility = $(if ($x.Children.Count) { 'Visible' } else { 'Collapsed' })
}
