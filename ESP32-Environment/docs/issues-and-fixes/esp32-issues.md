# ESP32 Issues Log (Part 1 of 3) — NIS16 ESP-WIFI-MESH testbed

Running log of problems hit while building/flashing/running the ESP32 mesh and
the analysis pipeline. **Add a new entry every time something breaks.** Each
entry records the symptom, the root cause, and a **Status**:

- ✅ **FIXED** — root cause removed; won't recur.
- 🩹 **WORKAROUND** — not truly fixed, but there's a reliable way around it.
- 🔴 **OPEN** — not solved yet; under investigation.
- ⛔ **CAN'T FIX** — external/hardware limit; document it and live with it.

Branch context: `integration-test`. Newest issues on top.

---

## I-017 · Attacker under-sampled + corrupt CSV — full SPIFFS (slow writes)
- **Status:** ✅ FIXED — 2026-07-15 (firmware + host; one-time `erase-flash` on the
  already-full board).
- **Symptom:** COM25 (attacker) logged ~0.5 Hz instead of ~20 Hz AND its exported
  `telem.csv` had corrupt/fused lines. Priority fix (I-016) did not help.
- **Diagnosis (via a temporary INSTR loop-timer in `blackhole_victim.c`):** the
  blocker was the per-sample SPIFFS write — `log_max` measured **1.3–7.7 seconds**
  per `csv_logger_append_telemetry`, while `rssi`/`mesh` calls were ~60–160 µs.
  Boot banner showed **`SPIFFS Used: 1603 / 2287 KB` (70% full)**. SPIFFS write
  speed collapses and garbage-collection thrashes as it fills; multi-second,
  stressed writes both starved sampling and wrote malformed lines. COM25 was the
  board reflashed/re-run dozens of times during debugging, so its flash filled;
  the fresh victims wrote in <1 ms and sampled at ~10 Hz.
- **Root cause of the buildup:** `-Wipe` sent `DELETE_LOGS`, which only
  `remove()`d the file — SPIFFS never reclaimed the space, so it crept up every
  run.
- **Fix:**
  1. `DELETE_LOGS` in `csv_logger.c` now **formats the whole SPIFFS partition**
     (`esp_spiffs_format`), closing open handles first — so every `-Wipe` resets
     `Used` to ~0 and the flash can't build up again.
  2. `export_logs.py --wipe` now waits for the device's `LOGS_DELETED` ack (a
     format takes longer than the old fixed 1 s sleep) so it isn't cut off by the
     reflash that follows.
  3. One-time `idf.py -p COM25 erase-flash` to clear the already-full board (the
     format-on-wipe only takes effect once the new firmware is on the board).
- **Note:** the INSTR instrumentation is left in `blackhole_victim.c` behind
  `#define ATTACKER_TELEM_INSTRUMENT 0` (off) for future use.

## I-016 · Attacker under-sampled telemetry — attack-phase windows discarded
- **Status:** ✅ FIXED — 2026-07-15 (needs reflash of the attacker boards).
- **Symptom:** In a blackhole/linear run every board logged ~5000–7400 telemetry
  rows, but the ATTACKER (COM25) logged only **487** (~0.75 Hz vs the intended
  ~20 Hz at `SAMPLING_INTERVAL_MS=50`), with a 47 s blackout. After M6 windowing
  the attacker kept **0 windows in the attack phase** (each 5 s window had <4
  samples → discarded), so `ForwardingRatio`/`IngressEgressDelta`/`ConsistencyScore`
  came out null for the Blackhole phase even though the attacker board WAS
  exported. (The attack itself was still proven on the victim side: PDR
  0.94→0.00.) Wormhole tunnel features would suffer the same way.
- **Cause:** the attacker's `telemetry_task` ran at `TASK_PRIO_TELEMETRY`=5 —
  BELOW the relay/tunnel sink (6). On an intermediate attacker (esp. linear
  topology) the relay path and the prio-8 phase listener kept the CPU busy, so
  the lowest-priority telemetry loop was starved and missed most of its 50 ms
  ticks. The victim's identical prio-5 loop is fine because it has no relay
  competing for the CPU.
