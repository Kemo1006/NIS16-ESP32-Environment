# NIS16 Setup · Rules · Config — v2026-09-14 (NEW / CURRENT)

> Supersedes the old `BASELINE-SETUP.md`, `BLACKHOLE-SETUP.md`, `WORMHOLE-SETUP.md`, `BOARD-CHECK.md`, `ATTACKS-Commands.md` (archived under `_archive/20260913_pre-redesign/docs/`). Field steps are in `docs/2026-09-14_RUNBOOK.md`.

---

## PART A — SETUP

### A1. Environment
- Run from the **"ESP-IDF 5.3 PowerShell"** window (`idf.py`, `python`, `pyserial` on PATH), at the repo root.
- Analysis deps once: `pip install -r analysis\requirements.txt` (pandas/numpy for M6+M7; matplotlib/seaborn/scipy/scikit-learn for M8/EDA).

### A2. Two firmware projects
- `root_node\`  → the **root** (phase controller + probe sink + `arrivals.csv`).
- `child_node\` → every **non-root** board (victims + attackers; role/attack set by build flags).
- Shared code in `components\mesh_common\` (mesh setup, phase listener, CSV logger).

### A3. Identify boards (do at each location)
COM = USB socket, not board. Identify by MAC: `.\menu.ps1` → *Identify a board* (or `python tools\board_check.py --port COMxx`). Record board→node→MAC.

### A4. SD-card logging — IMPLEMENTED
CSVs mirror to a microSD over SPI alongside internal SPIFFS → bigger storage + fast export
(pop the card, no slow per-node serial pull). Wiring: `CS→GPIO5, SCK→GPIO18, MOSI→GPIO23,
MISO→GPIO19, VCC→VIN/5V (not 3V3), GND→GND` — see `docs/2026-09-14_SD-CARD.md` and
`../../Setups/SD-CARD-WIRING.md` for the two gotchas that aren't obvious from the pin table.
Export with `python tools\import_sdcard.py --card E:\ --repeat N`.

---

## PART B — RULES (what the panel + papers require of every run/dataset)

1. **No single feature may decide "attack."** If one of the 16 features is a giveaway (e.g. tunnel counters = attack on/off), clustering is invalid. → Exclude the 3 auxiliary **tunnel** features from the clustering input; audit per-feature separability (AUC / mutual-info) before clustering.
2. **Controlled variance across repeats.** Vary attacker position + run time + location; log them. Identical r1..r3 is not accepted.
3. **Balance the dataset** across topologies/attacks/locations (stratified sampling — REAL-IoT, Zhan et al. 2025) so topology/scenario effects are visible.
4. **Realistic scenario, cited.** Indoor **school + home environmental-monitoring** mesh, periodic sensor traffic — basis: **Khan et al. 2022** (ESP-MESH indoor/outdoor). Not "random deployment."
5. **Paper-backed attack verification (not our own tool).** Verify each run with a **3-sigma normal-vs-attack** test (Zhukabayeva et al. 2025); expected signatures: blackhole → forwarding-ratio/PDR collapse (Airehrour et al. 2018); wormhole → duplicate arrivals + hop↓/latency-mismatch (Zhukabayeva 2025; duplicate-packet signature: Ramírez 2019).
6. **Benign-load variation.** Include benign runs at low/normal/high legitimate load so "high legit traffic" ≠ "malicious flood" (behavioral, not volume-based). *(needs firmware — week-1 bench.)*
7. **Metadata on every run:** `location, topology, attack, repeat, attacker_position, run_seed, start_time, board→node map`.
8. Full citation set + roles: `memory/thesis-citations.md`. Framing = behavioral/observable equivalence (papers are ZigBee/RPL, not ESP-MESH; pair with Espressif docs + Khan).

---

## PART C — CONFIG REFERENCE

### C1. `run.ps1` parameters (what the menu sets for you)
| Param | Values | Meaning |
|---|---|---|
| `-Port` | e.g. `COM8` | USB socket of the board |
| `-Role` | `root` \| `child` (`victim` alias) | mesh position (root_node vs child_node project) |
| `-Topology` | `tree`(default) \| `star` \| `linear` \| `partial` | build shaping; flash all boards the SAME |
| `-Attack` | `none` \| `blackhole` \| `wormhole` | attack build |
| `-BlackholeRole` | `attacker` \| `victim` | (blackhole, child only) |
| `-WormholeEnd` | `A`(exit/root-side) \| `B`(entry/leaf-side) | (wormhole, child only) |
| `-Label` | e.g. `node5` | goes in the CSV filename; identifies the board |
| `-Flash` | switch | (re)flash before monitor — needed to apply topology/attack |
| `-Wipe` | switch | before run: with `-Flash` = full chip erase (fixes 'storage full'); without = serial DELETE_LOGS |
| `-Export` | switch | pull CSVs on monitor exit (Ctrl+]) |
| `-Clean` | switch | wipe board AFTER a good export |
| `-Analyze` | switch | run M6+M7+M8 after export (use on ROOT, exported last) |
| `-DestAttack` | `none`\|`blackhole`\|`wormhole` | file a control victim's CSV under an attack folder |
| `-Repeat` | int | r-number → export filename |

### C2. Build-flag mapping (set automatically from the flags above)
- `MESH_TOPOLOGY`: star=0, tree=1, linear=2, partial=3.
- `ACTIVE_ATTACK`: none=255, blackhole=1, wormhole=2.
- `BLACKHOLE_ROLE`: attacker=0, victim=1. `WORMHOLE_END`: A=0 (exit), B=1 (entry).
- Each variant builds in its own `build_<role>_<attack>_<topology>[_end/role]_<PORT>\` dir (parallel-flash safe; ccache shares objects via `CCACHE_BASEDIR`). These dirs live at `%LOCALAPPDATA%\esp32_builds\<repo-tag>\`, NOT under this OneDrive-synced repo — safe to delete anytime for a full clean rebuild.

### C3. Wormhole tunnel wiring (UART cable, required)
Node A `GPIO17(TX)` → Node B `GPIO16(RX)` · Node A `GPIO16(RX)` → Node B `GPIO17(TX)` · **shared GND**. Wire BEFORE power-on. (No MAC to set — the old `WORMHOLE_NODE_A_MAC` is obsolete.)

### C4. Data layout
`tools\exports\<attack>\<topology>\<location>\{raw, trimmed}\`  →  `analysis\<attack>\<topology>\<location>\{windowed_dataset.csv, feature_table.csv, eda_output\}`.
Topology folder names: `star`, `tree`, `linear`, `partial_mesh`. Location: `home`, `G402`, `DLSU_Library`, `Goks`.

### C5. Verify tools
`tools\validate_integrity.py` (schema/phases/coverage/labels) · `tools\verify_topology.py` (parent/layer structure) · `tools\board_check.py` (MAC/node id) · `tools\verify_attack.py` (paper-backed 3-sigma attack signature).

### C6. Pending config
- ~~SD-card logging build flag~~ — **implemented** (see `docs/2026-09-14_SD-CARD.md`).
- Attack-variance knobs: randomized probe interval/jitter + configurable attacker position + `run_seed` in metadata.
- Benign-load levels (low/normal/high).
