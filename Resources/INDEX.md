# Resources — workstation-owned reference (domain-specific)

<!-- Unlike 0_Resources/ (cross-workstation, never domain-specific), everything
     here belongs to THIS thesis only. Not auto-loaded — routed to on demand,
     same spirit as 0_Resources/INDEX.md. -->

## reference/ — standing reference docs (still live for Thesis 3)
| File | Read when… |
|---|---|
| `ATTACK-MECHANICS.md` | Explaining what the blackhole/wormhole attacks actually do vs. Espressif's routing internals — panel-spoken form |
| `OUTPUT-VERIFICATION.md` | Checking whether a milestone's outputs are actually correct against real files |
| `NODE-INVENTORY.md` | Mapping a physical board ↔ MAC ↔ COM port ↔ run role |

## figures/ — topology diagrams
| File | Read when… |
|---|---|
| `linear_topology_blackhole.png` / `.svg` | Need the linear-chain blackhole topology figure (paper figures, slides) |

## Why these moved here (sep. 12, 2026)
Previously sat loose at the workstation root. Moved into `Resources/` (this
workstation's own domain-specific folder) rather than `0_Resources/` — that
folder is reserved for resources shared *across* workstations, and these are
NIS16-thesis-specific. See `MEMORY.md` for the dated decision.
