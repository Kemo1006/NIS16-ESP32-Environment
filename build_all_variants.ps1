# build_all_variants.ps1 — compile every firmware variant and report warning counts.
#
# WHY THIS EXISTS
#   M1 criterion 1 is "all firmware variants compile without warnings". A normal
#   `run.ps1 -Flash` proves it for ONE variant and buries the proof in ~200 lines of
#   CMake chatter. This builds each variant with no board attached, greps the compiler
#   output for warnings, and prints a one-screen table you can screenshot.
#
# RUN IT FROM AN ESP-IDF POWERSHELL (the one where `idf.py` works):
#     .\build_all_variants.ps1
#
# Takes ~2-6 min total. ccache makes runs after the first much faster.
# Nothing is flashed and no board is needed.

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$log  = Join-Path $repo "build_all_variants.log"
if (Test-Path $log) { Remove-Item $log -Force }

# The distinct firmware variants. Each differs by the compile flags it is built with,
# which is what makes it a separate "variant" for the milestone.
$variants = @(
    @{ Name = "ROOT";              Proj = "root_node";  Flags = @("-DACTIVE_ATTACK=1","-DMESH_TOPOLOGY=0") }
    @{ Name = "CHILD plain";       Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=0","-DMESH_TOPOLOGY=0") }
    @{ Name = "BLACKHOLE attacker";Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=0","-DMESH_TOPOLOGY=0") }
    @{ Name = "BLACKHOLE victim";  Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=1","-DMESH_TOPOLOGY=0") }
    @{ Name = "WORMHOLE Node A";   Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DWORMHOLE_END=0","-DMESH_TOPOLOGY=0") }
    @{ Name = "WORMHOLE Node B";   Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DWORMHOLE_END=1","-DMESH_TOPOLOGY=0") }
)

$results = @()
$i = 0
foreach ($v in $variants) {
    $i++
    Write-Host ("[{0}/{1}] Building {2} ..." -f $i, $variants.Count, $v.Name) -ForegroundColor Cyan
    $dir = Join-Path $repo $v.Proj
    $bld = "build_check_" + ($v.Name -replace '[^A-Za-z0-9]','_')

    Push-Location $dir
    $out = & idf.py -B $bld @($v.Flags) build 2>&1 | Out-String
    $code = $LASTEXITCODE
    Pop-Location

    Add-Content $log ("=" * 70)
    Add-Content $log ("VARIANT: " + $v.Name + "   flags: " + ($v.Flags -join ' '))
    Add-Content $log ("=" * 70)
    Add-Content $log $out

    # Count real compiler diagnostics. ESP-IDF prints unrelated lines containing the
    # word "warning" (e.g. GDB's COM-port notice), so match the gcc diagnostic form
    # "<file>:<line>:<col>: warning:" instead of any occurrence of the word.
    $warnings = ([regex]::Matches($out, '(?m)^.*:\d+:\d+:\s+warning:')).Count
    $errors   = ([regex]::Matches($out, '(?m)^.*:\d+:\d+:\s+error:')).Count

    $results += [pscustomobject]@{
        Variant  = $v.Name
        Result   = if ($code -eq 0) { "BUILD OK" } else { "FAILED" }
        Warnings = $warnings
        Errors   = $errors
    }
}

Write-Host ""
Write-Host "==================== M1 criterion 1 ====================" -ForegroundColor Yellow
$results | Format-Table -AutoSize
$totW = ($results | Measure-Object -Property Warnings -Sum).Sum
$totE = ($results | Measure-Object -Property Errors   -Sum).Sum
$bad  = @($results | Where-Object { $_.Result -ne "BUILD OK" }).Count

if ($bad -eq 0 -and $totW -eq 0 -and $totE -eq 0) {
    Write-Host ("ALL {0} VARIANTS BUILD CLEAN - 0 warnings, 0 errors" -f $results.Count) -ForegroundColor Green
} else {
    Write-Host ("{0} variant(s) not clean - {1} warning(s), {2} error(s). See {3}" -f $bad, $totW, $totE, $log) -ForegroundColor Red
    Write-Host "Do NOT hide these in the presentation - state what they are." -ForegroundColor Yellow
}
Write-Host "Full output: $log"
