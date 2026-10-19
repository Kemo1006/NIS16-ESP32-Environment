# gui\Zoom.ps1 - the window fits the screen it is on (oct. 19 2026, user: "auto adjust,
# zoom, auto layout / resize depending on the screen or monitor, scroll").
#   * At start the window is sized to the monitor's work area and the whole UI is zoomed:
#       small screen  (smaller than the layout needs) -> zoom DOWN just enough to fit (>= 60 %)
#       big monitor   (much larger than the design)   -> zoom UP a little (<= 125 %)
#       otherwise 100 %
#   * Ctrl + mouse wheel / Ctrl + plus / Ctrl + minus = your own zoom (remembered per
#     laptop in the GUI settings); Ctrl + 0 or a click on the zoom chip = automatic again.
#   * The whole page scrolls instead of being cut off when the window is smaller than the
#     layout needs; above that size everything stretches as before.
#   * Moving the window to another monitor re-fits the automatic zoom.
# Dot-sourced by run_gui.ps1; Initialize-GuiZoom runs once the window exists. ASCII only.

$script:ZoomDesign = @{ W = 1440; H = 900; MinW = 1100; MinH = 760 }   # the layout's design / minimum size (unzoomed);
# MinH 760 = the sidebar's menu + its bottom block (I AM, search, toggles) without overlapping
$script:ZoomAuto   = 1.0
$script:ZoomUser   = 0.0        # 0 = automatic
$script:ZoomScreen = ''

function Get-ZoomScreenArea {
    # work area (WPF units) of the monitor the window is on; the primary one before it is shown
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
        if ($h -ne [IntPtr]::Zero) {
            $s = [Windows.Forms.Screen]::FromHandle($h)
            $src = [Windows.PresentationSource]::FromVisual($win)
            if ($src -and $src.CompositionTarget) {
                $m = $src.CompositionTarget.TransformFromDevice
                $wa = $s.WorkingArea
                $p1 = $m.Transform((New-Object Windows.Point $wa.Left, $wa.Top))
                $p2 = $m.Transform((New-Object Windows.Point $wa.Right, $wa.Bottom))
                return @{ Rect = (New-Object Windows.Rect $p1, $p2); Name = [string]$s.DeviceName }
            }
        }
    } catch { }
    return @{ Rect = [Windows.SystemParameters]::WorkArea; Name = 'primary' }
}

function Get-AutoZoom($Rect) {
    $d = $script:ZoomDesign
    $fit = [Math]::Min(($Rect.Width - 16) / $d.MinW, ($Rect.Height - 40) / $d.MinH)   # minus the window frame / title bar
    if ($fit -lt 1.0) { return [Math]::Max([Math]::Round($fit, 2), 0.6) }           # small screen: shrink to fit
    $big = [Math]::Min($Rect.Width / 1600, $Rect.Height / 1000)                     # big monitor: grow a little
    return [Math]::Round([Math]::Min([Math]::Max($big, 1.0), 1.25), 2)
}

function Get-GuiZoom { if ($script:ZoomUser -gt 0) { return $script:ZoomUser } return $script:ZoomAuto }

function Update-ZoomFit {
    # the content gets at least its minimum size (the page scrolls below it) and otherwise
    # exactly the window's size, in unzoomed units
    $sv = $script:ZoomSv; $root = $script:ZoomRoot
    if (-not $sv -or -not $root) { return }
    $z = Get-GuiZoom
    $root.LayoutTransform.ScaleX = $z; $root.LayoutTransform.ScaleY = $z
    $w = $sv.ActualWidth / $z; $h = $sv.ActualHeight / $z
    if ($w -gt 0) { $root.Width = [Math]::Max($w, $script:ZoomDesign.MinW) }
    if ($h -gt 0) { $root.Height = [Math]::Max($h, $script:ZoomDesign.MinH) }
    if ($script:ZoomChip) {
        $script:ZoomChip.Content = $(if ($script:ZoomUser -gt 0) { 'Zoom {0:0}%' -f (100 * $z) } else { 'Auto {0:0}%' -f (100 * $z) })
    }
}

function Set-GuiZoom([double]$Z) {
    # $Z = 0 -> automatic for this screen
    $script:ZoomUser = $(if ($Z -le 0) { 0.0 } else { [Math]::Round([Math]::Min([Math]::Max($Z, 0.6), 1.6), 2) })
    Update-ZoomFit
    try { $script:Settings.Zoom = $script:ZoomUser; Save-Settings } catch { }
    try { Set-Status $(if ($script:ZoomUser -gt 0) { 'Zoom {0:0}% (Ctrl + 0 = automatic for this screen)' -f (100 * $script:ZoomUser) } else { 'Zoom: automatic for this screen ({0:0}%)' -f (100 * $script:ZoomAuto) }) } catch { }
}

