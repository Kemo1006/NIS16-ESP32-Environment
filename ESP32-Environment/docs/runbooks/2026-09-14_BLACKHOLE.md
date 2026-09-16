# Runbook: BLACKHOLE attack run - v2026-09-14

> One **attacker** board relays victim probes; during the attack window it **silently drops**
> them so they never reach the root. Ground-truth: `0 -> 1 -> 0`. Hub: `docs/2026-09-14_START-HERE.md`.
> Placement per topology: `docs/runbooks/2026-09-14_TOPOLOGIES.md`.
> **Paper basis:** drop-after-attract + forwarding-ratio/PDR collapse - Airehrour et al. 2018 (`memory/thesis-citations.md`).

## Boards needed
| Role | Build (menu picks this for you) | Count |
|---|---|---|
| Root | `root_node/`, attack=blackhole (announces the phase) | 1 |
| Attacker (relay) | `child_node/`, attack=blackhole, role=**attacker** | 1 |
| Victim (targets attacker) | `child_node/`, attack=blackhole, role=**victim** | 1 or more |

**Minimum 3 boards** (root + attacker + 1 victim). More victims = stronger signature.
No cables between boards (blackhole is wireless-only).

## !! BEFORE you build: set the attacker's MAC (one time, or whenever the attacker board changes)
Victims must address their probes to the attacker's MAC. If you skip this, nothing reaches the
attacker and there's **no signature**.
1. Plug in the board you'll use as the attacker and read its MAC:
   ```powershell
   .\menu.ps1   # -> "Identify a board"   (or: .\tools\Get-EspMac.ps1 -Port COM<attacker>)
   ```
   You get an array like `{0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}`.
2. Open `components\mesh_common\include\mesh_config.h`, find `BLACKHOLE_ATTACKER_MAC`, paste it:
   ```c
   #define BLACKHOLE_ATTACKER_MAC   {0xF4, 0x2D, 0xC9, 0x73, 0xE6, 0x18}
   ```
3. Save. (The attacker also prints its MAC at boot - use it to double-check.) Because this edits
   `mesh_common`, the first flash below rebuilds it.

## Timeline (fixed in firmware)
| Phase | Duration | Label | What happens |
|---|---|---|---|
| Stabilize | 60 s | (not logged) | mesh forms |
| Baseline | 300 s | `0` | victims -> attacker -> root (normal relay) |
| **Blackhole** | 180 s | **`1`** | attacker **drops** the victims' probes |
| Cooldown | 120 s | `0` | attacker forwards again |
| Terminate | instant | - | ready to export |

**Total ~11 minutes** from when the root finishes flashing.

---

## Step 1 - Flash the ATTACKER (relay) first
**Connection: [USB] attacker board.**
```powershell
.\menu.ps1
#  -> Run a board -> attacker COM -> role: child -> topology: <t>
#     -> attack: blackhole -> blackhole role: attacker -> Flash yes, Wipe yes, Export yes
```
Watch for:
```
=== BLACKHOLE ATTACKER (relay) STARTING ===
This is the blackhole ATTACKER. Set BLACKHOLE_ATTACKER_MAC ... to my STA MAC: XX:XX:...
Relay task running.
```
Confirm the printed MAC matches `mesh_config.h`. Press **Ctrl+]**.

## Step 2 - Flash the VICTIM board(s)
**Connection: [USB] victim board.**
```powershell
.\menu.ps1
#  -> Run a board -> victim COM -> role: child -> topology: <t>
#     -> attack: blackhole -> blackhole role: victim -> Flash yes, Wipe yes, Export yes
```
Watch for:
```
=== VICTIM NODE STARTING ===
Blackhole victim mode: probes -> attacker XX:XX:...
```
The `-> attacker` line confirms it's targeting the attacker MAC. Press **Ctrl+]**. Repeat per victim.

## Step 3 - Flash the ROOT LAST (with analysis)
**Connection: [USB] root board.**
```powershell
.\menu.ps1
#  -> Run a board -> root COM -> role: root -> topology: <same t>
#     -> attack: blackhole -> Flash yes, Wipe yes, Export yes -> Analyze YES
```
The root just **announces** the blackhole phase; it never drops anything. Press **Ctrl+]**.

> **Order:** attacker + victims first, root LAST, so all boards join the mesh before baseline
> starts. All boards run independently once powered; the root's broadcasts sync the labels.

## Step 4 - Place boards + wait ~11 min
**Connection: [PWR] power only.** Attacker placement matters per topology (it should be the
parent/relay the victims route through) - see TOPOLOGIES runbook. On the attacker's console
you'll see `BLACKHOLE: dropped victim probe seq=...` start exactly at the attack phase and stop
at cooldown. Don't touch the boards during the run.

---

## Step 5 - EXPORT

### Way A - over USB
Handled if you chose Export. Manual/later, one board at a time:
```powershell
.\menu.ps1   # -> "Export a board only" -> COM/role/topology, attack: blackhole
# equivalent: python tools\export_logs.py --port COM<x> --role <root|child> --topology <t> --location <loc> --attack blackhole --repeat <n>
```

### Way B - by SD card
After the run: power off -> pop each microSD into your laptop's reader ->
`python tools\import_sdcard.py --card E:\ --repeat <n>` -> re-insert. No board plugged in.
Setup: `docs/2026-09-14_SD-CARD.md`.

---

## Step 6 - Verify the SIGNATURE (this is the important part)
Files land in `tools\exports\blackhole\<topology>\<location>\`. Confirm the blackhole is real:
- **Root `arrivals.csv`:** for each victim `src_mac`, arrivals are present during `gt_label=0`
  rows and **absent (a gap) during `gt_label=1`**, resuming at cooldown. **That gap is the signature.**
- **Attacker `telem.csv`:** `tx_count` (forwarded) climbs during baseline/cooldown and **goes
  flat during label 1**, while `retry_count` (dropped) **climbs during label 1**. `probes_count`
  (received from victims) climbs throughout.
- **Victim `telem.csv`:** `probes_count` climbs the whole run (it keeps sending, unaware).
- **Paper-backed check (3-sigma):** forwarding ratio and PDR during label-1 windows fall
  >3 sigma below the baseline-phase mean. This is the citable verification (Zhukabayeva 2025
  method; Airehrour 2018 signature). Run it:
  `python tools\verify_attack.py analysis\blackhole\<topology>\<location>\feature_table.csv`
- Automated: `python tools\validate_integrity.py`, `python tools\verify_topology.py`,
  `python tools\verify_attack.py` (above).

## Field log (vary each repeat)
```
Date ____  Location ______  Topology ______  Attack: blackhole  Repeat r__
Attacker board+node: ______  Attacker PHYSICAL position (change per repeat!): ______
Victim boards+nodes: ______  Start time: ______  Notes: ______
```

## Connection-state quick reference
| Step | Laptop |
|---|---|
| Set MAC / identify | [USB] attacker |
| 1-3 flash | [USB] one at a time |
| 4 run (~11 min) | [PWR] power only |
| 5 export USB | [USB] one at a time |
| 5 export SD | none - card into laptop |
