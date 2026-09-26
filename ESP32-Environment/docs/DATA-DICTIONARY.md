# Telemetry data dictionary — what every column actually contains

**Created:** sep. 20, 2026 · **Updated:** sep. 25, 2026 (§2 rewritten for post-C7 firmware; see `issue_logs/thesis-deviate.md` D-12, D-15) · **Applies to:** `*_telem.csv`, `*_arrivals.csv`, `windowed_dataset.csv`, `feature_table.csv`

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
   it from model inputs on such (pre-F3, v1) captures.
2. **Table 3.4's prediction of increased victim retransmissions is a pre-registered MISS.**
   Victims show **zero** change. Report it as a miss; do **not** edit the table. §3.3.1.2 already
   explains why — the attacker still ACKs every frame at the link layer, so the victims' radios
   never see a failure. A blackhole that drops at the application layer is *invisible* to the
   victim's own telemetry. That is a legitimate and defensible finding.
3. **On victims, `tx_count` equals `probes_count` on every row.** One of the two is redundant.
   "Accepted by the mesh stack" is not "delivered" — ~34 probes per session were counted as sent
   while the board had no parent.

---

## 2. Telemetry schema v2 (14 columns) — current firmware (F3 sep. 20 + C7 Option 1 sep. 21, 2026)

Adds three counters that mean **the same thing on every role**, appended at the end so that any
positional reader of v1 keeps working:

| Column | Meaning — identical on all roles |
|---|---|
| `recv_count` | frames this node received from another node **for relay** (not frames it originated) |
| `forward_count` | frames this node **passed on** toward their destination |
| `drop_count` | frames this node received for relay and **did not pass on** |

**Since C7 Option 1 (D-12) these are populated on honest nodes too.** Every node sends its probes
to its own parent with `MESH_DATA_P2P` and relays what it receives one hop further up
(`components/mesh_common/src/probe_relay.c`), so an honest relay now counts its own forwarding.
**Verified on real data**, G402 blackhole·linear r1, sep. 24, 2026: honest `node3` ended at
`recv = forward = 1767, drop = 0`; the attacker at `recv 2322 / forward 1782 / drop 540`, with
`drop_count` rising **only** during phase 1 (540 = 3 downstream children × 180 s).
`ForwardingRatio = forward_count / recv_count` is therefore defined for every node that relays;
a leaf (nothing below it) still has `recv_count = 0` and a NaN ratio, which is correct.
`analysis/leakage.py` decides per dataset (`relay_features_are_gated()`): pre-C7 captures still
exclude the relay features, post-C7 captures admit them.

### The three older columns on v2 firmware, per role

The `role` column reads `child` on honest nodes (renamed from `victim` sep. 23, 2026;
`preprocess.py` treats both as `child`).

| Column | `child` (`victim_main.c`) | `blackhole` attacker | `root` | `wormhole_b` (entry) | `wormhole_a` (exit) |
|---|---|---|---|---|---|
| `probes_count` | own probes the stack **accepted** | probes **received for relay** (= `recv_count`) | probes **received** (arrivals) | probes **generated** | probes **received from B over the tunnel** |
| `tx_count` | own probes accepted (**equals `probes_count`**) | probes **forwarded** (= `forward_count`) | successful phase **broadcasts** | probes sent **direct to root** | probes **re-injected** into the mesh |
| `retry_count` | **failed `esp_mesh_send()`** of own probes | **failed `esp_mesh_send()`** (F3; drops moved to `drop_count`) | **failed** phase broadcasts | ⚠️ probes **tunnelled** to A — still overloaded, read by the Tunnel* features | **failed re-injections** |

On the root, `recv_count`/`forward_count`/`drop_count` are always 0: it is the destination, not a
relay (`root_main.c`).

⚠️ **`retry_count` is still not an 802.11 retransmission count on any role** — it is send
failures seen by the application, or on Node B the tunnel count. That departure from Table 4.5 is
documented as **D-15** in `issue_logs/thesis-deviate.md`. Since sep. 26, 2026 RetryRate is a model input on schema-v2 data
(excluded only on v1 captures or when a wormhole Node B is present - `leakage.retry_count_is_overloaded()`), and a window with
no send attempt is NaN, not 0 (`features.compute_link_reliability_features`).

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
