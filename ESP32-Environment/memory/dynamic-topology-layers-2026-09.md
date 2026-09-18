# Dynamic layer assignment, no hardcoded topology limits (sep. 17, 2026)

Trigger: an 8-board LINEAR run only showed 7 nodes. Cause: `MESH_MAX_LAYER 7`
in `components/mesh_common/include/mesh_config.h` - in chain mode every board
takes its own layer, so board 8 had no layer left to join. User asked for a
full audit and removal of every hardcoded layer/node-count assumption across
all four topologies (star/tree/linear/partial), with layers derived from the
actual graph instead, and topology-appropriate strictness when checking a
captured run.

## What was actually hardcoded (full inventory)

Not just the one constant - also fixed at 32 nodes: the root's heartbeat/node
table, the phase-broadcast routing-table buffer; fixed at 16: the probe
duplicate-filter table; the heartbeat's `layer` field was `uint8_t` (would
wrap past 255); `tools/verify_topology.py`'s star/linear/tree checks only
looked at layer counts, never the actual parent/child graph, so a genuine
branch in a "linear" run wouldn't fail; the fake-data generators
(`generate_fake_data.py`, `generate_eda_fake_data.py`) had fixed 3-node
layer/parent lists.

ESP-IDF's OWN ceilings (esp_mesh.h) are the only real limits left: tree/star/
partial topology maxes out at layer 25, chain (linear) at layer 1000, 10
children per node max. These can't be worked around - they're the ESP-WIFI-MESH
stack's actual limit, not this project's choice.

## What changed

**One shared rule set, in both C and Python** (kept in step deliberately):
`components/mesh_common/src/topology_graph.c` (+`.h`) and `tools/topology_graph.py`.
Layers = BFS depth from whichever node the parent links show has no parent AND
carries the most of the mesh (root is discovered, never assumed by ID/position).
Structural rules, not size limits:
- **star**: every node a direct child of center → max layer 2, any N. Violation = FAIL.
- **linear**: every node ≤1 child → chain of any length. Violation = FAIL.
- **tree**: one root, no cycles, any depth. Flat (depth ≤2) = WARN, not FAIL.
- **partial**: nodes seen under 2+ parents over the run (union of every parent
  link ever reported), not every pair linked (that's full mesh, also WARN).

STAR/LINEAR fail hard because the firmware itself enforces those shapes: a
violation means something is actually broken. TREE/PARTIAL only warn because
their shape depends on physical board placement, which this code can't control.

**Firmware**: `MESH_MAX_LAYER` replaced with `MESH_STACK_MAX_LAYER_TREE` (25)
/ `_CHAIN` (1000) - the topology's own ceiling, applied per-topology in
`mesh_setup.c`. Root's node table, phase-broadcast buffer, and probe-dedup
table all grow (realloc/doubling) instead of being fixed arrays. Heartbeat
packet now carries `parent_mac` (was missing entirely - previously the root
only knew EACH node's OWN reported layer, never the actual tree shape) and a
16-bit layer; magic bumped so an old-firmware board is named in a warning
instead of silently misread. Root's console table now prints the real
derived tree + `STATUS : OK/WARN/FAIL` and `DETAIL : reason` lines (was a
`TOPOLOGY CHECK:` line before the sep. 18, 2026 protocol-dump reformat), built
from the same topology_graph.c the tests exercise.

**Python**: `verify_topology.py` rebuilds the graph via `topology_graph.py`
instead of only counting layers; exits non-zero on a real FAIL. Fake-data
generators take `--topology`/`--nodes` and get layers/parents from
`topology_graph.synthetic_roster()` - any size produces a valid shape, root
always layer 1 (was inconsistently 0 in some fixtures, 1 in others).

## Verified

C module: 1222/1222 host-test checks (gcc, no ESP-IDF) across chains 3..1000
nodes, stars to 100, trees to depth 40, partial/full-mesh/cycle/missing-parent
cases. Python: 15/15 unit tests, same case matrix. Firmware: all 8 root/child
× topology combinations compile clean with `-Werror` (ESP-IDF 5.3.5, via
`C:\Espressif\Initialize-Idf.ps1 -IdfId esp-idf-b6a194b5a91072dd391c1b6ce749efc8`
- the plain `export.ps1` picks up the wrong system Python/cmake/ninja on this
machine, see [[reference-windows-ps1-ascii]]-adjacent gotcha, worth its own
memory if it bites again). Real 8-board linear export
(`tools/exports/blackhole/linear/G402/`) re-verified: correctly found board
`B0:CB:...18` (node5) never exported, root is `2805...`, chain below the gap
reconstructs cleanly.

## Not yet done

**Not bench-tested on real hardware at all** - every board needs re-flashing
together since the heartbeat wire format changed (v1 boards would only get a
warning, not be listed). `node_identity.c`'s hardcoded MAC→nickname table
still labels whatever board holds that MAC "Node-5-Attacker" regardless of
current role - same stale-label problem as the board_check.py fix in
[[wizard-prebuild-and-live-identify-2026-09]], not touched this pass.
`analysis/preprocess.py` discards 100% of windows from the regenerated fake
fixtures (expects 10Hz, fixtures are 1Hz) - confirmed pre-existing (the
original generator does this too), not caused by this change, not fixed.
