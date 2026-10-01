# Wireshark quickstart: read a capture and the filters you need

**Created:** sep. 26, 2026 · **For:** NIS 16 · **Read time:** ~8 min

Short companion to [WIRESHARK-GUIDE.md](WIRESHARK-GUIDE.md) (that one explains *why* and how to
capture; this one is *how to read the screen*). Where they disagree, this file is newer and was
checked against real captures (sep. 23 and sep. 26, 2026).

> **Fastest way (sep. 26, 2026):** `run_wizard.ps1` → **WIRESHARK** → *Open a capture in Wireshark*.
> It reads the board MACs from the capture itself and opens Wireshark with the §5 columns, the
> filter for the view you pick (§6–§7) and the I/O graph lines preloaded. Its settings live in
> `%APPDATA%\Wireshark-ThesisMesh`, so your normal Wireshark setup is never changed.
>
> Every filter below was checked with tshark 4.6.9 on the sep. 26 capture. tshark ships with
> Wireshark but is not on PATH. Sets need commas: `{a, b}` — `{a b}` is rejected for MACs.

---

## 1. The three panes

| Pane | What it is |
|---|---|
| Top (packet list) | One row per frame heard. Columns: No., Time, Source, Destination, Protocol, Length, Info |
| Bottom left (details) | The selected frame split into layers. **Click a row first**, then expand here |
| Bottom right (hex) | The raw bytes. Ignore it |

Filter bar (green/red) is above the packet list. **Green = valid filter, red = typo.**

## 2. The four frame types you will see

| What the row says | What it is | Use it for |
|---|---|---|
| `Beacon frame` (Destination Broadcast) | "I exist" announcement, every ~100 ms | Who is alive, topology forming |
| `U, func=UI; SNAP, OUI 0x18FE34 (Espressif) PID 0xEEEE` | **Mesh data frame** (the real traffic) | Forwarding, drops, PDR |
| `Acknowledgement` (blank Source) | Receiver confirming a frame | Ignore (proves delivery only) |
| `Request-to-send` / `Clear-to-send` | Handshake before data | Ignore |

Frames with `Retry` set are re-sends, meaning a weak link.

## 3. Names you have to know

- **ESP32 has two MACs.** Station (STA) = base, e.g. `20:50:0d:e7:1c:38`. SoftAP = base **+1**,
  e.g. `…:39`. Children send from their STA MAC and address the *parent's SoftAP* MAC.
- Wireshark shows `Espressif_73:e6:18` instead of `f4:2d:c9:73:e6:18`. To see full MACs:
  **View → Name Resolution → untick Resolve Physical Addresses.**
- **Destination is the next hop, not the final target.** Every mesh frame is one hop. Never filter
  "attacker → root" with `wlan.da == <root>`; it returns zero frames always.
- A sniffer never transmits, so **its own MAC never appears** in its capture.
- Mesh payload is **not encrypted** (Protected bit is 0). Your seq_num is readable in the data bytes,
  but only the first 64 bytes of each data frame are kept.

## 4. Which fields to read in the details pane

Expand these and ignore the rest:

1. **Radiotap → Antenna signal (dBm)**: link strength. −30 very close, −60 good, −71 usable,
   below −85 barely heard. Also confirm **Channel 11 / 2462 MHz**.
2. **IEEE 802.11 → Type/Subtype** (beacon, data, ACK).
3. **Transmitter address** = who sent this hop. **Receiver address** = next hop.
4. **Sequence number** and the **Retry** flag.
5. **Beacon only:** SSID, Beacon Interval, vendor-specific tag.
6. **LLC → OUI 0x18FE34 / PID 0xEEEE**: confirms it is ESP-MESH data.

Ignore: Frame (Wireshark bookkeeping), Radiotap header revision/pad/length, duplicate
"802.11 radio information", Frame Control bit breakdown, Duration, FCS.

## 5. Add columns (do this once)

Click a packet, **right-click the field in the details pane → Apply as Column** (or Ctrl+Shift+I).

| Column | Field | Click this line |
|---|---|---|
| RSSI | `radiotap.dbm_antsignal` | Antenna signal / Signal strength |
| TA (sender) | `wlan.ta` | Transmitter address |
| RA (next hop) | `wlan.ra` | Receiver address |
| Seq | `wlan.seq` | Sequence number |
| Retry | `wlan.fc.retry` | Flags → Retry |

Right-click a column header → **Edit Column** to rename. Click a header to sort (e.g. RSSI).
Keep a saved copy: **Edit → Preferences → Appearance → Columns** is where they live.

To put sender/receiver first without the Source/Destination confusion, untick the Source and
Destination columns (right-click header → tick to hide).

## 6. Filters (type in the bar, press Enter)

Replace `<MAC>` with a full MAC, e.g. `20:50:0d:e7:1c:38`.

### Clean up the noise

| Goal | Filter |
|---|---|
| Only mesh data | `llc.oui == 0x18fe34` |
| Only data frames | `wlan.fc.type == 2` |
| Hide beacons and ACKs | `!(wlan.fc.type_subtype == 0x08) && !(wlan.fc.type_subtype == 0x1d)` |
| Beacons only | `wlan.fc.type_subtype == 0x08` |
| Management (joins, leaves, beacons) | `wlan.fc.type == 0` |

