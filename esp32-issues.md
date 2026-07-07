# ESP32 Issues Log — NIS16 ESP-WIFI-MESH testbed

Running log of problems hit while building/flashing/running the ESP32 mesh and
the analysis pipeline. **Add a new entry every time something breaks.** Each
entry records the symptom, the root cause, and a **Status**:

- ✅ **FIXED** — root cause removed; won't recur.
- 🩹 **WORKAROUND** — not truly fixed, but there's a reliable way around it.
- 🔴 **OPEN** — not solved yet; under investigation.
- ⛔ **CAN'T FIX** — external/hardware limit; document it and live with it.

Branch context: `integration-test`. Newest issues on top.

---

## I-010 · Victims join too late → capture only cooldown/terminate; root ran baseline-only
- **Status:** ✅ FIXED — workaround applied and VERIFIED to produce a clean
  blackhole capture (2026-07-08). Export set
  `root_COM11_tree_blackhole_r1_20260708_035005*` /
  `..._035013_arrivals.csv` / `victim_COM3_..._035008` /
  `victim_COM8_..._035007` shows the textbook signature: all 4 files carry
  ~179–180 `phase_id=1` rows, and in `arrivals.csv` split by `src_mac`, the
  blackhole board (`B0:CB:D8:F3:32:18`) drops from **257 baseline arrivals → 0
  during phase 1 → 121 in cooldown**, while the normal victim
  (`F4:2D:C9:73:E6:18`) is unaffected (307 / 180 / 120). Root arrivals halved
  from 30→15 per 15 s window exactly at the phase 0→1 flip and recovered at
  1→3. Keep the boot-order + root-`-Attack` discipline below and it reproduces.
- **Symptom:** In a 3-board run (root COM11, victim COM8, blackhole COM3), BOTH
  victims logged only `phase_id=3` (cooldown) then `phase_id=4` (terminate) —
  never phase 0 (baseline) or phase 1 (attack). Blackhole reported
  `Dropped: 0`. Root reached cooldown at `root_ts ≈ 361 s`.
- **Cause (two independent mistakes):**
  1. **Late join.** The root's phase clock starts at ROOT boot and does NOT wait
     for children. `run.ps1` flashes+monitors one board at a time (~30–40 s
     flash each), so flashing root→victim→blackhole sequentially meant the
     victims didn't join until the root was already ~360 s in (cooldown). They
     missed baseline AND attack entirely.
  2. **Root was baseline-only.** Cooldown at `root_ts ≈ 361 s` = 60 (stabilise)
     + 300 (baseline), with NO 180 s attack window → the root was flashed
     `-Attack none`. `-Attack blackhole` on the *victim* is inert unless the
     ROOT also announces phase 1 (hence `Dropped: 0`).
- **Fix / Workaround:**
  1. Put `-Attack blackhole` on the **ROOT** too — the root drives the attack
     phase; the victim flag only selects which victim firmware is built.
  2. Get all boards booted inside the root's 60 s stabilise window. Firmware
     persists across resets, so: flash victim + blackhole FIRST (they sit
     scanning `[FIND] fail to find a network`, harmless), then flash the root
     LAST — its 60 s stabilise absorbs the join, then baseline starts with all
     3 present. Confirm `nodes in mesh: 3` on the root BEFORE the first
     `phase_id=0` broadcast; during phase 1 the blackhole should log
     `Dropped: N>0`.

## I-009 · Compiling too slow — full rebuild on every baseline↔blackhole switch
- **Status:** ✅ FIXED
- **Symptom:** Root builds took minutes even for a tiny change; every
  `run.ps1 -Flash` that switched attack mode recompiled the whole ESP-IDF tree.
- **Cause:** `root_node/CMakeLists.txt` applied `-DACTIVE_ATTACK=<n>` as a
  **global** compile option (`idf_build_set_property COMPILE_OPTIONS`). Since
  `run.ps1` passes an explicit value on every flash (255 baseline / 1 blackhole),
  switching mode changed every object's command line → ninja rebuilt everything.
