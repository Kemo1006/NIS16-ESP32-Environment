# 🩺 BOARD CHECK — is this ESP32 dead, blank, or fine?

> **What this file is:** how to use [`tools/board_check.py`](tools/board_check.py) to settle
> the question *"is this board broken, or does it just need flashing?"* — **without erasing
> anything**. Run it on any board you suspect before you waste an 11-minute capture on it.

---

## 🧠 Why you need this

A board that "doesn't work" can fail in four completely different places, and they need
**opposite fixes**:

| It looks like | But it's actually | The fix |
|---|---|---|
| Board is dead | Charge-only USB cable | swap the cable — **the board is fine** |
| Board is dead | No firmware on it | flash it — **the board is fine** |
| Board is dead | Crash-looping on a full SPIFFS | `-Wipe -Flash` — **the board is fine** |
| Board is dead | Chip / flash / USB bridge genuinely faulty | retire the board |

Guessing wastes hours. `board_check.py` runs **four independent checks** and tells you which
of those four you're looking at.

---

## 🚀 Quick start

Works from **any** PowerShell — it finds `esptool` itself (see below):

```powershell
cd "C:\Users\Angelo Calpoporo\CLionProjects\NIS16-ESP32-Environment\tools"

python board_check.py --list          # 1. which COM ports exist right now?
python board_check.py --port COM28    # 2. diagnose that one
```

> 💡 Plug in **only the suspect board** while testing. That way `--list` shows exactly one
> new port and there's no ambiguity about which board you're holding.

Optional: `--wait 20` gives the runtime check longer to listen (default 10 s). Useful on a
board that boots slowly or joins a mesh before it chatters.

### 🔎 How it finds esptool

`esptool.py` is only on PATH inside the **ESP-IDF PowerShell**. Rather than demand that shell,
the tool searches in order and uses the first that works:

1. `esptool.py` on PATH
2. `esptool` on PATH
3. `python -m esptool` (the interpreter you launched it with)
4. **the ESP-IDF install's own python + bundled `esptool.py`** — auto-discovered under
   `C:\Espressif\frameworks\esp-idf-*` and `C:\Espressif\python_env\*`

On this machine it resolves to #4, so a plain PowerShell is fine.

> ⚠️ **If esptool genuinely cannot be found, the tool REFUSES to judge the board.** It prints
> `VERDICT: CANNOT JUDGE THIS BOARD` and exits — a missing tool is an environment problem and
> must never be mistaken for a hardware fault. Fix it with the ESP-IDF PowerShell shortcut, or
> `pip install esptool`.

---

## 🔬 The four checks

### 1️⃣ Serial port
Does Windows see a USB-serial device at all?

**FAIL means the problem is not the board.** In order of likelihood:
1. **Charge-only USB cable** — by far the most common cause. Many cables have no data lines.
2. Plugged into a **hub** — go direct to the laptop.
3. Missing **CP210x / CH340** driver.

Your boards enumerate as `Silicon Labs CP210x USB to UART Bridge`.

### 2️⃣ Bootloader
Does the ESP32 ROM bootloader answer `esptool`?

**PASS proves a lot at once:** the chip powers up, the USB-serial bridge works, and the
DTR/RTS auto-reset circuit is wired correctly.

**FAIL (with check 1 passing) is the first real evidence of bad hardware** — but try once
more holding the **BOOT / IO0** button while it prints `Connecting....`, then release. If it
connects that way, the chip is fine and only the **auto-reset circuit** is weak — annoying
but usable, and it tells you the board is repairable rather than dead.

This check also reads the **MAC**, which identifies *which* board you're holding (below).

### 3️⃣ Flash chip
Is the SPI flash detected, and is it the **4MB** this project's `partitions.csv` requires?

The 20 Hz sampling era needed the 4MB layout; at the current 10 Hz it still applies. A board
reporting less than 4MB cannot hold the partition table.

### 4️⃣ Firmware runtime
Is an app actually **running and talking** on UART0?

It listens passively for boot/mesh output, then sends **`LIST_FILES`** and waits for the
`csv_logger` export task to answer with `FILE:` / `END_LIST`.

