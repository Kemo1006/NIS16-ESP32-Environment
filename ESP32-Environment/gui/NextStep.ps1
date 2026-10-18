# gui\NextStep.ps1 - one plain line per run: what to do next
#   captured -> import the cards (k missing) -> analyse -> verify -> done / redo
# Shown on the Campaign side panel and under each run on the Analyse page.
# Expected boards come from the preset for that run (root + expectedChildren).
# Dot-sourced by run_gui.ps1. ASCII only.

$script:PresetExpect = @{}   # preset path -> @{ T = write ticks; N = boards }

function Get-ExpectedBoards([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario) {
    # boards a preset of this run lists (root + expectedChildren); 0 = no preset here.
    # The presets folder is listed ONCE (refreshed every 15 s), not once per run:
    # per-run listing cost ~0.6 s on the Analyse page with 52 runs.
    $a = if ($Attack -in @('none', 'benign', 'baseline')) { 'baseline' } else { $Attack }
    $t = $Topology -replace '^partial$', 'partial_mesh'
    $name = ('{0}-{1}-{2}-{3}.json' -f $a, $t, $Location, $Scenario).ToLower()
    if (-not $script:PresetIndex -or ((Get-Date) - $script:PresetIndexAt).TotalSeconds -gt 15) {
        $idx = @{}
        foreach ($f in @(Get-ChildItem (Join-Path $base 'presets') -Filter '*.json' -Recurse -File -ErrorAction SilentlyContinue)) {
            $c = $script:PresetExpect[$f.FullName]
            if (-not $c -or $c.T -ne $f.LastWriteTimeUtc.Ticks) {
                $n = 0
                try { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; if ($j.expectedChildren) { $n = 1 + [int]$j.expectedChildren } } catch { }
                $c = @{ T = $f.LastWriteTimeUtc.Ticks; N = $n }; $script:PresetExpect[$f.FullName] = $c
            }
            $k = $f.Name.ToLower()
            if ($c.N -gt [int]$idx[$k]) { $idx[$k] = $c.N }
        }
        $script:PresetIndex = $idx; $script:PresetIndexAt = Get-Date
    }
    return [int]$script:PresetIndex[$name]
}

$script:TelemMac = @{}   # file -> @{ T; Mac }
function Get-TelemMac([IO.FileInfo]$F) {
    # the board of an export, from its first data row (names like child_node3_... carry no MAC)
    $c = $script:TelemMac[$F.FullName]
    if ($c -and $c.T -eq $F.LastWriteTimeUtc.Ticks) { return $c.Mac }
    $mac = $F.Name
    try {
        $sr = New-Object IO.StreamReader($F.FullName); [void]$sr.ReadLine(); $first = $sr.ReadLine(); $sr.Close()
        $m = [regex]::Match([string]$first, 'NODE_([0-9A-Fa-f]{12})'); if ($m.Success) { $mac = $m.Groups[1].Value.ToUpper() }
    } catch { }
    $script:TelemMac[$F.FullName] = @{ T = $F.LastWriteTimeUtc.Ticks; Mac = $mac }
    return $mac
}

function Get-NextStep([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario) {
    # @{ Text; Hex } - the one next thing to do for this run on this laptop
    $a = if ($Attack -in @('none', 'benign', 'baseline')) { 'baseline' } else { $Attack }
    $t = $Topology -replace '^partial$', 'partial_mesh'
    $exp = Join-Path $base ("datasets\exports\{0}\{1}\{2}\{3}" -f $a, $t, $Location, $Scenario)
    $ana = Join-Path $base ("datasets\analysis\{0}\{1}\{2}\{3}\feature_table.csv" -f $a, $t, $Location, $Scenario)
    if (-not [IO.Directory]::Exists($exp)) { return @{ Text = 'capture it'; Hex = $Pal.Dim } }
    # plain .NET, no cmdlets / pipelines: this runs for every run on each Analyse refresh
    $seen = @{}; $newest = [datetime]::MinValue
    foreach ($fp in [IO.Directory]::GetFiles($exp, '*_telem.csv')) {
        $fi = New-Object IO.FileInfo $fp
        $seen[(Get-TelemMac $fi)] = 1
        if ($fi.LastWriteTime -gt $newest) { $newest = $fi.LastWriteTime }
    }
    $want = Get-ExpectedBoards $a $t $Location $Scenario
    if ($want -gt 0 -and $seen.Count -lt $want) {
        return @{ Text = ("import the SD cards - {0} of {1} boards here ({2} missing)" -f $seen.Count, $want, ($want - $seen.Count)); Hex = $Pal.Amber }
    }
    if (-not [IO.File]::Exists($ana)) { return @{ Text = 'analyse it (data complete, no tables yet)'; Hex = $Pal.Cyan } }
    if ($newest -gt [IO.File]::GetLastWriteTime($ana).AddSeconds(5)) { return @{ Text = 'analyse it again (new data since the last analysis)'; Hex = $Pal.Cyan } }
    $r = $script:Redo[(Get-CellKey $a $t $Location $Scenario)]
    if ($r) {
        switch ([string]$r.severity) {
            'REDO'  { return @{ Text = 'capture it again - ' + [string](@($r.reasons | Where-Object { $_.severity -eq 'REDO' })[0].text); Hex = $Pal.Red } }
            'CHECK' { return @{ Text = 'check: ' + [string](@($r.reasons)[0].text); Hex = $Pal.Amber } }
            default { return @{ Text = 'done - verified'; Hex = $Pal.Green } }
        }
    }
    if ($a -eq 'baseline') { return @{ Text = 'done (benign run - nothing to verify)'; Hex = $Pal.Green } }
    return @{ Text = 'verify it'; Hex = $Pal.Cyan }
}

function Add-NextStepCard($Panel, [string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario) {
    # a "NEXT" strip at the top of a side panel
    try { $n = Get-NextStep $Attack $Topology $Location $Scenario } catch { return }
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 10; $b.Padding = '12,8'; $b.Margin = '0,0,0,10'
    $b.Background = Get-Brush $Pal.Card2; $b.BorderThickness = '3,0,0,0'; $b.BorderBrush = Get-Brush $n.Hex
    $sp = New-Object Windows.Controls.StackPanel
    [void]$sp.Children.Add((New-Text 'NEXT' 10 $n.Hex 'Bold'))
    $t = New-Text $n.Text 12.5 $Pal.Text 'SemiBold'; $t.TextWrapping = 'Wrap'; $t.Margin = '0,2,0,0'; [void]$sp.Children.Add($t)
    $b.Child = $sp
    $Panel.Children.Insert(0, $b)
}
