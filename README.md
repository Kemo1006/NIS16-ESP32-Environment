# NIS16 — Cross-Layer Dataset Design and Exploratory Analysis of ESP32-Based ESP-WIFI-MESH Network

## 1. Install ESP-IDF
We're using **ESP-IDF v5.3.5**. Other 5.3.x versions are probably fine, but match this if possible.

1. Download the Windows installer: https://dl.espressif.com/dl/esp-idf/
2. Run it and select **v5.3.5** when asked which version to install.
3. Keep the default install path (`C:\Espressif`).
4. The installer includes Python 3.11 and the compiler — you don't need to install anything else.

## 2. Open the build environment
After installation, the ESP-IDF installer creates two shortcuts on your desktop (and in the Start Menu):

- **ESP-IDF 5.3 CMD** — a Command Prompt window
- **ESP-IDF 5.3 PowerShell** — a PowerShell window

**Use either one.** Both open with the ESP-IDF environment already active — you don't need to run any setup commands. Just open the shortcut, `cd` into the project folder, and start building.

## 2. What you need
- 2 ESP32 boards (one becomes root, one becomes victim)
- USB cables
- This repo, cloned or downloaded into your assignments folder

## 3. Folder layout
```
esp32-mesh-firmware/
├── components/mesh_common/     ← shared code (used by every board)
├── root_node/                  ← flash this onto ONE board
└── victim_node/                ← flash this onto the other board(s)
```

You don't need to touch `mesh_common` directly — `root_node` and `victim_node` both pull it in automatically.

## 4. Before building: set your mesh password
Open `components/mesh_common/include/mesh_config.h` and check these two lines:

```c
#define MESH_ID         {0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45}
#define MESH_PASSWORD   "MeshSecure2026!"
```

Every board needs the **same** values here. Don't change this file between flashing the root and flashing the victim.

## 5. Build and flash
**Root node** (one board, e.g. COM3):
```powershell
cd root_node
idf.py set-target esp32
idf.py build
idf.py -p COM3 flash monitor
```

**Victim node** (open a second terminal, other board, e.g. COM4):
```powershell
cd victim_node
idf.py set-target esp32
idf.py build
idf.py -p COM4 flash monitor
```

If you change anything in `mesh_common`, rebuild **both** projects. Delete the build folder first:

```powershell
# PowerShell
Remove-Item -Recurse -Force build
idf.py build
```
```cmd
rem CMD / Start Menu shortcut
rmdir /s /q build
idf.py build
```