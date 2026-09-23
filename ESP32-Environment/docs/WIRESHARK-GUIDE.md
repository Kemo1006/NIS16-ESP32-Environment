# Wireshark, for people who have never opened it

**Created:** sep. 20, 2026 · **For:** NIS 16 · **Read time:** ~15 min

---

## 0. Why you can't skip this

Your approved proposal already promises it. Two places:

> **§ Tools —** *"Wireshark is used as a supplemental packet-capture and verification tool to observe
> wireless traffic patterns, confirm packet-forwarding behavior, and support validation of attack
> effects."*

> **Ethics form —** *"Wireshark: GNU GPL license; used solely for verification within the isolated
> test network."*

**As of today the project has never captured a single packet.** That is a promised method that was
never performed — the kind of gap a panel finds by reading your own tool list and asking "show me."
This guide closes it.

It also happens to be the cleanest answer to the professor's *"we created our own format"* warning.
More on that in §6.

---

## 1. What Wireshark actually is

Think of your mesh as a room full of people talking.

- **Your CSV logs** are like asking each person afterwards: *"How many times did you speak? Who were
  you talking to?"* — you get their **own account** of what they did.
- **Wireshark** is a **microphone in the middle of the room.** It records what was actually said in
  the air, by whom, to whom, and exactly when — **regardless of what anyone claims afterwards.**

That difference is the entire point. Right now, the only evidence your blackhole attacker dropped
packets is **the attacker's own counter saying it dropped packets.** The node performing the attack
is the witness to the attack. A panel will notice. A microphone in the room is an independent
witness.

Wireshark itself is just the **viewer**. The recording is a file called a **`.pcap`** (or `.pcapng`)
— the universal, decades-old standard format for captured network traffic. Every network tool on
earth reads it.

---

## 2. The honest part: what it CAN and CANNOT see

Your mesh is encrypted (`MESH_PASSWORD "MeshSecure2026!"`). Read this table before you get excited
or disappointed:

| ✅ You CAN see | ❌ You CANNOT see |
|---|---|
| **Who transmitted** (source MAC) | **The probe contents** — `seq_num`, timestamps, payload |
| **Who it was for** (destination MAC) | Anything inside the encrypted body |
| **The 802.11 Retry bit** ⭐ | Application-layer meaning |
| Frame type (data / ACK / beacon / auth) | |
| **Exact timing**, to the microsecond | |
| Frame length, data rate, RSSI | |
| 802.11 sequence numbers | |
| **Beacons, joins, leaves, disassociations** ⭐ | |

The two ⭐ rows are why this is worth doing. Keep reading.

---

## 3. Why this matters for *your* thesis — three concrete wins

### Win 1 — You finally get REAL MAC-layer data

Your paper's Table 4.5 says `retry_count` and `tx_count` are *"cumulative MAC retransmissions"* from
the *"ESP-IDF Wi-Fi statistics API."*

**They are not.** They're application counters, and they mean three different things depending on
which board wrote the row (see `docs/DATA-DICTIONARY.md`). No column in your dataset contains a real
802.11 retry.

The 802.11 header has a **Retry bit** — one bit, set by the radio itself, meaning "this is a
re-transmission." That is the genuine article. Capture it once and the claim becomes true instead of
approximately-true.

### Win 2 — Independent proof of your topology

Right now, "the chain formed correctly" rests on each node reporting its own layer and parent.
Self-reported, again.

Beacons and association frames are **not encrypted**. A capture shows you, from the outside, exactly
which node associated with which parent and when — including every re-parenting event. That's
independent confirmation of Milestone 3.

### Win 3 — Independent proof the blackhole dropped packets

