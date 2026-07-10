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
   checksums). ❌ **does not exist yet on this branch.**

## Test the extraction half — needs the boards

Close the monitor first (export shares UART0), then pull each board from **its
own** port:

```powershell
cd tools
python export_logs.py --port COM9 --role root   --topology tree --attack none --repeat 1
python export_logs.py --port COM3 --role victim --topology tree --attack none --repeat 1
```

Files land in `tools/exports/` with run metadata baked into the filename. Every
file already in `tools/exports/` is passing evidence that extraction works.
`run.ps1 -Export` wraps this to auto-pull when you exit the monitor.

## Test the integrity half — NOT POSSIBLE YET

There is no `validate_integrity.py` (or equivalent) on this branch, so there is
nothing to run for this half — **you can't test what isn't built.** This is
exactly why M5 is stuck at PARTIAL.

What such a tool would check against `tools/exports/`:
- **Schema width** — `telem.csv` is exactly 11 columns, `arrivals.csv` exactly 14.
- **Per-phase row counts** — each phase produced roughly the expected number of
  1 Hz samples (no silent truncation).
- **Timestamp monotonicity** — `timestamp_us` never goes backwards within a node.
- **Manifest / checksums** — a SHA-256 per file so a re-pull can be proven identical.

## Status & the gap

**PARTIAL.** Extraction ✅, integrity validation ❌. Building the integrity
checker is the single code change that moves M5 from "extraction only" to a
demonstrable extraction-**and**-validation deliverable — and it can run entirely
against the existing captures, no hardware required.
