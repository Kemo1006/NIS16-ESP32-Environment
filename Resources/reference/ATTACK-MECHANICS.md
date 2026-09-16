# NIS16 — How the Blackhole & Wormhole Attacks Work (panel explainer)

Written to be **spoken** to a panel. The panel's real question isn't "did you hack the mesh?" — it's *"if you didn't fake the routing, in what sense is this an attack?"* The honest, winning answer is the same for both: **we reproduce the attack's observable behaviour, not Espressif's closed routing internals.** Companion to [DEFENSE-PREP.md](0_Resources/archive/DEFENSE-PREP.md), [DEFENSE-PREP-CODE.md](0_Resources/archive/DEFENSE-PREP-CODE.md), [TERMS-GLOSSARY.md](0_Resources/archive/TERMS-GLOSSARY.md).

---

## The one sentence to open with

> "On the ESP32, routing and forwarding live in Espressif's **closed firmware** — we can't inject fake routes. So instead of faking the attack's *mechanism*, we reproduce its *effect*. What a network monitor would see — forwarding collapses, delivery drops, probes arrive twice — is identical to the real attack. Our study is about **observable cross-layer behaviour**, so that is exactly what matters."

Say this first. It pre-empts the "this isn't a real attack" ambush and frames everything after it as a deliberate design choice, not a limitation you got caught on.

---

## 1. Blackhole — "receive everything, forward nothing"

### What a real blackhole is
A malicious relay lures traffic by **lying about routes** ("send through me, I'm the best path"), accepts the packets it's trusted to pass along, and silently discards them. Delivery to the destination collapses.

### What we reproduce, and how
We can't lie about routes (closed stack), so we arrange the same funnel by configuration: **every victim is told, at the app layer, to address its once-per-second probes to the attacker's MAC** instead of straight to the root. Now all probe traffic flows through one node — the attacker — regardless of where the mesh would naturally route it.

The attacker then runs one honest loop with a single decision in it:

```c
// child_node/main/blackhole_victim.c — relay_task() (line 177)
if (phase_listener_get_phase_id() == PHASE_ID_BLACKHOLE) {
    s_probes_dropped++;                                  // ATTACK: count it, drop it
} else {
    esp_mesh_send(NULL, ..., MESH_DATA_TODS, ...);       // NORMAL: forward to root
    s_probes_forwarded++;
}
```

That `if` **is** the whole attack. During baseline it forwards every probe like an honest relay; during the attack window it just skips the send. No protocol hacking — it stays a well-behaved mesh member and changes only this one app-layer choice ("true relay model," file header lines 1–34).

### Why it's an attack and not a crashed node (the question they push hardest)
Because the attacker's **own counters prove it chose to drop**. It writes three numbers every second — received / forwarded / dropped — into shared columns (`telemetry_task`, line 275: received→`probes_count`, forwarded→`tx_count`, dropped→`retry_count`). In the attack window, across all three repeats:

- **received keeps climbing to ~2,120** → victims never stopped sending
- **forwarded plateaus at ~1,400** → it stopped relaying the moment the attack began
- **dropped ≈ 720 / 925 / 720** → deliberate discards, on the record

And the tell that separates *attack* from *failure*: **ParentSwitchRate = 0, LayerChangeCount = 0**. A genuinely dead node makes the mesh re-route around it. Ours shows **zero re-routing** — the node is alive and cooperating, it just refuses to forward. That's intent, not a breakdown.

### What the monitor sees (the signature — all verified from real logs)
| Feature | Baseline → Attack | Meaning |
|---|---|---|
| ForwardingRatio | 0.951 → **0.000** | relay stopped forwarding — primary tell |
| PDR (delivery) | 0.855 → **0.226** | delivery collapses |
| IngressEgressDelta | 0.82 → **15.9** | packets absorbed, not passed on |
| RetryRate | 0.019 → **0.166** | link stress spikes as sends fail |
| ConsistencyScore | 0.064 → **1.000** | total deviation from ideal forwarding |

### The honest limitation to volunteer
The attacker sits deep in the chain (Layer 4), yet even nodes closer to the root go quiet — because **every** victim addresses the attacker, so all traffic funnels through it by our design, not by natural mesh routing. State this plainly as a setup-driven limitation; don't let them "discover" it.

---

## 2. Wormhole — "one probe, logged twice"

### What a real wormhole is
Two cooperating nodes secretly linked by an **out-of-band channel** pass traffic to each other through that private link, making two far-apart parts of the network look like neighbours — a fake shortcut. It breaks the assumption "closer nodes have stronger signal / shorter paths."

### What we reproduce, and how
The tunnel is **real**: two attacker boards joined by a physical **UART serial wire** — a separate channel from the mesh Wi-Fi, exactly what a wormhole is. **Node B** sits near the victims, **Node A** near the root. One firmware file drives both ends, chosen by the `WORMHOLE_END` build flag (`child_node/main/wormhole_victim.c`).

The mechanism, three steps:

1. **Private wire brought up** — `wormhole_uart_init()` (line 127): a dedicated UART port, wired board-to-board, separate from the USB console.
2. **Node B forwards each probe twice** — `tunnel_forwarder_task()` (line 233): *always* `esp_mesh_send(... TODS ...)` to the root over the mesh (the slow copy); then *only during the attack phase*, wraps the probe with a CRC and `uart_write_bytes(...)` it down the wire to A.
3. **Node A re-injects the fast copy** — `reinject_task()` (line 408): stamps the probe with a marker `PROBE_MAGIC_WORMHOLE` and sends it to the root as a second, faster arrival.

### Why the duplicate survives (the clever bit)
The root normally **de-duplicates** — it keeps "highest seq per sender" and ignores repeats so PDR isn't inflated (`probe_is_duplicate()`, line 97). But for the wormhole-marked copy it **deliberately skips de-dup** (`probe_data_cb()`, comment lines 312–320), so **both arrivals of the same probe survive into the log**. That surviving duplicate — and the tiny latency gap between the two arrivals — is the wormhole signature.

### What the monitor sees (the signature — verified by direct count)
From the raw `arrivals.csv`: **2,797 arrivals, 2,616 unique → exactly 181 duplicate copies, every one from a single source MAC** (`F4:2D:C9:73:E6:18`, the tunnelled node). The other three victims show **zero** duplicates. Clean, one-node doubling — precisely what a wormhole produces.

> Have this ready: an integrity checker once flagged a *perfect* wormhole run as "broken" because it assumed attacks mean **fewer** packets. A wormhole means **more** (duplicates). That's a great story to tell — it shows you understood the attack's real behaviour well enough to fix a tool that didn't.

---

## 3. Why these two attacks (if asked)
They're the two cleanest, opposite routing threats:
- **Blackhole breaks forwarding** — "what you receive, you forward."
- **Wormhole breaks topology** — "closer nodes have stronger signal"; it fakes a shortcut.

One attacks the *flow* of packets, the other the *shape* of the network. Together they cover both categories; grayhole, Sybil, etc. are out of scope by design.

---

## 4. The three-line summary to close on
- **Blackhole** = one node quietly stops forwarding during the attack window; its own counters (received≫forwarded, hundreds dropped) prove it's deliberate, and zero re-routing proves it's not a crash.
- **Wormhole** = two boards joined by a real wire replay each probe to the root, which logs it twice on purpose; 181 duplicates from one MAC is the signature.
- **Both** = we implement the *behaviour and its cross-layer footprint*, which is faithful to the real attack, because the ESP32's closed stack blocks the routing-level mechanism — and behaviour is exactly what a dataset is meant to capture.
