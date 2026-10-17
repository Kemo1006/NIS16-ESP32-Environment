# tools/test_wizard_nav.ps1 - run_wizard.ps1 navigation tests (oct. 17 2026).
# Run: powershell -File tools\test_wizard_nav.ps1   Loads the REAL
# functions out of the wizard by AST (nothing in the wizard runs), replaces
# Read-Line's input source with a scripted queue, and checks every back path.
$ErrorActionPreference = 'Stop'
$Error.Clear()
$wiz = Join-Path (Split-Path $PSScriptRoot -Parent) 'run_wizard.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($wiz, [ref]$null, [ref]$null)

# script-scope constants the menus use (copied from the wizard's own lines)
foreach ($st in $ast.EndBlock.Statements) {
    $t = $st.Extent.Text
    if ($t -match '^\$(script:MaxPromptTries|script:MainMenuSignal|script:BackSignal|script:ToolBackSignal|script:NavLocked|TOPOLOGIES|DATA_LOCATIONS|SCENARIOS|SCENARIO_LABELS)\s*=') {
        . ([scriptblock]::Create($t))
    }
}
$want = 'Show-Menu', 'Read-Line', 'Test-BackAnswer', 'Test-ClearScreenAnswer', 'Test-MainMenuAnswer',
        'Request-MainMenu', 'Request-ToolBack', 'Select-RunCell', 'Show-CaptureWizardMenu'
$fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
       Where-Object { $want -contains $_.Name }
foreach ($f in $fns) { . ([scriptblock]::Create($f.Extent.Text)) }

# scripted keyboard: Read-Host is what Read-Line calls
$script:Q = New-Object System.Collections.Queue
function Read-Host { if ($script:Q.Count -eq 0) { throw 'input queue empty' }; $script:Q.Dequeue() }
function Feed { param([string[]]$a) $script:Q.Clear(); foreach ($x in $a) { $script:Q.Enqueue($x) } }
$base = 'C:\nonexistent'   # main menu skips the member-board banner when its file is absent

$pass = 0; $fail = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { $script:pass++; Write-Host "  ok    $what" -ForegroundColor Green }
    else     { $script:fail++; Write-Host "  FAIL  $what" -ForegroundColor Red }
}
# Hide Write-Host (stream 6); keep any error that actually reaches the screen
# (stream 2) - those are failures even when the menu still returns a value.
$script:Printed = New-Object System.Collections.ArrayList
function Quiet([scriptblock]$b) {
    foreach ($o in (& $b 6>$null 2>&1)) {
        if ($o -is [System.Management.Automation.ErrorRecord]) { [void]$script:Printed.Add($o) } else { $o }
    }
}

Write-Host "`n[1] Show-Menu WITHOUT -AllowBack: 'b' leaves the tool (ToolBackSignal)"
Feed 'b'
$msg = $null
try { Quiet { Show-Menu -Title 't' -Options @('x', 'y') } | Out-Null } catch { $msg = $_.Exception.Message }
Check ($msg -eq $script:ToolBackSignal) "throws the tool-back signal (got '$msg')"

Write-Host "`n[2] Show-Menu WITH -AllowBack: 'b' returns -1 (previous question)"
Feed 'back'
$r = Quiet { Show-Menu -Title 't' -Options @('x', 'y') -AllowBack }
Check ($r -eq -1) "returns -1 (got $r)"

Write-Host "`n[3] Normal picks unchanged"
Feed '2'; $r = Quiet { Show-Menu -Title 't' -Options @('x', 'y') }
Check ($r -eq 1) "'2' -> index 1"
Feed '';  $r = Quiet { Show-Menu -Title 't' -Options @('x', 'y') -DefaultIndex 1 }
Check ($r -eq 1) "Enter -> default"
Feed 'zz', '1'; $r = Quiet { Show-Menu -Title 't' -Options @('x', 'y') }
Check ($r -eq 0) "garbage re-asks, then '1' -> 0"