- **Fix:** Moved the define to the root's `main` component only
  (`target_compile_definitions(${COMPONENT_LIB} PRIVATE ACTIVE_ATTACK=...)`),
  since `root_main.c` is its sole consumer. A mode switch now recompiles ~1 file.
  Verified `root_main.c:249` is the only C consumer; other components fall back
  to the `#ifndef ACTIVE_ATTACK` default in `mesh_config.h`.
- **Other build-speed facts (not bugs):** ccache is already enabled
  (`-DCCACHE_ENABLE=1`), so the *second* build of a given config is fast — do
  NOT `idf.py fullclean` unless truly needed (it throws away the ccache-backed
  objects). The *first* build of each project compiles all of ESP-IDF (~minutes,
  unavoidable). Build root + victim in parallel (separate folders = safe) to
  halve wall-clock. The `-- USING O3` line is mbedTLS building itself, not our
  code; global app optimization is already `-Og` (fast to compile).

## I-008 · WiFi link flaps: victim connects to root then drops (reason 6)
- **Status:** 🩹 WORKAROUND — largely resolved by a different root board + ch 11.
  Latest run (2026-07-08): a THIRD root board (MAC `1c:c3:ab:c1:98:a8`, COM11) on
  **channel 11** ran the **FULL ~8-min experiment** to completion with BOTH
  children joined (routing table = 3), victim RSSI **−54..−58 dBm** (was
  −66..−69), victim sent **441 probes**, only 2 brief child drops (auto-rejoined
  in ~10 s) vs constant flapping before. This **confirms the earlier root board
  was the bad actor** (power/RF) — swapping it + moving to a quiet channel fixed
  it. Keep an eye on the 2 residual drops; if they matter, chase root power
  (cable/port) further. Original OPEN diagnosis kept below for history.
- **(history) Status:** 🔴 OPEN (environmental — not a firmware bug)
- **Symptom:** Victim finds the root and **associates successfully every time**
  (`auth → assoc → run`), then the link dies ~1–2 s later and repeats forever.
  Disconnect reasons are a grab-bag: **6** (non-auth STA / deauth), **105**
  (parent stopped), **202**, **204** (handshake timeout). Every probe fails
  `ESP_ERR_MESH_DISCONNECTED`. RSSI a weak **−66..−69 dBm** for two boards on the
  same desk (should be −20..−40 that close).
- **Why it's not firmware:** a config/credential mismatch fails cleanly at auth
  and never reaches `run`. Here association always succeeds and then can't be
  *sustained*, with mixed disconnect reasons + abnormally weak RSSI — the
  fingerprint of RF/power instability. Both boards run the same commit, correct
  roles (root `Role: 0`, victim joins), and boot fine at 460800 baud.
- **Suspected causes (most→least likely):**
  1. **Power/brownout** on WiFi TX spikes — thin USB cable / two boards sharing
     one weak USB controller. Top suspect (weak RSSI + varied deauths).
  2. **Channel 6 congestion** — mesh was hard-coded to ch 6, the busiest 2.4 GHz
     channel; local APs there cause deauth/handshake-timeout storms.
  3. **RF proximity** — radios <~30 cm apart desensing each other.