To keep only your boards, use the `in {}` set in §7.3 (different boards have different MAC prefixes).

### One node

| Goal | Filter |
|---|---|
| Everything to or from a node | `wlan.addr == <MAC>` |
| Node's own sends (its STA MAC) | `wlan.ta == <STA MAC>` |
| Frames addressed **to** a node's SoftAP | `wlan.ra == <SoftAP MAC = STA + 1>` |
| Both interfaces of one board | `wlan.addr == <MAC-18> \|\| wlan.addr == <MAC-19>` |

### Quality and loss

| Goal | Filter |
|---|---|
| Real MAC retransmissions | `wlan.fc.retry == 1` |
| Weak links | `radiotap.dbm_antsignal < -80` |
| Strong links | `radiotap.dbm_antsignal > -60` |
| Data from one child up to its parent | `wlan.ta == <child STA> && wlan.ra == <parent SoftAP>` |

The parent's MAC is **per run**. Roles rotate every time you flash, so never reuse an old table.
Read it from that run's own data, or from a capture: the hop is `wlan.ra` on the child's frames.

### Topology forming

| Goal | Filter |
|---|---|
| Joins and re-joins | `wlan.fc.type_subtype == 0x00 \|\| wlan.fc.type_subtype == 0x02` (association / reassociation request) |
| Leaves | `wlan.fc.type_subtype == 0x0a \|\| wlan.fc.type_subtype == 0x0c` (disassoc / deauth) |
| Who beacons at which rate | Filter beacons, then read `Beacon Interval` (BI=100 vs 300) in the Info column |

## 7. Thesis workflows

### 7.1 Blackhole: does the attacker stop forwarding?

1. Find the attacker's **parent SoftAP MAC** (the receiver of the attacker's frames).
2. Filter: `wlan.ta == <attacker STA> && wlan.ra == <attacker's parent SoftAP>`
3. **Statistics → I/O Graph**, paste that filter into a graph line. The line should **fall to zero
   during the attack window and recover in cooldown.**
4. Prove it still receives (so it isn't just dead): `wlan.ra == <attacker SoftAP>` should stay present
   in every phase.

### 7.2 Wormhole

Wireshark cannot see the wired A↔B tunnel. It only sees the Wi-Fi side effects:
node B's sends drop and node A's sends up (compare phases), and **no** new association frames
(`wlan.fc.type_subtype in {0x00, 0x02}`) appear, which shows the topology did not change.

### 7.3 Only my mesh, all boards

```
wlan.addr in {<MAC1>, <MAC2>, <MAC3>}
```

List **both** the STA (`…:18`) and SoftAP (`…:19`) MAC of every board, or you lose frames.

## 8. Menus worth knowing

| Menu | Gives you |
|---|---|
| **Statistics → Conversations → IEEE 802.11** | Who talks to whom; start here |
| **Statistics → I/O Graph** | Traffic over time, plot one filter per line |
| **Statistics → WLAN Traffic** | Frames and retry % per node |
| **Statistics → Capture File Properties** | Duration, frame count, confirm the whole run is there |
| **File → Export Specified Packets** | Save just the filtered frames |

## 9. Reading the sep. 26 capture (`esp32_sniffer_2026-09-26_191818.pcap`)

- Channel 11 (2462 MHz), confirmed in Radiotap, so the sniffer was on the right channel.
- Data frames chain up the tree: `20:50:0d:e7:0c:80 → …1c:39`, `…1c:38 → f4:2d:c9:73:e6:19`,
  `…73:e6:18 → b0:cb:d8:f3:32:19`. `f3:32:19` beacons fastest (BI=100), so it is probably the root
  in this capture. Confirm before relying on it.
- Frame 486 comes from a random-looking source `42:2f:86:ba:66:9b` with an all-zero SSID. Not one of
  your boards. Worth a look.
- Signal from `0c:80` heard at −71 dBm (noise −96 dBm, SNR 25 dB).

## 10. Troubleshooting

| Problem | Fix |
|---|---|
| Filter bar red | Typo. Check quotes and `&&` |
| Filter shows nothing | Wrong MAC (use STA vs SoftAP), or wrong hop. Try `wlan.addr == <MAC>` first |
| Capture empty | Sniffer not on channel 11, or too far |
| "cut short in the middle of a packet" | Only the last packet is partial. Harmless |
| See only Source/Destination, no TA/RA | Add the TA and RA columns (§5) |
| Payload cut off | Snaplen. Only 64 bytes of data are stored by design |

## 11. Cheat card (copy this)

```
mesh data only:        llc.oui == 0x18fe34
no beacons/acks:       !(wlan.fc.type_subtype == 0x08) && !(wlan.fc.type_subtype == 0x1d)
one board:             wlan.addr == <MAC>
retransmissions:       wlan.fc.retry == 1
child up to parent:    wlan.ta == <child STA> && wlan.ra == <parent SoftAP>
joins:                 wlan.fc.type_subtype == 0x00 || wlan.fc.type_subtype == 0x02
weak signal:           radiotap.dbm_antsignal < -80
```