Write-Host "`n[4] 'b' after flashing started (NavLocked) does NOT leave"
$script:NavLocked = $true
Feed 'b', '1'; $r = Quiet { Show-Menu -Title 't' -Options @('x', 'y') }
Check ($r -eq 0) "stays on the menu, next answer counts (got $r)"
$script:NavLocked = $false

Write-Host "`n[5] 'm' still goes to the main menu"
Feed 'm'; $msg = $null
try { Quiet { Show-Menu -Title 't' -Options @('x', 'y') -AllowBack } | Out-Null } catch { $msg = $_.Exception.Message }
Check ($msg -eq $script:MainMenuSignal) "throws the main-menu signal"

Write-Host "`n[6] Select-RunCell: step-by-step back"
# attack=blackhole(2), topology=tree(2), b -> back to topology, star(3), b, b -> attack again,
# wormhole(3), linear(1), scenario highload(3), location Yuchengco(3)
Feed '2', '2', 'b', '3', 'b', 'b', '3', '1', '3', '3'
$c = Quiet { Select-RunCell }
Check ($c.Attack -eq 'wormhole' -and $c.Topology -eq 'linear' -and $c.Scenario -eq 'highload' -and
       $c.Location -eq 'Yuchengco') "ends on wormhole/linear/highload/Yuchengco (got $($c.Attack)/$($c.Topology)/$($c.Scenario)/$($c.Location))"
Feed 'b'; $c = Quiet { Select-RunCell }
Check ($null -eq $c) "'b' on the FIRST question returns null (tool leaves)"
Feed '', '', '', ''; $c = Quiet { Select-RunCell -Defaults @{ attack = 1; topology = 2 } }
Check ($c.Attack -eq 'blackhole' -and $c.Topology -eq 'star' -and $c.Scenario -eq 'stationary' -and $c.Location -eq 'G402') "Enter x4 keeps the defaults"
Feed '3', '1', '2', 'b', '2', '4'; $c = Quiet { Select-RunCell -Steps @('attack', 'topology', 'location', 'scenario') -AttackOptions @('baseline', 'blackhole', 'wormhole') }
Check ($c.AttackIdx -eq 2 -and $c.LocationIdx -eq 1 -and $c.ScenarioIdx -eq 3) "custom order + back on the last step (idx $($c.AttackIdx)/$($c.LocationIdx)/$($c.ScenarioIdx))"
Feed '2', '1'; $c = Quiet { Select-RunCell -Steps @('attack', 'topology') }
Check ($c.Attack -eq 'blackhole' -and $c.Topology -eq 'linear' -and $null -eq $c.Location) "two-step chain"

Write-Host "`n[7] Main menu: renders, Enter = Run a capture, a number maps to its tool"
Feed ''; $r = Quiet { Show-CaptureWizardMenu }
Check ($r -eq 0) "Enter -> modeIdx 0 (run a capture)"
# The LAST number is Exit, however many tools the menu has (it grew to 28 on
# oct. 17 with 'Open the GUI version') - count the items instead of hard-coding.
$menuSrc = ($fns | Where-Object Name -eq 'Show-CaptureWizardMenu').Extent.Text
$lastNum = ([regex]::Matches($menuSrc, '@\{ Idx = \d+;')).Count + 1
Feed '99', "$lastNum"; $r = Quiet { Show-CaptureWizardMenu }
Check ($r -eq 8) "out-of-range 99 re-asks, then $lastNum (last) -> Exit (modeIdx 8)"

# Any error the menus PRINTED is a failure, even if every check passed: the
# oct. 17 console-width bug printed 54 errors while all 14 checks still passed.
$script:Printed | Select-Object -First 3 | ForEach-Object { Write-Host ('    error: ' + $_.Exception.Message) -ForegroundColor Yellow }
Check ($script:Printed.Count -eq 0) ("no errors printed while the menus ran (" + $script:Printed.Count + ")")
Write-Host ("`n{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
