# Run scenarios v1 (sep. 16, 2026)

Panel asked for real-world run-to-run variation: a node sending a burst of packets
to root (does the detector tell a legit burst from blackhole/wormhole?), a node
moving A->B, a node being unplugged/replugged. See panel-change-2026-09.md items
2/7. Design + full implementation plan lives in
`C:\Users\Basti\.claude\plans\c-users-basti-onedrive-documents-thesis-greedy-allen.md`
(the plan file from the session that built this).

## What was built

Five scenarios, selectable in BOTH run_wizard.ps1 and menu.ps1, via `run.ps1
-Scenario {none|burst|highload|mobility|powercycle} [-ScenarioTarget]`:

- **none** — today's behaviour. No build flag at all (not `=0`), so a plain
  run's compile line and build dir are byte-identical to before this feature.
- **burst** (code) — the `-ScenarioTarget` child fires 300 probes back-to-back
  60s into the attack-length window. Root also needs `-Scenario burst` so it
  holds that window on a BASELINE run too (gt_label unchanged, phase stays 0),
  giving a matched legit-burst-vs-attack-burst pair at the same offset.
- **highload** (code) — every child probes at 250ms instead of 1000ms for the
  whole run. Root untouched.
- **mobility** / **powercycle** (human) — no firmware change. run.ps1 prints a
  checklist right before the root boots, naming the target child and roughly
  when to act; the tooling does not time or beep it.

## Mechanism

Build-time `-DTRAFFIC_PROFILE=1` (burst) / `=2` (highload), same pattern as
`-DACTIVE_ATTACK` / `-DMESH_TOPOLOGY`. `mesh_config.h` derives `PROBE_INTERVAL_MS`
and the burst constants (`BURST_COUNT`, `BURST_OFFSET_S`, `BURST_GAP_MS`,
`BURST_POLL_MS`, `BURST_QUEUE_RETRY`) from it.

Burst arming: the target child watches `phase_listener_get_bcast_seq()` (new
getter) for a change — that's "the root just announced a phase boundary" even
when phase_id stays 0 (the baseline-run case). Window opens on phase_id 1/2, or
on the 2nd accepted broadcast on a baseline run; fires once, `BURST_OFFSET_S`
later. Only `victim_main.c`-based boards (plain child, blackhole victim,
wormhole `control`) are eligible — the attacker relay and wormhole A/B build
different source files with no probe generator this logic can hook into.

`root_main.c`'s `experiment_controller_task` gains a burst-flag-gated `#else`
branch: on `ACTIVE_ATTACK == ATTACK_NONE` it now re-broadcasts
`PHASE_ID_BASELINE` and holds an attack-length delay, but ONLY when
`TRAFFIC_PROFILE == TRAFFIC_PROFILE_BURST` — a plain baseline run is unaffected.

## Folder, not filename

`exports/<attack>/<topology>/<location>/<scenario>/` — but the scenario
segment is added ONLY for an actual scenario (burst/highload/mobility/
powercycle). `none` (the pre-scenario default, the vast majority of runs)
gets NO folder — it resolves to the exact `.../location/` path every run
used before this feature existed. `export_logs.py _subdir_for()`,
`run_wizard.ps1`/`run.ps1`'s `Get-RunDirs`/`-Analyze` block, and
`run_matrix.py`'s `cell_dir()` all agree on this. **History:** this session's
first draft did the opposite (always append, `none` included, for internal
consistency) — that created a real `analysis/blackhole/linear/home/none/`
folder that the user found unprompted in their IDE and correctly called a
bug (an extra folder level for the DEFAULT case breaks every existing path
convention for the 99% common case, for the sake of consistency nobody asked
for). Fixed in real time across all 5 path-builders while this same feature
was still being built; `verify_topology.py`'s `--scenario` narrowing and
`discover_groups`'s "no subfolder = none" inference already matched this
design correctly and needed no change. Filenames are untouched either way
(several tools parse them positionally by field).

## Touch list (for the next person extending this)

- Firmware: `mesh_config.h`, `phase_listener.h`/`.c` (new getter), `root_main.c`,
  `victim_main.c`, both `CMakeLists.txt` (child_node, root_node).
- Host: `run.ps1` (params, flag mapping, build-dir suffix, checklist),
  `menu.ps1` (`Select-Scenario`, `Get-BuildDirSpec`, both run flows, export-only,
  SD import), `run_wizard.ps1` (`$SCENARIOS`, step machine steps 3 + 9,
  `New-RunParams`, `Save-Preset`/`ConvertTo-Roster`, `Get-RunDirs`,
  `Get-BoardBuildDir`, `Invoke-ImportSdCard`).
- Python: `export_logs.py` (`SCENARIOS`, `--scenario`, `_subdir_for`),
  `import_sdcard.py` (`--scenario`, `_Args`), `run_matrix.py` (`SCENARIOS`,
  `SCENARIO_TARGETS`, ledger columns, every cell-key function), `verify_topology.py`
  (`discover_groups` keys by attack+scenario+repeat, not just attack+repeat).

## Build-dir suffix rule (mirrored in 3 places — keep identical)

Only a board that actually gets `-DTRAFFIC_PROFILE` takes a `_burst`/`_highload`
suffix: `run.ps1` (source of truth), `menu.ps1 Get-BuildDirSpec`, `run_wizard.ps1
Get-BoardBuildDir`. Drift here only mispredicts warm/cold, never flashes the
wrong firmware — but wastes minutes on a needless cold build.

## Verified (this session, no ESP32 attached)

Full-file PowerShell parse-check on all three `.ps1` files; `run.ps1` rejects
an invalid `-Scenario` value and `-ScenarioTarget` on `-Role root` before
touching hardware; `-Scenario none -ScenarioTarget` warns and keeps the plain
build dir name; a legacy no-scenario preset loads as `Scenario: none`
unmodified; a synthetic burst+target preset shows the TARGET marker, the right
export/analysis paths, and the exact `-Scenario`/`-ScenarioTarget` run.ps1
command; a burst preset with no target board throws on load; `run_matrix.py
--plan/--cmds` smoke-tested for real (scenario + target land correctly, the
`nodeb`+wormhole invalid combo is rejected); `verify_topology.py`'s
`discover_groups` tested against a synthetic tree — a `none` r1 and a `burst`
r1 no longer merge into one group.

**NOT bench-tested on real hardware** — no ESP32 in this session. Before the
next field day: flash one root + one plain child with `-Scenario burst
-ScenarioTarget`, confirm the child's console logs `BURST: window opened` /
`BURST: done 100/100`, and check the root's `_arrivals.csv` for 100
consecutive-`seq_num` rows in a ~1-2s span at the expected offset. Also watch
SPIFFS usage on a `highload` run with 4-5 children (I-017 risk — probes are
4x denser).
