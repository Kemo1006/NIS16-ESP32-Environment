# Wormhole Attack — build, wire, run, verify (Milestone 2)

This is the **wormhole** half of Milestone 2 (the blackhole half is a teammate's
module). It emulates a wormhole at the application layer — no raw 802.11 frames —
using two attacker boards joined by a **wired UART tunnel**, the out-of-band
channel that makes it a wormhole rather than ordinary mesh forwarding.

## What happens during the wormhole phase

```
                    slow legitimate multi-hop path
   ┌─────────┐  probe  ┌──────────────────────────────┐  ┌──────┐
   │ Victim  │────────────────────────────────────────►│ Root │
   └────┬────┘                                          └──────┘
        │ capture-copy (P2P, only in wormhole phase)        ▲
        ▼                                                    │ fast
   ┌──────────┐   {seq,src,ts} over UART   ┌──────────┐  replica
   │Attacker B│──────────────────────────► │Attacker A│──────┘
   │near victims│   CRC-framed tunnel       │ near root │
   └──────────┘                            └──────────┘
```

* The victim keeps sending its probe to root normally (the **slow** copy).
* During the wormhole phase it *also* unicasts a capture-copy to **Attacker B**.
* **B** ships `{seq_num, src_mac, send_ts_us}` to **A** over the UART tunnel
  (CRC-16/CCITT protected — see `components/mesh_common/src/wormhole.c`).
* **A**, sitting one hop from root, rebuilds a replica probe with the *original*
  identifiers and re-injects it to root (the **fast** copy).
* **Root** logs the same `(src_mac, seq_num)` **twice** in `arrivals.csv`, with a
  measurable latency mismatch — the wormhole signature.

## Hardware

**Minimum for a wormhole run:** 4 boards — root + 1 victim + Attacker A + Attacker B.
**Recommended (and what M3's topologies want):** 6 boards — 1 root + 2–3 victims +
Attacker A + Attacker B. The milestone form asks for **5–10 nodes** per topology,
so 6–8 is the sweet spot. You need **exactly 2 attacker boards** for the wormhole
regardless of topology.

## Wiring the UART tunnel (ESP32 DevKitC, UART2)

| Attacker A | ↔ | Attacker B |
|-----------|---|-----------|
| TX = GPIO17 | → | RX = GPIO16 |
| RX = GPIO16 | ← | TX = GPIO17 |
| GND | — | GND (common ground REQUIRED) |

Data only flows B→A, but wire both directions + a shared ground for a clean link.
Pins/baud are in `mesh_config.h` (`WORMHOLE_UART_*`).

## One-time setup: tell the victims where B is

1. Flash `attacker_b_node` once and read the `NODE_XXXXXXXXXXXX` line it prints at
   boot — those 6 hex bytes are B's STA MAC.
2. Put them in `mesh_config.h`:
   ```c
   #define WORMHOLE_ATTACKER_B_MAC { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }
   ```
   (Left at the all-zero placeholder, victims simply skip the capture-copy.)
3. Rebuild the victim(s) so they pick up the MAC.

## Build & flash (per board, from the ESP-IDF 5.3 PowerShell)

For a wormhole run in, say, the **tree** topology (`MESH_TOPOLOGY=1`,
`ACTIVE_ATTACK=2`):

```powershell
cd root_node
idf.py -DMESH_TOPOLOGY=1 -DACTIVE_ATTACK=2 -p <ROOT_PORT>  flash monitor
cd ../victim_node
idf.py -DMESH_TOPOLOGY=1 -p <VICTIM_PORT> flash monitor
cd ../attacker_a_node
idf.py -DMESH_TOPOLOGY=1 -p <A_PORT> flash monitor
cd ../attacker_b_node
idf.py -DMESH_TOPOLOGY=1 -p <B_PORT> flash monitor
```

The root drives the timeline: 60 s stabilise → 300 s baseline → **180 s wormhole**
→ 120 s cooldown → terminate. Only the root needs `-DACTIVE_ATTACK`.

`tools/run_matrix.py --build-cmds --topology tree --attack wormhole` prints these
commands for you.

## Export & verify

After terminate, close every monitor, then from `tools/`:

```powershell
python export_logs.py --port <ROOT_PORT> --role root       --topology tree --attack wormhole --repeat 1
python export_logs.py --port <VICTIM_PORT> --role victim    --topology tree --attack wormhole --repeat 1
python export_logs.py --port <A_PORT> --role attacker_a     --topology tree --attack wormhole --repeat 1
python export_logs.py --port <B_PORT> --role attacker_b     --topology tree --attack wormhole --repeat 1

python analyze_wormhole.py --topology tree --repeat 1
```

`analyze_wormhole.py` confirms the three Milestone-2 wormhole criteria: duplicate
arrivals in the attack window, a measurable latency mismatch, and no leakage into
the baseline/cooldown windows.

## Sanity checks if the signature doesn't appear

* **A's console shows `injected=0`** → no tunnel frames arrived. Check the UART
  wiring (TX↔RX crossed, common GND) and that both boards booted `wormhole` build.
* **B's console shows `captured=0`** → victims aren't sending the capture-copy.
  Confirm `WORMHOLE_ATTACKER_B_MAC` matches B's STA MAC and the victims were
  rebuilt after setting it.
* **CRC mismatch warnings on A** → loose jumper or wrong baud; reseat and retry.
* **Duplicates appear in baseline too** → you exported a *stacked* file from an
  un-wiped board; wipe with `run.ps1 -Wipe` (or `export_logs.py --delete`) and
  re-run so each CSV holds a single run.
