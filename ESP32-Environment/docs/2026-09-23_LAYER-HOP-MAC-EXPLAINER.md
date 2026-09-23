# "Layer vs hop" and "MAC mismatch" — plain-language explainer + dataset check

**Created:** sep. 23, 2026. Companion to `docs/REVIEWER-QUESTIONS.md` §3 and §7, which have the
technical/code-cited version of the same two answers. **This file is the dumbed-down version** —
written so anyone on the team (or a panelist mid-question) can follow it without reading code first.
Also logs the dataset spot-check done the same day. Session details: `STATUS.md` / `MEMORY.md`
(sep. 23 entries).

---

## 1. What we checked today

We independently re-verified one capture — `blackhole/linear/home`, run r1, captured sep. 22, 2026 —
by reading the raw exported CSVs and the analysis outputs (feature table, EDA plots, leakage audit)
directly, without trusting any prior summary. **Verdict: the capture is clean and matches the paper's
blackhole model exactly.** Detail in §4. While doing that we ran into two things in the data that look
like bugs but aren't — those are §2 and §3.

---

## 2. Thesis in one paragraph (for context)

Title: *Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based ESP-WIFI-MESH Network*
(DLSU CCS, CTTHES2/THES3). In plain terms: a small mesh of ESP32 boards runs normal traffic, then one
board attacks (blackhole = silently drops packets; wormhole = tunnels/duplicates them), then goes back
to normal. Every board logs its own radio signal strength, its position in the mesh, and its packet
counts once a second. "Cross-layer" means the dataset intentionally combines readings from several
different levels at once — radio signal (physical), mesh position/parent (network), packet
forwarding (link), and probe timing (application) — so an attack's fingerprint can be looked for
across all of them together, not just one.

---

## 3. "layer" vs "hop" — why both columns exist

**Dumbed down:** The chip's own firmware has a built-in word for "how deep is this node in the mesh
tree" — it calls it `layer`. Problem: `layer` already means something else in networking class (the
OSI model — physical layer, network layer, application layer, etc.). That's a *completely different
concept*. So a panel member reading our column name `layer` would reasonably think we meant OSI
layers, when we actually meant "hops from the root." To kill that confusion, we introduced a second
column called `hop`, which is the standard, unambiguous word for "number of jumps from the root."

**Why we can't just rename the column and keep the same numbers:** Espressif's firmware counts the
**root itself as layer 1**, not layer 0. So if we just swapped the label without changing the number,
our data would claim "the root is 1 hop from itself" — which is nonsense, and exactly the kind of
thing a panel would catch. So the real rule is:

```
hop = layer - 1
```

| Node | `layer` (raw firmware) | `hop` (what we report) |
|---|---|---|
| Root | 1 | 0 |
| Root's direct child | 2 | 1 |
| That child's child | 3 | 2 |

One more wrinkle: sometimes a board briefly has no parent yet (just booted, or mid-reconnect), and the
firmware logs `layer = -1` as a placeholder meaning "no parent right now" — not a real depth. Our
conversion turns that into a blank value (`NaN`), never into `-2`.

**What to say if a panelist asks:** *"`layer` is the raw value straight from the firmware, kept only
for traceability. `hop` is the corrected, reported version — same information, renamed to avoid OSI
confusion, and adjusted so hop count correctly starts at zero at the root."*

**We did not invent this — Espressif did.** The root-is-layer-1 convention is hard-coded in
Espressif's own SDK, not something our team chose:

```c
// esp_mesh.h, ESP-IDF v5.3.5 (the exact firmware version this thesis builds against)
#define MESH_ROOT_LAYER    (1)   /**< root layer value */
```
Source: [`esp_mesh.h`, ESP-IDF tag v5.3.5](https://github.com/espressif/esp-idf/blob/v5.3.5/components/esp_wifi/include/esp_mesh.h)
(also documented in prose at the
[ESP-WIFI-MESH Programming Guide, ESP-IDF v5.3](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/network/esp-wifi-mesh.html)).

Code reference: `analysis/preprocess.py`, function `_layer_to_hop()` (its docstring records this was
adviser feedback dated sep. 21, 2026).

---

## 4. Why `parent_mac` never matches any `node_id` — the MAC address "mismatch"

**Dumbed down, with an analogy:** Think of each ESP32 board like a person with **two phone numbers**
— one for making calls out, one for receiving calls on a different line. Same person, two numbers,
and the second number is always exactly **one digit higher** than the first.

- **`node_id`** in our data = the board's "calling out" number
- **`parent_mac`** in our data = the board's "receiving calls" number

So if you see node3 listed as `node_id = ...1C:38`, and somewhere else its `parent_mac` shows up as
`...1C:39` for one of *its* children — that is **not two different boards**. It's the exact same
board, just its other number showing up, because it's doing a different job in that moment.

**Why does a board have two numbers at all?** Because of the job it's doing right then:

| Job the board is doing | Radio role | MAC it uses |
|---|---|---|
| Connecting **up** to its own parent | Station (STA) | its base MAC |
| Accepting connections **from** its children | SoftAP | base MAC **+ 1** (last digit) |

Every board (except the root, which has no parent, and a leaf, which has no children) is doing *both*
jobs at once — so it effectively has both numbers live at the same time, one per role.

**The one-line version, if you get confused again:** the +1 never happens to a board's *own*
identity — it only shows up in *someone else's* `parent_mac` field. Say node X is node Y's parent:

| Where you're looking | What you see for node X |
|---|---|
| X's own row, `node_id` column | X's base MAC — **no +1** |
| Y's row, `parent_mac` column (Y is X's child) | X's base MAC **+1** |