During the attack window your attacker still **receives** frames and still **ACKs** them at the radio
level (that's why victims see no retries — §3.3.1.2 predicted this correctly). A capture shows:

- frames going **into** the attacker: present, ACKed ✅
- frames coming **out** of the attacker toward the root: **gone** ❌

That is the attack, witnessed from outside the attacker. No circularity.

---

## 4. Getting a capture — pick your path

Normal Wi-Fi adapters only show you *your own* traffic. To hear everything you need **monitor mode**.

| Path | Difficulty | Verdict |
|---|---|---|
| **A. Spare ESP32 as sniffer** | ⭐⭐ Medium | ✅ **Recommended.** Same hardware you already own and can already flash |
| **B. Linux + monitor-capable USB adapter** | ⭐⭐⭐ Hard | Best data quality, needs specific hardware |
| **C. macOS built-in** | ⭐ Easy | ✅ Do this **today** if anyone has a Mac |
| **D. Windows laptop Wi-Fi** | 🚫 | **Does not work.** Don't burn a day on it |

### ⚠️ The one setting that ruins everything

Your mesh is on **channel 11** (`MESH_CHANNEL 11` in `mesh_config.h`). A sniffer on any other channel
records **an empty file** while looking perfectly healthy. **Lock the sniffer to channel 11.** This
is the single most common way a capture session gets wasted.

---

### Path A — ESP32 sniffer (recommended)

ESP-IDF already ships this. On this machine:

```
C:\Espressif\frameworks\esp-idf-v5.5.4\examples\network\simple_sniffer\
```

It puts the ESP32's radio in promiscuous mode and writes a real `.pcap` to an SD card (or RAM /
JTAG — **not** plain serial). ⚠️ Out of the box it expects SDMMC or SPI pins 15/2/14/13 at ~20 MHz;
our boards are SPI on **23/19/18/5 at 4 MHz** (`mesh_config.h`), so it needs those edits first.
Flash a spare board, set channel 11, run it beside your mesh during a capture, then open the
file in Wireshark.

> Want this wired into `run.ps1` as a proper `pcap_sniffer/` project alongside `root_node/` and
> `child_node/`, so a sniffer board just joins the normal run flow? Ask — it's a contained job.

### Path C — macOS (fastest if you have a Mac)

**Updated sep. 21, 2026 after checking current reports — the earlier "Apple Silicon is broken"
framing in this guide was too pessimistic. It usually DOES work; there's just one specific step
people miss.** Sources at the bottom of this section.

**The #1 thing that breaks monitor-mode capture on ANY modern Mac (Intel or Apple Silicon), and is
the actual cause almost every time someone sees an empty capture:**

> ⚠️ **Disconnect the Mac from Wi-Fi entirely (click the Wi-Fi icon → Wi-Fi Off, or forget the
> network) BEFORE you turn on Monitor Mode in Wireshark.** If the Mac stays joined to a network
> while you enable monitor mode, capture silently returns nothing useful — no error, it just
> doesn't work. This is a documented, common issue, not something specific to your machine or your
> chip. Turn Wi-Fi back on afterward if you need internet again.

**Click-only method:**

1. Install Wireshark on the Mac if it isn't already: [wireshark.org/download.html](https://www.wireshark.org/download.html)
2. **Turn the Mac's Wi-Fi OFF** (menu bar Wi-Fi icon → Turn Wi-Fi Off) — see the box above
3. Open Wireshark. On the start screen you'll see a list of interfaces (Wi-Fi, Loopback, etc.)
4. Click the **little gear/cog icon** next to **Wi-Fi** (or: menu bar → **Capture → Options…**)
5. In the row for **Wi-Fi: en0**, tick the box under the column labelled **Monitor Mode**
6. Still in that same Options window, click **Wi-Fi: en0** once to select it, then close the window
7. Click the blue shark-fin ▶ button (top-left) to start capturing
8. **Walk near your boards, with the mesh already powered on and running**
9. Let it run for ~20–30 seconds
10. Click the red ⏹ square to stop
11. **File → Save As…** → save it somewhere you'll remember, ending in `.pcapng`

**If step 5 has no "Monitor Mode" column at all, OR you ticked it and step 9 still shows nothing,
use Apple's own built-in sniffer instead** — it has reliably supported monitor mode across both
Intel and Apple Silicon Macs even as Apple's command-line tools changed underneath it:

1. **Option-click** the Wi-Fi icon in the menu bar (hold Option, then click)
2. Choose **"Open Wireless Diagnostics…"**
3. In the menu bar (while Wireless Diagnostics is the active app): **Window → Sniffer**
4. Pick channel **11**, width **20 MHz**, click **Start**
5. Let it run ~20–30 s near your boards, click **Stop**
6. It saves a `.wcap`/`.pcap` file — on newer macOS in **`/var/tmp`** (Finder → Cmd+Shift+G), on
   older ones the Desktop — open that file directly in Wireshark

