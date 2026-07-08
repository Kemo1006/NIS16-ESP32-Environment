# ESP32 Issues Log (Part 2 of 2) — older resolved issues

> ⬅️ **Back to [`esp32-issues.md`](esp32-issues.md)** (Part 1 of 2) — the
> active log (newest issues + the new-entry template). This file holds the
> older, long-settled entries (I-001…I-005), split out to keep the main log
> under 200 lines. Same Status legend (✅ FIXED / 🩹 WORKAROUND / 🔴 OPEN /
> ⛔ CAN'T FIX). Newest of this batch on top.

---

## I-005 · `run.ps1` missing the `-Wipe` switch
- **Status:** ✅ FIXED
- **Symptom:** CLAUDE.md documented `-Wipe` but the integration-test `run.ps1`
  didn't have it, so runs stacked old data into one CSV.
- **Cause:** `-Wipe` lived only on the `Carlos(Testing)` branch.
- **Fix:** Ported the `-Wipe` param + pre-run `export_logs.py --port X --wipe`
  step into the integration-test `run.ps1`. `--wipe` was already supported by
  `export_logs.py` on this branch.

## I-004 · Victim stuck "fail to find a network"
- **Status:** ✅ FIXED (operator issue)
- **Symptom:** Victim looped `[FIND] … fail to find a network`, `root:0` — no
  root present on channel 6.
- **Cause:** The root board wasn't running the root firmware / wasn't up, so
  nothing was advertising the mesh for the victim to join.
- **Fix:** Flash `root_node` firmware on the root board and confirm it comes up
  `Role: 0` / `[MANUAL]designated as root` BEFORE starting the victim.

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
