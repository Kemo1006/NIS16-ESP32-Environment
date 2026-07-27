# ⛔ partial · wormhole · r1 — INVALID, do not record

**Captured 2026-07-27 ~09:10–09:30. Kept for the record only. Must be re-run.**

## What went wrong

`node5` — the **wormhole Node A (tunnel exit)** — **never joined the mesh.**

```
node5 :   212 rows   layer = -1 on ALL 212 rows   phase 0 only   0.27 Hz
node6 :  9602 rows   layer normal                 phases 0/2/3   ~11 Hz
```

`layer = -1` means disconnected. It scanned for the full ~800 s and never
associated, so it never received a phase broadcast — which is why every row is
stamped phase 0.

## Why that invalidates the run

Node A is the tunnel **exit**: it reconstructs the replica probe and re-injects it
toward the root. With it out of the mesh there was nothing to re-inject, so the
attack never happened. The root's arrivals log confirms it:

| phase | rows | unique `(src_mac, seq_num)` | **duplicates** |
|---|---:|---:|---:|
| 0 baseline | 1437 | 1437 | **0** |
| **2 wormhole** | 720 | 720 | **0** ⛔ |
| 3 cooldown | 479 | 479 | **0** |

**Zero duplicates in the attack window.** A valid wormhole run shows ~180.

## ⚠️ Why this folder is dangerous

The other six files are individually clean and the arrivals file **validates
without error** — it simply contains no duplicates. So `--autorecord` would tick
this cell and put a wormhole cell with no wormhole in it into the dataset.

The only reason it wasn't recorded is that node5's first export returned 0 rows,
so the untrimmed-file guard in `run_matrix.py` refused.

## Before re-running

1. `python tools\board_check.py --port COM20 --wait 75` on node5
2. **Move node5 closer** to the root or to a branch head with a free child slot —
   partial mesh caps `max_children=2`, so a full parent forces it to reach further
3. **Watch the root monitor during formation.** You want:
   ```
   MESH_SETUP: Routing table updated — nodes in mesh: 6
   ```
   If it stalls at 5, stop and re-place. That check costs 30 seconds and would have
   caught this before the 11-minute run.
