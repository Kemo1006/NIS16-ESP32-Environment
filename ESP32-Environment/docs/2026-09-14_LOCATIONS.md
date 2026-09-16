# Runbook: LOCATIONS & SCENARIO - v2026-09-14

> We run the same experiments across **several real indoor sites** on purpose: different Wi-Fi
> interference at each location is **natural, defensible variance** (a panel requirement) and fits
> our scenario. Hub: `docs/2026-09-14_START-HERE.md`.

## The scenario (say this to the panel)
An **indoor environmental / ambient-monitoring mesh** deployed across two realistic indoor
settings - a **university building** (rooms, library, common areas) and a **residence** (home) -
with periodic sensor-style traffic (our fixed-interval probes). **Proven basis:** Khan et al.
(2022) deployed ESP-MESH ESP32 nodes for indoor/outdoor monitoring across a campus, PDR >97%. Full
citation + role: `memory/thesis-citations.md`. This is why our topologies and locations are
*chosen*, not random.

## The schedule (6 runs/site = 3 wormhole + 3 blackhole; Mon=Tree, Wed=Linear, Thu=Partial, Fri=Star)
| Dates | Site | Team | Firmware |
|---|---|---|---|
| **Sept 14-18** | **Room G402** | Mon Tree (Kyle,Basti) - Wed Linear (Kyle,Basti) - Thu Partial (Angelo,Kyle,Basti) - Fri Star (Angelo,Kyle,Basti) | current (frozen) |
| Sept 21-25 (19-23, no Kyle) | DLSU Library | - | new (variance + SD) |
| Sept 28-Oct 2 | Goks Ground Floor | - | new |
| - | Home | - | - |
> **Confirm with the team:** is "6 runs" per site *total*, or per topology-day (-> 24/site)? That
> decides how many repeats (r1/r2/r3) you shoot each day.

## What to do at EVERY location (checklist)
1. Pick the room/area; note walls, metal, crowds (they attenuate/interfere - that's fine, log it).
2. Power: bring **USB power banks / wall chargers** so boards run without the laptop after flashing.
3. **Identify boards** (`.\menu.ps1` -> Identify) and write board->node->MAC on the field log.
4. Place boards per the **TOPOLOGIES** runbook for that day's topology; space ~3-5 m.
5. Run **baseline first** (sanity), then the day's attack runs (3 wormhole + 3 blackhole), each a
   different repeat (move the attacker / change time - see variance rule).
6. Export (USB, or pull the SD card and `import_sdcard.py` — see `2026-09-14_SD-CARD.md`)
   and `validate_integrity.py` before leaving.
7. Record on the field log: site, room, topology, attack, repeat, attacker position, start time,
   interference notes, board->node map.

## Per-site notes

### Room G402 (Sept 14-18) - controlled classroom
- Quietest RF environment of the four; good for the first clean runs. Close the door to reduce
  hallway Wi-Fi bleed.
- Good place to confirm each topology forms correctly (`verify_topology.py`) before the busier sites.
- Firmware is **frozen** here - get variance from attacker repositioning + time-of-day (see below).

### DLSU Library (Sept 21-25; 19-23 no Kyle) - busy, lots of Wi-Fi
- Heavy co-channel interference from campus Wi-Fi and phones = realistic "noisy" data. Expect more
  RSSI variance and occasional re-parenting; that's real behavior, log it.
- Be considerate: keep boards on a table, cables tidy, don't block walkways. This is the week the
  new SD + variance firmware should be in use.

### Goks Ground Floor (Sept 28-Oct 2) - open common area
- Open space + foot traffic; more multipath and moving obstacles. Expect the most environmental
  variation - good for showing the dataset isn't location-invariant.
- Secure boards/power so people don't bump them mid-run (a bump breaks the log).

### Home - residential
- The "residence" half of the scenario. Different construction (walls, appliances) than campus.
- Easiest place to do careful repeats and re-shoots. Good for any topology that misbehaved elsewhere.

## Time-of-day = free variance
Running the same cell in the **morning vs afternoon** at a site gives different interference, which
is legitimate cross-run variation. If you must do r1/r2/r3 back-to-back, at least **move the
attacker** each time (TOPOLOGIES runbook). Never ship three identical repeats.

## Etiquette / safety
- Isolated testbed only - our mesh is its own Wi-Fi, not attacking any real network. (Say so if asked.)
- No connection to campus/production networks; all data is our own telemetry (no personal data).
- Keep power banks and cables tidy; don't leave boards unattended in public areas.

## What each location contributes to the dataset
Same topologies + attacks, different RF environment -> the `location` metadata column lets us show
the attack signatures **hold across environments** (and lets analysis stratify by site). That
cross-site robustness is part of what the panel asked for. Record `location` on every run.

> **sep. 15, 2026 fix:** `analysis/combine_all.py` (the M8 cross-run aggregator) globbed a
> fixed `<attack>/<topology>/feature_table.csv` depth from before locations existed, so any
> run captured under a `<location>` subfolder was silently missing from `combined_all.csv` —
> only pre-location legacy runs were ever included. It now walks recursively and adds a
> `location` column (`unrecorded` for those legacy runs, matching `run_ledger.csv`'s own
> backfill convention), so cross-site comparisons in the combined dataset are actually
> possible now. Individual per-run M6/M7/M8 (`preprocess.py`/`features.py`/`eda.py`) were
> never affected — `run.ps1` always pointed them at one fully-resolved location folder.