**FAIL here while 1–3 PASS is the good news case:** the hardware is fine, the board is just
blank or crash-looping. Flash it and move on.

---

## ✅ Reading the verdict

```
------------------------------------------------------------
VERDICT: BOARD IS FINE — hardware good, firmware running.
------------------------------------------------------------
```
Nothing wrong with it. If it still misbehaves during a capture, the problem is **placement or
radio**, not the board — see the troubleshooting table in
[`LINEAR-RUNBOOK.md`](LINEAR-RUNBOOK.md#-quick-troubleshooting).

```
VERDICT: HARDWARE IS FINE — no firmware running (blank or crash-looping).
```
**The board is usable.** Flash it:
```powershell
.\run.ps1 -Port COM28 -Role child -Topology linear -Wipe -Flash
```
`-Wipe` full-erases first, which also cures a board crash-looping on a full SPIFFS.

```
VERDICT: SUSPECT HARDWARE — bootloader or flash did not check out.
```
Retry **once with a different cable** before condemning it. If check 2 only passes while
holding BOOT, keep the board but expect to hold BOOT on every flash.

---

## 🏷️ Which board am I holding?

Check 2 reads the STA MAC and matches it against the roster in `board_check.py`, built from
this project's own captured telemetry (`node_id = NODE_<MAC>`) and `BLACKHOLE_ATTACKER_MAC`:

| MAC | Board |
|---|---|
| `28:05:a5:32:d7:b4` | **COM20** — ROOT |
| `b0:cb:d8:f3:32:18` | **COM26** — blackhole ATTACKER / wormhole Node A |
| `f4:2d:c9:73:e6:18` | **COM27** — wormhole Node B |
| `b4:bf:e9:34:ed:80` | **COM21** |
| `b4:bf:e9:32:fe:90` | **COM25** |
| `70:4b:ca:25:b7:68` | **COM22** |

`NOT in the known roster` = a genuine spare. That matters: **`MESH_MAX_LAYER` is now 7**, so a
7th board can join a LINEAR chain (5 children need depth 6; 6 children need depth 7).

> ⚠️ `b0:cb:d8:f3:32:18` is special — it is hard-coded as `BLACKHOLE_ATTACKER_MAC` in
> `mesh_config.h`. **Only that physical board can be the blackhole attacker.** If it dies,
> you must edit `BLACKHOLE_ATTACKER_MAC` and re-flash *every* victim, or the victims will
> send probes to a MAC that isn't in the mesh — which looks exactly like the
> `no route found` failure documented in the troubleshooting table.

---

## 🔒 Safety

- **Never erases.** Reads only — no `write_flash`, no `erase_flash`. Safe on a board that
  still holds an unexported capture.
- **Check 2 does reset the board** (esptool toggles DTR/RTS to enter the bootloader). So
  don't run it mid-capture — it's a bench tool.
- Check 4 opens the port with DTR/RTS **deasserted**, the same trick `export_logs.py` uses,
  so the runtime probe itself does not reboot the board.

---

## 🧭 When to reach for it

| Situation | Do this |
|---|---|
| A board never joins the mesh (`nodes in mesh: 5` not 6) | check it before blaming placement |
| Export hangs with no progress bar | check it — a crash-looping board can't answer `EXPORT_LOGS` |
| Flash fails with `Packet content transfer stopped` | usually the cable; check 1 confirms |
| You found a spare board in a drawer | check it, then read its MAC to see if it's known |
| A board behaved oddly in a run | check it before the repeat, not after |

---

## 🔗 Related

- [`tools/trim_run.py`](tools/trim_run.py) — strip reboot sessions from an exported CSV
  ([why](LINEAR-RUNBOOK.md#-trimming-exports-before-analysis))
- [`LINEAR-RUNBOOK.md`](LINEAR-RUNBOOK.md#-quick-troubleshooting) — the shared troubleshooting table
- [`ARCHIVE-RUNBOOK.md`](ARCHIVE-RUNBOOK.md) — tuck a finished run away safely
