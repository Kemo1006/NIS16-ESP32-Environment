# Telemetry data dictionary — what every column actually contains

**Created:** sep. 20, 2026 · **Updated:** nov. 5, 2026 (**§0 added: schema v3, role-neutral columns, D-44**; §1-§3 describe the older layouts and stay valid for old captures; see `deviations-limitations/thesis-deviate.md` D-12, D-15, D-44) · **Applies to:** `*_telem.csv`, `*_arrivals.csv`, `windowed_dataset.csv`, `feature_table.csv`

This file exists because three columns in the telemetry schema **mean different things depending on
which board wrote the row**, and the manuscript currently describes them as something they are not.
A reviewer who reads Table 4.5 and then opens a CSV will find a mismatch. Fixing the names costs a
recapture; writing down what they really contain costs nothing and removes the accusation of
misrepresentation. Do the second immediately, the first at the next capture.

> **The single most important line in this file:**
> **No column in this dataset contains an 802.11 MAC-layer retransmission count.**
> `retry_count` is an application-layer counter on every role. The ESP-IDF Wi-Fi statistics API is
> not read anywhere in this firmware — grep for `esp_wifi_get_statistics`, there are no hits.
> It cannot be: ESP-IDF 5.3/5.5 only *print* Wi-Fi stats (`esp_wifi_statis_dump`). Real 802.11
> retries come from the sniffer's Retry bit — `tools/pcap_retry.py`, see D-15.

---

## 0. Telemetry schema v3 (19 columns) — role-neutral, D-44 (nov. 5, 2026)

**Why:** in v1/v2 `probes_count`, `tx_count` and `retry_count` meant a different thing on each role
(§1-§2), so a reader had to special-case every board. In v3 **every column has one meaning on every
role, and is 0 where it does not apply.** The raw v1/v2 logs are never edited; `analysis/schema.py`
(`to_v3`) reads v1, v2 and v3 alike, and `tools/migrate_telem_v3.py` writes clean copies of every raw
file to `datasets/exports_v3/` (with `manifest_v3.csv`: source path, SHA-256, row counts).

| Column | Meaning (same on every role) | Non-zero on |
|---|---|---|
| `timestamp_us, node_id, role, layer, parent_mac, rssi_dbm, phase_id, gt_label` | unchanged (§1) | all |
| `own_sent` | probes this node **created** and the mesh stack accepted | child, wormhole B |
| `own_failed` | this node's own `esp_mesh_send()` calls that failed (application layer, **not** an 802.11 retry) | child, blackhole |
| `recv_count` | frames received **for relay** (not created here) | relays only (the attacker) |
| `forward_count` | relay frames passed on | relays only |
| `drop_count` | relay frames received and not passed on | relays only |
| `arrivals_count` | probes that arrived at the root | root |
| `bcast_count`, `bcast_failed` | phase broadcasts sent / failed | root |
| `tunnel_tx` | B: probes also written into the tunnel; A: probes re-injected toward the root | wormhole ends |
| `tunnel_rx` | A: tunnelled probes received from B | wormhole A |
| `tunnel_fail` | A: re-injection send failures | wormhole A |

**Zero by design:** the blackhole attacker and the root write `own_sent = 0` (they create no probes);
only the root has `arrivals_count`; only wormhole ends have `tunnel_*`. A 0 means "does not apply", not
"nothing happened". Honest children report `recv/forward/drop = 0` because the mesh stack relays below the
application layer (§2).

**Old name → v3 name** (what `to_v3` does; checked row by row against the firmware mapping):

| Role | probes_count | tx_count | retry_count |
|---|---|---|---|
| child | `own_sent` | (not kept; equals probes_count except ~7 of 1.1 M rows) | `own_failed` |
| blackhole (v2) | (relay in = `recv_count`, already separate) | (= `forward_count`, already separate) | `own_failed` |
| blackhole (v1, pre-F3) | `recv_count` | `forward_count` | `drop_count` |
| root | `arrivals_count` | `bcast_count` | `bcast_failed` |
| wormhole B | `own_sent` | (not kept) | `tunnel_tx` |
| wormhole A | `tunnel_rx` | `tunnel_tx` | `tunnel_fail` |

**What changed in the analysis tables:** windowed and feature tables carry the v3 names
(`own_sent_delta`, `own_failed_delta`, ...). The 16 features are unchanged, **except `RetryRate`**
(`own_failed / (own_sent + own_failed)`): it is now **blank** on the attacker, the root and wormhole end A
(they send no probes; it used to read 0.0 there because it divided a forwarding or broadcast count by
itself), and on wormhole end B it now measures its real failed sends (it used to measure the tunnel
count). Checked on all 83 data folders by `tools/gate_v3_regression.py` against the old code on the same
input: 0 unexpected differences; verdict sync, false-positive, threshold-sensitivity and separability
audits are identical.

**Which firmware writes v3:** builds after nov. 5, 2026 (`csv_logger.c` maps the callers' counters onto
v3 in one place; no counting code changed). Captures before that are v1/v2; read them through
`analysis/schema.py`. Note: 83 data folders exist but the design is 80 runs; the extra 3 are home-site
pilot runs (`blackhole/linear/home/burst`, `.../highload`, `baseline/linear/home/highload`).
`tools/recover_spiffs.py` still recovers only the old 11-column layout.

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
documented as **D-15** in `deviations-limitations/thesis-deviate.md`. Since sep. 30, 2026 RetryRate is a **dataset column only**:
kept in `feature_table.csv`, but out of attack verification, EDA and every model input (no cited study backs it as an
attack signature; it measured flat). A window with no send attempt is NaN, not 0 (`features.compute_link_reliability_features`).

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
| `MacRetryRate` | `features.compute_mac_retry_features()` + `tools/pcap_retry.py` | **real 802.11 retry rate** of this node's frames to its parent, from the sniffer (Retry bit). Sniffer runs only; **NaN = not measured**, never "no retries". Not a model input. D-15 |
| `MacFramesHeard` | same | frames the sniffer heard from this node to its parent that second (0 = covered but silent, NaN = not covered) |
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