- **Attempts:**
  - 2026-07-08: reflashed both at 460800 — flap persists identically (rules out
    the baud change; confirms it's the link, not serial).
  - 2026-07-08: **made the channel configurable** — new `MESH_CHANNEL` in
    `mesh_config.h` (was hard-coded `cfg.channel = 6` in `mesh_setup.c`), set to
    **11**. Reflash BOTH boards; if still flapping, try `MESH_CHANNEL 1`. ⏳ test.
  - 2026-07-08: `netsh wlan show networks` saw only **1 AP nearby** → the 2.4 GHz
    band is quiet here, so **channel congestion is unlikely** the cause.
    Suspect #2 (channel) DEPRIORITIZED; **power/brownout + RF proximity are now
    the overwhelming suspects.** Also note reason **105 "parent stopped" = the
    ROOT's AP dropping** → the ROOT board's power/stability may be the culprit;
    monitor the root during a victim run to see if it resets or its AP restarts.
- **Still-untested physical fixes:** good short/thick USB cables; power boards
  from separate strong ports / a powered hub; move them ~1–2 m apart; power-cycle
  both, start root first, wait ~10 s, then victim. This hardware *has* captured
  clean baseline CSVs before, so the setup is capable.

## I-007 · CSV export over serial is slow → 460800 attempt REVERTED
- **Status:** ⛔ CAN'T FIX (as attempted) — reverted to 115200 for reliability.
- **Symptom:** Exporting `telem.csv` took ~20–25 s (a 267 KB stacked file).
- **Cause:** Console/UART0 baud is 115200 (~11.5 KB/s); baud is the bottleneck.
- **Attempt (2026-07-08) and why it was reverted:** Raised
  `CONFIG_ESP_CONSOLE_UART_BAUDRATE` to 460800 in sdkconfig + sdkconfig.defaults,
  and set `export_logs.py BAUD=460800`. **It did not stick**: idf regenerated
  `sdkconfig` back to **115200** on later builds (the sdkconfig.defaults line is
  only applied to keys not already present, and the direct edit was normalized
  away), so the FIRMWARE stayed at 115200 while the host tools moved to 460800.
  Result — a baud MISMATCH that broke BOTH export AND wipe: `export_logs.py`
  (and `run.ps1 -Wipe`) sent commands at 460800 that the 115200 device saw as
  garbage → `TIMEOUT: never saw END_OF_FILE`, and `--wipe` silently did nothing
  (board still showed old `Used: 262 KB` after a "successful" wipe).
  Proof it never took: `idf.py monitor` still opened at `-b 115200` and showed
  CLEAN text (would be garbage if firmware were at 460800).
- **Resolution:** reverted everything to **115200** — `export_logs.py BAUD`,
  `SERIAL_BAUD`, and removed the 460800 line from both `sdkconfig.defaults`.
  sdkconfig was already back at 115200, so **no reflash needed** — export/wipe
  work again immediately. Export stays ~20 s for a big file; acceptable, and a
  `-Wipe` before each run keeps files to a single run (~50 KB, a few seconds).
- **If you ever want the speedup for real:** set the console baud via
  `idf.py menuconfig` (Component config → ESP System Settings → Channel/baud, or
  Component config → Console) so it persists in sdkconfig, confirm `idf.py
  monitor` opens at the new `-b`, THEN set `export_logs.py BAUD` to match. Don't
  hand-edit sdkconfig — it gets regenerated.

## I-006 · Blackhole attack required hand-editing two files
- **Status:** ✅ FIXED
- **Symptom:** Running the blackhole attack (M2) meant manually editing source on
  both boards; easy to mismatch and leave a half-configured run.
- **Cause:** No build-time attack selector; victim source was hard-picked.
- **Fix:** Added `-DACTIVE_ATTACK` build flag (`mesh_config.h` `#ifndef` guard;
  `ATTACK_NONE=255`, blackhole=1). Root announces the phase; victim
  `main/CMakeLists.txt` builds `blackhole_victim.c` when `ACTIVE_ATTACK==1`.
  Also wired `run.ps1 -Attack blackhole` to inject the flag on flash, and
  `-Attack none` passes `-DACTIVE_ATTACK=255` (also clears a cached blackhole
  build). Build-verified with zero warnings, and confirmed live: victim booted
  `=== BLACKHOLE NODE STARTING ===`.

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

---

### Template for new entries

```
## I-00N · <one-line title>
- **Status:** ✅ FIXED | 🩹 WORKAROUND | 🔴 OPEN | ⛔ CAN'T FIX
- **Symptom:** what you saw (paste the key log line).
- **Cause:** root cause once known.
- **Fix / Workaround:** what resolved it, or the steps still to try.
```
