# NIS16 — Defense Prep, Explained + Where It Lives in the Code

For each idea a panel will ask about: **what the word means** (plain), **how it actually works**, and **the exact code file/function that does it**. Companion to [DEFENSE-PREP.md](DEFENSE-PREP.md) and [TERMS-GLOSSARY.md](TERMS-GLOSSARY.md).

## First, how the code is split across folders
Everything is under `NIS16-ESP32-Environment-semi-final/`:

| Folder | What runs there |
|---|---|
| `components/mesh_common/` | **Shared code every board uses** — mesh setup, the phase listener, the CSV logger. Not a board itself; the root and children both pull it in. |
| `root_node/main/root_main.c` | The **root** board's program: runs the experiment timeline, receives probes, logs. |
| `child_node/main/` | The **children's** programs. Which one compiles is chosen by a build flag: `victim_main.c` (normal), `blackhole_victim.c` (attacker), `wormhole_victim.c` (both wormhole ends). |
| `analysis/` | The **Python** that turns raw logs into features: `preprocess.py` (M6, cleans + windows), `features.py` (M7, the 16 features), `eda.py` (M8, clustering/plots). |
| `tools/` | Host-side scripts to pull data off boards and check it (`export_logs.py`, `validate_integrity.py`, etc.). |

> **Key idea to say out loud:** the boards only log *raw counters and readings*. All the "features" are computed later on a laptop in Python. The ESP32 does the measuring; the analysis folder does the math.

---

## Q2 explained — "What is a true label / ground truth?"

**Plain meaning.** A **label** is the correct answer attached to a row of data — here, "this 1-second reading happened during *normal* / *blackhole* / *wormhole*." **Ground truth** just means "the label we *know* is correct because we set it ourselves," as opposed to a guess. In machine learning you compare a model's guess against the ground truth to see if it's right.

**Why it matters for you.** Your whole analysis rests on the labels being trustworthy. If a panelist could argue your labels were influenced by the very measurements you're studying, the results would be circular. So you need to show the label comes from the *experiment control*, completely separate from the data.

**How it works.** The **root** board is the conductor. It runs a fixed timeline — 300 s normal, then 180 s attack, then a cooldown — and at each change it **broadcasts** which phase is now active. Every board hears that broadcast and stamps the matching label onto each row it logs. The label is decided by the schedule, never by an RSSI or forwarding value.

**The code:**
- **Root announces the phase** — `root_node/main/root_main.c`, `experiment_controller_task()` (around line 244). It sleeps for each phase's duration and calls `broadcast_and_count(PHASE_ID_BASELINE)`, then the attack, then cooldown, then terminate.
- **Every board listens and converts phase → label** — `components/mesh_common/src/phase_listener.c`. The function `phase_id_to_label()` (line 281) is literally the whole rule:
  - phase 1 → label 1 (blackhole), phase 2 → label 2 (wormhole), everything else → label 0 (normal).
- **The label gets written into every row** — `components/mesh_common/src/csv_logger.c`, `csv_logger_append_telemetry()` (line 152). The last column it writes is `gt_label`. The CSV header (line 40) ends in `...phase_id,gt_label`.
- **Reliability detail worth knowing:** the root sends each phase message several times, and every board ignores repeats using a sequence number (`phase_listener.c`, line 244: `if (msg->seq_num <= s_last_seq) ignore`). So a phase is applied exactly once even though it's broadcast repeatedly — that's how no board misses a transition.

**Say it like this:** "The label isn't derived from the data. The root broadcasts the active phase on a fixed schedule, each board maps that phase to a label in `phase_id_to_label()`, and writes it as the `gt_label` column on every row. It comes from the experiment's control channel, so it's true ground truth."

---

## The blackhole attack — how the drop actually happens

**Plain meaning.** A blackhole node accepts traffic it's supposed to pass along, then quietly throws it away instead of forwarding it.