> ⚠️ **For the Wireless Diagnostics Sniffer, Wi-Fi must be ON but NOT joined to a network**
> (Option-click Wi-Fi → Disconnect). The "turn Wi-Fi OFF" advice above is for Wireshark's monitor
> mode only — the Sniffer needs the radio powered, so Wi-Fi OFF gives a 0-byte file (sep. 23 2026,
> M1 MacBook). **Test first:** `run_wizard.ps1` → *MacBook sniffer test* (~2 min, no attack run).

⚠️ **Do NOT use the old `airport` Terminal command** shown in older Wireshark tutorials online —
**Apple permanently removed it in macOS Sonoma 14.4** (early 2024). If your Mac is on Sonoma 14.4+
or newer, that command will simply fail with "command not found." Use the Wireless Diagnostics
Sniffer above instead; it's Apple's maintained replacement path.

⚠️ Whichever method you use, **you must be physically near the ESP32 boards while capturing** —
Wi-Fi doesn't reach very far, and the Mac can only hear frames that reach its own antenna.

**Sources checked sep. 21, 2026:**
[Wireshark Q&A — "Can no longer capture traffic on M1"](https://ask.wireshark.org/question/26479/can-no-longer-capture-traffic-on-m1/) ·
[Intuitibits — "Goodbye, airport!"](https://www.intuitibits.com/2024/03/14/goodbye-airport/) ·
[nuxx.net — command-line monitor mode on Sonoma](https://nuxx.net/blog/2023/10/20/command-line-802-11-monitor-mode-on-macos-sonoma-14-0/)

### Path B — Linux

```bash
sudo airmon-ng start wlan0            # creates wlan0mon
sudo iwconfig wlan0mon channel 11     # ⚠️ channel 11
sudo wireshark                        # capture on wlan0mon
```

Needs an adapter whose chipset supports monitor mode (Atheros AR9271, Ralink RT3070, MediaTek
MT7612U are the usual safe buys).

---

## 5. You have a capture. Now what?

Open the file. You'll see thousands of rows and panic. **Don't read them** — filter them. The bar at
the top is the **display filter**. Type, press Enter.

### Your boards (copy-paste these)

⚠️ **This table was WRONG until sep. 23, 2026 — it had ROOT and child_8 swapped.** It listed
`b0:cb:d8:f3:32:18` as ROOT, but that board has been a plain child since at least the sep. 22
capture, where `70:4b:ca:25:b7:68` is the root. Filtering for "the root" with the old MAC would have
shown you a child's traffic and nothing would have looked obviously broken. Corrected below against
`blackhole/linear/home` r1. **Re-derive it before you trust it** — see the command under the table.

| Board | MAC | Role in the sep. 22 `blackhole/linear/home` r1 run |
|---|---|---|
| ROOT | `70:4b:ca:25:b7:68` | root (hop 0) |
| attacker | `20:50:0d:e7:1c:38` | **blackhole** (hop 2) |
| child (downstream) | `20:50:0d:e7:0c:80` | **VICTIM** — below the attacker (hop 3) |
| child (upstream) | `b0:cb:d8:f3:32:18` | not in the attack path (hop 1) |
| spare | `f4:2d:c9:73:e6:18` | not in this run |
| spare | `28:05:a5:32:d7:b4` | not in this run |
| spare | `b4:bf:e9:32:fe:90` | not in this run |
| spare | `b4:bf:e9:34:ed:80` | not in this run |

**The role column is PER RUN, not a property of the board.** Which board is root, and which children
sit below the attacker, depends on how the mesh formed that day. Only the ATTACKER is fixed at build
time. Since sep. 23 the root prints an EXPOSURE block at boot naming who is actually a victim, and
`verify_topology.py --structure` prints the same from a finished capture — use either rather than
assuming this table still applies.

**Re-derive the MAC↔role mapping from any capture in one line** (this is where the table above came
from, so it can never drift again):

```bash
python tools/verify_topology.py --dir tools/exports --topology linear \
    --attack blackhole --location home --repeat 1 --expect linear --structure
```

That prints HOP, MAC, ROLE and EXPOSURE together. Copy the MACs straight out of it.

**Where this table came from — and when it goes stale:** every MAC above was read directly from
each board's own telemetry (the `node_id` column every board writes into its own CSV), cross-checked
against `mesh_config.h`'s compiled `BLACKHOLE_ATTACKER_MAC` and `member_boards.json`. An ESP32's MAC
is burned into the chip and doesn't change on reflash — **but if you ever physically swap which
board is root or which is the attacker, this table is wrong for that board**, and any Wireshark
filter using the old MAC will silently show nothing for it.

**If you swap boards, do this before your next capture:**
1. `run_wizard.ps1` → **"Identify all boards"** — prints the live COM port + MAC for every board
2. Update `member_boards.json` (the wizard's member-list submenu does this for you)
3. Update the filters you're using in Wireshark with the new MAC(s)

⚠️ **Swapping the ATTACKER specifically is the dangerous one, not just for Wireshark.** Victims are
built with the attacker's MAC compiled in (`BLACKHOLE_ATTACKER_MAC`). Swap in a different physical
board as the attacker without updating that, and every victim addresses probes to a board that isn't
there any more — the root logs **zero arrivals in every phase**, PDR and ForwardingRatio come out
**100% NaN**, and every board still looks perfectly healthy. This exact failure cost two full runs
before it was diagnosed (sep. 15, sep. 16).
**Since F2 you don't need to re-flash to fix it** — on each victim, run:
```
python tools\export_logs.py --port COMxx --set-attacker-mac <new attacker MAC>
```
then power-cycle that victim. The attacker board itself also prints a loud MISMATCH banner at boot
if a victim is still targeting the wrong MAC, so a stale target is hard to miss once you look.

**Swapping the ROOT is comparatively harmless.** Victims never address the root by a fixed MAC —
they send with `MESH_DATA_TODS` ("route this to whoever the mesh currently has as root"), which the
mesh stack resolves automatically. A different physical root board just means a different MAC in
step 1–3 above; nothing needs re-flashing or re-targeting.

### The five filters that matter

**1. Only my mesh — ALL 8 boards** (drop the whole campus's/library's Wi-Fi in one go):
```
wlan.addr in {b0:cb:d8:f3:32:18, 20:50:0d:e7:1c:38, 20:50:0d:e7:0c:80, f4:2d:c9:73:e6:18,
              70:4b:ca:25:b7:68, 28:05:a5:32:d7:b4, b4:bf:e9:32:fe:90, b4:bf:e9:34:ed:80}
```
*(Wireshark's `in {}` accepts a set of addresses in one filter — much cleaner than chaining 8
`||`s. Type it as one line; wrapped here only for page width.)*

**Just checking ONE board** (e.g. the practice capture, or isolating one victim):
```
wlan.addr == 70:4b:ca:25:b7:68
```

**2. ⭐ Real MAC retransmissions** — the thing your dataset does not have:
```
wlan.fc.retry == 1
```

**3. Everything the attacker sent:**
```
wlan.sa == 20:50:0d:e7:1c:38
```

**4. ⭐ Attacker → ITS PARENT** (the count should collapse across the attack window):
```
wlan.sa == 20:50:0d:e7:1c:38 && wlan.da == b0:cb:d8:f3:32:18
```
⚠️ **This filter says "attacker → its PARENT", not "attacker → root".** In the sep. 22 run the chain
was `root → b0:cb…18 → attacker → 20:50…0c:80`, so the attacker's parent happened to be `b0:cb…18`
and this is the right frame to watch. **The parent changes when the topology changes**, and then this
MAC is wrong and the filter silently shows nothing. Get the current one from
`verify_topology.py --structure` (the UPLINK column of the attacker's row) before each capture.

**5. The mesh forming / re-forming** (beacons + joins, unencrypted):
```
wlan.fc.type == 0
```

### Three menu items worth knowing

| Menu | What it gives you |
|---|---|
| **Statistics → Conversations** | Who talked to whom, how many frames, how many bytes. **Start here** |
| **Statistics → I/O Graph** | Traffic over time. Set the filter to #4 and *watch the attack window drop to zero* |
| **Statistics → WLAN Traffic** | Per-node frame counts and retry percentages |

**Statistics → I/O Graph with filter #4 is the single most valuable screenshot in this guide.** It is
your attack, drawn as a line falling off a cliff and coming back, witnessed from outside.

---

## 6. How this answers the professor

The warning was *"we created our own format in networking."*

Your dataset is per-node CSVs with columns you defined. Established intrusion-detection datasets
(**AWID**, **CIC-IDS**) are built from **pcap** plus derived features.

> **Do not replace your CSVs — add pcap alongside them.**

Your CSVs hold things a sniffer physically cannot see: each node's mesh layer, its parent, the phase
label, the relay counters. A sniffer holds things your CSVs cannot: real MAC retries, independent
timing, unencrypted management frames.

**"Raw pcap + derived per-node features" is exactly the shape AWID and CIC-IDS have.** That sentence
alone converts "you invented a format" into "we used the standard format *and* added cross-layer
node state." Same data, completely different reception.

⚠️ **Be honest about coverage.** Runs already captured have no pcap and never will. Say so plainly in
the limitations — *"packet-level verification was introduced from run N onward"* — and do **not**
backfill or imply otherwise.

---

## 7. Full MacBook walkthrough — step by step

### Do you need more than one MacBook?

**No. One is enough.** Wireshark on the Mac isn't listening for "its own" traffic — in monitor mode
it just records **everything in the air on that channel**, like a microphone in the room. Every one
of your boards is talking on the same channel (11), so one Mac sitting near the boards hears **all
of them at once.** You do not need a Mac per board, per role, or per topology.

The only physical requirement is **range** — see step 8 below.

### 7.1 One-time setup (do this once, ever)

1. ☐ Install Wireshark on the Mac: [wireshark.org/download.html](https://www.wireshark.org/download.html)
   (free — download the `.dmg`, drag Wireshark into Applications)
2. ☐ Open Wireshark once, just to let macOS finish its first-run setup
3. ☐ Have this file's board MAC table (§5) open on a phone or second screen — you'll paste from it

### 7.2 A practice capture (do this BEFORE your first real run)

**Goal: prove you can see your own boards. Nothing else matters yet.**

1. ☐ Power on your ESP32 mesh (root + at least 2–3 children) and let it form — wait **~60 seconds**
2. ☐ **Turn the Mac's Wi-Fi OFF** (menu bar Wi-Fi icon) — see §4 Path C for why this step matters
3. ☐ Open Wireshark on the Mac
4. ☐ Click the **gear icon ⚙** next to **Wi-Fi** in the interface list
   *(or: menu bar → **Capture → Options…**)*
5. ☐ Find the row **Wi-Fi: en0** → tick the **Monitor Mode** checkbox
   *(no such checkbox, or ticked it and still nothing in step 11? use the Wireless Diagnostics
   Sniffer fallback in §4 Path C instead — NOT the old `airport` command, which Apple removed)*
6. ☐ Close that dialog, select **Wi-Fi: en0**, click the blue **shark-fin ▶** button
7. ☐ **Carry the Mac to within a few metres of the boards** — Wi-Fi range is short, closer is safer
8. ☐ Let it run **~30 seconds**
9. ☐ Click the red **⏹ stop** square
10. ☐ In the filter bar, type your root's MAC and press Enter:
    ```
    wlan.addr == 70:4b:ca:25:b7:68
    ```
    *(That is the root as of the sep. 22 run. If you have swapped boards, get the current root's MAC
    from `verify_topology.py --structure` — the row with hop H00.)*
11. ☐ **Rows appear?** ✅ You're done — you can see your mesh. Move to §7.3.
    **Nothing appears?** See Troubleshooting below.

### 7.3 Capturing a REAL run (once the practice capture worked)

Do this **alongside** a normal `run.ps1` / `run_wizard.ps1` capture — the Mac runs the whole time
your boards do, start to finish. It doesn't slow anything down or interfere with the mesh.

1. ☐ **Start the Mac capture FIRST** (§7.2 steps 2–6: Wi-Fi off, open Wireshark, tick Monitor Mode,
   start), then start your normal board run
   *(capturing a few extra seconds of "nothing yet" at the start is harmless; missing the start of
   the real run is not — always start the Mac first)*
2. ☐ Stay within range of the boards for the whole run (an 11-minute run = an 11-minute walk-along,
   or just sit near the rig)
3. ☐ Once your boards finish (root announces TERMINATE, exports happen as normal), **stop the Mac
   capture a few seconds after**, same over-capture-a-little rule as the start
4. ☐ **File → Save As…**

### 7.4 Naming the file (so it can be matched to its CSVs later)

Your CSV exports already follow a strict pattern (`tools/validate_integrity.py` `FILENAME_RE`):

```
<role>_<nick>_<topology>_<attack>_r<repeat>_<date>_<time>_<telem|arrivals>.csv
```

Name the pcap the same way, with `pcap` as the kind, so anyone can tell at a glance which run it
belongs to:

```
pcap_<topology>_<attack>_r<repeat>_<date>_<time>.pcapng

  e.g.  pcap_linear_blackhole_r1_20260921_143000.pcapng
```

Save it into the **same folder** as that run's CSVs:
```
tools/exports/<attack>/<topology>/<location>/
```
so `pcap_linear_blackhole_r1_20260921_143000.pcapng` sits right next to
`root_ROOT_linear_blackhole_r1_20260921_143010_telem.csv` — same run, same folder, obvious pairing.

### 7.5 After saving — confirm the whole run is in there

1. ☐ Reopen the saved file (or it's still open)
2. ☐ **Statistics → Capture File Properties** — check the duration roughly matches the run length
   (~11 min for a full baseline→attack→cooldown run)
3. ☐ Apply filter #4 from §5 (attacker → root) and check **Statistics → I/O Graph** — you should see
   the line **drop during the attack window and recover during cooldown**. That graph is your proof.

**Do not attempt a full 11-minute real run on your very FIRST try with the Mac.** Do the §7.2
practice capture first, confirm you can see your boards, THEN attach it to a real run. That
separation is the whole point of §7.2 — it turns "did the Wireshark part work?" into a yes/no answer
you already know before it matters.

### Troubleshooting — nothing showed up in step 11

| Check | Fix |
|---|---|
| Was Monitor Mode actually ticked? | Reopen Capture Options, confirm the checkbox — it doesn't always stay ticked between sessions |
| Are the boards even powered and mesh-formed? | Wait the full 60 s; check a board's own serial log for "Phase update" |
| Were you close enough? | Move within a few metres; Wi-Fi range indoors is shorter than you'd expect |
| Right channel? | Your mesh is **channel 11**. If using Wireless Diagnostics Sniffer, confirm you picked channel 11 (not another number) |
| Still on Wi-Fi while capturing? | **Wireshark monitor mode:** turn the Mac's Wi-Fi off first. **Wireless Diagnostics Sniffer:** the opposite — Wi-Fi ON but disconnected; Wi-Fi OFF = 0-byte file. See §4 Path C |
| Typo'd the MAC filter? | Copy-paste from §5's table — a single wrong hex digit filters out everything |

---

## 8. Cheat sheet

| I want to... | Do this |
|---|---|
| See only my mesh | `wlan.addr == <mac>` |
| **Find real retransmissions** | `wlan.fc.retry == 1` |
| See who talks to whom | Statistics → Conversations |
| **See the attack happen** | I/O Graph + `wlan.sa == <attacker> && wlan.da == <root>` |
| Watch the mesh form | `wlan.fc.type == 0` |
| Nothing is being captured | **You are on the wrong channel. It is 11.** |
| Wireshark: "cut short in the middle of a packet" | Only the LAST packet is partial (file grabbed before the Sniffer finished writing — wait ~10 s after Stop). Everything else is fine. `python tools\check_pcap.py <file>` (or wizard → *Check a Mac sniffer capture file*) reports mesh beacons/data + span and writes a `_fixed` copy |

---

## 9. Using this to validate the blackhole and wormhole SPECIFICALLY

`docs/ATTACK-VALIDATION.md` already proves both attacks conform to their published definitions —
but every bit of evidence there comes from the boards' **own CSV logs**. A board reporting on
itself is still one witness. Wireshark is a **second, independent** witness that doesn't depend on
any board telling the truth about itself. This section shows exactly which filter proves which
claim, matching the criteria tables in `ATTACK-VALIDATION.md` one-for-one.

**Do this on a run that includes all three phases** — baseline, attack, cooldown — so you can
compare "before" against "during" against "after," not just look at one snapshot.

### 9.1 Validating the BLACKHOLE

| Claim from `ATTACK-VALIDATION.md` | Filter | What you should see |
|---|---|---|
| Attacker **receives** the packets (not radio jamming) | `wlan.da == 20:50:0d:e7:1c:38` | Frames arriving **in every phase**, including during the attack — proves it's receiving, not being jammed off the air |
| Attacker **drops instead of forwarding** — the core claim | `wlan.sa == 20:50:0d:e7:1c:38 && wlan.da == <the attacker's PARENT, H01 in verify_topology --structure>` | Frames present in baseline **and** cooldown, then **a gap** for the whole attack-phase window. **This is the single most convincing screenshot in your whole thesis** — apply **Statistics → I/O Graph** to this exact filter and watch the line fall to zero and climb back |
| Attacker **stays protocol-compliant** — still a live mesh member | `wlan.addr == 20:50:0d:e7:1c:38` (drop the `da`/`sa` restriction) | Traffic from the attacker continues throughout the attack window — it's still associated, still sending/receiving management frames, just not forwarding victim probes. If it went completely silent instead, that would mean something different happened (a crash, not a blackhole) |
| **Independent check of Table 3.4's "increased retries" prediction** | `wlan.fc.retry == 1 && (wlan.addr in {victim MACs from §5})` | Should stay near-zero through the attack window. This corroborates the pre-registered MISS in `ATTACK-VALIDATION.md` §2.2 using **real 802.11 header data**, not the application-layer `retry_count` column — a stronger, independent form of the same finding |

### 9.2 Validating the WORMHOLE — read the limit first

⚠️ **Be honest about what Wireshark can and can't show here.** The actual A↔B tunnel is a
**physical wired UART cable** between the two boards (`mesh_config.h`), not a Wi-Fi transmission —
Wireshark is a radio-frequency tool, so **it cannot see the tunnel itself, at all, ever.** What it
*can* see is the Wi-Fi-side evidence of what the tunnel causes:

⚠️ **Node A's and Node B's MAC are NOT the same as the §5 table's roles.** Which physical board
plays "root", "attacker", "wormhole_a" or "wormhole_b" depends on which firmware it was flashed
with **for that specific run** — the same board can be root in one capture and a wormhole endpoint
in the next. Don't reuse the §5 table's blackhole-run MACs here. For the wormhole run you're
validating, get the real values from that run's own CSVs (the `node_id` column, `role` column says
`wormhole_a` / `wormhole_b`) or `run_wizard.ps1 → Identify all boards` at the time of that capture.
*(For reference — the archived 2026-09-16 wormhole/linear r2 and r3 runs analysed in
`ATTACK-VALIDATION.md` used `NODE_B0CBD8F33218` = wormhole_a and `NODE_F42DC973E618` = wormhole_b —
the SAME two physical boards that played ROOT and child_7 in the later G402 blackhole capture. That
is exactly the "same board, different role" case this warning is about.)*

| Claim from `ATTACK-VALIDATION.md` | Filter | What you should see |
|---|---|---|
| Node B stops sending its probes directly (it's tunnelling them over the wire instead) | `wlan.sa == <Node B's MAC>` — compare baseline phase vs. wormhole phase | B's direct Wi-Fi transmissions should **drop noticeably** during the wormhole phase vs. its own baseline rate — it's routing its traffic through the wire now, not the air |
| Node A **re-injects** the tunnelled probes on B's behalf | `wlan.sa == <Node A's MAC> && wlan.da == <Node A's PARENT>` — compare the same two phases | Node A's traffic toward the root should be **higher** during the wormhole phase than its own baseline rate — the extra volume is B's re-injected probes |
| **Independent check of the "topology does NOT distort" finding** — the actual headline result in `ATTACK-VALIDATION.md` §2 | `wlan.fc.type == 0`, watch the **Info** column for "Association Request/Response" or "Reassociation…" | You should see **zero** new association/reassociation events during the wormhole phase. Beacons and associations are **unencrypted**, so this confirms — from OUTSIDE any board's own self-report — that no node actually re-parented during the attack. This is the strongest possible corroboration of that result, because it comes from a source that couldn't be fooled even if a board's telemetry were lying |

### 9.3 What to put in the paper

A screenshot of the blackhole's **I/O Graph drop** (§9.1, row 2) next to the CSV-derived
`ForwardingRatio` collapse (`ATTACK-VALIDATION.md` §1) is two independent measurements of the same
event, agreeing. That pairing — one from the attacker's own telemetry, one from a witness that
doesn't trust the attacker at all — is exactly what turns "we measured an effect" into "we verified
an effect," and it's the strongest form of evidence this thesis can produce.

---

**Related:** `docs/DATA-DICTIONARY.md` (what your CSV columns really contain) ·
`docs/ATTACK-VALIDATION.md` (how the attacks are validated against literature; §9 above adds
independent packet-capture corroboration to those same claims)
