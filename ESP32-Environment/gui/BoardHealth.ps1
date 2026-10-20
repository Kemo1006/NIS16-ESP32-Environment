# gui\BoardHealth.ps1 - LIVE BOARD HEALTH card on the Live run page (oct. 20 2026, user: "a live
# illustration on the side panel of the UART status, the health of every board and the SD cards
# - without lag").
#
# Data: the root firmware (oct. 20 2026) prints one line per child after every status table:
#   NODESTAT AA:BB:CC:DD:EE:FF sd=OK|WAITING|STALLED|INCOMPLETE|NO_CARD|GIVEN_UP|NA
#            uart=OK|CHECKING|NO_SIGNAL|LOST|ONE_WAY|ECHO|NA age=<s since heard> up=<s> rssi=<dBm>
# The children run on powerbanks during a capture, so the ROOT is the only live source.
# No lag: lines only update a table; the card is redrawn at most every 2 s and only when
# something changed (the root prints every ~14 s) - never on every 250 ms tick. Uptime going
# DOWN between two reports = that board restarted (counted). Older root firmware prints no
# NODESTAT: the card then says so instead of showing stale dots. Dot-sourced. ASCII only.

$script:BH = $null

function Reset-BoardHealth {
    $script:BH = @{ Stat = @{}; Dirty = $true; DrawnAt = [datetime]::MinValue; Lost = @{} }
    Initialize-BoardHealthUi
    if ($script:BHCard) { $script:BHCard.Visibility = 'Visible'; $script:BHBody.Children.Clear(); $script:BHNote.Text = 'Waiting for the root''s first status table (it prints one every ~14 s once children join).' }
}

function Initialize-BoardHealthUi {
    if ($script:BHCard) { return }
    try { $host_ = $ui.RunTunnelCard.Parent } catch { return }
    if (-not ($host_ -is [Windows.Controls.Panel])) { return }
    $card = New-Object Windows.Controls.Border
    try { $card.Style = $win.FindResource('Card') } catch { }
    $card.Padding = '16,12'; $card.Margin = '0,0,0,12'
    $sp = New-Object Windows.Controls.StackPanel
    $hd = New-Object Windows.Controls.TextBlock; $hd.Text = 'BOARD HEALTH  (live, from the root)'
    try { $hd.Style = $win.FindResource('Label') } catch { }
    [void]$sp.Children.Add($hd)
    $chips = New-Object Windows.Controls.WrapPanel; $chips.Margin = '0,2,0,6'; [void]$sp.Children.Add($chips)
    $link = New-Object Windows.Controls.StackPanel; $link.Margin = '0,0,0,6'; [void]$sp.Children.Add($link)
    $body = New-Object Windows.Controls.StackPanel; [void]$sp.Children.Add($body)
    $note = New-Object Windows.Controls.TextBlock; $note.FontSize = 10.5; $note.TextWrapping = 'Wrap'; $note.Margin = '0,4,0,0'
    $note.Foreground = & $brush $Pal.Faint; [void]$sp.Children.Add($note)
    $card.Child = $sp
    # right under the START gate = above the MESH card (visible without scrolling)
    $at = $host_.Children.IndexOf($ui.RunTunnelCard)
    try {
        $x = $ui.RunTopoBadge
        while ($x -and $x.Parent -ne $host_) { $x = $x.Parent }
        if ($x) { $at = $host_.Children.IndexOf($x) }
    } catch { }
    [void]$host_.Children.Insert($at, $card)
    $script:BHCard = $card; $script:BHChips = $chips; $script:BHLink = $link; $script:BHBody = $body; $script:BHNote = $note
}

function Read-BoardHealthLine([string]$T) {
    # $true = it was a NODESTAT line (the caller stops there)
    if ($T -notmatch '^NODESTAT (?<mac>(?:[0-9A-F]{2}:){5}[0-9A-F]{2}) sd=(?<sd>\S+) uart=(?<uart>\S+) age=(?<age>-?\d+) up=(?<up>\d+) rssi=(?<rssi>-?\d+)') { return $false }
    if (-not $script:BH) { Reset-BoardHealth }
    $mac = $Matches.mac.ToLower()
    $old = $script:BH.Stat[$mac]
    $up = [long]$Matches.up
    $restarts = 0; if ($old) { $restarts = $old.Restarts; if ($up + 30 -lt $old.Up) { $restarts++ } }
    $script:BH.Stat[$mac] = @{ Sd = $Matches.sd; Uart = $Matches.uart; Age = [int]$Matches.age; Up = $up; Rssi = [int]$Matches.rssi; Restarts = $restarts; At = (Get-Date) }
    if ($old -and $restarts -gt $old.Restarts) { Add-RunAlert ("{0} RESTARTED (uptime went back to {1} s) - power or crash; its file is split" -f (Get-BHName $mac), $up) $Pal.Amber }
    if ($old -and $old.Sd -ne $Matches.sd -and $Matches.sd -in @('NO_CARD', 'GIVEN_UP', 'STALLED', 'INCOMPLETE')) { Add-RunAlert ("{0}: SD card {1}" -f (Get-BHName $mac), $Matches.sd.Replace('_', ' ')) $(if ($Matches.sd -in @('NO_CARD', 'GIVEN_UP')) { $Pal.Red } else { $Pal.Amber }) }
    if ($old -and $old.Uart -eq 'OK' -and $Matches.uart -notin @('OK', 'NA', 'CHECKING')) { Add-RunAlert ("{0}: wormhole UART link {1} - check the jumpers and the common GND" -f (Get-BHName $mac), $Matches.uart.Replace('_', ' ')) $Pal.Red }
    $script:BH.Dirty = $true
    return $true
}

