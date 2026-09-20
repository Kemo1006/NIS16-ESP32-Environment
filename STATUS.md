# Status

<!-- Overwrite each session. Hard cap: 40 lines — move "done" items to ARCHIVE.md. First thing a new session reads. -->

**Updated:** sep. 20, 2026 — **F1 + F2 + F3 + P5 APPLIED, ALL SIX FIRMWARE VARIANTS BUILD CLEAN under `-Wall -Wextra -Werror` (ESP-IDF 5.5.4).** Telemetry is now **schema v2 (14 cols)**: v1's 11 unchanged and in place, plus `recv_count,forward_count,drop_count`. `retry_count` means ONE thing on every role again. **UNCOMMITTED** (together with the sep. 20 P1/P2/P3 analysis fixes). Audit report Rev 2: https://claude.ai/artifact/RGB3RTXvfK7yzK9erEFNzE

## Current focus
Every host-side and firmware fix that does not need a design decision is now in. What remains is (a) ONE decision — C7 Option 1 — and (b) capture: only one experimental cell has data and zero wormhole runs exist.

## Next step
1. **Commit** the whole sep. 20 batch (P1/P2/P3 + F1/F2/F3/P5). Nothing is committed yet.
2. ⛔ **DECIDE C7 Option 1** (`Plan/THESIS3-MEMBER-HOWTO.md` §1 C7) — the one blocker left, adviser-facing. F3 removed the `retry_count` OVERLOAD but honest nodes still report `recv=0/forward=0/drop=0`, because they send `MESH_DATA_TODS` and the mesh stack relays below the app layer — so `ForwardingRatio` is still defined only on the attacker. Making every node relay to its parent explicitly fixes that AND makes attacker position genuinely topological, but it changes the traffic model and makes the sep. 18 capture non-comparable. **That cost is near zero right now** (1 cell, which needs re-capture anyway) and rises with every run captured. Decide BEFORE the campaign, not after.
3. **Re-flash every board** — schema v2, F1 and F2 all need it. Then re-capture G402 as the first v2 run.
4. **Then the campaign** — 38-run matrix, §14 of the report. **Block G first** (high-legitimate-load benign vs high-load-under-attack): cheapest direct answer to "benign and malicious scenarios are identical".
5. Carried: commit the build-dir self-heal + presets-upload work; prove data sync laptop-to-laptop; reflash + hardware-test `DELETE_SD_PATH`.

## Blockers / open questions
- ⚠️⚠️ **ROOT POWER — verify before EVERY capture.** Direct laptop USB port, never a shared hub; known-good short cable. F1 now makes a root-joined-late run *self-identifying* in the data instead of silently poisoning the baseline, and `analyze.ps1 -Verify` gates on it — but it still ruins the run. Prevention is still manual.
- ⚠️ **PDR alone scores 0.9987 vs a 0.7031 majority baseline** (new, measured by `leakage.py` this session). Excluding leaking features does NOT fix this: a **100% drop rate in a fixed 180 s window is separable by construction**. Only attack-parameter variation fixes it — which collides with scope conflict R-B (§1.4.1 excludes grayhole/selective forwarding, and a partial drop rate IS selective forwarding). **Adviser decides.** Safest reading stays: the panel asked for different attacker POSITIONS, not different drop rates.
- ⚠️ **Only ONE experimental cell has data**, `tools/exports/run_ledger.csv` is header-only, zero wormhole captures exist ⇒ Table 3.5 entirely unvalidated. M4 needs ≥24 runs; CTTHES3 wants ≥5 repeats per combination.
- ⚠️ **Attacker placement is not topological** — layer 7 of an 8-node chain, 5 of 6 victims UPSTREAM. F2 makes moving it cheap (no re-flash); C7 Option 1 would make position actually *mean* something.
- **Two unreconciled panel tracks:** `Plan/THESIS3-PANEL-PLAN.md` (aug. 06) vs `ESP32-Environment/memory/panel-change-2026-09.md` (sep. 13).
- **Scope amendments R-A / R-B still unwritten** — §1.4.1's "controlled indoor environment" contradicts the DLSU-campus decision.
- **SD-card picker shows only `C:\`/`S:\`, no `D:\`** — not a script bug; waiting on the user re File Explorer.
- **Angelo Calpoporo's bootloader build fails** on Windows `MAX_PATH` — needs an admin answer (`LongPathsEnabled` vs an `$env:ESP32_BUILD_ROOT` override). ⚠️ Note: the sep. 20 builds on this machine SUCCEEDED with short `-B` names (`bh1`,`bv1`,`wa1`,`wb1`,`rb1`,`rn1`) — short build-dir names are the working mitigation.
- `mesh_config.h` `BLACKHOLE_ATTACKER_MAC` → `20:50:0d:e7:1c:38`; still the compiled fallback, now overridable at runtime (F2).

## Recently done (last 3 max, newest first — older entries roll to ARCHIVE.md)
- sep. 20, 2026 — **F1/F2/F3/P5 applied + verified.** F1 `PHASE_ID_UNSET`; F2 runtime attacker MAC (NVS + 3 serial cmds + 3 `export_logs.py` flags); F3 schema v2 relay counters, de-overloading `retry_count`; P5 `analysis/leakage.py` + `eda.py` wiring; 3 gates in `analyze.ps1`; `member_boards.json` child_8/child_10 swap corrected; `docs/DATA-DICTIONARY.md` written. **Verified:** v1 `windowed_dataset.csv` + `feature_table.csv` byte-identical (no regression); 20/20 `test_segments.py`; synthetic v2 capture end-to-end → attacker FR 1.0/0.0/1.0, root and victims correctly NaN, BLACKHOLE CONFIRMED; 6/6 firmware builds clean.
- sep. 20, 2026 — **APPLIED P1/P2/P3.** P1 `preprocess.assign_segments()`; P2 `features.py` WINDOW_SECONDS import; P3 `verify_attack.py` INFEASIBLE/dispersion-ceiling/ratio-of-sums. `verify_attack.py` → BLACKHOLE CONFIRMED, exit 0.
- sep. 20, 2026 — **Full-pipeline audit + independent re-verification**: root cause of the blackhole FAIL, the `WINDOW_SECONDS` bug, measured leakage numbers.
