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
#
# -------------------------------------------------------------------------
# WARM BUILDS PRODUCE A FALSE "0 warnings" -- USE -Clean FOR MILESTONE PROOF
# -------------------------------------------------------------------------
# ninja only recompiles what changed. A source file that does NOT recompile
# CANNOT re-emit its warnings, so a warm run can print "ALL 6 VARIANTS BUILD
# CLEAN - 0 warnings" while real warnings sit in the source untouched.
#
# Demonstrated 2026-09-22 on this exact tree: a warm run reported 0 warnings;
# `touch child_node/main/wormhole_victim.c` and re-running the SAME script on
# the SAME source reported WORMHOLE Node A = 1, Node B = 1. Nothing had been
# fixed in between -- the first run simply never recompiled that file.
#
# M1 criterion 1 is "all firmware variants compile without warnings". Quoting a
# warm run as evidence for that is quoting the cache, not the code, and a panel
# rebuilding from scratch sees what the warm run hid. So:
#
#   .\build_all_variants.ps1 -Clean     <- milestone evidence / screenshots
#   .\build_all_variants.ps1            <- fast "did I break the build" check
#
# A warm run still runs, but it will NOT claim a clean build; it says the count
# is incremental and unverified, and names the variants it could not vouch for.
param(
    # Wipe every build directory first, so every file recompiles and every
    # warning is re-emitted. Slower (no ccache reuse for the changed parts) and
    # the only mode whose warning count means anything.
    [switch]$Clean
)

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$log  = Join-Path $repo "build_all_variants.log"
if (Test-Path $log) { Remove-Item $log -Force }

