# NIS16 — Running the experiment, exporting & troubleshooting (Part 2 of 2)

> ⬅️ **Back to [`README.md`](README.md)** (Part 1 of 2) — the setup guide
> (steps 1–6: what you need, installing ESP-IDF, folder layout, mesh settings,
> finding COM ports, building + flashing). **Do those first.** This file
> continues from there: letting the run finish (step 7), exporting the CSVs
> (step 8), verifying the data (step 9), re-running clean, gotchas,
> troubleshooting, and a quick reference. Split from `README.md` to keep each
> file under 200 lines.

## 7. Let the experiment run (~8 minutes, fully automatic)

The root controls the timeline. Just watch the two monitors:

| Phase       | Duration | What happens                                             |
|-------------|----------|----------------------------------------------------------|
| Stabilize   | 60 s     | mesh settles                                             |
| Baseline    | 300 s    | each node logs telemetry at 1 Hz; victim sends 1 probe/s |
| Cooldown    | 120 s    | network settles                                          |
| Terminate   | —        | logging stops, export task starts listening              |

You'll see phase messages in the logs as it advances. When it reaches
**terminate**, the run is DONE and the data is saved on each board's flash.
Data survives reboots, so there's no rush to export.

---

## 8. Export the data (CSV)

> **Each board stores ONLY its own data, and you export each board from its OWN
> USB port.** There is no "master" board that collects everyone's logs — telemetry
> is never sent over the mesh. So connect to the root's port to get the root's
> files, and the victim's port to get the victim's files. Exporting the wrong port
> just gives you a duplicate of that board's data.

### Easiest way — auto-export on Ctrl + ] (recommended)

`run.ps1` opens the monitor and, the moment you press **Ctrl + ]**, automatically
runs the export for that board. No typing export commands.

From the project root, in an ESP-IDF PowerShell:

```powershell
cd "PATH\TO\NIS16-ESP32-Environment"

# Terminal 1 — root: flash, watch ~8 min, then Ctrl+] to auto-export
.\run.ps1 -Port COM3 -Role root   -Flash

# Terminal 2 — victim: flash, watch, then Ctrl+] to auto-export
.\run.ps1 -Port COM6 -Role child  -Flash
```

- **`-Role` must match what the board is actually flashed as.** Only `-Role root`
  pulls `arrivals.csv` (the probe-arrival proof). Export the root as "victim" by
  mistake and you'll miss `arrivals.csv`.
- Already flashed / board still running and you just want to export? Drop `-Flash`:
  ```powershell
  .\run.ps1 -Port COM6 -Role child 
  ```
- Add `-Clean` to wipe the board's logs **after** a good export, so the next run
  starts empty (prevents stacked, mixed-run files):
  ```powershell
  .\run.ps1 -Port COM3 -Role root -Flash -Clean
  ```

### Manual way (if you prefer)

1. **Close the monitors first.** The export shares the serial port with the
   monitor. Press **Ctrl + ]** in each monitor window to free the port.
2. Run the export from the `tools` folder:
   ```powershell
   cd tools
   python export_logs.py --port COM3 --role root   --topology star --attack none --repeat 1
   python export_logs.py --port COM6 --role child  --topology star --attack none --repeat 1
   ```

**Flags:**
| Flag | Meaning |
|------|---------|
| `--port` | the board's current COM port |
| `--role` | `root` or `victim` (root also pulls `arrivals.csv`) |
| `--topology` | `star` \| `tree` \| `linear` \| `partial` (labels the filename) |
| `--attack` | `none` \| `blackhole` \| `wormhole` (use `none` for Milestone 1) |
| `--repeat` | run number; bump it for repeat runs (r1, r2, …) |
| `--list` | only list what's stored on the board; download nothing |
| `--delete` | erase the board's logs after a successful download |

---

## 9. Where the files go + how to verify

Files land in:
```
NIS16-ESP32-Environment\tools\exports\
```

