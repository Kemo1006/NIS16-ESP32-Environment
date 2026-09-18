---
name: dataset-audit-2026-09-18
description: sep. 18, 2026 audit of the G402 linear captures - folders mix runs, rssi 0 = not measured, phase 0 includes pre-baseline; new tools/audit_dataset.py groups runs by seq, not clock
metadata:
  type: project
---

Full write-up: `docs/DATASET-AUDIT-2026-09-18.md`. Tool: `tools/audit_dataset.py`
(read-only; outputs in `analysis/dataset_audit_2026-09-18/`, clean_telemetry.csv is
57 MB - not gitignored, think before `git add`).

**What was wrong (sep. 17 archive + sep. 18 Recycle-Bin copies, 40 files):**
- The G402 folders mixed **6 runs**, all named `r1`; 0C80 had 5 files. Only
  `linear_blackhole_20260918_111347` (root + 0C80/2805/704B + attacker 1C38) is complete.
- Sep. 17 12:4x: victims 2805/704B/FE90 delivered **0** probes even in baseline
  (attacker got exactly 2 victims' worth) - most likely stale BLACKHOLE_ATTACKER_MAC.
- `phase_id 0` = baseline + stabilise + "no broadcast heard yet": 178/1569 label-0
  windows (11%) in the committed G402 feature table were pre-baseline.
- `rssi_dbm 0` = no parent link (root / unjoined), never a reading: 692/2471
  RSSI_Hop_Diff values were an exact fake 0.

**How runs are proven without a clock:** victim `probes+retry` at its phase-0 exit ==
root's last baseline `seq_num` (+-2) and final == root max; root telem<->arrivals by
last counter. Attacker counts are design-driven (victims x 120 s) so only "weak".
Phase anchor (own first phase-0 exit) validated: roots exit at 363-366 s; per-segment
probes 300/180/120 match mesh_config.h.

**Open (user to decide):** C6 pipeline fix (no re-capture) vs C5 firmware
PHASE_ID_UNSET/empty RSSI (schema change + re-capture); C1-C4 import/provenance fixes.
Related: [[pdr-seq-join-fix-2026-09]], [[latency-features-recovered]].
