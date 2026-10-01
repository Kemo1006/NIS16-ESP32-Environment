# Issues — panel Q&A: struggles along the way

<!-- One-stop map for "what problems did you run into?" Each row routes to
     where the real detail lives — some are written out here, some are
     already tracked elsewhere and just get pointed to (don't duplicate a
     log that's actively maintained in the code repo). -->

## Hardware bring-up (new track, adviser-requested)
- [SD-CARD-AND-WORMHOLE-WIRING.md](SD-CARD-AND-WORMHOLE-WIRING.md) — SD card reader
  integration and the wormhole UART tunnel wiring: board mix-ups, wrong power pin,
  SPI clock speed, in panel Q&A form. sep. 2026.

## Firmware / pipeline bugs — full detail lives in the code repo
The running **I-001 … I-017** log is in `NIS16-ESP32-Environment-semi-final/esp32-issues.md`
(+ `esp32-issues-Part2.md`, `-Part3.md`). Each entry has Status / Symptom / Cause / Fix.
Read there for any of these; highlights if a panelist pushes on "what's still open":
- **I-014** — a `preprocess.py` OOM traced to one corrupt `timestamp_us` sample; pipeline
  now guards against it, but *why* the firmware emitted the bad timestamp is still open.
- **I-013** — an ESP-IDF log line leaking into a telemetry CSV during export; pipeline
  drops the contaminated rows, but the export-side leak itself isn't fixed yet.
- **I-012** — Windows USB selective suspend silently dropping a board's serial port
  mid-flash; fixed at the power-plan level (per-device Device Manager fix doesn't stick
  across re-enumeration).
- **I-017** — full SPIFFS quietly collapsing write speed and corrupting CSV rows;
  root cause was `DELETE_LOGS` never reclaiming space, fixed by formatting on wipe.

## Methodological / design limitations — not bugs, deliberate scope calls
These are honest limitations we chose to volunteer rather than let a panelist "discover":
- **Attack evidence is circular** — the blackhole attacker counts its own drops; no
  independent observer yet. (`MEMORY.md`, `ATTACK-MECHANICS.md` §1.)
- **Dataset is trivially separable** — role-gated features are non-NaN only for the
  attacker's own role, so "is this column NaN?" is a near-perfect label. (`MEMORY.md`
  panel P1.)
- **Every attack/traffic parameter is a compile-time constant** — no runtime
  attack-intensity variation; attacker position can't change without reflashing every
  victim board. (`MEMORY.md`.)
- Full reasoning and panel-ready phrasing: `ATTACK-MECHANICS.md` (the "honest
  limitation to volunteer" callouts) and `Plan/THESIS3-PANEL-PLAN.md`.
