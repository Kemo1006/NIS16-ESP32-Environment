# NIS16 — Board / Node Inventory (running log)

Physical ESP32 boards by MAC, so you can name any node in a run. MAC (STA) is the board's true identity; the softAP MAC is always +1 (e.g. `…fe:90` → `…fe:91`). Built from flash logs on jul. 26–27, 2026 (linear-chain prep). Extend as more runs come in.

| Label | STA MAC | Node ID | Usual role | Notes |
|---|---|---|---|---|
| node2 | `b4:bf:e9:34:ed:80` | NODE_B4BFE934ED80 | victim (child) | tail of the linear chain in the jul-26 blackhole run |
| node3 | `70:4b:ca:25:b7:68` | NODE_704BCA25B768 | victim (child) | |
| node4 | `b4:bf:e9:32:fe:90` | NODE_B4BFE932FE90 | victim (child) | |
| node5 | `b0:cb:d8:f3:32:18` | NODE_B0CBD8F33218 | **attacker** | wormhole Attacker A here; was the blackhole attacker (layer 2) in the jul-26 run — **same physical board is the attacker across runs** |
| root | `28:05:…:D7:B4` (from jul-26 log) | — | root | experiment controller / receiver |

## Build-flag decoder (the `-D...` values in the monitor command)
- `ACTIVE_ATTACK=255` → **no attack** (baseline/control build). node2/3/4 above.
- `ACTIVE_ATTACK=2` → **wormhole** build. node5 above.
- `WORMHOLE_END=0` → tunnel **End A** = root-side "exit" endpoint (injects tunneled probes toward root). `=1` would be End B (leaf side).
- `MESH_TOPOLOGY=2` → **linear** chain.
- Firmware banner confirms role: `=== VICTIM NODE STARTING ===` vs `=== WORMHOLE NODE A (exit) STARTING ===`.
- `Role: 1` in `MESH_SETUP` = child/victim role in the mesh.

## How the linear topology is forced
`MESH_SETUP: Topology shaping: LINEAR (max_layer=7, max_children=1)` — each node accepts **only one child** (`max_children=1`), so the self-organizing mesh is constrained into a single chain up to 7 layers deep. That's the answer to "how do you make a linear topology on an auto-forming mesh?"
