# Verification: tree wormhole firmware now runs partial's mesh logic, and nothing else changed (D-41)

**Date:** oct. 23, 2026
**Verdict:** ✅ CONFIRMED (all 4 sub-claims)

## The claim

Before committing D-41 (`TREE_WH_AS_PARTIAL`):

1. Tree + wormhole builds now run exactly partial's mesh logic.
2. Partial wormhole builds are unchanged.
3. Tree blackhole and tree baseline builds are unchanged.
4. The four tree wormhole variants (root, A, B, victim) compile with 0 warnings.

## What this means (plain language)

The code change does what it says: a tree wormhole board now forms the mesh exactly as a partial wormhole board does, and every other firmware (partial, tree blackhole, tree baseline) compiles to the same code as before. It is NOT proven on hardware: partial with leaf tunnel ends (D-36) has never run on boards, and today's failures were caused by board B0:18 and the UART wiring, which no firmware change touches.

## Evidence

Method: `mesh_setup.c` was run through the ESP32 compiler's preprocessor (`xtensa-esp32-elf-gcc -E -P`, the exact include paths and defines from the build's `compile_commands.json`), once per firmware type, for the new source and for the HEAD (`78ac088`) source. The preprocessor output is the code that actually gets compiled once every `#if` is decided, so comparing it shows real behaviour differences, not comment or layout changes. The file/line numbers that `ESP_ERROR_CHECK` embeds were normalised out. Script: scratchpad `pp_compare.py` + `pp_compare_tree_other.py`.

- **Partial wormhole, HEAD vs new: 0 differing lines** — claim 2: partial compiles to identical code.
- **Tree wormhole new vs partial wormhole new: 25 differing lines, all non-mesh** — the topology label (`topo_kind_str(1)` vs `(3)`, used in log text and the SD folder name "tree"), the new `TREE WORMHOLE (D-41)` log line, and the root's partial-only `entry_note_parent()` (the root remembers each board's past parents for its report; it does not steer the mesh). Claim 1: every mesh-forming call is identical.
- **Tree wormhole HEAD vs new: 45 differing lines** — `max_children = 10` -> `2`; `esp_mesh_set_ap_assoc_expire(30)` -> `(10)`; D-26 sticky-parent block removed; `sc.channel = 11` (D-39) removed; B's exact-depth rule (`me != peer_layer + 2`, `min_layer + 1`) and D-37's 6-scan fallback replaced by partial's `me <= peer_layer` / "at least as deep as A". These are exactly the intended changes.
- **Tree blackhole (`ACTIVE_ATTACK=1`) HEAD vs new: 0 lines; tree baseline (`ACTIVE_ATTACK=255`) HEAD vs new: 0 lines** — claim 3.
- **Clean builds, IDF 5.3.5, from scratch in `C:\esp32b\d41`** (`build.log`): ROOT / A / B / VICTIM tree wormhole each `exit=0 warnings=0 errors=0` — claim 4. Root, A and B ELFs contain the string `TREE WORMHOLE (D-41)` and none of `D-38, encrypted` / `STICKY PARENTS (D-26)`.
- **Built copy = repo working tree:** `cmp` of `components/mesh_common/src/mesh_setup.c` and `components/mesh_common/include/mesh_config.h` against the build copy: identical.

## Conflicts between sources (if any)

- STATUS/MEMORY D-40 (oct. 23 ~3 PM) recorded tree wormhole at fan-out 10 with D-37/D-38/D-39 kept; D-41 supersedes that for tree wormhole only (user's decision, oct. 23 ~4:30 PM).
- Paper Fig. 4.18 (tunnel skips 2 hops, A H01 -> B H03) no longer matches what the tree wormhole firmware enforces - checklist A44.

## What remains unverified

- Hardware: no run yet on D-41 firmware. The partial wormhole PASS runs (oct. 21 + oct. 22 5:08 PM) predate D-36 leaf ends (oct. 22 6:30 PM), so partial + leaf ends is itself unproven on boards.
- Only IDF 5.3.5 was compiled here; the repo's sdkconfig targets IDF 5.5.4 (other laptops).
- Only `mesh_setup.c` was compared; it is the one file holding topology-specific mesh logic (`MESH_TOPOLOGY` is private to mesh_common; `sd_status.c` uses it only for folder names).

## Sources

- `ESP32-Environment/components/mesh_common/include/mesh_config.h` — `TREE_WH_AS_PARTIAL` switch (D-41)
- `ESP32-Environment/components/mesh_common/src/mesh_setup.c` — `TREE_AS_PARTIAL` macro and the five gated spots
- `C:\esp32b\d41\build.log`, `C:\esp32b\d41\pp\*.i` — build output and preprocessed code (local to Basti's laptop)
- `ESP32-Environment/docs/deviations-limitations/thesis-deviate.md` D-41; checklist A44; dataset-verification #86/#87
