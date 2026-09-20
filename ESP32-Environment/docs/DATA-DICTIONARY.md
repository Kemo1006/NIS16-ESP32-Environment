# Telemetry data dictionary — what every column actually contains

**Created:** sep. 20, 2026 · **Applies to:** `*_telem.csv`, `*_arrivals.csv`, `windowed_dataset.csv`, `feature_table.csv`

This file exists because three columns in the telemetry schema **mean different things depending on
which board wrote the row**, and the manuscript currently describes them as something they are not.
A reviewer who reads Table 4.5 and then opens a CSV will find a mismatch. Fixing the names costs a
recapture; writing down what they really contain costs nothing and removes the accusation of
misrepresentation. Do the second immediately, the first at the next capture.

> **The single most important line in this file:**
> **No column in this dataset contains an 802.11 MAC-layer retransmission count.**
> `retry_count` is an application-layer counter on every role. The ESP-IDF Wi-Fi statistics API is
> not read anywhere in this firmware — grep for `esp_wifi_get_statistics`, there are no hits.

---

## 1. Telemetry schema v1 (11 columns) — every capture up to and including sep. 18, 2026

Written by `csv_logger_append_telemetry()` (`components/mesh_common/src/csv_logger.c`).

| Column | Type | Meaning (role-independent) |
|---|---|---|
| `timestamp_us` | int64 | `esp_timer_get_time()` — microseconds since **this board's** boot. **Not wall clock, not synchronised between boards.** See §4. |
| `node_id` | string | `NODE_<12-hex STA MAC>` |
| `role` | string | `victim` · `blackhole` · `wormhole_a` · `wormhole_b` · `root` |
| `layer` | int | ESP-WIFI-MESH layer. **Root is layer 1**, per Espressif and per `mesh_setup.c:131`. `-1` = no parent. See §3. |
| `parent_mac` | string | Parent's BSSID; all-zero on the root and when unparented |
| `rssi_dbm` | int | `esp_wifi_sta_get_rssi()` — **this node to its parent, one link only.** See §3. |
| `phase_id` | uint8 | 0 baseline · 1 blackhole · 2 wormhole · 3 cooldown · 4 terminate |
| `gt_label` | uint8 | 0 normal · 1 blackhole · 2 wormhole (cooldown and terminate both map to 0) |

### The three role-dependent columns

| Column | On `victim` | On `blackhole` (attacker) | On `root` | On `wormhole_b` (entry) | On `wormhole_a` (exit) |
|---|---|---|---|---|---|
| `probes_count` | probes this node **originated** (`victim_main.c:165`) | probes **received from victims** for relay (`blackhole_victim.c`) | probes **received** from the mesh | probes **generated** | probes **received from B over the tunnel** |
| `tx_count` | probes accepted by the mesh stack | probes **forwarded to the root** | successful **phase broadcasts** (`root_main.c:421`) | probes sent **direct to root** | probes **re-injected** to root |
| `retry_count` | **failed `esp_mesh_send()` calls** (`victim_main.c:288`) | **probes DROPPED** — the attack's own counter (`blackhole_victim.c`), plus forward failures | failed phase **broadcasts** | probes **tunnelled** to A | **re-injection failures** |

**Consequences you must state in the paper, not hide:**

1. **`retry_count` on the blackhole attacker is the manipulation's own control variable.** It goes
   `0.0033 → 0.9991` across the attack window while victims go `0.0008 → 0.0000`. Any feature
   derived from it (`RetryRate`) is label leakage, not a measurement. `analysis/leakage.py` excludes
   it from model inputs for this reason.
2. **Table 3.4's prediction of increased victim retransmissions is a pre-registered MISS.**
   Victims show **zero** change. Report it as a miss; do **not** edit the table. §3.3.1.2 already
   explains why — the attacker still ACKs every frame at the link layer, so the victims' radios
   never see a failure. A blackhole that drops at the application layer is *invisible* to the
   victim's own telemetry. That is a legitimate and defensible finding.
3. **On victims, `tx_count` equals `probes_count` on every row.** One of the two is redundant.
   "Accepted by the mesh stack" is not "delivered" — ~34 probes per session were counted as sent
   while the board had no parent.

---

## 2. Telemetry schema v2 (14 columns) — F3, from the next capture onward

