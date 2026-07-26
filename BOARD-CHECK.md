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

| MAC | Board | (old port name) |
|---|---|---|
| `28:05:a5:32:d7:b4` | **node1** — ROOT | COM20 |
| `b4:bf:e9:34:ed:80` | **node2** ⚠️ | COM21 |
| `70:4b:ca:25:b7:68` | **node3** | COM22 |
| `b4:bf:e9:32:fe:90` | **node4** ⚠️ | COM25 |
| `b0:cb:d8:f3:32:18` | **node5** — blackhole ATTACKER / wormhole Node A | COM26 |
| `f4:2d:c9:73:e6:18` | **node6** — wormhole Node B | COM27 |

> 🏷️ **Node numbers, not COM ports.** Every board now goes through whichever single port
> you plug it into, so a board sitting on COM20 that reports "COM26" reads like a
> contradiction. The node number is what you actually type (`--label node5` →
> `child_node5_*.csv`) and how the runbooks name boards. The old port names are kept in
> the last column only so the pre-2026-07-26 placement tables still decode.
>
> ⚠️ **node2 / node4 are unconfirmed.** `ATTACKS-Commands.md`'s board table has these two
> MACs the other way round. Nothing in the campaign depends on it — both are plain victims
> and every CSV keys on the MAC, not the name — but the *label* may be swapped. Confirm
> once by plugging one in and reading the MAC here, then make `ATTACKS-Commands.md` agree.

`NOT in the known roster` = a genuine spare. That matters: **`MESH_MAX_LAYER` is now 7**, so a
7th board can join a LINEAR chain (5 children need depth 6; 6 children need depth 7).

> ⚠️ `b0:cb:d8:f3:32:18` is special — it is hard-coded as `BLACKHOLE_ATTACKER_MAC` in
> `mesh_config.h`. **Only that physical board can be the blackhole attacker.** If it dies,
> you must edit `BLACKHOLE_ATTACKER_MAC` and re-flash *every* victim, or the victims will
> send probes to a MAC that isn't in the mesh — which looks exactly like the
> `no route found` failure documented in the troubleshooting table.

---

## 🔎 WHICH FIRMWARE is on this board?

The MAC tells you *which board*. It does not tell you *what was flashed onto it* — and with
six boards taking five different builds, that is the easier thing to get wrong.

Check 4 now reports it:

```powershell
cd tools
python board_check.py --port COM20
```

```
[4/4] Firmware runtime ....... OK  (app running and answering LIST_FILES)
      firmware: BLACKHOLE ATTACKER  (-Attack blackhole -BlackholeRole attacker)   [boot banner]
```

The variants it distinguishes, and the flags that produce each:

| Reported | Flashed with | Identified from |
|---|---|---|
| `ROOT` | `-Role root` | boot banner — instant |
| `BLACKHOLE ATTACKER` | `-Attack blackhole -BlackholeRole attacker` | boot banner — instant |
| `WORMHOLE NODE A` | `-Attack wormhole -WormholeEnd A` | boot banner — instant |
| `WORMHOLE NODE B` | `-Attack wormhole -WormholeEnd B` | boot banner — instant |
| `BLACKHOLE VICTIM` | `-Attack blackhole -BlackholeRole victim` | ⏳ **needs `--wait 75`** |
| `PLAIN CHILD` | `-Role child`, no `-Attack` | ⏳ **cannot be proven — see below** |

### ⚠️ Plain child vs blackhole victim — the one pair it cannot separate quickly

Both are built from the **same** `victim_main.c`, so at boot both print exactly
`=== VICTIM NODE STARTING ===` and nothing else. The only line that distinguishes them —

```
Blackhole victim mode: probes -> attacker b0:cb:d8:f3:32:18
```

— lives in `probe_gen_task()` (`victim_main.c:147`, inside `#if defined(BLACKHOLE_VICTIM_TARGET)`),
and that task is only started at `victim_main.c:89` — **after `mesh_setup_init()` returns**.

That is the part that matters: `mesh_setup_init()` blocks in `xEventGroupWaitBits()` for up to
**`PHASE_STABILISE_S` = 60 s** (`mesh_setup.c:196`) waiting to join a mesh. When you are
checking a single board on the desk there *is* no mesh, so it waits the **full 60 s** every
time. The default 10 s listen window ends long before that, so you get:

