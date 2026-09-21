# Reviewer questions — answered, with the source for each

**Created:** sep. 21, 2026 · Adviser (Cu, Gregory G.) + panel side comments, verified against code
and captured data on the dates shown. **Nothing here is answered from memory.**

Use this as the pre-defense answer sheet. Each row names the file that proves it, so the answer can
be shown, not asserted.

---

## 1. "Why is it `timestamp_us`?"

**Because that is what the chip's clock returns, unrounded.** The firmware calls
`esp_timer_get_time()` (`victim_main.c`, `root_main.c`, `blackhole_victim.c`), whose native unit is
**microseconds since that board booted**. We log it as-is rather than converting, for two reasons:

1. Converting to seconds would throw away precision we cannot get back. Storing it raw costs
   nothing and keeps the option open.
2. It is not a wall clock, and calling it seconds would imply it was. **Boards never synchronise
   their clocks** — every board's `timestamp_us` starts at *its own* boot. Cross-node alignment is
   done on each node's own first phase-0 exit (`preprocess.assign_segments()`), the one event all
   nodes observe, never on raw timestamp arithmetic. See `docs/DATA-DICTIONARY.md` §4.

---

## 2. "Are you sure the MAC address is really from the ESP and not the connector?"

**Yes — confirmed in source.** Every board reads its own MAC with:

```c
esp_read_mac(mac, ESP_MAC_WIFI_STA);   // sd_status.c:540 comment: "eFuse read"
```

(`mesh_setup.c`, `node_identity.c`, `sd_status.c`, `victim_main.c`, `blackhole_victim.c`,
`wormhole_victim.c` — 9 call sites, all `ESP_MAC_WIFI_STA`.)

`ESP_MAC_WIFI_STA` is the ESP32's **Wi-Fi station MAC, burned into the chip's eFuse at
manufacture**. It is read straight off the silicon, before the mesh even starts.

**The USB connector cannot be the source.** The board talks to the laptop through a CP210x
USB-to-UART bridge, which is a *serial* device — it has no MAC address at all, because it is not a
network interface. There is nothing for it to contribute.

---

## 3. "Change layer to hop" / "make it topology layer, not OSI layer"

**Done — see `docs/issue_logs/thesis-deviate.md` D-11.** Two reviewers raised this independently,
which made it a naming defect rather than a misreading.

- `hop` is now a column in the analysis output: **root = hop 0**, its children = hop 1, and so on.
- The Table 4.11 feature `LayerChangeCount` is renamed **`HopChangeCount`**.
- The raw `layer` column is kept, because it is what the firmware actually reported.

⚠️ **The values could not simply be renamed.** Espressif numbers the **root as layer 1**, so a
straight rename would have said "the root is 1 hop from itself." `hop = layer − 1` fixes that;
`layer == -1` (no parent) becomes NaN, not −2.

**`HopChangeCount`'s numbers are identical to `LayerChangeCount`'s** — it counts *changes* in depth,
and a count of changes is unaffected by a constant offset. Only the name moved.

---

## 4. "What's dBm / how is RSSI computed? Is it automatic?"

**It is automatic — we do not compute it, we read it.**

- **dBm** = decibels relative to 1 milliwatt, the standard unit for radio signal strength. It is
  negative and *closer to zero is stronger*: −45 dBm is a strong signal, −85 dBm is weak.
- The firmware calls **`esp_wifi_sta_get_rssi(&rssi)`** (`victim_main.c:371` and the other node
  firmwares). The Wi-Fi driver measures it on the radio; the value is not calculated by our code.
- **It measures ONE link only** — this node to *its parent*. It does **not** accumulate across hops.

**`RSSI_mean` is the only part we compute**, and it is a plain arithmetic mean of the `rssi_dbm`
samples inside each 1-second window (`preprocess.py` produces `rssi_dbm_mean`; `features.py:761`
passes it through unchanged). No weighting, no smoothing, no conversion.

⚠️ Related known error to own, not hide: the manuscript's claim that **"RSSI drops 5–10 dB per
hop"** is wrong — RSSI is per-link, so a layer-6 node one metre from its parent reads *strong*. See
`docs/DATA-DICTIONARY.md` §3.

---

## 5. "How about retry_count? What does tx_count = 0, 1, 2 mean?"

**This is the schema's weakest point and it has been fixed — declare both the old state and the
fix.** Full table in `docs/DATA-DICTIONARY.md` §1.

`tx_count` is **cumulative, not per-event**: it counts probes since boot. So `2` does not mean "sent
twice just now", it means "2 probes sent in total so far". The analysis uses per-window **deltas**
(`tx_count_delta`), never the raw running total.

**The real problem was `retry_count`:** it meant *three different things* depending on which board
wrote the row — on a victim, failed `esp_mesh_send()` calls; on the blackhole attacker, **the
packets it deliberately dropped**. That made the derived `RetryRate` feature the attack's own
control variable wearing a MAC-layer name.

**Fixed (F3, schema v2):** `recv_count` / `forward_count` / `drop_count` are now separate columns
meaning the same thing on every role, and `retry_count` means one thing everywhere (send failures).

⚠️ **No column in this dataset contains a real 802.11 MAC retransmission** — old schema or new. The
manuscript's Table 4.5 says otherwise and must be corrected. Genuine MAC retries need a packet
capture (`wlan.fc.retry == 1`); see `docs/WIRESHARK-GUIDE.md`.

---

## 6. "You should see the topology from the data without visuals" (adviser, 8:15–9:45)

**Agreed — and you now can.** Run:

