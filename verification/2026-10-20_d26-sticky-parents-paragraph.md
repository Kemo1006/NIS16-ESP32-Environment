# Verification — paper paragraph on D-26 sticky parents (oct. 20, 2026)

**Paragraph (paper v3, §4.2.2 tree topology):** "The tree children keep their parent unless the link degrades
substantially: ESP-WIFI-MESH's own parent-switch and weak-link thresholds are moved 6 dB lower and its weak-link
watch lasts three times longer, while the first choice of parent is unchanged and the loss of a parent still makes
its children move (D-26). Tree runs captured before this change used the stock thresholds, and this change is not
yet confirmed on hardware."

**Evidence:** `components/mesh_common/src/mesh_setup.c:37-58, 340-363` (HEAD `f22ee5cd`, unchanged by
`fee82b71`); ESP-IDF header `components/esp_wifi/include/esp_mesh_internal.h:42-61` (v5.3.5 and v6.0.1 read
identically); `thesis-deviate.md:448-458`; `STATUS.md:26`; `MEMORY.md:37`; `dataset-verification.md:149` (#66).

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Thresholds moved 6 dB lower | ✅ | `cnx_rssi -= 6`, `switch_rssi -= 6` on the values read at boot (`STICKY_PARENT_DB 6`) |
| 2 | Weak-link watch ×3 | ✅ | `duration_ms *= 3`; header: "parent weak RSSI monitor duration" |
| 3 | First choice of parent unchanged | ✅ | `select_rssi` and the `mesh_rssi_threshold_t` bands are not touched (narrowed in `f786c07`) |
| 4 | Parent loss still moves children | ✅ | ordinary tree children stay self-organised; only the root and the D-30 wormhole ends are pinned (`mesh_setup.c:295, 565`) |
| 5 | Names "parent-switch and weak-link thresholds" | 🔶 | ESP-IDF calls `cnx_rssi` the threshold "for keeping a good connection with parent"; its own weak-RSSI threshold is `mesh_rssi_threshold_t.low` (default -85 dBm), which is **not** changed |
| 6 | "keep their parent unless the link degrades substantially" | 🔶 intent, not shown | header: switch to a new parent "when the RSSI is greater than" `switch_rssi` — lowering it makes a candidate parent acceptable sooner once a search starts, i.e. that half pushes toward switching. Libmesh is closed source, so the net effect can only be measured on hardware |
| 7 | Runs before the change used stock thresholds | 🔶 | true for runs before oct. 19 ~11 AM; the oct. 19 2:21 PM G402 highload run used the first D-26 version (selection lowered too, MEMORY.md:37); the oct. 19 evening G402 burst/highload runs had 4 of 8 boards on older firmware (#66) |
| 8 | Not yet confirmed on hardware | ✅ | `thesis-deviate.md:456` "not yet tested on hardware"; `STATUS.md:26` lists D-26 as pending |

**Suggested wording:** "In tree runs the children's hold on their parent is relaxed: ESP-WIFI-MESH's
keep-connection and parent-switch RSSI thresholds are lowered by 6 dB and its weak-parent watch lasts three times
longer, while the first choice of parent is unchanged and the loss of a parent still makes its children move
(D-26). The intended effect is that a child keeps its parent unless the link degrades substantially; the G402
burst and highload tree captures ran on boards with mixed firmware, earlier tree runs used the stock thresholds,
and the effect is not yet confirmed on hardware."

## Re-check after "the member fixed it" (oct. 20, 2026, ~11:30 PM)

- **GitHub:** nothing newer than `f22ee5cd`. No commit touched the D-26 block after `f786c070` (oct. 19, 5:33 PM,
  "D-26 no longer changes parent SELECTION (it flattened trees)"). That is the fix; the paper already describes it.
  Later firmware commits (`4a8488df`, `6fb00803`, `c461711a`) are SD logging, crash/IPC and board-health only.
- **Real stock values (board boot log, `run_logs/blackhole/tree/G402/highload/…oct19_0221PM.log:293`):**
  `watch 60000->180000 ms, keep -120->-126, select -78->-84, switch -78->-84 dBm` (first D-26 version).
  ESP-IDF's stock `cnx_rssi` is **-120 dBm**, and its header says the parent-RSSI monitor is armed only
  "if set a value greater than -120 dBm". Moving it to -126 leaves the monitor off → **the "keep" change is a
  no-op.** `switch_rssi` -78 → -84 makes a new parent acceptable sooner (header: switch "when the RSSI is greater
  than" it). The only change that pushes toward staying is the watch ×3 (60 s → 180 s).
- **No boot log of the fixed version exists** (only the 2:21 PM run printed D-26 lines, all 3 boards on the first
  version). The oct. 19 evening serial logs are empty `.err` files.
- **Datasets — parent changes inside the labelled phases (raw telem, non-root boards):**

| Tree cell | Captured | Boards | Boards that changed parent | Max layer |
|---|---|---|---|---|
| blackhole DLSU burst / highload / stationary | oct. 11-12 | 7 each | 0 / 0 / 0 | 4 |
| blackhole Yuchengco burst / highload / stationary | oct. 11-12 | 7 each | 1 / 0 / 0 | 4 / 4 / 3 |
| blackhole G402 stationary | oct. 18 | 7 | 1 | 4 |
| wormhole DLSU stationary | oct. 16 | 7 | 0 | 4 |
| **blackhole G402 burst (after fix)** | oct. 19 pm | 7 | **0** | 3 |
| **blackhole G402 highload (after fix)** | oct. 19 pm | 6 | **0** | 3 |

  Runs after the fix: no parent change and not flat (3 layers), so the fix did undo the flattening. But runs
  WITHOUT D-26 also had 0-1 changes, so the data cannot show D-26 keeping parents. Still not confirmed.

**Updated suggested wording:** "In tree runs a child waits three times longer (180 s instead of 60 s) on a weak
parent before it looks for another, while its first choice of parent is unchanged and the loss of a parent still
makes its children move (D-26). Tree runs captured before this change used the stock settings. The two G402 tree
captures made after it show no parent change during the experiment, but tree runs without the change rarely
showed one either, so its effect is not yet confirmed."

**For the code owner:** the `cnx_rssi -= 6` line has no effect at the stock -120 dBm, and `switch_rssi -= 6`
probably works against stickiness — worth a look before D-26 is tested on hardware.

Read-only check; no paper or code change made.
