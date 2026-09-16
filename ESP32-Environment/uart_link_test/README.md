# uart_link_test — wormhole UART wire loopback test

A tiny **standalone** ESP-IDF app (not part of the mesh firmware) that verifies the
physical UART tunnel wire between the two wormhole attacker boards **in seconds**,
so you never have to sit through an 11-minute run to find out the wire is dead.

## Why it exists

The wormhole tunnel is a **wired UART link** between Node A and Node B
(TX2/GPIO17 ↔ RX2/GPIO16, crossed, + shared GND). If that wire is wrong — a
missing GND, or straight-through instead of crossed — the tunnel **silently
delivers nothing**: Node A's `probes_count` stays 0 and the root shows no
duplicate signature. You only discover this after a full run + export + analysis.
This test catches it up front.

## What it does

Both boards run the same firmware. Each one continuously **sends** a `LINKPING`
out its TX pin (GPIO17) and **listens** on its RX pin (GPIO16). If a board
receives pings, the wire feeding *that board's* RX works. When both boards are
running and correctly wired, **both print `[LINK OK]`**.

## How to use

```powershell
cd uart_link_test
idf.py set-target esp32          # once
idf.py -p COM26 flash monitor    # Node A board — press Ctrl+] at the banner
idf.py -p COM27 flash monitor    # Node B board — WATCH this one
```

Read the output:

| Output | Meaning |
|---|---|
| `>>> RX OK ... [LINK OK]` | ✅ wire good — proceed to the real wormhole run |
| `RX received=0` (stays 0) | ❌ wire feeding that board's GPIO16 is dead — check GND and the crossing |

**Isolation tip:** if it fails, jumper one board's own TX2→RX2 (self-loopback) —
if that shows `[LINK OK]`, the board is fine and the fault is the wire between
the boards; if it stays 0, that board's RX pin / labels are the problem.

## Pins (match `WORMHOLE_UART_*` in `mesh_config.h`)

```
Node A TX2/GPIO17 → Node B RX2/GPIO16
Node A RX2/GPIO16 → Node B TX2/GPIO17
Node A GND        → Node B GND        (do NOT skip — UART fails silently without it)
```

> ⚠️ On WROVER (PSRAM) boards GPIO16/17 are reserved by the PSRAM chip. Change
> `TX_PIN`/`RX_PIN` in `main/uart_link_test.c` (and `WORMHOLE_UART_*` in
> `mesh_config.h`) to a free pair before wiring.

## After testing

This overwrites the board's firmware, so re-flash the real wormhole firmware
(`run.ps1 ... -Attack wormhole -WormholeEnd A/B`) before the actual run. Leave the
3 tunnel wires connected.
