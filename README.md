# NIS16 — ESP32 ESP-WIFI-MESH Testbed (Part 1 of 2)

Firmware + tooling for the thesis *"Cross-Layer Dataset Design and Exploratory
Analysis of ESP32-Based ESP-WIFI-MESH Network"* (DLSU CTTHES2/THES3).

This guide is **Part 1 of 2** and takes you from a fresh laptop to a flashed,
running mesh (steps 1–6). **Follow it top to bottom.** Running the experiment,
exporting the CSVs, verifying the data, gotchas, troubleshooting, and the quick
reference continue in **Part 2, [`README-Part2.md`](README-Part2.md)** (steps 7
onward). If you just need a refresher, jump to the
[Quick Reference](README-Part2.md#quick-reference).

> ⚠️ **The single most important rule:** never run `idf.py set-target`. See
> [Gotchas in README-Part2.md](README-Part2.md#gotchas-read-before-you-build) —
> it silently breaks data logging.

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
├── child_node/              build + flash this onto the victim board(s)
├── tools/                    host-side export script (export_logs.py)
├── run.ps1                   one-command flash + auto-export helper
└── partitions.csv            flash layout (includes the 'spiffs' data partition)
```

You never edit `mesh_common` to build — `root_node` and `child_node` both pull
it in automatically.

**Rule: the FOLDER you build from decides the role, not the COM port.**
`root_node` → root firmware. `child_node` → victim firmware.

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
- `SPIFFS mounted. Total: 345 KB ...`  ← if this line is missing, see [Gotchas in README-Part2.md](README-Part2.md#gotchas-read-before-you-build)
- mesh starts forming

Leave this monitor open. (Exit any monitor anytime with **Ctrl + ]**.)

### Victim board (second PowerShell window)

Open a **second** "ESP-IDF 5.3 PowerShell", then:

```powershell
cd "PATH\TO\NIS16-ESP32-Environment"
cd child_node
idf.py build
idf.py -p COM6 flash monitor      # replace COM6 with the victim's actual port
```

**Success looks like:**
- `Project name: child_node`
- `=== VICTIM NODE STARTING ===`
- `SPIFFS mounted ...`
- within ~60 s, the **root** monitor prints `Child connected` and
  `nodes in mesh: 2` → **the mesh formed.** 🎉

> If you edit anything in `components/mesh_common`, rebuild **both** projects.

---

## ➡️ Next: run it, export, verify → [`README-Part2.md`](README-Part2.md)

The mesh is up. Continue in **Part 2, [`README-Part2.md`](README-Part2.md)** for:
- **Step 7** — let the ~8-minute run finish (phase timeline)
- **Step 8** — export the CSVs (auto-export via `run.ps1`, or manual)
- **Step 9** — where the files land + the Milestone-1 verification checklist
- Re-running clean, **Gotchas**, **Troubleshooting**, and the **Quick Reference**