- **Fix:** added `TASK_PRIO_ATTACKER_TELEMETRY`=7 (above the relay/tunnel sink 6,
  below the phase listener 8) and used it for the telemetry task in
  `blackhole_victim.c` and both wormhole ends in `wormhole_victim.c`. Telemetry
  now preempts the relay (its per-sample work is sub-millisecond, so no probe is
  lost and the forward/drop attack timing is unaffected) but still yields to the
  packet handler. Restores the uniform `SAMPLING_INTERVAL_MS` rate the telemetry
  loop (thesis Fig 4.24) assumes for every node — an implementation fix, not a
  design change. Victim/root sampling is untouched.

## I-015 · Export progress bar crawled at ~1 KB/s despite 115200 baud being ~11 KB/s
- **Status:** ✅ FIXED — 2026-07-14.
- **Symptom:** `EXPORT_LOGS` on a large `telem.csv` (hundreds of KB) took many
  minutes; the added progress bar showed a steady ~1 KB/s rather than anywhere
  near the 115200 baud's line rate.
- **Cause:** the device (`csv_logger.c` `serial_export_task`) was already
  streaming at full line rate — the bottleneck was entirely host-side.
  `export_logs.py`'s `_capture_stream` called pyserial's `ser.readline()`, which
  reads **one byte per call**; an 800 KB file meant ~800,000 per-byte Python
  reads.
- **Fix:** rewrote `_capture_stream` to read whatever's already buffered in one
  `ser.read(ser.in_waiting)` call and split lines from a local `bytearray`
  buffer itself (same framing/column-width filtering as before, verified
  identical across chunk boundaries of 1/3/7/4096 bytes in a stubbed-serial
  test). Throughput went from ~1 KB/s to ~11 KB/s (near the 115200 line rate) —
  roughly a 10x speedup. Host-only change; takes effect immediately, no
  reflash needed. (Separately, the device now also announces each file's byte
  size on `READY_TO_SEND:<bytes>` so the progress bar can show a true `%` —
  that half DOES need a reflash to take effect; see `m5_extraction/README.md`.)
  Considered raising the console baud instead (would be a further ~4x) but
  rejected: I-007 already showed a higher `CONFIG_ESP_CONSOLE_UART_BAUDRATE`
  doesn't stick in `sdkconfig`, and any host/device baud mismatch fails the
  whole export (and risks silently dropping malformed-width rows) rather than
  erroring cleanly.

---

## I-014 · `preprocess.py` OOM `Unable to allocate 29.9 GiB` — one corrupt `timestamp_us` blows up the reindex grid
- **Status:** 🩹 WORKAROUND (pipeline side) — verified 2026-07-13: M6→M7→M8 runs
  clean on `baseline/linear_topology` after the guard drops the bad sample.
- **Symptom:** `preprocess.py` on `baseline/linear_topology` aborted with
  `numpy ArrayMemoryError: Unable to allocate 29.9 GiB for an array with shape
  (4015695301,)` at `_fill_node_gaps`'s `reindex(full_index)`.
- **Cause:** `victim_COM26_linear..._telem.csv` row 5006 had
  `timestamp_us = 4015695302104779` (~4×10¹⁵ µs vs the normal ~10⁸) — an esp_timer
  glitch. It's a valid integer so it passed numeric coercion, but after per-node
  rebasing its relative time is ~4×10⁹ s, so `RangeIndex(min, max+1)` becomes ~4
  billion rows → a 29.9 GiB allocation.
- **Fix (pipeline, two layers so it can NEVER OOM again):** (1) `_fill_node_gaps`
  drops any sample whose relative time exceeds `MAX_SESSION_SECONDS` (86400)
  before the grid is built; (2) a hard tripwire refuses to densify if the grid
  would exceed `MAX_GRID_ROWS` (500k), falling back to observed timestamps only.
  The reindex is the pipeline's ONLY unbounded allocation (audited), so this caps
  it absolutely. Verified: the 4-billion-row poison case peaks at **0.1 MB** even
  with layer (1) disabled. Clean data untouched (tree output byte-identical).
- **Still open (firmware side):** why esp_timer emitted a garbage timestamp for
  one sample — possibly a logging race in `csv_logger.c`. Rare (1 row); pipeline
  guard absorbs it for now.

---