function Update-ZoomScreen {
    # (re)fit the automatic zoom to the monitor the window is on
    $a = Get-ZoomScreenArea
    if ($a.Name -eq $script:ZoomScreen) { return }
    $script:ZoomScreen = $a.Name
    $script:ZoomAuto = Get-AutoZoom $a.Rect
    Update-ZoomFit
}

function Initialize-GuiZoom {
    $root = $win.Content
    if (-not $root -or $script:ZoomSv) { return }
    # the whole UI inside one scroller; the zoom is a layout transform on the UI itself
    $win.Content = $null
    $sv = New-Object Windows.Controls.ScrollViewer
    $sv.HorizontalScrollBarVisibility = 'Auto'; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Focusable = $false
    $root.LayoutTransform = New-Object Windows.Media.ScaleTransform 1, 1
    $sv.Content = $root
    $win.Content = $sv
    $script:ZoomSv = $sv; $script:ZoomRoot = $root
    $win.MinWidth = 640; $win.MinHeight = 420           # smaller than the layout -> it scrolls
    $sv.Add_SizeChanged({ Update-ZoomFit })

    # the zoom chip in the status bar (click = automatic again)
    try {
        $bar = $ui.ToggleActivity.Parent
        $chip = New-Object Windows.Controls.Button
        $chip.Padding = '10,2'; $chip.Margin = '0,0,8,0'; $chip.FontSize = 11
        $chip.ToolTip = "Zoom - Ctrl + mouse wheel or Ctrl + plus / minus to change it.`nClick (or Ctrl + 0) = automatic for this screen."
        [Windows.Controls.DockPanel]::SetDock($chip, 'Right')
        $chip.Add_Click({ Set-GuiZoom 0 })
        $bar.Children.Insert(1, $chip)
        $script:ZoomChip = $chip
    } catch { }

    # Ctrl + wheel / Ctrl + plus, minus, 0
    $win.Add_PreviewMouseWheel({
        param($s, $e)
        if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -eq 0) { return }
        Set-GuiZoom ((Get-GuiZoom) + $(if ($e.Delta -gt 0) { 0.05 } else { -0.05 }))
        $e.Handled = $true
    })
    $win.Add_PreviewKeyDown({
        param($s, $e)
        if (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -eq 0) { return }
        switch ([string]$e.Key) {
            { $_ -in 'OemPlus', 'Add' }       { Set-GuiZoom ((Get-GuiZoom) + 0.1); $e.Handled = $true }
            { $_ -in 'OemMinus', 'Subtract' } { Set-GuiZoom ((Get-GuiZoom) - 0.1); $e.Handled = $true }
            { $_ -in 'D0', 'NumPad0' }        { Set-GuiZoom 0; $e.Handled = $true }
        }
    })

    try { if ([double]$script:Settings.Zoom -gt 0) { $script:ZoomUser = [double]$script:Settings.Zoom } } catch { }
    if ($SelfTest) {
        # screenshots stay comparable: 100 %, design size
        $script:ZoomAuto = 1.0; $script:ZoomUser = 0.0; $script:ZoomScreen = 'selftest'
        # test hook: NIS16_ZOOM_TEST="zoom,width,height" renders another screen size
        if ($env:NIS16_ZOOM_TEST -match '^([\d.]+),(\d+),(\d+)$') {
            $script:ZoomUser = [double]$Matches[1]; $win.Width = [double]$Matches[2]; $win.Height = [double]$Matches[3]
        }
        Update-ZoomFit
        return
    }
    # size the window to the screen before it is shown
    $a = Get-ZoomScreenArea
    $script:ZoomScreen = $a.Name
    $script:ZoomAuto = Get-AutoZoom $a.Rect
    $z = Get-GuiZoom
    $wantW = $script:ZoomDesign.W * $z; $wantH = $script:ZoomDesign.H * $z
    if ($wantW -ge $a.Rect.Width * 0.97 -or $wantH -ge $a.Rect.Height * 0.97) {
        $win.WindowState = 'Maximized'
    } else {
        $win.Width = $wantW; $win.Height = $wantH
    }
    Update-ZoomFit
    # another monitor -> re-fit the automatic zoom
    $win.Add_LocationChanged({ Update-ZoomScreen })
    $win.Add_StateChanged({ Update-ZoomScreen })
}