```powershell
python tools\verify_topology.py --dir tools\exports --topology linear --attack blackhole --structure
```

or `run_wizard.ps1` → **VERIFY** → *"Show TOPOLOGY STRUCTURE of a captured run"*. Real output from
the sep. 18 G402 capture:

```
 HOP   MAC ADDRESS        ROLE       UPLINK (= ITS PARENT)
 H00   B0:CB:D8:F3:32:18  ROOT       --:--:--:--:--:--  (root, no parent)
 H01   28:05:A5:32:D7:B4  VICTIM     B0:CB:D8:F3:32:18
 H02   B4:BF:E9:34:ED:80  VICTIM     28:05:A5:32:D7:B4
 ...
 H06   20:50:0D:E7:1C:38  BLACKHOLE  20:50:0D:E7:0C:80
 H07   F4:2D:C9:73:E6:18  VICTIM     20:50:0D:E7:1C:38
```

Each node's uplink is the node above it — the chain is readable straight from the data, no diagram
needed. The firmware prints this same banner over serial during a live run, but that scrolls away
and is not in the dataset; this rebuilds it from the exported CSVs, so it works for **archived runs
from months ago** too.

---

## 7. "Show which is the parent MAC and which is the child MAC"

**In the raw CSV:**

| Column | What it is |
|---|---|
| `node_id` | the row's **own** MAC — i.e. the **child** in any parent/child pair |
| `parent_mac` | that node's **parent** |

⚠️ **They are deliberately not directly comparable, and this trips everyone up once.** `node_id`
holds the **STA MAC**; `parent_mac` holds the parent's **SoftAP BSSID**, and on the ESP32 the
**SoftAP MAC is always the STA MAC + 1**. So joining `parent_mac` to `node_id` literally matches
nothing, and a reader would wrongly conclude the mesh was disconnected.

Confirmed on all 7 non-root nodes of the sep. 18 capture — e.g. `parent_mac` `20:50:0D:E7:1C:39`
is the attacker `20:50:0D:E7:1C:38` **+1**.

`tools/verify_topology.py` has always resolved this correctly (`_resolve_parent()`, documented at
its line 15). The `--structure` view in §6 above prints the resolved parent, so you never have to do
the −1 by hand.

---

## 8. "What's the protocol of the ESP32?"

**ESP-WIFI-MESH**, Espressif's own mesh networking protocol, running over **IEEE 802.11 (Wi-Fi)** on
**channel 11**, with WPA2 protecting the links.

The point that matters for this thesis: **ESP-WIFI-MESH operates below IP.** It is a self-organising
layer-2 tree with its own header — there is no routing protocol like AODV or RPL involved, and no IP
layer to attack. That is exactly why the classical blackhole/wormhole definitions had to be adapted
rather than applied directly (`docs/ATTACK-VALIDATION.md` §0), and why calling `layer` an OSI layer
was wrong (§3 above).

---

## 9. "Explain why the dataset has nulls / check the NaNs in the EDA"

**Every NaN has a specific, documented cause — they are not missing data or logging failures.**
Measured on `blackhole/linear/G402` (sep. 21, 2026):

| Feature | NaN % | Why |
|---|---|---|
| `TunnelIntensity`, `TunnelBytes`, `TunnelLatency` | **100%** | This is a **blackhole** run. Tunnel features only exist on wormhole endpoints. A blackhole run *should* have these empty |
| `ForwardingRatio`, `IngressEgressDelta`, `ConsistencyScore` | **89.8%** | Defined only on the **blackhole attacker** (1 of 8 boards). Honest nodes send with `MESH_DATA_TODS`, so the mesh stack relays *below* the app layer and an honest node cannot observe its own forwarding |
| `LatencyHopRatio` | **64.8%** | Needs a matched probe **arrival** at the root. During the attack the probes are dropped — so the NaN *is* the attack |
| `PDR` | **33.0%** | Same cause: computed per window from root arrivals, absent where nothing arrived |
| `RSSI_Hop_Diff` | 9.6% | Inherits RSSI's gaps |
| `RSSI_mean` | 8.7% | `rssi_dbm == 0` is the firmware's **"no parent link" placeholder, not a reading** — blanked to NaN on purpose (6,446 rows). A 0 dBm reading would be a physically impossible perfect signal |
| `RetryRate`, `ParentSwitchRate`, `HopChangeCount`, `HopStabilityDuration`, `RSSI_var`, `RSSI_stability` | **0%** | Complete |

**Two of these are results, not gaps.** `PDR` and `LatencyHopRatio` going NaN during the attack
window is the blackhole *working* — there were no arrivals to measure.

⚠️ **The role-gated NaNs are also a known leakage risk**: "is this column NaN?" identifies the node
role, and therefore the run type. `analysis/leakage.py` excludes those columns from any model input
and states the reason per column. That is the panel's 2:40–4:50 objection, handled.

---

## Where each answer is enforced in code

| Question | File |
|---|---|
| timestamps, per-role column meanings, RSSI placeholder | `docs/DATA-DICTIONARY.md` |
| hop vs layer, and the off-by-one | `analysis/preprocess.py` `_layer_to_hop()`, `thesis-deviate.md` D-11 |
| parent/child MAC resolution | `tools/verify_topology.py` `_resolve_parent()` |
| topology readable from data | `tools/verify_topology.py --structure` |
| why each NaN exists / which are excluded | `analysis/leakage.py` |
| attack conformance to literature | `docs/ATTACK-VALIDATION.md` |
| real MAC-layer retries | `docs/WIRESHARK-GUIDE.md` |