function Get-BHName([string]$Mac) {
    try { foreach ($b in @($script:Run.Plan.Full)) { if ($b.Mac -and ([string]$b.Mac).ToLower() -eq $Mac) { return [string]$b.Label } } } catch { }
    try { $k = (Get-MemberInfo)[(Get-ShortMac $Mac).ToLower()]; if ($k -and $k.Nick) { return [string]$k.Nick } } catch { }
    return (Get-ShortMac $Mac)
}

function New-BHDot([string]$Hex, [string]$Tip) {
    $e = New-Object Windows.Shapes.Ellipse; $e.Width = 10; $e.Height = 10; $e.Margin = '0,0,6,0'; $e.VerticalAlignment = 'Center'
    $e.Fill = & $brush $Hex; $e.ToolTip = $Tip; return $e
}

function Get-BHSdLook([string]$S) {
    switch ($S) { 'OK' { $Pal.Green } 'WAITING' { $Pal.Dim } 'STALLED' { $Pal.Amber } 'INCOMPLETE' { $Pal.Amber } 'NO_CARD' { $Pal.Red } 'GIVEN_UP' { $Pal.Red } default { $Pal.Faint } }
}
function Get-BHUartLook([string]$S) {
    switch ($S) { 'OK' { $Pal.Green } 'CHECKING' { $Pal.Dim } 'NA' { $Pal.Faint } default { $Pal.Red } }
}
function Get-BHAliveLook([int]$Age) { if ($Age -le 20) { $Pal.Green } elseif ($Age -le 40) { $Pal.Amber } else { $Pal.Red } }

