# docs/ — index by topic (sep. 30, 2026)

One folder per thing an adviser or panelist can ask about. Open the folder whose
question you were just asked; don't browse the whole tree. Nothing in the moved
files was edited — only their location changed.

## If you are asked about the attacks

| Folder | The question it answers | Files |
|---|---|---|
| `blackhole/` | How is the blackhole staged, and what must its signature show? | `2026-09-14_BLACKHOLE.md` |
| `wormhole/` | How is the UART tunnel built, and why are duplicate arrivals the signature? | `2026-09-14_WORMHOLE.md` |
| `attack-validation/` | "How do you know it is *really* a blackhole/wormhole?" | `ATTACK-VALIDATION.md` (conformance vs Karlof & Wagner 2003 and Hu-Perrig-Johnson 2003, **including the criteria we fail**), `2026-09-15_VERIFY.md` (the 3-sigma verifier runbook) |

Wormhole **wiring** trouble is not here — it is in `issues-and-fixes/SD-CARD-AND-WORMHOLE-WIRING.md`,
because the panel asks about it as a hardware struggle, not as an attack design.

## If you are asked about a result that looks wrong

| Folder | The question it answers | Files |
|---|---|---|
| `highload-collapse/` | Why did r3 (7 nodes) fail verification? | `COOLDOWN-RECOVERY-2026-09-30.md` — the attack is the best ever captured (all 5 victims at PDR 0.000); the run fails because the mesh never recovers during cooldown, and §10 shows a **no-attack** 7-board highload run collapsing the same way. So the collapse is congestion from 7 boards × 4 probes/s through one relay, **not** the blackhole. Working file — add to it, don't start a new one |
| `dataset-integrity/` | Is the dataset trustworthy? What went wrong in a capture? | `DATASET-AUDIT-2026-09-18.md` (G402 folders mixed six runs under r1; placeholder zeros), `SESSION-REPORT-2026-09-25.md` (the sep. 24 incident, what the root's own data proved, and the firmware fix) |
| `data-and-results/` | What does this column mean? What should a good run look like? | `DATA-DICTIONARY.md` (schema v1 vs v2, what the manuscript gets wrong, clocks), `EXPECTED-RESULTS.md` (real measured numbers per phase, the verifier output to expect, why NaNs are not bugs, red flags) |

## If you are asked for evidence outside our own logs

| Folder | The question it answers | Files |
|---|---|---|
| `packet-capture/` | "What protocol does the ESP32 use?" / can you show it independently? | `WIRESHARK-QUICKSTART.md` (read a capture), `WIRESHARK-TERMS.md` (what every word on screen means; the retry rate off the status bar), `WIRESHARK-GUIDE.md` (what a sniffer can and cannot see on an encrypted mesh) |

⚠️ The mesh is on **channel 11**. A sniffer on any other channel writes an empty file while
looking perfectly healthy.

## If you are asked what went wrong / what changed

| Folder | The question it answers | Files |
|---|---|---|
| `issues-and-fixes/` | "What problems did you run into?" | `INDEX.md` (the map — start here), `esp32-issues.md` + `-Part2` + `-Part3` (I-001…I-017, each with Status / Symptom / Cause / Fix), `SD-CARD-AND-WORMHOLE-WIRING.md` (board mix-ups, wrong power pin, SPI clock — in Q&A form) |
| `deviations-limitations/` | "Why does this differ from your proposal?" | `thesis-deviate.md` — D-1…D-15, each with what changed and why. Volunteer these rather than let a panelist find them |
| `progress-reports/` | What was done when? | dated CTTHES2 milestone reports, jul. 2026 |

## Everything else

| Folder | What it is |
|---|---|
| `operations/` | How to actually run the study — `2026-09-14_START-HERE.md` (read first), `MENU-WALKTHROUGH`, `SETUP-RULES-CONFIG`, `SD-CARD`, `LOCATIONS`, `2026-09-14_BASELINE.md`, `2026-09-14_TOPOLOGIES.md`. Not panel material; kept out of the way of it |
| `references/` | `2026-09-14_REFERENCES.md` — the tiered citation list (Tier 1 load-bearing → Tier 4 supporting) |
| `_archive/` | Superseded guides, runbooks and setups. Left exactly as it was, so "superseded" stays visible. Do not cite from here |

## Two honest limitations to have ready

These are in `issues-and-fixes/INDEX.md` in full, but they are the ones most likely to be asked:

- **Attack evidence is partly circular** — the blackhole attacker counts its own drops. The sniffer
  capture in `packet-capture/` is what starts to answer this independently.
- **Every attack and traffic parameter is a compile-time constant** — no runtime intensity change,
  and the attacker cannot move without reflashing every board.