**How it works.** One child is the attacker. Every other child is told to send its probes *to the attacker's address* instead of straight to the root. The attacker keeps a running loop: during normal phases it forwards each probe on to the root; during the attack phase it just... doesn't. It receives the probe, then skips the "send" step. The packet vanishes, and the root stops seeing those probes.

**The code:** `child_node/main/blackhole_victim.c`, `relay_task()` (line 177). The heart of it:
```c
if (phase_listener_get_phase_id() == PHASE_ID_BLACKHOLE) {
    s_probes_dropped++;          // attack: count it and do nothing else
} else {
    esp_mesh_send(NULL, ..., MESH_DATA_TODS, ...);  // normal: forward to root
    s_probes_forwarded++;
}
```
That single `if` is the entire attack — forward, or drop. No protocol hacking; the board stays a normal mesh member and only changes this one app-layer decision. (The file's top comment, lines 1–34, explains this is the "true relay model.")

**The proof it's deliberate, not a crash:** the attacker counts what it does — `s_probes_received`, `s_probes_forwarded`, `s_probes_dropped`. In the telemetry it writes those into the shared columns (`telemetry_task`, line 275): received → `probes_count`, forwarded → `tx_count`, dropped → `retry_count`. That's how you can later show "720 received, 720 dropped, 0 forwarded."

---

## The wormhole attack — how the "tunnel" and the duplicate work

**Plain meaning.** A wormhole is two cooperating nodes secretly linked by a private channel. They pass traffic through that private link to make far-apart parts of the network look like neighbors — a fake shortcut.

**How it works.** Two attacker boards, **Node B** (near the victims) and **Node A** (near the root), are joined by a **physical wire** (a UART serial cable), *not* Wi-Fi. During the attack, Node B sends each probe two ways: the normal slow way over the mesh, *and* down the wire to Node A. Node A then re-injects that probe to the root as a second, faster copy. So the root receives the **same probe twice** — and the gap between the two arrival times is the signature.

**The code:** `child_node/main/wormhole_victim.c` (one file, both ends, chosen by the `WORMHOLE_END` build flag):
- **The private wire** is set up in `wormhole_uart_init()` (line 127) — a separate UART port from the USB console, wired board-to-board.
- **Node B forwards twice** — `tunnel_forwarder_task()` (line 233): Step 1 always `esp_mesh_send(... TODS ...)` to root (the slow copy); Step 2, *only during the wormhole phase*, wraps the probe with a CRC and `uart_write_bytes(...)` down the wire to A.
- **Node A re-injects** — `reinject_task()` (line 408): it stamps the probe with a special marker `PROBE_MAGIC_WORMHOLE` and sends it to the root as the fast copy.
- **The root keeps both copies** — `root_node/main/root_main.c`, `probe_data_cb()` (line 301). Normal probes get de-duplicated (line 321), but the wormhole-marked copy is *deliberately not* de-duplicated (comment at 312–320), so both arrivals survive into the log. That surviving duplicate is what the analysis measures.

**Say it like this:** "The tunnel is a real wired UART link between the two attacker boards, separate from the mesh. Node B sends each probe over the mesh *and* down the wire; Node A replays it to the root. The root logs the same probe twice on purpose — we suppress de-duplication only for the tunneled copy — and the latency gap between the two is the wormhole signature."

---

## How probes and PDR work (and the de-duplication)

**Plain meaning.** A **probe** is the little once-a-second packet a victim sends toward the root. **PDR (Packet Delivery Ratio)** is "how many of those actually made it," from 0 to 1.

**How it works on the board.** The root receives probes and writes one row per probe into `arrivals.csv`, recording who sent it (`src_mac`), its number (`seq_num`), and a latency. Because the mesh sometimes delivers the same probe twice on its own, the root keeps a small table of "highest number seen per sender" and ignores repeats — otherwise PDR would be inflated.
- Code: `root_main.c`, `probe_is_duplicate()` (line 97) and `probe_data_cb()` (line 301).

**How PDR is computed later (in Python).** On the laptop, `analysis/features.py`, `compute_pdr_features()` (line 271): for each victim and each 5-second window, it counts the **distinct** sequence numbers the root logged from that victim, and divides by how many that victim *said* it sent. A careful detail they built in: if the root logged the victim at all but got zero in one window, PDR is a real **0.0** (the blackhole signature); if the root never logged that victim at all, PDR is left **blank (NaN)** — a coverage gap, not a delivery failure. Those two must not look the same (comment at 324–333).

---

## Forwarding Ratio — and why the attacker "overloads" columns

**Plain meaning.** Forwarding Ratio = of the packets a relay received to pass on, what fraction did it actually pass on. ~1.0 = honest relay, ~0 = blackhole.

**The trick to know about.** The firmware's CSV has a fixed 11 columns shared by every board. Rather than add new columns just for the attacker, the attacker **reuses** three existing counter columns to mean something attacker-specific: `probes_count` = received, `tx_count` = forwarded, `retry_count` = dropped. This is called *overloading*. It keeps one schema for all boards.
- Firmware side: `blackhole_victim.c`, `telemetry_task()` line 275 (the mapping).
- Python side: `features.py`, `compute_forwarding_features()` (line 113): for rows where `node_role == "blackhole"`, it reads those columns back and computes `forward / received`. For every other node it leaves the feature blank, because a non-relay has no forwarding ratio.

**Say it like this:** "To avoid changing the schema, the attacker overloads three counter columns — received, forwarded, dropped. The Python reads them back for attacker rows and computes the ratio; it's undefined and left blank for everyone else."

---

## The latency / clock trick (the clever recovery)

**Plain meaning.** You wanted delay per hop, but two boards' clocks aren't synced, so the raw latency number is nonsense (we saw −194 seconds).

**How it's fixed.** The error is the *same constant* for a given sender in a given run, so if you subtract two of that sender's readings, the error cancels. For latency-per-hop, subtract each node's own minimum (its fastest delivery) and divide by hop count. For tunnel latency, subtract the two arrivals of the *same* duplicated probe — the error cancels exactly.
- Code: the raw (broken) value is written at `root_main.c` line 329 (`latency = now - pkt->send_ts_us`). The fix is in `features.py`, `compute_latency_features()` (line 369) — the long docstring there (379–439) explains the cancellation, and the actual subtraction is line 453 (`latency_us - group min`) and line 465 (`max - min` per duplicated probe).

---

## RSSI and topology features (why some are computed from raw, not the average)

**Plain meaning.** Some features (like "how long did the signal stay steady" or "how many times did the parent change") can't be computed from a window's *average* — averaging throws away the moment-to-moment changes you need.

**How it works.** So the pipeline keeps two tables: the windowed averages, *and* a `filled_long` table with one row per second before averaging. The change-over-time features are computed from that second table.
- Code: `features.py`, `compute_topology_stability_features()` (line 527, parent switches / layer changes / hop-stability) and `compute_physical_layer_features()` (line 606, where `RSSI_stability` scans the raw per-second RSSI). Both loop over `filled_long`, not the averaged table — the docstrings say exactly why (windowing "destroys the transition information").

---

## One-line pointers for the rest
- **Phase timeline (300/180/180/120 s):** `root_main.c`, `experiment_controller_task()` — the sleeps between broadcasts.
- **Why a board full of data can't be read:** `csv_logger.c`, the `DELETE_LOGS` handler (line 486) formats the whole flash on every `-Wipe` precisely to stop the storage-full failure.
- **The 16 features assembled into one table:** `features.py`, `compute_features()` (line 784) — it calls each family and merges them, then adds the `Label` column.
- **Cleaning + 5-second windows (M6):** `analysis/preprocess.py` (referenced by `features.py` at the top of `main()`).