function Update-BoardHealth {
    # called from the run tick; cheap when nothing changed
    $B = $script:BH; if (-not $B -or -not $script:BHCard) { return }
    if (-not $B.Dirty -or ((Get-Date) - $B.DrawnAt).TotalSeconds -lt 2) { return }
    $B.Dirty = $false; $B.DrawnAt = Get-Date
    $rows = @($B.Stat.GetEnumerator() | Sort-Object { Get-BHName $_.Key })
    if (-not $rows.Count) { return }
    # how stale each report is NOW (the root's age + seconds since its line)
    $alive = 0; $sdOk = 0; $restarts = 0; $ends = @()
    foreach ($r in $rows) {
        $s = $r.Value; $s.AgeNow = $s.Age + [int]((Get-Date) - $s.At).TotalSeconds
        if ($s.AgeNow -le 40) { $alive++ }
        if ($s.Sd -eq 'OK') { $sdOk++ }
        $restarts += $s.Restarts
        if ($s.Uart -ne 'NA') { $ends += $r }
    }
    $script:BHChips.Children.Clear()
    $chip = {
        param([string]$Text, [string]$Hex)
        $bd = New-Object Windows.Controls.Border; $bd.CornerRadius = 8; $bd.Padding = '8,2'; $bd.Margin = '0,0,6,4'
        $bd.Background = & $brush $Hex
        $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $Text; $tb.FontSize = 11; $tb.FontWeight = 'SemiBold'; $tb.Foreground = & $brush '#0B1020'
        $bd.Child = $tb; [void]$script:BHChips.Children.Add($bd)
    }
    & $chip ("alive {0}/{1}" -f $alive, $rows.Count) $(if ($alive -eq $rows.Count) { $Pal.Green } elseif ($alive) { $Pal.Amber } else { $Pal.Red })
    & $chip ("SD writing {0}/{1}" -f $sdOk, $rows.Count) $(if ($sdOk -eq $rows.Count) { $Pal.Green } else { $Pal.Amber })
    if ($ends.Count) {
        $uOk = @($ends | Where-Object { $_.Value.Uart -eq 'OK' }).Count
        & $chip ("UART {0}" -f $(if ($uOk -eq $ends.Count) { 'linked' } else { 'NOT linked' })) $(if ($uOk -eq $ends.Count) { $Pal.Green } else { $Pal.Red })
    }
    & $chip ("restarts {0}" -f $restarts) $(if ($restarts) { $Pal.Amber } else { $Pal.Green })
    # the tunnel drawing: A ===== B, the wire coloured by the worse end
    $script:BHLink.Children.Clear()
    if ($ends.Count -ge 1) {
        $g = New-Object Windows.Controls.Grid; $g.Height = 30
        foreach ($w in 'Auto', '*', 'Auto') { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq '*') { New-Object Windows.GridLength 1, 'Star' } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
        $worst = if (@($ends | Where-Object { $_.Value.Uart -notin @('OK', 'CHECKING') }).Count) { $Pal.Red } elseif (@($ends | Where-Object { $_.Value.Uart -eq 'CHECKING' }).Count) { $Pal.Dim } else { $Pal.Green }
        $i = 0
        foreach ($e in @($ends | Select-Object -First 2)) {
            $bx = New-Object Windows.Controls.Border; $bx.CornerRadius = 6; $bx.Padding = '8,3'; $bx.Background = & $brush $(Get-BHAliveLook $e.Value.AgeNow)
            $tb = New-Object Windows.Controls.TextBlock; $tb.Text = (Get-BHName $e.Key); $tb.FontSize = 11; $tb.FontWeight = 'Bold'; $tb.Foreground = & $brush '#0B1020'
            $bx.Child = $tb; $bx.ToolTip = ("UART {0}, heard {1} s ago" -f $e.Value.Uart, $e.Value.AgeNow)
            [Windows.Controls.Grid]::SetColumn($bx, $(if ($i -eq 0) { 0 } else { 2 })); [void]$g.Children.Add($bx); $i++
        }
        $ln = New-Object Windows.Shapes.Rectangle; $ln.Height = 4; $ln.Margin = '6,0'; $ln.RadiusX = 2; $ln.RadiusY = 2; $ln.Fill = & $brush $worst
        $ln.ToolTip = 'The UART wire between the two wormhole boards (TX-RX, RX-TX, GND-GND)'
        [Windows.Controls.Grid]::SetColumn($ln, 1); [void]$g.Children.Add($ln)
        $cap = New-Object Windows.Controls.TextBlock; $cap.FontSize = 10.5; $cap.Foreground = & $brush $worst
        $cap.Text = $(if ($worst -eq $Pal.Green) { 'UART tunnel linked - both ends hear each other' } elseif ($worst -eq $Pal.Dim) { 'UART tunnel: still checking' } else { 'UART tunnel BROKEN - ' + ((@($ends | ForEach-Object { '{0} {1}' -f (Get-BHName $_.Key), $_.Value.Uart.Replace('_', ' ') })) -join ', ') + ' - check TX/RX/GND' })
        [void]$script:BHLink.Children.Add($g); [void]$script:BHLink.Children.Add($cap)
    }
    # one compact row per board
    $script:BHBody.Children.Clear()
    foreach ($r in $rows) {
        $s = $r.Value
        $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = '0,1,0,1'
        $dots = New-Object Windows.Controls.StackPanel; $dots.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($dots, 'Left')
        [void]$dots.Children.Add((New-BHDot (Get-BHAliveLook $s.AgeNow) ("heard {0} s ago" -f $s.AgeNow)))
        [void]$dots.Children.Add((New-BHDot (Get-BHSdLook $s.Sd) ("SD card: {0}" -f $s.Sd)))
        if ($s.Uart -ne 'NA') { [void]$dots.Children.Add((New-BHDot (Get-BHUartLook $s.Uart) ("UART: {0}" -f $s.Uart))) }
        [void]$dp.Children.Add($dots)
        $info = New-Object Windows.Controls.TextBlock; $info.FontSize = 10.5; $info.Foreground = & $brush $Pal.Faint; [Windows.Controls.DockPanel]::SetDock($info, 'Right')
        $info.Text = ("{0}s ago  up {1}{2}" -f $s.AgeNow, (Format-Duration ([int]$s.Up)), $(if ($s.Restarts) { "  restarts $($s.Restarts)" } else { '' }))
        [void]$dp.Children.Add($info)
        $nm = New-Object Windows.Controls.TextBlock; $nm.Text = (Get-BHName $r.Key); $nm.FontSize = 12; $nm.FontWeight = 'SemiBold'
        $nm.Foreground = & $brush $(if ($s.AgeNow -gt 40) { $Pal.Red } else { $Pal.Text })
        [void]$dp.Children.Add($nm)
        [void]$script:BHBody.Children.Add($dp)
    }
    $lost = @($rows | Where-Object { $_.Value.AgeNow -gt 40 })
    $script:BHNote.Text = $(if ($lost.Count -eq $rows.Count -and $rows.Count) { 'NO board heard for 40 s+ - if a hub / parent dropped, every board under it is cut off: they keep logging and close their files themselves after the planned run (new firmware).' }
                            elseif ($lost.Count) { ("Not heard for 40 s+: {0}" -f ((@($lost | ForEach-Object { Get-BHName $_.Key })) -join ', ')) }
                            else { 'dots: heard recently  /  SD card writing  /  UART (wormhole ends only). Hover a dot for details.' })
}