You'll get files named like:
```
root_COM3_star_none_r1_<date>_telem.csv       (11 columns)
root_COM3_star_none_r1_<date>_arrivals.csv    (14 columns, root only)
victim_COM6_star_none_r1_<date>_telem.csv     (11 columns)
```

**Milestone 1 is satisfied when:**
- [ ] firmware built with **zero warnings** (clean `idf.py build` output)
- [ ] mesh formed within 60 s (`nodes in mesh: 2` on the root)
- [ ] phase transitions happened on schedule (phase messages in the logs)
- [ ] `telem.csv` has ~1 row/second with no gaps
- [ ] `arrivals.csv` row count ≈ the victim's "Total probes sent" (≈ 1:1 delivery)
- [ ] the CSV files actually appear in `tools\exports\`

---

## Running it again (clean run)

Logs are append-mode, so old data stays unless you wipe it. For a fresh run:
- export with `--delete`, **or**
- wipe first: `python export_logs.py --port COM3 --delete`

Then re-flash / reset both boards and repeat from step 6, bumping `--repeat`.

---

## Gotchas (read before you build)

1. **NEVER run `idf.py set-target`.** It regenerates `sdkconfig` from defaults and
   **drops the custom partition table**, so the build has no `spiffs` partition.
   The board then reboot-loops with `spiffs partition could not be found` (it
   "blinks") and logs nothing. The target is already pinned in each project — just
   run `idf.py build`. **Fix if someone ran it:**
   ```powershell
   git checkout -- root_node/sdkconfig child_node/sdkconfig
   idf.py build
   ```

2. **One `idf.py` per project folder at a time.** Two builds hitting the same
   `build/` folder corrupt each other (`ranlib: libwear_levelling.a: No such file`).
   Building `root_node` and `child_node` in parallel is fine — they're different
   folders. Fix a corrupted build with `idf.py fullclean` then `idf.py build`.

3. **Flashing the app does NOT erase logs.** Telemetry lives at a fixed flash
   address that reflashing leaves untouched, so data survives a reflash. Only
   `erase-flash` or `--delete` / `DELETE_LOGS` wipes it.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `spiffs partition could not be found` / board blinks / reboot loop | Someone ran `idf.py set-target`. Run `git checkout -- root_node/sdkconfig child_node/sdkconfig` then `idf.py build`. Never run set-target again. |
| `ranlib: libwear_levelling.a: No such file` | Two `idf.py` commands hit the same `build/`. Run `idf.py fullclean` then `idf.py build`. |
| Wrong role on a board (e.g. "Project name: root_node" on the victim) | You built from the wrong folder. `cd` into the correct folder and re-flash. |
| `could not open COMx` during export | The monitor is still open. Press **Ctrl + ]** in the monitor window first. |
| Exported "victim" file looks like the root | You exported the wrong COM port. The victim must be exported from the victim board's own port — see step 8. |
| `uart driver error` flood | Old firmware. Re-flash with the current build. |
| `pyserial` not installed | You're not in the ESP-IDF PowerShell. Open that shortcut, or run `pip install pyserial`. |

---

## Quick Reference

```powershell
# 0. Find ports (numbers change!)
python -m serial.tools.list_ports

# EASIEST: auto-export on Ctrl+]
.\run.ps1 -Port COM3 -Role root   -Flash      # terminal 1
.\run.ps1 -Port COM6 -Role child  -Flash      # terminal 2
# wait ~8 min, then Ctrl+] in each -> auto-exports to tools\exports\

# MANUAL:
cd root_node;   idf.py build; idf.py -p COM3 flash monitor   # terminal 1
cd child_node; idf.py build; idf.py -p COM6 flash monitor   # terminal 2
# wait ~8 min, then Ctrl+] in both monitors
cd tools
python export_logs.py --port COM3 --role root   --topology star --attack none --repeat 1
python export_logs.py --port COM6 --role child  --topology star --attack none --repeat 1
```

**Two rules to never forget:** build from the **"ESP-IDF 5.3 PowerShell"**
shortcut, and **never run `idf.py set-target`**.
