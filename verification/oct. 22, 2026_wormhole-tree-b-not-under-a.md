# Verification: wormhole B never takes A as parent, tree builds only

**Date:** oct. 22, 2026
**Verdict:** 🔶 PARTIALLY CONFIRMED — behaviour gating confirmed by reading the code; tree builds + host test confirmed by running them; partial/star builds were NOT re-compiled after the final edit.

## The claim

1. The change makes wormhole end B refuse A's mesh AP as parent **only in tree builds** (`WH_B_NOT_UNDER_A`).
2. Star and partial behaviour is unchanged.
3. It compiles cleanly for tree A / B / victim / root, and the auto-switch host test passes 79/79.

## What this means (plain language)

Only a tree wormhole build can ever learn A's address, and every new check needs that address, so partial and star boards run exactly the old logic. The tree firmware builds and the simulator passes. What nobody has seen yet is a real tree run on hardware, and the partial/star images were not rebuilt after the last edit (their behaviour is unchanged by construction, but "it compiles" is not proven for them).

## Evidence

- **`components/mesh_common/src/mesh_setup.c:169`** — `WH_B_NOT_UNDER_A` = `ACTIVE_ATTACK == PHASE_ID_WORMHOLE && MESH_TOPOLOGY == NIS_TOPO_TREE`: a compile-time switch that is true only for tree wormhole images.
- **`mesh_setup.c:1990-2008`** — the only place `s_wh_peer_ap_known` (the flag "B knows A's AP address") is set to true sits inside `#if WH_B_NOT_UNDER_A`. In partial/star images that code is not compiled, so the flag stays `false` (its initial value, `mesh_setup.c:179`).
- **`mesh_setup.c:749`, `:804`, `:2015`** — every new check (skip A in the scan, "still under A" log, re-pick when under A) starts with `s_wh_peer_ap_known && ...`, so with the flag false they never fire. `a_seen` (`:750`) is set only inside that check; the new log text at `:822` needs `a_seen`, so it is dead in partial/star too. `other_deep` (`:753`) is written but only read together with `a_seen`.
- **`mesh_setup.c:407`** — `s_pin_no_root` (B's "never the root" mode) is set only under `WH_B_NO_ROOT` (tree or partial). Star never enters that scan branch at all — unchanged.
- **Builds (IDF 5.3.5, clean `C:\esp32b\whB_check` / `whR_check`)** — `child tree B`, `child tree A`, `child tree victim`, `root tree wormhole`: all "Project build complete", zero `warning:`/`error:` lines.
- **Host test** (`tools/test_wormhole_autoswitch`, gcc `-Wall -Wextra -Werror`) — `79 check(s), 0 failure(s)`.

## Conflicts between sources

- `docs/deviations-limitations/thesis-deviate.md` D-30 previously listed "B may hang under A" as an accepted side effect; updated in the same change to say tree no longer allows it, partial still can.

## What remains unverified

- Partial and star images were not compiled after the final edit (star compiled OK before the tree-only gate was added). Behaviour there is unchanged by the code reading above.
- **No hardware run.** First tree run: B must log `joining non-root parent` with a victim's MAC, and the root's tree print must show B under a victim, not under A.
- `tools/test_wormhole_autoswitch/run_test.sh` breaks on paths with spaces (unquoted `-I`); gcc was run by hand with quoted paths.

## Sources

- `ESP32-Environment/components/mesh_common/src/mesh_setup.c:169, 178-179, 407, 723-753, 804, 822, 1987-2030`
- `ESP32-Environment/child_node/main/wormhole_victim.c:833` — passes A's MAC (`f->h.mac`) from the UART HELLO
- `ESP32-Environment/docs/deviations-limitations/thesis-deviate.md` D-30
