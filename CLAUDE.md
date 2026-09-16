# combined (NIS16 ESP-WIFI-MESH thesis) — Workstation Anchor

Auto-loaded every session. **Rules only** — facts live in MEMORY.md. Cap: 125 lines; trim before adding.

## Session start (in order, nothing more)

1. Read [AGENTS.md](AGENTS.md) — how you work (task complexity + roles). Small, always applies.
2. Read [STATUS.md](STATUS.md) — current state, next step, blockers.
3. If the task matches a row in **Workstations** below, read that subfolder's CLAUDE.md + MEMORY.md.
4. Load everything else **only when routed**. Never read the whole folder "to get context."

## Routing — load on demand

| Need | Read |
|---|---|
| Where does X live / structure | [FILEMAP.md](FILEMAP.md) |
| Why was X decided / facts, prefs, constraints | [MEMORY.md](MEMORY.md) |
| History of completed work | [ARCHIVE.md](ARCHIVE.md) — **only if the user explicitly asks** |
| Task needs a shared reference | [0_Resources/INDEX.md](0_Resources/INDEX.md) — match a trigger, load only that file |

## Workstations — the routing map (add rows as domains emerge; skip for single-domain projects)

This table is how sessions route. At session start, match the task here; a hit → load that workstation's CLAUDE.md + MEMORY.md. Each workstation owns its **local** resources (its own `Resources/` folder + Resources table); only cross-workstation files live in 0_Resources. This is the one glance-able map when the domain is unclear.

| Workstation | Route here when the task is about... |
|---|---|
| (none yet) | |

To create one: follow the recipe in [0_Resources/creating-workstations.md](0_Resources/creating-workstations.md), then add a row above. Root files stay authoritative; workstation files only add domain specifics.

## Rules vs facts — where things go

