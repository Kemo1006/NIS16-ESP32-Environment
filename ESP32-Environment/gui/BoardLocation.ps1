# gui\BoardLocation.ps1 - the Boards page's LOCATION box says what the CARD says
# (oct. 18 2026). Before, its picker simply started on the first item (G402) for
# every board, which read as "this board is in G402" although nothing was read.
#  * "card says: X" per board (by MAC - COM numbers change), filled from the
#    boot reports a Live run sees, from Read (its answer is parsed now) and from
#    Write (pending until the next boot). Amber when it is not the run's site.
#  * the picker (what WRITE writes) starts on the current run's location, else
#    the last used preset's - never silently on G402.
# Nothing here opens a port by itself: Read is still a button.
# Dot-sourced by run_gui.ps1. ASCII only.

$script:CardLoc = @{}   # mac (12 hex, lower) -> @{ Loc; When; How }

function Get-MacKey([string]$Mac) { return (($Mac -replace '[^0-9A-Fa-f]', '').ToLower()) }

function Set-CardLoc([string]$Mac, [string]$Loc, [string]$How) {
    $k = Get-MacKey $Mac; if ($k.Length -ne 12 -or -not $Loc) { return }
    $script:CardLoc[$k] = @{ Loc = $Loc; When = Get-Date; How = $How }
    Update-BoardLocView
}

function Get-DefaultLocation {
    if ($script:Run -and $script:Run.Plan -and $script:Run.Plan.Location) { return [string]$script:Run.Plan.Location }
    try { $L = Get-LastUsedPreset; if ($L -and $L.Location) { return [string]$L.Location } } catch { }
    return $null
}

function Update-BoardLocView {
    $tb = $script:CardLocText; if (-not $tb) { return }
    $r = $ui.PortGrid.SelectedItem
    if (-not $r) { $tb.Text = ''; return }
    $want = Get-DefaultLocation
    $c = if ($r.Mac) { $script:CardLoc[(Get-MacKey ([string]$r.Mac))] } else { $null }
    if ($c) {
        $tb.Text = 'card says: {0}   ({1}, {2})' -f $c.Loc, $c.How, $c.When.ToString('h:mm tt')
        $tb.Foreground = Get-Brush $(if (-not $want -or $c.Loc -eq $want) { $Pal.Green } else { $Pal.Amber })
        if ($want -and $c.Loc -ne $want) { $tb.Text += "   - not $want (the current run)" }
    } else {
        $tb.Text = 'card: not read yet - press Read (no reset; the board must be running)'
        $tb.Foreground = Get-Brush $Pal.Faint
    }
    if (-not $script:LocPickTouched) {
        $d = if ($c) { $c.Loc } else { $want }
        if ($d -and @($ui.LocPick.ItemsSource) -contains $d) { $script:LocPickSetting = $true; $ui.LocPick.SelectedItem = $d; $script:LocPickSetting = $false }
    }
}

function Complete-LocRead([string]$Text, $Row) {
    $m = [regex]::Match($Text, '(?m)^CURRENT_LOCATION:\s*(\S+)')
    if ($m.Success -and $Row -and $Row.Mac -and $m.Groups[1].Value -notin @('UNKNOWN')) { Set-CardLoc ([string]$Row.Mac) $m.Groups[1].Value 'read' }
}

function Complete-LocWrite([string]$Text, [int]$Code, $St) {
    if ($Code -eq 0 -and $Text -match 'LOCATION_SET|location.txt set to' -and $St.R -and $St.R.Mac) { Set-CardLoc ([string]$St.R.Mac) $St.Loc 'written - applies on its next boot' }
}

function Initialize-GuiBoardLocation {
    $row = $ui.LocWrite.Parent; if (-not $row -or -not ($row.Parent -is [Windows.Controls.Panel])) { return }
    $tb = New-Object Windows.Controls.TextBlock; $tb.FontSize = 11.5; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,6,0,0'
    $row.Parent.Children.Insert($row.Parent.Children.IndexOf($row) + 1, $tb)
    $script:CardLocText = $tb
    $ui.PortGrid.Add_SelectionChanged({ $script:LocPickTouched = $false; Update-BoardLocView })
    $ui.LocPick.Add_SelectionChanged({ if (-not $script:LocPickSetting) { $script:LocPickTouched = $true } })
}
