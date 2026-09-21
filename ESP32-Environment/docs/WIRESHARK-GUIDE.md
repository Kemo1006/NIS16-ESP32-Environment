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

It puts the ESP32's radio in promiscuous mode and writes a real `.pcap` to an SD card or over
serial. Flash a spare board, set channel 11, run it beside your mesh during a capture, then open the
file in Wireshark.

> Want this wired into `run.ps1` as a proper `pcap_sniffer/` project alongside `root_node/` and
> `child_node/`, so a sniffer board just joins the normal run flow? Ask — it's a contained job.

### Path C — macOS (fastest if you have a Mac)

Macs are the easy case: the built-in Wi-Fi chip supports monitor mode, and Wireshark's own menus
can turn it on — no Terminal needed.

**Click-only method:**

1. Install Wireshark on the Mac if it isn't already: [wireshark.org/download.html](https://www.wireshark.org/download.html)
2. Open Wireshark. On the start screen you'll see a list of interfaces (Wi-Fi, Loopback, etc.)
3. Click the **little gear/cog icon** next to **Wi-Fi** (or: menu bar → **Capture → Options…**)
4. In the row for **Wi-Fi: en0**, tick the box under the column labelled **Monitor Mode**
5. Still in that same Options window, click **Wi-Fi: en0** once to select it, then close the window
6. Click the blue shark-fin ▶ button (top-left) to start capturing
7. **Walk near your boards, with the mesh already powered on and running**
8. Let it run for ~20–30 seconds
9. Click the red ⏹ square to stop
10. **File → Save As…** → save it somewhere you'll remember, ending in `.pcapng`

**If step 4 has no "Monitor Mode" column at all** (some macOS versions hide it), use the Terminal
fallback instead:
```bash
sudo /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport \
     en0 sniff 11
```
Writes a `.cap` into `/tmp/airportSniffXXXX.cap`. Stop with Ctrl-C, then open that file from inside
Wireshark with **File → Open**.

⚠️ Either way, **you must be physically near the ESP32 boards while capturing** — Wi-Fi doesn't
reach very far, and Wireshark can only hear frames that reach the Mac's own antenna.

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

| Board | MAC |
|---|---|
| ROOT | `b0:cb:d8:f3:32:18` |
| attacker_5 | `20:50:0d:e7:1c:38` |
| child_6 | `20:50:0d:e7:0c:80` |
| child_7 | `f4:2d:c9:73:e6:18` |
| child_8 | `70:4b:ca:25:b7:68` |
| child_9 | `28:05:a5:32:d7:b4` |
| child_10 | `b4:bf:e9:32:fe:90` |
| child_11 | `b4:bf:e9:34:ed:80` |

### The five filters that matter

**1. Only my mesh** (drop the whole campus's Wi-Fi):
```
wlan.addr == b0:cb:d8:f3:32:18 || wlan.addr == 20:50:0d:e7:1c:38
```

**2. ⭐ Real MAC retransmissions** — the thing your dataset does not have:
```
wlan.fc.retry == 1
```

**3. Everything the attacker sent:**
```
wlan.sa == 20:50:0d:e7:1c:38
```

**4. Attacker → root specifically** (run this across the attack window; the count should collapse):
```
wlan.sa == 20:50:0d:e7:1c:38 && wlan.da == b0:cb:d8:f3:32:18
```

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

The only physical requirement is **range** — see step 7 below.

### 7.1 One-time setup (do this once, ever)

1. ☐ Install Wireshark on the Mac: [wireshark.org/download.html](https://www.wireshark.org/download.html)
   (free — download the `.dmg`, drag Wireshark into Applications)
2. ☐ Open Wireshark once, just to let macOS finish its first-run setup
3. ☐ Have this file's board MAC table (§5) open on a phone or second screen — you'll paste from it

### 7.2 A practice capture (do this BEFORE your first real run)

**Goal: prove you can see your own boards. Nothing else matters yet.**

1. ☐ Power on your ESP32 mesh (root + at least 2–3 children) and let it form — wait **~60 seconds**
2. ☐ Open Wireshark on the Mac
3. ☐ Click the **gear icon ⚙** next to **Wi-Fi** in the interface list
   *(or: menu bar → **Capture → Options…**)*
4. ☐ Find the row **Wi-Fi: en0** → tick the **Monitor Mode** checkbox
   *(if there's no such checkbox, see the Terminal fallback in §4 Path C)*
5. ☐ Close that dialog, select **Wi-Fi: en0**, click the blue **shark-fin ▶** button
6. ☐ **Carry the Mac to within a few metres of the boards** — Wi-Fi range is short, closer is safer
7. ☐ Let it run **~30 seconds**
8. ☐ Click the red **⏹ stop** square
9. ☐ In the filter bar, type your root's MAC and press Enter:
   ```
   wlan.addr == b0:cb:d8:f3:32:18
   ```
10. ☐ **Rows appear?** ✅ You're done — you can see your mesh. Move to §7.3.
    **Nothing appears?** See Troubleshooting below.

### 7.3 Capturing a REAL run (once the practice capture worked)

Do this **alongside** a normal `run.ps1` / `run_wizard.ps1` capture — the Mac runs the whole time
your boards do, start to finish. It doesn't slow anything down or interfere with the mesh.

1. ☐ **Start the Mac capture FIRST** (steps 3–5 above), then start your normal board run
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

### Troubleshooting — nothing showed up in step 10

| Check | Fix |
|---|---|
| Was Monitor Mode actually ticked? | Reopen Capture Options, confirm the checkbox — it doesn't always stay ticked between sessions |
| Are the boards even powered and mesh-formed? | Wait the full 60 s; check a board's own serial log for "Phase update" |
| Were you close enough? | Move within a few metres; Wi-Fi range indoors is shorter than you'd expect |
| Right channel? | Your mesh is **channel 11**. If using the Terminal fallback, confirm `sniff 11` (not another number) |
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

---

**Related:** `docs/DATA-DICTIONARY.md` (what your CSV columns really contain) ·
`docs/ATTACK-VALIDATION.md` (how the attacks are validated against literature)
