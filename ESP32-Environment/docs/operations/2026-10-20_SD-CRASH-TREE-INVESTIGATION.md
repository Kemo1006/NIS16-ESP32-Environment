# SD cards not saving, boards crashing, unstable trees — investigation (oct. 20, 2026)

*Requested by Angelo: "boards suddenly fail to save data to their SD cards — one node records
nothing, the rerun works but another node fails. Did the code change cause it?" Verification #66.
Read this before the next capture. Evidence first, then what changed, then what to do.*

## 1. What the evidence says

| Evidence | Where | What it shows |
|---|---|---|
| Firmware changes to SD code since the oct. 11-12 runs that worked | `git log` on `csv_logger.c`, `sd_status.c` | **Mount, file naming, open modes and the SPI config did NOT change.** Only additions: crash record (oct. 18, writes one small file at boot then closes it), SD-logging heartbeat byte + a fix (oct. 19). |
| File names | `sd_csv_path()` | `<role>_<NODE_MAC>_r<run>_b<boot>_telem.csv`, one card per board → boards **cannot** overwrite each other's files. |
| Root dashboard "SD LOGGING" lines | `datasets/run_logs/blackhole/tree/G402/highload/*oct19*` | Every board on the new firmware was writing (8/8 in the 8:37 PM run; "4/8 (the rest run older firmware - not reported)" in 6:45/6:54 PM = not a failure). |
| 2805's card read in a reader (#63) | verification #62/#63 | Status report written at boot, but the run's telemetry file **never opened**; card reads over serial inconsistent (76 vs 14 files); board brownout-rebooting → **an unstable card link on that board (power / wiring / card)**, not a code path that skips one board. |
| Crash records on 4 cards (`crashes_*.csv`) | `datasets/run_logs/blackhole/tree/G402/highload/crashes/` | **0C80, 2805, FE90, E618: PANIC FAULT at the SAME PC `0x40081d4d` with the same backtrace**, mid-run (last [HEALTH] 33-663 s), heap ~90 KB free. Hardware faults do not land on one instruction on four boards → **a deterministic firmware/SDK crash**. On every IDF 5.5.4 build of oct. 19 (victim, attacker, wormhole, root) that address is inside `ipc_task` (`esp_ipc.c:85`, the call right after a blocking cross-core call returns). 2805 also had INT_WDT in spinlock code. Exact cause NOT proven: the ELF those boards ran was not kept. |
| Crashes started with the oct. 17 4:55 PM firmware | verification #39 | before it, every run on all 7 cards ended POWERON. |
| Why boards re-parent | verification #55 | children re-parent after their **parent crashed / browned out** (E618 ~10×, 0C80 PANIC, 2805 brownouts). The only tree-firmware change still active (D-26 sticky parents) makes boards *less* likely to switch; parent selection is stock again since `f786c07`. |

## 2. Answer: did the code cause it?

* **The SD write path did not regress in a way that targets one board.** But the firmware turned
  any *transient* card problem into a total loss for the run, and said so only on a serial port
  nobody watches (children run on powerbanks):
  1. one failed card init at boot → no card copy for the whole run (no retry);
  2. one failed open / write mid-run → before oct. 19 the next row **re-opened the file with
     `"w"` and truncated it**; after the oct. 19 fix the card copy simply **stopped for the rest of
     the run** (`4a8488d` — not hardware-tested yet);
  3. a failed internal-flash (SPIFFS) write **skipped the SD write** of the same row;
  4. a failed `fflush` / `fsync` was only warned about, every 5 s, while every row was lost.
  That is why it looks random: whichever board's card hiccups on that run loses its copy.
* **The crash IS a firmware-level problem** and it is the common cause behind three symptoms:
  a crashed board (a) reboots into a NEW card file (data split into pieces → "missing samples",
  "stalled windows"), (b) takes its children with it → they **re-parent** (unstable tree), and
  (c) if it was the attacker, its victims' delivery drops for a reason that is not the attack.