Adds three counters that mean **the same thing on every role**, appended at the end so that any
positional reader of v1 keeps working:

| Column | Meaning — identical on all roles |
|---|---|
| `recv_count` | frames this node received from another node **for relay** (not frames it originated) |
| `forward_count` | frames this node **passed on** toward their destination |
| `drop_count` | frames this node received for relay and **did not pass on** |

Once v2 exists, `retry_count` reverts to one meaning (send failures) on every role, and
`ForwardingRatio = forward_count / recv_count` becomes computable for any node that relays.

⚠️ **v2 alone does not clear the leakage.** Honest nodes send with `MESH_DATA_TODS`, so the mesh
stack relays *below* the application layer and an honest node still observes `recv_count = 0`.
Getting a populated ForwardingRatio distribution requires **Option 1 of `Plan/THESIS3-MEMBER-HOWTO.md`
§1 C7** — every node explicitly relaying to its parent — which changes the traffic model and
invalidates comparison with earlier runs. That is a design decision, not a code change.

Both schemas are accepted by `tools/validate_integrity.py` (`ACCEPTED_HEADERS`).

---

## 3. Two things the manuscript states that the firmware contradicts

**RSSI does not accumulate across hops.** `esp_wifi_sta_get_rssi()` reports the signal on **one
link**: this node to its parent. A layer-6 node sitting one metre from its parent reads a strong
RSSI. The manuscript's "RSSI drops 5–10 dB per hop" (§3.2.3.1, Tables 3.3/3.7, §4.3.1.4, and the
rationale behind Eq 4.12) is therefore wrong as written, and `RSSI_Hop_Diff` inherits the error.
The defensible version of the claim: *RSSI and hop count are independent measurements, and a
mismatch between them is informative precisely because RSSI is per-link.*

**The root is layer 1, not layer 0.** ESP-WIFI-MESH numbers the root as 1 and the firmware follows
that (`mesh_setup.c:131`, "center(L1)"). §3.1.2, Table 3.1, Table 3.5 and the Fig 4.19 text all say
Layer 0. Every layer number in the manuscript is off by one against the data.

**"Network layer" means the mesh layer, not OSI layer 3.** ESP-WIFI-MESH runs *below* IP — it is a
layer-2 mesh with its own header. `layer` and `parent_mac` describe tree position within that mesh.

---

## 4. Clocks

`timestamp_us` is per-board uptime. **Board clocks are never synchronised** (`thesis-deviate.md`
D-2). The manuscript's claim that clocks are aligned using the root's phase log is not what the
code does. Cross-node alignment uses each node's **own first exit from phase 0** as the anchor
(`preprocess.assign_segments()`) — the only clock-free event every node observes. Anything derived
from raw cross-board timestamp differences is dominated by boot-time offset, not by network delay;
this is why `LatencyHopRatio` is a *relative one-way* measure (D-2), not RTT.

---

## 5. Derived columns added host-side

| Column | Added by | Meaning |
|---|---|---|
| `segment` | `preprocess.assign_segments()` | `pre_baseline` · `baseline` · `attack` · `cooldown`. **`pre_baseline` rows are excluded from the labelled dataset** (`window_label = NaN`) — they are the window between a node booting and the root's first phase broadcast, which v1 firmware records as an ordinary phase 0. Rows are kept, never deleted. |
| `t_anchor_s` | `preprocess.assign_segments()` | seconds relative to this node's own phase-0 exit |
| `window_label` | `preprocess` | ground truth for the window; `NaN` outside the three real phases |
| `rssi_dbm` (windowed) | `preprocess` | **`rssi_dbm == 0` is blanked to NaN** — it is the firmware's "no parent link" placeholder, not a reading (6,446 rows in the sep. 18 G402 capture) |

---

## 6. Where this is enforced in code

| Concern | File |
|---|---|
| Which columns a model may see, and why not the rest | `analysis/leakage.py` |
| Segment assignment, placeholder blanking | `analysis/preprocess.py` |
| Both accepted telemetry schemas | `tools/validate_integrity.py` (`ACCEPTED_HEADERS`) |
| Paper-backed 3-sigma attack verification | `tools/verify_attack.py` |
| Gate ordering (integrity → topology → attack) | `analyze.ps1` (`Invoke-Validate`) |
