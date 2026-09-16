# menu.ps1 navigation rebuild (sep. 17, 2026)

`menu.ps1` now navigates like `run_wizard.ps1`: `b` goes back one question, every
prompt states its default, and the multi-board plan can be edited after it is built.

## Why

The launcher only ever offered `m` (main menu), which throws away the whole action.
Answering one question wrong part-way through a 14-question flow — or hitting Enter
on "Add another board?" by reflex — meant redoing everything, so the only real exit
was killing the window.

## What changed

**Step machines.** Six flows were rewritten as `:label while` + `switch ($step)` loops,
the same shape `run_wizard.ps1` uses: Run a board, Run MULTIPLE (run-wide settings),
Export only, Verify, Analysis only, Import SD card. Every answer lives in a variable
initialised before the loop and is passed back as that step's own `-Default`, so going
back and forward again re-offers what you already picked. `b` on the FIRST question of
a flow backs out to the main menu.

**`$dir` (the non-obvious part).** Steps that don't apply — attack sub-role on a root
board, location when you're not exporting — do `$step += $dir` instead of jumping
forward. Without it, travelling backwards through a skipped step bounces forward again
and the step before it is unreachable. Verified: `b` from the scenario-target question
on a baseline run lands on Scenario, two skipped steps earlier.

**Defaults made explicit.** `Read-YesNo` now renders `[Y/n, default Y]` instead of
encoding the default only in which letter is capitalised — `Read-Choice` was already
announcing `[default 1]` right next to it. `Read-Line` gained `-Default`/`-AllowBack`,
both opt-in so nested one-off prompts keep rendering unchanged.

**Multi-board plan editing.** `Add-BoardInteractive` collects one board and is shared
by the initial add loop and a new "Add another board" entry on the plan summary, which
also gained "Remove a node". `b` mid-board abandons just that board. haveRoot /
haveScenarioTarget are derived fresh from the committed board list each call, so an
abandoned board can't leave a phantom "root already taken" behind.

## Two bugs found while doing it

1. **`Get-ReorderedBoards` scalar collapse.** `return $ordered` UNROLLS a one-element
   array to a scalar `PSCustomObject`. `$boards += $new` then died with *"does not
   contain a method named 'op_Addition'"*, and `$boards.Count` silently read as `$null`,
   labelling the second board "Board 1". Latent until the plan-summary "add" path
   existed. Fixed with `return ,$ordered`.
2. **`-eq` coercion against the back sentinel.** `$bool -eq $script:BackSignal` converts
   the string to `$true`, so a legitimate "yes" matched as a back request. The sentinel
   must be the LEFT operand: `$script:BackSignal -eq $answer`. Applies anywhere a
   `Read-YesNo -AllowBack` result is tested.

## Status

Syntax-checked and driven end-to-end with scripted stdin (Verify, Export only, Analysis
only, Wipe, Run a board, and the full multi-board add/cancel/add/remove sequence that
previously crashed). No board was flashed: fake COM98/COM97 and a stubbed `idf.py` were
used, and every final confirm was declined. **Not bench-tested on real hardware.**
`menu.ps1` re-checked as pure ASCII per [[reference-windows-ps1-ascii]].
