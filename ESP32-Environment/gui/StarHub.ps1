# gui\StarHub.ps1 - star + wormhole (D-28): every board but end A joins ONLY end A,
# so every board built for that run needs A's MAC (run.ps1 -AttackerMac). When A
# is flashed on ANOTHER laptop this preset does not know it; oct. 19 2026 a
# teammate flashing only the controls was blocked by a red STOP. Now the GUI asks
# for it once per preset per session. Dot-sourced by run_gui.ps1. ASCII only.

$script:StarHubMacs = @{}

function Read-StarHubMac([string]$PresetFile, [string]$Who) {
    if ($script:StarHubMacs.ContainsKey($PresetFile)) { return $script:StarHubMacs[$PresetFile] }
    if ($script:AutoConfirm) { return '' }    # -SelfTest: never block on a dialog
    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop } catch { return '' }
    $msg = "STAR + wormhole: $Who (wormhole end A) is the star's hub, and it is flashed on ANOTHER laptop.`n`n" +
           "Every board you flash here must be built with A's MAC, or it will never join.`n`n" +
           "Type end A's MAC (ask the laptop that flashes A - the GUI's Boards page shows it), e.g. 20:50:0d:e7:0c:80:"
    for ($try = 0; $try -lt 3; $try++) {
        $v = [Microsoft.VisualBasic.Interaction]::InputBox($msg, 'End A MAC (star hub)', '')
        if (-not $v) { return '' }    # cancelled
        $v = $v.Trim().ToLower() -replace '-', ':'
        if ($v -match '^[0-9a-f]{12}$') { $v = ($v -split '(..)' | Where-Object { $_ }) -join ':' }
        if ($v -match '^([0-9a-f]{2}:){5}[0-9a-f]{2}$') { $script:StarHubMacs[$PresetFile] = $v; return $v }
        $msg = "'$v' is not a MAC. Type it like 20:50:0d:e7:0c:80 (6 pairs of hex digits):"
    }
    return ''
}