Same physical board, same MAC family — the +1 depends on **who's asking**: X describing itself uses
its STA radio (no offset); Y describing "who is my parent" uses X's SoftAP radio (+1). It's never "X
has +1" as a fixed fact about X — it's "X's hosting radio, as seen by whoever connected to it."

Our CSV always names a board by its STA number (`node_id` — that's its constant "who is this board"
identity). But `parent_mac` records the **parent's SoftAP number**, because that's the address the
child actually connected to. Two different roles, two different numbers, off by exactly 1, both
belonging to the same physical board. **The fix when reading the table by hand:** subtract 1 from the
last digit of `parent_mac`, and it will exactly match a `node_id`.

**We did not invent this either — it's built into every ESP32's Wi-Fi driver:**

| Interface | MAC formula |
|---|---|
| Wi-Fi Station (STA) | `base_mac` |
| Wi-Fi SoftAP | `base_mac`, **+1** to the last octet |
| Bluetooth | `base_mac`, +2 |
| Ethernet | `base_mac`, +3 |

Source: [ESP-IDF MAC Address Allocation table, v5.3](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/system/misc_system_api.html#mac-address).
This is chip/firmware behavior we have no control over — we just had to learn it to correctly read
our own topology table. Code reference: `tools/verify_topology.py`, function `_resolve_parent()`,
already does this subtraction automatically so nobody has to do it by hand.

**What to say if a panelist asks:** *"This isn't something we implemented — it's inherent to how the
ESP32's Wi-Fi hardware assigns radio addresses. We didn't design it; we just had to account for it
when interpreting our own captured data."*

**Verified on the sep. 22 `blackhole/linear/home` run** — all 4 distinct `parent_mac` values in that
capture resolve cleanly as `node_id + 1`:

```
70:4B:CA:25:B7:69  →  NODE_704BCA25B768  (root)
B0:CB:D8:F3:32:19  →  NODE_B0CBD8F33218
20:50:0D:E7:1C:39  →  NODE_20500DE71C38  (the blackhole attacker)
20:50:0D:E7:0C:81  →  NODE_20500DE70C80
```
Resolved chain: `root → NODE_B0CBD8F33218 → NODE_20500DE71C38 (attacker) → NODE_20500DE70C80`.

---

## 5. Dataset spot-check — `blackhole/linear/home`, r1, sep. 22, 2026

**Short version: the attack worked exactly as designed, and the graphs are honest.**

- Phase timing matched the spec exactly: 300s normal → 180s attack → 120s back to normal.
- During the attack, the attacker board forwarded **0%** of what it received (it received 180
  packets, passed along 0, dropped all 180). During normal phases it forwarded 100%.
- The board *downstream* of the attacker had its messages reach the root **301 times → 0 times → 121
  times** across the three phases — vanished exactly during the attack, came back right after.
- The board *upstream* of the attacker (not behind it in the chain) was unaffected the whole time —
  proof the attack is about position in the mesh, not general breakage.
- A single-feature statistical check (`leakage_audit.csv`) found `ForwardingRatio` alone predicts the
  attack label with **99.9% accuracy**, and `PDR` alone with **84.6%** — both strong, legitimate
  signals, not artifacts.

**Two things that looked like bugs but are documented, intentional behavior, not fixed and not
broken:**
- The raw `arrivals.csv` `latency_us` column is 100% negative. This is because each board's internal
  clock starts counting from its own power-on, and boards power on at different times — so a raw
  subtraction between two boards' clocks produces a large negative number. The analysis code corrects
  for this before computing the reported `LatencyHopRatio` feature (`features.py`, documented at
  lines ~530–540).
- `RetryRate` is flat zero for this entire run. The EDA pipeline detected this itself and excluded it
  from the leakage audit rather than pretending it's informative. Likely just a clean, low-noise
  home-environment capture with no MAC-layer retries — not a data error.

**One caveat worth remembering for the write-up:** the PCA/t-SNE separability plot for this run
excludes `ForwardingRatio` and `PDR` — the two strongest attack-detecting features — because they're
missing (NaN) for node roles that don't apply to them. So that specific plot understates how separable
the attack actually is. If citing separability as evidence, use the `ForwardingRatio` distribution
plot or the leakage-audit accuracy numbers instead.

---

## 6. One-paragraph version, if you only have 30 seconds with the panel

*"Two naming things in our raw logs needed clarification for the paper. First: the mesh chip's own
firmware calls a node's tree depth 'layer,' which collides with the OSI-model meaning of that word, so
we report 'hop' instead — and had to subtract one from the raw value, because Espressif's firmware
numbers the root as layer 1, not 0. Second: our logs show two different MAC addresses per board
because every ESP32 has two separate Wi-Fi radio identities — one for connecting up to its parent, one
for hosting its children — and those two addresses always differ by exactly one. Neither of these is
something we designed; both are fixed behaviors of Espressif's ESP32 firmware and hardware, which we
verified directly against Espressif's own published documentation and source code. Neither affects any
measured value in the dataset — both are presentation-layer clarifications only."*

---

## Where else this is written up

| What | File |
|---|---|
| Technical/code-cited version of both answers | `docs/REVIEWER-QUESTIONS.md` §3, §7 |
| Raw vs corrected column definitions | `docs/DATA-DICTIONARY.md` |
| The `hop` conversion itself | `analysis/preprocess.py` → `_layer_to_hop()` |
| The MAC resolution itself | `tools/verify_topology.py` → `_resolve_parent()` |
| Today's session log (facts/decisions) | `STATUS.md`, `MEMORY.md` (sep. 23, 2026 entries) |