## I-013 · `preprocess.py` crashes `cannot interpolate with object dtype` — an ESP-IDF log line leaked into a telemetry CSV during export
- **Status:** 🩹 WORKAROUND (pipeline side) — verified 2026-07-13: `preprocess.py`
  drops the bad rows and M6→M7→M8 runs clean on `baseline/partial_mesh_topology`.
  The export-side contamination itself is not yet fixed (see last bullet).
- **Symptom:** `run.ps1 -Analyze` / `preprocess.py` on
  `baseline/partial_mesh_topology` died with `TypeError: Series cannot interpolate
  with object dtype` at `_fill_node_gaps`'s `grid["rssi_dbm"].interpolate(...)`.
  Only that folder; tree/star/linear baseline were fine.
- **Cause:** two victim_COM21 `*_telem.csv` each had **one non-sample row** — an
  async ESP-IDF mesh log line (`...<assoc>...channel:11...`, `[SCAN]...MAP:0...`)
  interleaved into the CSV over the shared UART during export. Its commas split
  into ~11 fields so `read_csv` didn't raise; `rssi_dbm` held a text token, typing
  the column `object` → `interpolate` raises → whole run aborts.
- **Fix (pipeline):** `preprocess.py` gained `NUMERIC_COLUMNS` +
  `_coerce_and_drop_malformed()` — `pd.to_numeric(errors="coerce")` on the numeric
  columns, drop any row whose present value won't parse, count them
  (`Rows dropped (contaminated)`) and warn with the filenames. Clean data is
  untouched → output byte-identical (determinism preserved).
- **Still open (export side):** stop logs contaminating the CSV — raise/mute the
  ESP-IDF log level during the export dump, or export over a framed channel. Until
  then the pipeline workaround absorbs it.

---

## I-012 · Flash/wipe fails `FileNotFoundError` on COM21 — USB selective suspend powered the CP210x down
- **Status:** ✅ FIXED (system-wide) — verified (2026-07-13): after disabling
  USB selective suspend at the power-plan level, `esptool ... flash_id` connected
  cleanly on COM21 (chip ESP32-D0WD-V3, MAC `f4:2d:c9:73:e6:18`, exit 0) on the
  exact reset+open path that was failing.
- **Symptom:** `run.ps1 -Port COM21 -Flash` failed *every* time — first the
  `-Wipe` step, then esptool: `could not open port 'COM21':
  FileNotFoundError(2, 'The system cannot find the file specified.')` /
  `Could not open COM21, the port is busy or doesn't exist`. 100% reproducible,
  yet `Get-CimInstance Win32_PnPEntity` showed COM21 present + `Status: OK` right
  after the failure — the port vanishes only *at the moment esptool opens it*.
- **Not the cause (ruled out by testing):** NOT a busy/held port (that throws
  PermissionError, not FileNotFoundError; the compile step never opens the port,
  so exiting mid-compile can't hold it); NOT a pyserial two-digit-COM bug (3.5
  opened COM21 fine in isolation incl. the dtr/rts-before-open sequence);
  NOT a PATH/python mismatch (failing esptool ran from the pinned venv). A raw
  open test succeeded 20/20 while idle — the port was healthy *at rest*.
- **Cause:** Windows USB **selective suspend** powered the CP210x down after 10 s
  idle — registry `Device Parameters` showed `DeviceSelectiveSuspended:1`,
  `SelectiveSuspendTimeout:10000`. Telltale timeline: an *immediate* open (my
  `erase_flash`, or a lone `flash_id`) hits it awake and works; but a `run.ps1`
  flash sits idle through the failed `-Wipe` + the minute-long ninja compile, so
  by the time `ninja flash` reaches esptool the bridge is suspended → Windows
  reports the device *gone* → FileNotFoundError. Same USB-power theme as I-008's
  link instability, on the serial side.
