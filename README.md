# NIS16 — ESP32 ESP-WIFI-MESH Testbed

Firmware + tooling for the thesis *"Cross-Layer Dataset Design and Exploratory
Analysis of ESP32-Based ESP-WIFI-MESH Network"* (DLSU CTTHES2/THES3).

This guide takes you from a fresh laptop to exported CSV data. **Follow it top to
bottom.** If you just need a refresher, jump to the [Quick Reference](#quick-reference)
at the bottom.

> ⚠️ **The single most important rule:** never run `idf.py set-target`. See
> [Gotchas](#gotchas-read-before-you-build) — it silently breaks data logging.

---

## What this project does

Two (or more) ESP32 boards form a wireless mesh. One board is the **root** (it
controls the experiment timeline and receives probes); the other(s) are
**victims** (they send a probe every second and record telemetry). Every board
logs cross-layer data (RSSI, mesh layer, parent, packet counters) to its own
on-board flash once per second. After the run, you pull those logs off **each
board** over USB as CSV files.

A full run is automatic and takes about **8 minutes**.

---

## 1. What you need

- **2 ESP32 boards** (one root, one victim). More victims are fine.
- **USB cables** (one per board) — a data cable, not charge-only.
- This repository, cloned/downloaded somewhere on your PC.
- A Windows PC. (These instructions are Windows-specific.)

Both boards show up in Windows as **"Silicon Labs CP210x USB to UART Bridge"**.

---

## 2. Install ESP-IDF (one time)

We use **ESP-IDF v5.3.5**. Other 5.3.x versions usually work, but match this if you can.

1. Download the Windows installer: https://dl.espressif.com/dl/esp-idf/
2. Run it and choose **v5.3.5** when asked which version to install.
3. Keep the default install path (`C:\Espressif`).
4. The installer bundles Python 3.11 and the compiler — you don't need anything else.

When it finishes, you'll have two shortcuts (desktop + Start Menu):

- **ESP-IDF 5.3 PowerShell**  ← use this one
- **ESP-IDF 5.3 CMD**

> **Always build from the "ESP-IDF 5.3 PowerShell" shortcut.** It opens with the
> ESP-IDF tools, `idf.py`, `python`, and `pyserial` already loaded. A normal
> PowerShell or CMD window will **not** work.

---

## 3. Folder layout

```
NIS16-ESP32-Environment/
├── components/mesh_common/   shared code used by EVERY board
├── root_node/                build + flash this onto the ONE root board
├── victim_node/              build + flash this onto the victim board(s)
├── tools/                    host-side export script (export_logs.py)
├── run.ps1                   one-command flash + auto-export helper
└── partitions.csv            flash layout (includes the 'spiffs' data partition)
```

You never edit `mesh_common` to build — `root_node` and `victim_node` both pull
it in automatically.

**Rule: the FOLDER you build from decides the role, not the COM port.**
`root_node` → root firmware. `victim_node` → victim firmware.

---

## 4. Before building: check the mesh settings (one time)

Open `components/mesh_common/include/mesh_config.h` and confirm these two lines:

```c
#define MESH_ID         {0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45}
#define MESH_PASSWORD   "MeshSecure2026!"
```

**Every board must use the exact same values.** Don't change this file between
flashing the root and flashing the victim, or they won't join the same mesh.

---

## 5. Find your COM ports

**Windows reassigns COM numbers depending on the USB port and plug order — they
change.** Always check before flashing. In the **ESP-IDF 5.3 PowerShell**:

```powershell
python -m serial.tools.list_ports
```

The two **"Silicon Labs CP210x"** entries are your two boards. (Ignore any
Bluetooth COM ports.)

**Which board is which?** Unplug one board and re-run the command — whichever
CP210x disappears is that board. **Label the boards physically** (e.g. tape
"ROOT" / "VICTIM") so you don't mix them up.

---

## 6. Build and flash

Open the project folder in the ESP-IDF PowerShell:

```powershell
cd "PATH\TO\NIS16-ESP32-Environment"
```

### Root board (do this first)

```powershell
cd root_node
idf.py build
idf.py -p COM3 flash monitor      # replace COM3 with the root's actual port
```

**Success looks like (in the monitor):**
- `Project name: root_node`
- `=== ROOT NODE STARTING ===`
- `SPIFFS mounted. Total: 345 KB ...`  ← if this line is missing, see [Gotchas](#gotchas-read-before-you-build)
- mesh starts forming

Leave this monitor open. (Exit any monitor anytime with **Ctrl + ]**.)

### Victim board (second PowerShell window)

Open a **second** "ESP-IDF 5.3 PowerShell", then:

```powershell
cd "PATH\TO\NIS16-ESP32-Environment"
cd victim_node
idf.py build
idf.py -p COM6 flash monitor      # replace COM6 with the victim's actual port
```

**Success looks like:**
- `Project name: victim_node`
- `=== VICTIM NODE STARTING ===`
- `SPIFFS mounted ...`
- within ~60 s, the **root** monitor prints `Child connected` and
  `nodes in mesh: 2` → **the mesh formed.** 🎉

> If you edit anything in `components/mesh_common`, rebuild **both** projects.

---

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
.\run.ps1 -Port COM6 -Role victim -Flash
```

- **`-Role` must match what the board is actually flashed as.** Only `-Role root`
  pulls `arrivals.csv` (the probe-arrival proof). Export the root as "victim" by
  mistake and you'll miss `arrivals.csv`.
- Already flashed / board still running and you just want to export? Drop `-Flash`:
  ```powershell
  .\run.ps1 -Port COM6 -Role victim
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
   python export_logs.py --port COM6 --role victim --topology star --attack none --repeat 1
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
   git checkout -- root_node/sdkconfig victim_node/sdkconfig
   idf.py build
   ```

2. **One `idf.py` per project folder at a time.** Two builds hitting the same
   `build/` folder corrupt each other (`ranlib: libwear_levelling.a: No such file`).
   Building `root_node` and `victim_node` in parallel is fine — they're different
   folders. Fix a corrupted build with `idf.py fullclean` then `idf.py build`.

3. **Flashing the app does NOT erase logs.** Telemetry lives at a fixed flash
   address that reflashing leaves untouched, so data survives a reflash. Only
   `erase-flash` or `--delete` / `DELETE_LOGS` wipes it.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `spiffs partition could not be found` / board blinks / reboot loop | Someone ran `idf.py set-target`. Run `git checkout -- root_node/sdkconfig victim_node/sdkconfig` then `idf.py build`. Never run set-target again. |
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
.\run.ps1 -Port COM6 -Role victim -Flash      # terminal 2
# wait ~8 min, then Ctrl+] in each -> auto-exports to tools\exports\

# MANUAL:
cd root_node;   idf.py build; idf.py -p COM3 flash monitor   # terminal 1
cd victim_node; idf.py build; idf.py -p COM6 flash monitor   # terminal 2
# wait ~8 min, then Ctrl+] in both monitors
cd tools
python export_logs.py --port COM3 --role root   --topology star --attack none --repeat 1
python export_logs.py --port COM6 --role victim --topology star --attack none --repeat 1
```

**Two rules to never forget:** build from the **"ESP-IDF 5.3 PowerShell"**
shortcut, and **never run `idf.py set-target`**.
