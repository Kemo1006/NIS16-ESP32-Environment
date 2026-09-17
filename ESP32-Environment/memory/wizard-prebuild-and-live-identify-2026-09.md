# Wizard pre-build + live identify, drop hardcoded roster roles (sep. 17, 2026)

Two independent changes to `run_wizard.ps1`/`run.ps1`/`tools\board_check.py`
made in the same session, both aimed at the wizard giving straighter answers
before any board gets touched.

## 1. Pre-build step + "what next" menu

`run.ps1` gained a `-BuildOnly` switch: compiles the exact variant (same build
dir, same `-D` flags run.ps1 itself computes) and exits with idf.py's exit
code - no wipe, no flash, no monitor, no port touched at all.

`run_wizard.ps1` now offers, right after the time estimate: "Pre-build every
node's firmware first?" If yes, it calls `run.ps1 -BuildOnly` per node
(children first, root last, same order as the real flash chain), so a cold
build never happens interleaved with the old per-child "Ctrl+] then press
'n'" cycle. A failed build stops the whole thing before anything is flashed.

Once every node compiles, a menu replaces the old blind "Proceed? [y/N]":
start the run now, save the preset then start, save the preset and stop, or
stop without saving. No Enter-default on purpose - the first two options
erase and flash real boards. Declining pre-build (or `-DryRun`) falls back to
the original flow unchanged.

Caveat: builds are cached per COM port, so a board that shows up on a
different port next time re-triggers a cold build. Children still flash +
monitor + export during the actual run - Ctrl+] is only skipped for the
compile step, not the flash-time hazards.

## 2. Dropped hardcoded ROOT/ATTACKER labels; live firmware read instead

`tools\board_check.py`'s `KNOWN` dict used to map each board's MAC to a role
guess baked in from one old campaign layout, e.g.
`"28:05:a5:32:d7:b4": "node1  (ROOT)"`. Since the MAC is burned into the chip
and the role is decided at flash time, that label survived every wipe,
reflash to a different role, or full erase - "identify" kept reporting
`(ROOT)` on a board that had been a plain child for weeks. Nothing in
`run_wizard.ps1` ever parsed the role text for logic (checked every read of
`$script:IdentifiedPorts` - all 10 call sites just display it), so this was
purely a misleading label, not a functional dependency.

Fix: `KNOWN` now maps MAC -> bare node number only (`"node1"`). A new
`short_firmware_tag()` in board_check.py turns `identify_firmware()`'s own
live boot-banner read into a short word (`ROOT`, `BLACKHOLE ATTACKER`,
`blank`, `CHILD (variant unclear...)`, etc.), printed as a machine-parseable
`firmware-short: ...` line. `run_wizard.ps1`'s identify (single-port and the
bulk "identify all" path) now captures that line and appends it, so the
display looks the same shape as before (`node1  (ROOT)`) but the role is a
live read, not a frozen guess. Bumped `--wait 1` to `--wait 5` for both
identify call sites so the runtime listen has a real chance at the boot
banner (board_check.py's own bootloader-check reset happens immediately
before this).

## Status

Both syntax-checked (`Parser]::ParseFile`, 0 errors) and ASCII-verified.
`run.ps1 -BuildOnly` smoke-tested with stubbed `idf.py`/`esptool` (correct
flags passed, no erase, no monitor call, exit code propagates on a forced
build failure). `board_check.py`'s `identify()`/`short_firmware_tag()` unit-
tested standalone (pyserial stubbed) - all branches return the expected
short tag. **Neither the pre-build path nor the live-identify read has been
run against real hardware.**
