# ESP32 Issues Log (Part 3 of 3) — earliest resolved issues

> ⬅️ **Back to [`esp32-issues-Part2.md`](esp32-issues-Part2.md)** (Part 2 of 3),
> which links back to [`esp32-issues.md`](esp32-issues.md) (Part 1 of 3 — the
> active log). This file holds the earliest entries (I-001…I-003), split out
> when Part 2 grew past 200 lines. Same Status legend (✅ FIXED / 🩹 WORKAROUND /
> 🔴 OPEN / ⛔ CAN'T FIX). Newest of this batch on top.

---

## I-003 · `idf.py monitor` fails with `lld: unable to find library -lunwind`
- **Status:** ✅ FIXED
- **Symptom:** Running `idf.py monitor` errored during CMake with a broken clang
  host-compiler test (`-lunwind`), never reaching the serial port.
- **Cause:** The command was run from the **parent** folder
  `NIS16-ESP32-Environment/`, which is NOT an IDF project (its `CMakeLists.txt`
  is a placeholder). idf.py treated it as a project, picked the host toolchain,
  and failed — and created a junk `build/` dir there.
- **Fix:** Run `idf.py` only from a real project subfolder (`root_node/` or
  `victim_node/`). Removed the stray `NIS16-ESP32-Environment/build/`.

## I-002 · Export failed: `could not open COM9` (FileNotFoundError)
- **Status:** ✅ FIXED (operator issue)
- **Symptom:** `export_logs.py --port COM9` → `FileNotFoundError … COM9`.
- **Cause:** COM9 didn't exist. FileNotFoundError = device absent at that port
  (vs PermissionError = port busy). Windows had reassigned the ports; the two
  CP210x boards enumerated on **COM3 and COM8**.
- **Fix:** List ports (`Get-CimInstance Win32_SerialPort` or Device Manager),
  identify each board by monitoring its boot banner, and export each from its
  OWN port with the matching `--role`. Root = COM8, victim = COM3 this session.

## I-001 · Export auto-handoff sometimes times out (`never saw END_OF_FILE`)
- **Status:** 🩹 WORKAROUND
- **Symptom:** The monitor→auto-export handoff in `run.ps1` occasionally fails
  with `TIMEOUT: never saw END_OF_FILE`.
- **Cause:** The monitor→export port handoff can reset the board, killing the
  export task mid-stream.
- **Workaround:** Data is still safe on SPIFFS (append-mode log). Recover with a
  standalone `export_logs.py --port <port> --role <role> …` after the monitor is
  fully closed. Don't `--wipe`/`--delete` until a good export is confirmed.