- Prescribes behavior ("always / never / before X do Y") → this file (or the workstation's CLAUDE.md).
- Describes changeable reality (status, decisions, preferences, environment) → MEMORY.md.
- User says **"remember it"** → write it to the right file immediately and confirm. Unsure which → propose one, ask.
- New info conflicts with recorded knowledge → flag the conflict before overwriting.

## How you work — see [AGENTS.md](AGENTS.md)

Task complexity (simple → just do it; complex → Planner→Builder→Tester→Mapper cycle) and the `@deep` / `@quick` overrides live in [AGENTS.md](AGENTS.md), loaded at session start. Kept there so any AGENTS.md-aware tool gets the same behavior — this file just points to it, no duplicate.

## Working rules

- Verify, don't assume: check FILEMAP.md or real files before claiming structure. If they disagree, fix FILEMAP.md.
- Read the target (relevant part only) before editing it.
- **MEMORY.md is the team's shared brain across every laptop/user working this project** — not
  a personal scratchpad for this one session. After **any** user-requested change (code, config,
  data/file moves, decisions, rejected approaches — not just what feels like a "big" decision):
  overwrite STATUS.md, and log a dated entry in MEMORY.md before ending the turn. Write it so a
  Claude session on a *different laptop*, with zero other context, can act on it cold — state the
  why, not just the what. Completed/superseded entries roll to ARCHIVE.md to hold the line cap.
  Pure Q&A / read-only turns (nothing changed) need no entry — don't pad it with noise.
- Destructive/irreversible actions (delete, overwrite non-generated files, deploy/publish): confirm first unless pre-authorized in MEMORY.md.
- If unsure and the wrong guess is costly → ask. Otherwise pick a sensible default and state it.
- This agent is synchronous — it never wakes on its own. Recurring/background checks (link audits, reminders, reviews) need an explicit scheduler (`/schedule`, `/loop`, or an OS cron / Task Scheduler entry), not an assumption that a future session will notice.
- Enforce line caps and link targets deterministically before calling a file done — a count or grep, not an eyeballed read. Self-reported compliance drifts.

## Resources — where reference files live

- **Global / shared** (cross-workstation) → [0_Resources/INDEX.md](0_Resources/INDEX.md). **Never auto-loaded, never read whole.** Consult the index, load only the one file whose trigger matches; no match → proceed without it.
- **Domain-specific** → inside the active workstation's own `Resources/`, listed in its CLAUDE.md. Loaded only while that workstation is active. Don't push domain files into 0_Resources.

**Dependency ledger:** any package install / update / retain / failed attempt (npm, pip, cargo, brew, apt, choco, global binaries) → append one row to [0_Resources/archive_tech.md](0_Resources/archive_tech.md) **immediately**, per the schema in its header. Append-only, no line limit, never edit past rows. Classify Action Type (New Install / Update (from X) / Retain (No Change)) and Status (Installed / Verified / Failed / Cancelled).

## Line caps & overflow

| File | Cap | Overflow protocol |
|---|---|---|
| CLAUDE.md (root) | 125 | Trim or move detail into the file it belongs to |
| STATUS.md | 40 | Move "done" items to ARCHIVE.md |
| MEMORY.md | 200 | Move oldest entries to ARCHIVE.md |
| FILEMAP.md | 200 | Collapse detail; map meaning, not every file |
| Workstation CLAUDE/MEMORY | 60 / 100 | Same: trim or archive |
| ARCHIVE.md | none | Append-only; never read unless asked |

## Model strategy & switching advisor

- On **"session summary"**: distill the session (decisions, files changed, open tasks) into STATUS.md + MEMORY.md, then tell the user a fresh chat can continue from those files alone.
- Before acting on any request, weigh its complexity against the tiers below. If the active model is under- or over-powered for the task, pause and post the advisory format instead of proceeding.

| Tier | Use for |
|---|---|
| Haiku / Fast | Bulk file ops (rename/sort/move by pattern), log/JSON/CSV/YAML cleanup, typo fixes, dedup, regex extraction, short-snippet explanations. |
| Sonnet — default (~80% of tasks) | Everyday scripts, UI components, CRUD APIs, tests, standard CI/CD, routine bug fixes, git workflows, drafting/research/summarizing, standard media scripting. |
| Opus / Deep reasoning | Destructive multi-file refactors, system/schema architecture, multi-file state management, edge-case bugs, real-time sync algorithms, multi-paper synthesis, high-stakes legal/financial drafting, complex AE/ExtendScript or long-form structural overhauls. |

- **Warn to upgrade** (→ Opus) when: the task needs multi-file structural edits, a destructive directory move that breaks dependencies, deep architectural design, or the user is stuck 2+ failed attempts on the same bug.
- **Warn to downgrade** (→ Haiku/Sonnet) when: the ask is bulk/mechanical (e.g. "rename these 100 files," "reformat this CSV") and a lighter model would be faster and cheaper.

Post this before acting, then wait for "Proceed" or an actual model switch:

> ⚠️ **Model Switching Advisory**
> * **Current Task:** <task>
> * **Current Model:** <current> ➔ **Recommended Model:** <recommended>
> * **Reason:** <one-sentence risk/speed/cost justification>

## Bootstrap facts (exception: kept here because every session needs them)

- Stack: ESP32 / ESP-IDF firmware (C) + Windows PowerShell orchestration + Python analysis (pandas/numpy/matplotlib/seaborn/scipy/scikit-learn).
- ⚠️ **ESP-IDF version is NOT uniform across team laptops** — confirmed both v5.3.5 and v5.5.4 in
  active use (sep. 16, 2026). SDK struct field types can differ by version (e.g. `sdmmc_card_t`'s
  `real_freq_khz`/`max_freq_khz`: `uint32_t` on one install, plain `int` on the other) — a build
  that's clean on one laptop's IDF can hit `-Werror=format=` on another's. Never hardcode a
  `printf` format specifier to match a struct field's assumed type; cast the argument explicitly
  at the call site instead (`(unsigned long)x` + `%lu`) so it's correct regardless of IDF version.
  Same logic applies to any other IDF-version-sensitive assumption, not just this one field.
- Run: `ESP32-Environment\menu.ps1` (one board, ~7 prompts) or `run_wizard.ps1` (multi-board: presets, MAC verify, bulk wipe/set-location). Both call `run.ps1`, which requires `-Location` with `-Export`/`-Clean`/`-Analyze`.
- Test: `python tools\validate_integrity.py`, `verify_topology.py`, `verify_attack.py` (paper-backed 3-sigma).
- Entry point: `ESP32-Environment\docs\2026-09-14_START-HERE.md`.
- Purpose: ESP-WIFI-MESH testbed capturing labeled blackhole/wormhole attack datasets for CTTHES2/3 exploratory analysis. `combined` merges CC's firmware/tooling (SD-card logging, wizard) with NIS16's onboarding redesign and panel-cited attack verification — see [STATUS.md](STATUS.md).
