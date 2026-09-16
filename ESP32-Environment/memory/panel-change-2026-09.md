---
name: panel-change-2026-09
description: The major CTTHES panel-mandated redesign (Sept 2026) — dataset variance, realistic scenario, cited verification, SD card, tooling, new schedule; all old runs to be redone/archived
metadata:
  type: project
---

**The panel (Peradilla/Solomon/Tiu) ordered a dataset redesign.** All prior runs are being **redone from scratch and archived** (user, 2026-09-13). This supersedes the old 16/24 matrix in [[project-state-and-instructions]].

**Why:** the panel found the dataset too weak to justify clustering/ML.

## Panel comments → required fixes
1. **No single-feature determinism** (invalidates clustering): if one of the 16 features explicitly = attack (1/0), the other 15 are irrelevant and ML is pointless. → Audit per-feature separability; drop/exclude trivially-leaking features (esp. auxiliary tunnel features — proposal already permits excluding them) from clustering input.
2. **Add controlled variance across runs** (2:40, 5:15, 12:45): r1..r3 are identical hardcoded scripts → redundant data. Vary attacker position per run, randomize probe interval/jitter, log per-run seed in metadata. **IN PROGRESS sep. 16, 2026:** run scenarios v1 (`none|burst|highload|mobility|powercycle`) built in both front-ends — see [[run-scenarios-2026-09]]. Covers traffic-shape variance (burst/highload) and human-behaviour variance (mobility/powercycle); attacker-position variance and probe jitter are NOT yet covered — still open.
3. **Balance the dataset** across topologies/runs; make topology effect actually visible.
4. **Define a realistic IoT scenario** (9:10, 12:45): pick smart-agriculture vs smart-home etc., cite deployment/topology papers, specify traffic model (constant vs bursty). Deployment currently looks random.
5. **Multiple locations** (8:40): not just house — public places. → new schedule below (Home, G402, DLSU Library, Goks) also captures Wi-Fi-interference variation.
6. **Paper-backed attack verification** (17:50, 44:30): must prove attacks are correct/valid against **published literature** — cannot use our own unproven verification. Find a study that used verification methods; map each attack to a cited basis.
7. **Benign baseline variation** (44:30): characterize normal traffic under varied load; distinguish high-but-legitimate utilization from malicious flooding by behavior, not volume. **IN PROGRESS sep. 16, 2026:** `-Scenario highload` gives a high-legitimate-load benign class (4x probe rate, whole run); `-Scenario burst` gives a matched legit-burst-vs-attack-burst pair for the same purpose — see [[run-scenarios-2026-09]].
8. **Shorter runs, more variations** (48:00): don't need full-hour runs; smaller intervals × more variations = wider range of test cases.

## User infra asks (2026-09-13)
- **SD card logging** on the ESP32s for faster export — update firmware + tooling to use it.
- **Verification via a cited paper** (see #6) — not our own tool.
- **Easy menu-driven tooling** for flash / export / config — choose A/B/C instead of long commands.
- **Redo all runs; archive everything** (existing captures + derived tables/EDA).
- Standing rule: **always update MEMORY.md, super-detailed, every edit.**

## New field schedule (6 runs/scenario = 3 wormhole + 3 blackhole; Mon=Tree, Wed=Linear, Thu=Partial, Fri=Star)
- Home — 6 runs.
- Sept 14–18 — Room G402 — 6 runs (Mon Tree Kyle,Basti · Wed Linear Kyle,Basti · Thu Partial Angelo,Kyle,Basti · Fri Star Angelo,Kyle,Basti).
- Sept 21–25 (19–23 no Kyle) — DLSU Library — 6 runs.
- Sept 28–Oct 2 — Goks Ground Floor — 6 runs.
- Confirm: "6 runs" per location total or per topology-day (→24/location)?

## Blocking decisions (asked user 2026-09-13)
scenario choice · SD hardware readiness · firmware-change timing vs Sept 14 first run · exact archive scope.
