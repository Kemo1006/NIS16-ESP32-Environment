# Verification — microSD limits + partial-mesh plain-tree claim (oct. 20, 2026)

**Source checked:** `Plan/Paper-Editing/1-Working-Copy/All_in_one_CTHESIS3_no_jitter_8boards v2 (code and data recheck, oct. 20, 2026).docx`,
limitations paragraph (starts "Several limitations are acknowledged…").

**Evidence base:** firmware in `ESP32-Environment/components/mesh_common`, `thesis-deviate.md` D-13,
`dataset-verification.md` #38/#71, and fresh runs of `verify_topology.py`, `attack_checks.topology_issues()`
and a raw-CSV parent scan on the 9 blackhole partial_mesh cells (G402 / DLSU_Library / Yuchengco ×
stationary / burst / highload) in `datasets/exports` and `datasets/analysis`.

## Verdicts

| # | Claim | Verdict |
|---|---|---|
| 1 | The fsync change (D-13) compiles but is not yet validated on hardware | ✅ CONFIRMED |
| 2 | Card clock capped at 4 MHz because jumper wires cannot carry the default speed | ✅ CONFIRMED |
| 3 | Pre-fsync captures that ended badly may have a 0-row card file, treated as lost, not empty (Section 4.2.7.5) | 🔶 PARTIALLY CONFIRMED — fact true, cross-reference wrong |
| 4 | In the nine partial-mesh captures analysed so far, no node was seen under a second parent | 🔶 PARTIALLY CONFIRMED — true for the labelled phases, not for the whole capture |

## 1 — fsync not hardware-validated
- Code: `csv_logger.c:1174-1184` `sd_mirror_sync()` = `fflush()` + `fsync(fileno(fp))`.
- `thesis-deviate.md:288` (D-13 Status): "Firmware compiles clean; NOT yet validated on hardware — it needs a
  board, a mid-run reset, and a card read back."
- Nothing in STATUS.md / MEMORY.md records that mid-run-reset test. The 0-of-435 zero-row result
  (verification #71) is supporting field evidence, but it is not that deliberate test.

## 2 — 4 MHz clock
- `mesh_config.h:727-729`: `#define SD_MAX_FREQ_KHZ 4000`, comment "Jumper wires can't reliably carry the
  ~20 MHz SDSPI default — higher than this reproducibly gives ESP_ERR_INVALID_CRC on the lab rig."
- Used at `sd_status.c:692` and `:916`. ARCHIVE.md sep. 12, 2026 records the bring-up fix.

## 3 — 0-row pre-fix files are "lost"
- `thesis-deviate.md:286`: "a pre-fix card file reading 0 rows should be treated as **lost**, not as 'the node
  logged nothing'". So the fact is right.
- **Cross-reference is wrong.** Paper §4.2.7.5 ("Limits") covers only wormhole conformance, plain-tree partial
  mesh, clustering metrics and the attack start time. The 0-row / fsync text is in **§4.2.3.6.3 Data Integrity
  During Manipulation**. That section says a bad ending "could leave a card file with 0 rows" but does
  **not** say such runs are treated as lost. Fix either the reference (→ 4.2.3.6.3) or add the "lost, not
  empty" sentence there.

## 4 — Partial mesh = plain trees
- Count: 9 = 3 sites × 3 non-jitter scenarios of blackhole/partial_mesh (the 2 jitter cells make the 11 in
  verification #38; wormhole partial cells are not analysed). "Nine" is right for this no-jitter paper.
- `attack_checks.topology_issues()` (judges baseline + attack + cooldown): **all 9 →** "8 nodes, each seen
  under only one parent so far - still a plain tree".
- `verify_topology.py --expect partial` (judges the **whole** raw capture): **4 of 9 show 2+ parents** —
  G402/burst (4 nodes), DLSU_Library/highload (6), Yuchengco/stationary (3), Yuchengco/highload (4).
- Raw-CSV scan places those switches in **phase 255 (formation)**; in Yuchengco/stationary they fall in an
  earlier aborted start (phase 0 at ~48-114 s, then back to 255) before the real 300/180/120 s run. In
  every run's actual baseline → attack → cooldown, each node has one parent.
- Implication: the sentence holds because formation is label 255 and excluded from analysis, but as written
  ("no node was seen under a second parent") it reads as absolute. A reviewer who runs
  `verify_topology.py` will see "4 node(s) seen under 2+ parents". Suggested wording: "…no node was seen
  under a second parent during the labelled phases (baseline, attack, cooldown); parent changes occurred
  only during mesh formation…"

## Not touched
Read-only check; no paper or code changes were made as part of this verification.
