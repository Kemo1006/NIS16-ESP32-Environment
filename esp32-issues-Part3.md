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
  `child_node/`). Removed the stray `NIS16-ESP32-Environment/build/`.

## I-002 · Export failed: `could not open COM9` (FileNotFoundError)
- **Status:** ✅ FIXED (operator issue)
- **Symptom:** `export_logs.py --port COM9` → `FileNotFoundError … COM9`.
- **Cause:** COM9 didn't exist. FileNotFoundError = device absent at that port
  (vs PermissionError = port busy). Windows had reassigned the ports; the two
  CP210x boards enumerated on **COM3 and COM8**.
- **Fix:** List ports (`Get-CimInstance Win32_SerialPort` or Device Manager),
  identify each board by monitoring its boot banner, and export each from its
  OWN port with the matching `--role`. Root = COM8, victim = COM3 this session.

## I-001 · Export times out (`never saw END_OF_FILE`) — esp. on the ATTACKER
- **Status:** ✅ FIXED (two independent causes; see below)
- **Symptom:** Export fails with `TIMEOUT: never saw END_OF_FILE`. Two distinct
  triggers were seen:
  1. The monitor→auto-export handoff in `run.ps1` occasionally times out.
  2. **The blackhole ATTACKER (COM25) reproducibly failed** while root + victims
     exported fine — the bar reached 99% / full byte count, then timed out.
- **Cause:**
  1. The monitor→export port handoff can reset the board, killing the export
     task mid-stream.
  2. **Concurrent UART0 logging corrupts the `END_OF_FILE` marker.** Victim/root
     app tasks all exit on terminate (`while(!is_terminated())` → `vTaskDelete`),
     so their UART0 goes quiet before export. The attacker's `relay_task`
     (blackhole) and the wormhole tunnel/reinject tasks are `while(true)` and
     **never exit** — post-run they (and the ESP-IDF mesh stack) keep emitting
     `ESP_LOGW` lines to UART0 *while the CSV is streaming*. A log fragment
     splices into the `END_OF_FILE\n` write, so the host never matches the bare
     marker even though the whole file already arrived.
- **Fix (cause 2 — permanent, both attacks):** `serial_export_task()` in
  `components/mesh_common/src/csv_logger.c` now calls
  `esp_log_level_set("*", ESP_LOG_NONE)` before the command loop, muting all
  `esp_log_*` output for the export. Shared logger → covers blackhole, wormhole,
  and every future attacker in one place. (Needs a reflash to take effect.)
- **Fix (host-side safety net):** `tools/export_logs.py` now completes the export
  once the device's announced byte total has fully arrived, after a short grace
  (`POST_TOTAL_GRACE_S`), even if the marker was lost — recovers already-on-flash
  data with NO reflash. This is what recovered the COM25 run.
- **Workaround (cause 1):** Data is safe on SPIFFS (append-mode log). Recover with
  a standalone `export_logs.py --port <port> --role <role> …` after the monitor is
  fully closed. Don't `--wipe`/`--delete` until a good export is confirmed.
