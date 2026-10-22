# Verification: pinning wormhole B's parent in the TREE topology still follows the thesis

**Date:** oct. 22, 2026
**Verdict:** 🔶 PARTIALLY CONFIRMED — pinning B under a **hop-2 victim** (B at hop 3) matches the thesis's tree wormhole design (Figure 4.18) and has a precedent already in the paper (blackhole star). Pinning B under a **hop-1 victim** (B at hop 2, e.g. under 1C:38) does NOT match Figure 4.18. Either way, two paper sentences must be edited, because the paper still says the tree "uses the default self-organization".

Source read: `Plan/Paper-Editing/1-Working-Copy/All_in_one_CTHESIS3_no_jitter_8boards v4 (Chapter 5 merged and checked, oct. 21, 2026).docx` (newest paper file), text extracted from `word/document.xml`. Line numbers below are paragraph numbers in that extract.

## The claim

A new tree-only option that pins the board flashed as wormhole B to one named victim as its parent (so B sits in a different branch, away from A) still follows the thesis.

## What this means (plain language)

The thesis's own tree wormhole figure puts A at hop 1 and B at **hop 3**, with B's normal traffic climbing "through legitimate intermediate nodes". Our runs had B at hop 2 directly under A, which does not match that. Pinning B to a victim that is itself at hop 2 (ED:80 or D7:B4 in your layout) produces exactly the figure. Pinning B to a hop-1 victim like 1C:38 is better than "under A" but still puts B at hop 2, not hop 3. The paper also needs two small wording edits, because it currently says the tree is fully self-organised, which was already untrue after D-30 (B barred from the root, pushed oct. 19).

## Evidence

- **Para 1925-1926, Figure 4.18 (Wormhole Attack on Tree Topology):** "Attacker A is positioned at hop 1 near the root, while Attacker B is positioned at hop 3 near the leaf nodes. The physical separation ensures that baseline communication between these regions requires traversing multiple layers through legitimate intermediate nodes. During the baseline phase, probes from Attacker B follow the natural multi-hop path up the tree." This is the target shape: B at hop 3, its normal copy relayed by victims. B under A (old runs) breaks "through legitimate intermediate nodes"; B under a hop-1 victim gives hop 2, not hop 3; B under a hop-2 victim gives exactly hop 3.
- **Para 1628, Figure 4.8:** "Attacker A … positioned shallower in the mesh, nearer the root … Attacker B … positioned deeper, toward the leaf nodes." This is satisfied by any pin deeper than A.
- **Para 439 (scope):** "neither changes how ESP-WIFI-MESH chooses parents or builds routes … for the same reason the position of the attacker in the mesh is an experimental variable." This **supports** fixing B's position (it is a controlled variable). The "neither changes how … chooses parents" part refers to the attack behaviour (the tunnel and the dropping), not to setup. A pin is set at boot, before Phase 0, so the attack itself still changes no parent. It needs one clarifying clause (see below).
- **Para 1920, Figure 4.17 (blackhole star), already in the paper:** "The victims are configured to join the attacker directly and never join the root, so that the star structure and the attacker position are fixed." This is a **precedent**: configured parents to fix the attacker's position are already accepted method text (D-16/D-28, the same `esp_mesh_set_parent()` mechanism).
- **Para 960:** "The mesh stack does not use the tunnel for routing, so it causes no parent switches or hop-count changes." This still holds: the pin is not the tunnel and is fixed before the run.
- **Para 1623 (D-17):** the ends are named by depth at run time. With B pinned deeper than A, auto-switch keeps the flashed B as B, so this is consistent.

## Conflicts between sources

- **Para 1902:** "The tree uses the default self-organization." This was **already contradicted** by the pushed firmware (D-30: B never joins the root, oct. 19; B never joins A, oct. 22), and a pin contradicts it more. The paper never got D-30's planned sentence (searched the extract for "associate with the root", "not allowed to", "strongest other node": no hits). **The code wins (it is what produced the data), so the paper must be edited.**
- **Para 1616 (Attacker B "near the victim leaf nodes … Victim nodes send their probe packets to Attacker B, which acts as the designated relay"):** older wording. Neither the current firmware nor a pin makes B a relay for victims. This is not caused by this change, but it is worth fixing in the same edit.

## Paper edits needed if the pin is adopted

1. Para 1902, after "The tree uses the default self-organization": add "except for the wormhole entry node B, which is configured to join a named hop-2 board, so that it sits at hop 3 as in Figure 4.18 and never under the root or Node A (D-30)."
2. Para 1926 (Figure 4.18): "Attacker B is positioned at hop 3 near the leaf nodes" → add "by configuring its parent, as the victims are in the blackhole star."
3. Para 439: make clear that "neither changes how ESP-WIFI-MESH chooses parents" refers to the attack behaviour; the attackers' positions are fixed by placement and configuration before the run.
4. The deviation log entry (D-30 addition) and THESIS-UPDATE-CHECKLIST, marked **Adviser check**, as for D-16/D-28.

## What remains unverified

- Whether the adviser accepts a configured parent in the tree (the star hub design is itself still marked "needs the adviser's approval", para 1916).
- Whether B can hear a hop-2 victim at all with the UART cable keeping A and B close. B only needs to hear that victim, not hear it loudest.
- Tree wormhole captures already taken had B under A (hop 2); against Figure 4.18 they are not the designed shape.

## Decision taken (same day)

The user chose a hop-2 victim, then a firmware RULE over an exact MAC pin: in tree wormhole builds B's parent must be at exactly H02, so B is always at H03. It meets Figure 4.18 every run without preset/wizard/GUI changes, and keeps working when the H02 victim is on another laptop. The paper edits listed above still apply ("configured to join a hop-2 board" instead of a named board).

Final form (later the same day, after the user found the first version reached partial builds): `WH_B_TREE_DEPTH` in `mesh_setup.c` only — B's parent must be exactly one hop below A (H02 while A is at H01), which also keeps A itself from ever being B's parent, with no MAC needed. Partial and star now compile exactly the pre-oct. 22 code: preprocessing `mesh_setup.c` old vs new with the real partial and star compile flags gives 0 differing lines (7239 / 7221 lines each); tree differs by 16 lines.

## Sources

- Paper v4 extract, paras 439, 960, 1616, 1623, 1628, 1902, 1916, 1920, 1925-1926
- `ESP32-Environment/docs/deviations-limitations/thesis-deviate.md` D-16, D-28, D-30
- `ESP32-Environment/components/mesh_common/src/mesh_setup.c` star-hub pin (`STAR_HUB`, `esp_mesh_set_parent`): the mechanism a pin would reuse
