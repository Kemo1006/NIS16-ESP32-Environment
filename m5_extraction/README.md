# M5 — Raw Data Extraction & Integrity Validation (10%)

How to **test** Milestone 5. The extraction script is not moved here — it lives
with the host-side tooling in [`../tools/export_logs.py`](../tools/export_logs.py)
(shared `tools/exports/` data dir, invoked by `run.ps1 -Export`); this folder is
its documentation home. See [`../../WORKFLOWS.md`](../../WORKFLOWS.md) for the
export runbook and [`../../MILESTONES.md`](../../MILESTONES.md) for status.

## What M5 has to prove — TWO halves

1. **Extraction** — pull the raw CSVs off each board's SPIFFS over USB. ✅ exists.
2. **Integrity validation** — independently verify the pulled data is complete
   and well-formed (schema width, per-phase row counts, monotonic timestamps,
   checksums). ✅ **`../tools/validate_integrity.py`, added 2026-07-12.**

## Test the extraction half — needs the boards

Close the monitor first (export shares UART0), then pull each board from **its
own** port (ports below are the confirmed 4-board matrix from
[`../../ATTACKS-Commands.md`](../../ATTACKS-Commands.md)):

```powershell
cd tools
python export_logs.py --port COM20 --role root   --topology tree --attack none --repeat 1
python export_logs.py --port COM25 --role victim --topology tree --attack none --repeat 1
```

Files land in `tools/exports/` with run metadata baked into the filename. Every
file already in `tools/exports/` is passing evidence that extraction works.
`run.ps1 -Export` wraps this to auto-pull when you exit the monitor.

**2026-07-14:** the transfer got a live progress bar and a ~10x speed fix. The
device now announces each file's byte size (`READY_TO_SEND:<bytes>`) so the host
renders a true `%`; separately, the host's read loop was switched from
pyserial's one-byte-at-a-time `readline()` to buffered chunk reads, which was
the actual bottleneck (~1 KB/s -> ~11 KB/s, near the 115200 line rate). The size
announcement needs a reflash to take effect; the speed fix is host-only and
applies immediately. See `esp32-issues.md` **I-015** if an export still looks
throttled after reflashing.

## Test the integrity half

```powershell
cd tools
python validate_integrity.py                     # validates ./exports, recursive
python validate_integrity.py --sample-interval-ms 1000   # for pre-2026-07-12 (1 Hz) captures
python validate_integrity.py --strict             # WARNings also fail (exit 1)
```

No hardware required — it runs entirely against whatever's already in
`tools/exports/`. Checks performed:
- **Schema width** — `telem.csv` is exactly 11 columns, `arrivals.csv` exactly 14;
  every data row's field count must match the header.
- **Per-phase row counts** — each phase produced roughly the expected number of
  samples for the configured rate (`SAMPLING_INTERVAL_MS`), flagging truncation.
- **Timestamp monotonicity** — `timestamp_us` never goes backwards within a file.
- **Manifest / checksums** — a SHA-256 per file (`exports/manifest.json`) so a
  re-pull can be proven identical; a changed hash fails unless `--relock`.

Run against real captures in `tools/exports/`, it correctly PASSed clean files
and caught two genuine problems: a timestamp regression where data from an
earlier, unwiped run bled into a later one, and attack-phase rows appearing in a
file whose filename says `attack=none` (a control victim's phase-bleed).

**`../tools/run_matrix.py --record`** (M4, see
[`../m4_execution/README.md`](../m4_execution/README.md)) wraps this validator:
it runs `validate_integrity.py` against a matrix cell's folder and only marks
that cell "done" in `exports/run_ledger.csv` if validation passes — use it
instead of calling `validate_integrity.py` by hand once you're working through
the 24-cell matrix.

## Status

**COMPLETE.** Extraction ✅ (`export_logs.py`, now with a chunked-read speed fix
+ progress bar), integrity validation ✅ (`validate_integrity.py`, added
2026-07-12; now also driven by `run_matrix.py --record`).