- **Fix (system-wide — do this, it's teammate-proof):** disable USB selective
  suspend in the active power plan; it covers **every** USB device and survives
  re-enumeration (which erasing/reflashing a board triggers, spawning a fresh
  device instance):
  ```powershell
  $sub='2a737441-1930-4402-8d77-b2bebba308a3'; $set='48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
  powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0
  powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0
  powercfg /setactive SCHEME_CURRENT   # verify: powercfg /q SCHEME_CURRENT $sub $set → both Current ...Index: 0x0
  ```
- **Why NOT the per-device Device Manager uncheck (Ports → CP210x → Power
  Management → "Allow the computer to turn off this device"):** it's per **device
  instance** and *reverts when the board re-enumerates* — after an `erase_flash`,
  COM21 came back as a new instance with the box re-checked (`SelectiveSuspendEnabled`
  blank, timeout back to `10000`), so the flash failed again. Use the power-plan
  fix above instead. Verify either way by connecting, not by the registry
  (`DeviceSelectiveSuspended` is a live-status snapshot, not the setting):
  `esptool.py --chip esp32 -p <COM> -b 460800 flash_id` should connect every time.
- **ALSO check the USB cable — likely the real culprit here (2026-07-13):** after
  the suspend fix, the COM21 cable *still* misbehaved, but moving the SAME board to
  a different port+cable (COM26) worked immediately. A marginal/charge-only cable
  drops the CP210x off the bus intermittently → port vanishes → the identical
  `FileNotFoundError`. So `FileNotFoundError` has TWO causes that look alike: USB
  selective suspend (above) AND a flaky cable/port. **Check the cable first — it's
  the 5-second test:** swap to a known-good short/thick DATA cable, or move the
  board to another physical port. Same power-margin theme as I-008. Use whichever
  COM the good cable enumerates as (`-Port COM26`), and label/retire the bad cable.

## I-011 · Stale build dir breaks the build after the repo folder moves ("configured for project 'OLD\path' not 'NEW\path'")
- **Status:** ✅ FIXED
- **Symptom:** `idf.py ... flash` (via `run.ps1`) fails immediately with
  `Build directory '...\build_<variant>' configured for project 'OLD\PATH\...'
  not 'THIS\PATH\...'. Run 'idf.py fullclean' to start again.` No compile
  happens; the monitor step never runs.
- **Cause:** CMake bakes the project's **absolute source path** into
  `CMakeCache.txt` (`CMAKE_HOME_DIRECTORY`) at configure time. `build_*` dirs
  are git-ignored (per Conventions in `CLAUDE.md`) so they don't ship via git —
  but a `build_*` dir surviving a repo move/rename (this repo moved from
  `...\Business\Claude\AI OS\...\Thesis\...` to `...\DLSU\Thesis\...`), or a
  teammate copying the whole tree instead of cloning fresh, leaves a cached
  path that no longer matches. **Can hit any teammate**, not just this
  machine — anyone reorganizing folders or zipping the project with `build_*`
  included will see it.
- **Fix:** `run.ps1` now self-heals before every `-Flash`: it reads
  `CMAKE_HOME_DIRECTORY` out of the target `build_<variant>/CMakeCache.txt` (if
  present) and compares it to the current project path. On a mismatch it
  prints a warning and deletes just that one stale `build_<variant>` dir, then
  lets `idf.py` reconfigure from scratch — no manual `idf.py fullclean` needed.
  Safe because `build_*` is disposable/git-ignored; nothing in source or SPIFFS
  data is touched.

## I-010 … I-001 · older / long-settled issues → archived

📦 Moved to **Part 2, [`esp32-issues-Part2.md`](esp32-issues-Part2.md)** to keep
this log under 200 lines: **I-010** victims joined too late (boot-order fix —
victims first, root LAST), **I-009** compiling too slow (per-component
`ACTIVE_ATTACK` define + cross-config ccache sharing), **I-008** WiFi link flaps
(reason 6 — fixed by a different root board + ch 11), **I-007** CSV export baud
(460800 reverted),
**I-006** blackhole hand-editing, **I-005** `run.ps1 -Wipe`, **I-004** "fail to
find a network", **I-003** `-lunwind` from wrong dir, **I-002** `could not open
COM9`, **I-001** export timeout workaround. Look there for those; add NEW issues
here on top.

---

### Template for new entries

```
## I-00N · <one-line title>
- **Status:** ✅ FIXED | 🩹 WORKAROUND | 🔴 OPEN | ⛔ CAN'T FIX
- **Symptom:** what you saw (paste the key log line).
- **Cause:** root cause once known.
- **Fix / Workaround:** what resolved it, or the steps still to try.
```