```
      firmware: UNDETERMINED — a CHILD — but PLAIN CHILD and BLACKHOLE VICTIM are
                built from the same firmware and are identical at boot. The line
                that separates them prints only after the mesh comes up (~10-30 s).
                Re-run with --wait 75 (currently 10).
```

**To resolve it, give it longer:**

```powershell
python board_check.py --port COM20 --wait 75
```

**75, not 60.** The tool spends a fixed 4 s on the `LIST_FILES` probe and the rest listening,
so `--wait 75` listens for 71 s — enough to clear the 60 s mesh timeout *and* catch what comes
after it. `--wait 60` listens for only 56 s and misses it every time.

If the board is a blackhole victim, the marker appears and it reports `BLACKHOLE VICTIM`.
If nothing appears even at `--wait 75`, it is *most likely* a plain child — but the tool
still will not claim so, because "no evidence of X" is not proof of "not X".

> 🧠 **Why it refuses to guess.** A confident `PLAIN CHILD` on a board that is really a
> blackhole victim is the worst possible output here: you would trust it, run the experiment,
> and only find out from the data. An honest `UNDETERMINED` costs you 50 seconds.

## 💾 Is this board's SPIFFS about to break the export?

**This is the check that would have saved r2 on 2026-07-26.** A full SPIFFS makes
the board unable to read its own `telem.csv` — `EXPORT_LOGS` announces the right
size and returns **0 rows** (`esp32-issues` I-017). Check 4 reports it:

```powershell
python board_check.py --port COM20 --wait 75
```

```
      SPIFFS:   12 / 2287 KB used (0%)  (healthy)
```

| reading | meaning |
|---|---|
| under ~10 % | clean — safe to run |
| ≥ 50 % | ⚠️ `<-- TOO FULL`. Clear it **before** the run |
| 70 % | the I-017 board: 0.75 Hz sampling, corrupt lines, unreadable export |

> ⏳ **`--wait 75` is required — the same 60 s wall as above.** `csv_logger_init()`
> runs *after* `mesh_setup_init()` (`blackhole_victim.c:125` then `:146`;
> `victim_main.c:75` then `:85`), and that call blocks up to **`PHASE_STABILISE_S`
> = 60 s** when there is no mesh to join. So `SPIFFS mounted. Total: … Used: …`
> lands ~60 s after reset, long after the startup banner.
>
> At the default you get `SPIFFS: not reported` — a **timing limitation, not a
> fault**. `--wait 60` is *also* too short (it listens 56 s); use **75**.

To clear a full board, prefer the guaranteed route:

```powershell
.\run.ps1 -Port COM20 -Role child -Label node5 ... -Wipe -Flash
```

`-Wipe -Flash` full-erases the chip. `export_logs.py --wipe` is faster but can
report `no ack` and silently not take effect — verify it prints
`SPIFFS formatted — flash reset to empty.` before trusting it.

> 🆘 Already stuck with an unreadable board? **Do not wipe it yet** —
> `tools/recover_spiffs.py --port COMxx -o <file>.csv` dumps the raw flash with
> esptool and extracts the rows, bypassing the filesystem entirely.

---

### Why it has to read the boot banner

The attack role is a **compile-time build flag** (`-DACTIVE_ATTACK`, `-DBLACKHOLE_ROLE`,
`-DWORMHOLE_END` — see `run.ps1:216-237`). It is baked into the binary; nothing on the device
exposes it at runtime. The banner each variant prints at startup is the **only**
self-declaration there is, so `board_check.py` matches against those strings.

Check 2 resets the chip via esptool immediately before Check 4 listens, so the banner is
normally still in the captured window. If the board booted long ago and has stopped
chattering you may instead get:

```
      firmware: UNDETERMINED — banner not in the captured window — the board booted
                a while ago. Power-cycle it and re-run to catch the banner
```

**That is not a failure — power-cycle the board and run it again.** It reports
`UNDETERMINED` rather than guessing, because a wrong answer here sends you into a run with
the wrong firmware on a board, which you would not discover until the data came out wrong.

> 🔁 If `run.ps1` reflashes a board, this reads the **new** firmware — it is live state, not a
> record of what you intended. To confirm a board *before* a run, check it after flashing.

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