# The distinct firmware variants. Each differs by the compile flags it is built with,
# which is what makes it a separate "variant" for the milestone.
# Flag values taken from run.ps1:223-237 and child_node/main/CMakeLists.txt:
#   ACTIVE_ATTACK=255 -> baseline / plain victim (M1 firmware)
#   ACTIVE_ATTACK=1   -> blackhole  (BLACKHOLE_ROLE 0 = attacker relay, 1 = victim)
#   ACTIVE_ATTACK=2   -> wormhole   (WORMHOLE_END  0 = Node A exit, 1 = Node B entry)
# Getting these wrong silently builds the WRONG firmware and still reports BUILD OK —
# an earlier version of this script used ACTIVE_ATTACK=1 for the wormhole rows, so it
# compiled the blackhole attacker twice and labelled it "WORMHOLE".
#
# ⚠️ Bld is the BUILD DIRECTORY NAME and it is deliberately TINY. Do not
# "improve" these into readable names like build_check_BLACKHOLE_attacker.
# ESP-IDF's bootloader subproject generates paths ~136 characters long INSIDE
# the build dir (e.g. bootloader\esp-idf\bootloader_support\CMakeFiles\
# __idf_bootloader_support.dir\bootloader_flash\src\
# bootloader_flash_config_esp32.c.obj.d). Add that to a workstation checkout
# path and Windows MAX_PATH (260) is close. This script previously used
# "build_check_<Name>" and the longest row, BLACKHOLE attacker, landed on
# EXACTLY 260 on a normal checkout: ninja died with
#   fatal error: opening dependency file ...obj.d: No such file or directory
# deep inside the BOOTLOADER, long after the app itself had compiled, so the
# error looked unrelated to the variant and the milestone table reported a
# FAILED build for perfectly good code. The budget also depends on the USER'S
# OWN PATH, so it failed on some machines and not others.
# See MEMORY.md -> "Failed approaches" for the original diagnosis.
# The Name column below is what gets PRINTED, so readability is not lost.
$variants = @(
    @{ Name = "ROOT";               Bld = "bcr";  Proj = "root_node";  Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0") }
    @{ Name = "CHILD plain";        Bld = "bcc";  Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0") }
    @{ Name = "BLACKHOLE attacker"; Bld = "bcba"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=0","-DMESH_TOPOLOGY=0") }
    @{ Name = "BLACKHOLE victim";   Bld = "bcbv"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=1","-DMESH_TOPOLOGY=0") }
    @{ Name = "WORMHOLE Node A";    Bld = "bcwa"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=2","-DWORMHOLE_END=0","-DMESH_TOPOLOGY=0") }
    @{ Name = "WORMHOLE Node B";    Bld = "bcwb"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=2","-DWORMHOLE_END=1","-DMESH_TOPOLOGY=0") }
    # SCENARIO builds (run.ps1 -Scenario): each -DTRAFFIC_PROFILE compiles
    # different code (burst: victim_main.c + root_main.c, jitter: root_main.c,
    # highload: the probe interval in mesh_config.h), and none of it was ever
    # built by this script. Same pairing rules as run.ps1: burst = root + the
    # -ScenarioTarget child, highload = any non-root, jitter = root only.
    @{ Name = "ROOT burst";               Bld = "bcrb";  Proj = "root_node";  Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=1") }
    @{ Name = "ROOT jitter";              Bld = "bcrj";  Proj = "root_node";  Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=3") }
    @{ Name = "CHILD burst target";       Bld = "bccb";  Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=1") }
    @{ Name = "CHILD highload";           Bld = "bcch";  Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=255","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=2") }
    @{ Name = "BLACKHOLE victim burst";   Bld = "bcbvb"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=1","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=1") }
    @{ Name = "BLACKHOLE victim highload"; Bld = "bcbvh"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=1","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=2") }
    @{ Name = "BLACKHOLE attacker highload"; Bld = "bcbah"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=1","-DBLACKHOLE_ROLE=0","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=2") }
    @{ Name = "WORMHOLE Node A highload"; Bld = "bcwah"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=2","-DWORMHOLE_END=0","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=2") }
    @{ Name = "WORMHOLE Node B highload"; Bld = "bcwbh"; Proj = "child_node"; Flags = @("-DACTIVE_ATTACK=2","-DWORMHOLE_END=1","-DMESH_TOPOLOGY=0","-DTRAFFIC_PROFILE=2") }
)

# Preflight: say it OUT LOUD if this checkout is too deep, instead of letting
# ninja fail 700 objects in with an error that names a bootloader file. The
# 136 is the longest path ESP-IDF generates inside a build dir (above); 260 is
# MAX_PATH. This is a WARNING, not a hard stop — LongPathsEnabled=1 (admin) or
# a shorter checkout path both make it a non-issue, and some builds still fit.
# Which build dirs already exist decides whether this run's warning count can
# be trusted. Captured BEFORE anything is built, and before -Clean deletes them.
$warmVariants = @()
foreach ($v in $variants) {
    $bldPath = Join-Path (Join-Path $repo $v.Proj) $v.Bld
    if (Test-Path $bldPath) {
        if ($Clean) {
            Write-Host ("  wiping {0}\{1} ..." -f $v.Proj, $v.Bld) -ForegroundColor DarkGray
            Remove-Item -Recurse -Force $bldPath -ErrorAction SilentlyContinue
        } else {
            $warmVariants += $v.Name
        }
    }
}
if ($Clean) {
    Write-Host "Clean build: every variant recompiles from scratch, so the warning count is real." -ForegroundColor Green
} elseif ($warmVariants.Count) {
    Write-Host ("Incremental build: {0} variant(s) reuse cached objects. Warning count will NOT be trustworthy -- re-run with -Clean for milestone evidence." -f $warmVariants.Count) -ForegroundColor Yellow
}
Write-Host ""

$longestBld = ($variants | ForEach-Object { $_.Bld.Length } | Measure-Object -Maximum).Maximum
$longestProj = ($variants | ForEach-Object { (Join-Path $repo $_.Proj).Length } | Measure-Object -Maximum).Maximum
$worstPath = $longestProj + 1 + $longestBld + 1 + 136
if ($worstPath -ge 260) {
    Write-Host ""
    Write-Host ("  WARNING: this checkout is deep enough to hit Windows MAX_PATH. Worst-case build" ) -ForegroundColor Yellow
    Write-Host ("  path is ~{0} characters; the limit is 260. Builds may fail inside the BOOTLOADER" -f $worstPath) -ForegroundColor Yellow
    Write-Host ("  with a misleading 'No such file or directory' on a .obj.d file." ) -ForegroundColor Yellow
    Write-Host ("  Fix: move the repo nearer the drive root, or enable LongPathsEnabled=1 (admin)." ) -ForegroundColor Yellow
    Write-Host ""
}

$results = @()
$i = 0
foreach ($v in $variants) {
    $i++
    Write-Host ("[{0}/{1}] Building {2} ..." -f $i, $variants.Count, $v.Name) -ForegroundColor Cyan
    $dir = Join-Path $repo $v.Proj
    $bld = $v.Bld   # tiny on purpose — see the MAX_PATH note on $variants above

    Push-Location $dir
    # Splat via a plain variable. `@($v.Flags)` is an array SUBEXPRESSION, not a splat:
    # PowerShell passed both -D flags to the native exe as one argument, producing
    #   -DACTIVE_ATTACK="1 -DMESH_TOPOLOGY=0"
    # which root_main.c's `#if ACTIVE_ATTACK` rejects with
    #   error: token "=" is not valid in preprocessor expressions
    # The child builds survived it only because they don't evaluate that macro the
    # same way — so the bug looked like "ROOT is broken" when nothing was.
    $flags = @($v.Flags)
    $out = & idf.py -B $bld @flags build 2>&1 | Out-String
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

    # Confirm CMake selected the source file we expected. A wrong flag value can build
    # a DIFFERENT variant and still exit 0, which would make this whole table a lie.
    $srcMatch = [regex]::Match($out, 'Building (?:the )?([A-Za-z0-9_ ]+?)(?: firmware)?\s*\(')
    $selected = if ($srcMatch.Success) { $srcMatch.Groups[1].Value.Trim() } else { "" }

    $results += [pscustomobject]@{
        Variant  = $v.Name
        Result   = if ($code -eq 0) { "BUILD OK" } else { "FAILED" }
        Warnings = $warnings
        Errors   = $errors
        Selected = $selected
    }
}

Write-Host ""
Write-Host "==================== M1 criterion 1 ====================" -ForegroundColor Yellow
$results | Format-Table -AutoSize
$totW = ($results | Measure-Object -Property Warnings -Sum).Sum
$totE = ($results | Measure-Object -Property Errors   -Sum).Sum
$bad  = @($results | Where-Object { $_.Result -ne "BUILD OK" }).Count

if ($bad -eq 0 -and $totW -eq 0 -and $totE -eq 0 -and $warmVariants.Count -eq 0) {
    Write-Host ("ALL {0} VARIANTS BUILD CLEAN - 0 warnings, 0 errors" -f $results.Count) -ForegroundColor Green
    if (-not $Clean) {
        Write-Host "(every build dir was already absent, so this was a full compile)" -ForegroundColor DarkGray
    }
} elseif ($bad -eq 0 -and $totW -eq 0 -and $totE -eq 0) {
    # The dangerous case: looks perfect, proves nothing. Say so instead of
    # printing the same green line a clean run earns.
    Write-Host ("0 warnings reported, but this was an INCREMENTAL build - NOT a clean-build result." -f $null) -ForegroundColor Yellow
    Write-Host ("These {0} variant(s) reused cached objects and could not re-emit warnings:" -f $warmVariants.Count) -ForegroundColor Yellow
    Write-Host ("  " + ($warmVariants -join ", ")) -ForegroundColor Yellow
    Write-Host "Re-run with -Clean before quoting this as M1 criterion 1 evidence." -ForegroundColor Yellow
} else {
    Write-Host ("{0} variant(s) not clean - {1} warning(s), {2} error(s). See {3}" -f $bad, $totW, $totE, $log) -ForegroundColor Red
    Write-Host "Do NOT hide these in the presentation - state what they are." -ForegroundColor Yellow
}
Write-Host "Full output: $log"