## 3. What was changed (oct. 20, not yet on hardware — reflash every board)

| Change | File | Effect |
|---|---|---|
| Boot mount: 3 attempts, 300 ms apart (same config) | `sd_status.c` | one slow card init no longer costs the run |
| R/W integrity check failure is an ERROR line | `sd_status.c` | a card that cannot read back 34 bytes is named at boot |
| **SD recovery**: a failed open / write / flush / fsync → mirror DOWN → background task: reopen, then card **remount**, every 5 s, given up after 6 consecutive failed tries; reopen is **append-only** (never truncates) | `csv_logger.c`, `sd_status.c` (`sd_status_remount`) | a card that browns out / misses an SPI transfer comes back; the 10 Hz telemetry task never waits on a card init |
| Rows missed while down are counted; `runs.csv` gets `sd_gap` / `sd_short` / `sd_lost` | `csv_logger.c` | the importer prints **CARD COPY INCOMPLETE: N rows** (`import_sdcard.py`) — a short card copy can no longer pass as a short run |
| SD write no longer skipped when SPIFFS fails | `csv_logger.c` | the two copies are independent |
| Heartbeat state `INCOMPLETE (card recovered, rows missed)`; `STALLED/RECOVERING`; `CARD GIVEN UP` | `csv_logger.h`, `mesh_setup.c` | the root dashboard names the board; GUI pre-START check catches it |
| End of run: `SD CARD COPY INCOMPLETE: x of y rows ... export over USB BEFORE re-flashing` | `csv_logger.c` | internal flash still has every row until the next flash |
| Crash rows carry the build's ELF SHA; `run.ps1` keeps every built .elf in `%LOCALAPPDATA%\NIS16\elf_archive\`; `fetch_crashes.py` decodes against the exact build | `crash_record.c`, `run.ps1`, `tools/fetch_crashes.py` | the next crash is decodable to a source line |
| [HEALTH] watches `ipc0`, `ipc1`, `sd_recover`; IPC task stack 1024 → 2048 | `health_log.c`, `sdkconfig(.defaults)` | **mitigation** for the ipc_task crash (2 KB of ~90 KB free) and the measurement that confirms or rules it out |

## 4. What to do on the next capture

1. **Reflash every board** (children AND root) from this commit, IDF 5.5.4 preferred (the build
   ID makes 5.3.5 builds decodable too, as long as that laptop runs the build through `run.ps1`).
2. Before START, the root must show `SD LOGGING : N/N board(s) writing`. Anything else → reseat /
   replace that card, reset that board.
3. After the run, read every card's import line: `CARD COPY INCOMPLETE` → export that board over
   USB (`EXPORT_LOGS`) **before** re-flashing it.
4. If a board crashes: `python tools/fetch_crashes.py --card E:\` — the decode names the
   function / line. Check the [HEALTH] lines for `ipc0=` / `ipc1=` near 0.
5. Boards that browned out before (2805): check the powerbank (auto-off at low current), the
   card module's supply (VIN/5 V, not 3V3) and the jumpers; swap the card if `R/W integrity check
   FAILED` appears at boot.

## 5. What is still unknown (and the test that answers it)

| Unknown | Test |
|---|---|
| The exact function that crashes in `ipc_task` | next crash with the oct. 20 firmware → `fetch_crashes.py` (exact ELF) |
| Whether the 2 KB IPC stack fixes it | [HEALTH] `ipc0=` / `ipc1=` minimum free stack over a full highload run; no PANIC FAULT at that PC |
| Whether SD recovery works on the real rig | pull a card for 10 s mid-run on a test board: the log must show `SD ... copy DOWN` → `SD RECOVERY: card re-initialised` → `RESUMED (append) after N row(s) missed`, and runs.csv `sd_gap` |
| 2805's card / power | swap its card + powerbank and run a 10-min test; boot reports must show no brownout |
