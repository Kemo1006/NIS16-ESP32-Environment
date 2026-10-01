# Wireshark terms: what every word on the screen means

**Created:** sep. 30, 2026 · **For:** NIS 16 · **Use:** look-up reference, not a read-through

The third Wireshark doc. The other two tell you *why* ([WIRESHARK-GUIDE.md](WIRESHARK-GUIDE.md))
and *how to drive it* ([WIRESHARK-QUICKSTART.md](WIRESHARK-QUICKSTART.md)). **This one is the
dictionary** — you see a word on screen, you find it here. Written so nobody has to search
YouTube mid-defense.

Every count and percentage below is from **our own** capture
`linear-blackhole-highload-home_r2_sept28_0806PM.pcap` (281,356 frames), not a textbook.

---

## 1. "What protocol does the ESP32 use?" — the adviser question

Three layers stacked. Naming only one of them is what makes the question feel like a trap.

| Layer | What it is | What you see in Wireshark |
|---|---|---|
| **Radio / MAC** | **IEEE 802.11** (Wi-Fi), 2.4 GHz, **channel 11**, forced **HT20** (`MESH_CHANNEL`, `MESH_FORCE_HT20`) | Every single frame. Beacons, ACKs, RTS/CTS, data — all of it |
| **Mesh** | **ESP-WIFI-MESH** — Espressif's *proprietary* tree-mesh protocol. Not a standard, not Zigbee/Thread/BLE. Every board is an access point **and** a client at the same time, so boards chain into a tree | The Association/Authentication traffic *between boards*, and the SSIDs like `ESPM_F33218` |
| **Application** | **Our own probe protocol** (`probe_pkt_t`, hop-relayed by `probe_relay.c`) | Payload inside data frames tagged `OUI 0x18FE34` |

**One-sentence answer:** *"IEEE 802.11 Wi-Fi at the radio layer; ESP-WIFI-MESH — Espressif's own
proprietary mesh protocol — organises the boards into a self-healing tree on top of it; and our
own probe protocol rides as the payload."*

⚠️ **It is not IP.** The mesh fabric carries raw 802.11 data frames with a vendor tag. There are
no IP addresses, no TCP, no ports to filter on. `ip.addr` returns nothing, always.

---

## 2. The columns

The wizard preloads these (`run_wizard.ps1` → WIRESHARK). Plain Wireshark shows
Source/Destination instead of TA/RA — ours are more honest, see §8.

| Column | Field | Meaning |
|---|---|---|
| **No.** | `frame.number` | Position in the file. Frame 1 = first heard |
| **Time** | `frame.time_relative` | Seconds since the **first frame in the file** (not since the run started) |
| **RSSI** | `radiotap.dbm_antsignal` | How loudly **the sniffer** heard this frame, in dBm. Not how loudly the receiver heard it |
| **TA (sender)** | `wlan.ta` | Who physically transmitted **this one hop** |
| **RA (next hop)** | `wlan.ra` | Who this hop is addressed to. **Not the final destination** |
| **Seq** | `wlan.seq` | The sender's own frame counter, 0–4095, wraps. A **re-send keeps the same number** |
| **Retry** | `wlan.fc.retry` | `1` = this is a re-transmission. Set by the radio hardware, not by our code |
| **Protocol** | — | `802.11` = management/control frame. `LLC` = a data frame carrying a payload |
| **Length** | `frame.len` | Bytes on the wire |
| **Info** | — | Wireshark's plain-English summary of the row |

---

## 3. What you will actually see (real proportions)

Three-quarters of any capture is bookkeeping. This surprises everyone the first time.

| Frame | Count | Share | Care? |
|---|---|---|---|
| RTS (Request to Send) | 113,415 | 40.3 % | No — §6 |
| ACK (Acknowledgement) | 58,367 | 20.7 % | No — but it's *why* retries happen |
| **QoS Data** | **58,039** | **20.6 %** | **YES — this is our traffic** |
| CTS (Clear to Send) | 35,013 | 12.4 % | No — §6 |
| Beacon | 14,087 | 5.0 % | Only for "who is alive" |
| Data (non-QoS) | 654 | 0.2 % | Rarely |
| Probe Request / Response | 504 / 377 | 0.3 % | Scanning, §4 |
| Block Ack / Block Ack Req | 403 / 305 | 0.3 % | No |
| Action | 76 | 0.03 % | No |
| Null / QoS Null | 42 / 9 | 0.02 % | No |
| **Deauthentication** | **26** | — | **Yes — §4, §5** |
| **Authentication** | **24** | — | Yes — §4 |
| Association Request / Response | 7 / 6 | — | Yes — §4 |
| Disassociation | 2 | — | Yes — §5 |

**Read this:** only ~21 % of a capture is real mesh data. The joins/leaves that worry people
(deauth, auth, assoc) are **61 frames out of 281,356** — 0.02 %.

---

## 4. Management frames — the ones people ask about

Management frames run the *membership* of a Wi-Fi network: who joins, who leaves, who is there.
In our mesh they happen **between two ESP32 boards**, one acting as AP (parent), one as STA (child).

### The join sequence, in order

A child board joining its parent always does these four, in this order:

1. **Probe Request** — *"is anybody out there?"* Broadcast scan asking for networks to identify
   themselves. Sent when a board is looking for a parent.
2. **Probe Response** — *"yes, I'm here, these are my parameters."* The reply, from an AP.
3. **Authentication** — the 802.11 handshake that **must** happen before joining.
   ⚠️ **This is not a password check.** With Open System auth (our case) it's two frames that say
   "I'd like to authenticate" / "fine, you're authenticated." It is a legacy formality the standard
   still requires. Real security (WPA2) happens *after* association, in a different exchange.
4. **Association Request** → **Association Response** — the actual join. The Request names the
   SSID it wants (`SSID="ESPM_F33218"`); the Response accepts or rejects and assigns an
   association ID. After this pair succeeds, that link of the mesh tree exists.

### The leave frames — the ones your adviser asked about

| Frame | Plain meaning | Ends what? | Who sends it |
|---|---|---|---|
| **Disassociation** | *"we are no longer associated"* | Association only — authentication survives | Either side |
| **Deauthentication** | *"we are no longer authenticated"* — the stronger one | **Both.** Authentication *and* association | Either side |

**Key point for the panel:** both are **notifications, not requests**. The receiver has no say —
it cannot refuse. And deauth is the heavier hammer: it drops the link all the way back to square
one, so the board must redo the full sequence in §4 to rejoin.

**Why they appear in our runs, legitimately:**
- A board rebooted (its old link is stale)
- A board **re-parented** — ESP-MESH self-healing moved a child to a different parent
- A parent hit its child limit and pushed one away (see reason 5, §5)
- A board was powered off at the end of a run

⚠️ **Deauth frames are also a real attack in the wild** (deauth flooding). Ours are not that — we
never implemented one, and 26 deauths across 11 minutes is ordinary churn, not a flood. Say this
plainly if asked; don't let a panelist assume the capture shows an unplanned second attack.

### Other management frames

- **Beacon** — the AP's periodic "I exist" broadcast (~every 100 ms), carrying SSID, channel,
  capabilities. This is how boards discover parents without probing.
- **Reassociation Request/Response** — roaming: moving from one AP to another *within the same
  network*, keeping context. Mesh re-parenting may use this instead of a fresh Association.
- **Action** — a catch-all management frame for negotiated extras (Block Ack setup, spectrum
  management). `Dialog Token=1` just numbers the exchange. Safe to ignore.

---

## 5. Reason codes (the number inside a deauth/disassoc)

Every deauth/disassoc carries a **reason code** saying *why*. Wireshark shows it in the Info
column and in the details pane. These four appear in our r2 capture:

| Code | Standard meaning | What it means **in our mesh** |
|---|---|---|
| **5** (×18) | "AP unable to handle all currently associated STAs" | A parent is **full** and pushed a child away. The child then re-parents elsewhere. Most common by far |
| **3** (×6) | "Sending STA is leaving the IBSS/ESS" | A board **left on purpose** — reboot, reflash, or end of run |
| **6** (×2) | "Class 2 frame received from nonauthenticated STA" | One side still thinks the link exists and kept sending; the other had already forgotten it. Normal after a reboot |
| **8** (×2) | "Sending STA is leaving the BSS" | Same as 3, one scope narrower |

**None of these indicate an attack or a bug.** They are the mesh reorganising itself, which is
exactly what ESP-WIFI-MESH is designed to do.

---

## 6. Control frames — 73 % of the file, and you can ignore all of it

These have no payload. They exist to stop two radios talking over each other.

| Frame | Meaning |
|---|---|
| **RTS** (Request to Send) | *"I'm about to transmit, everyone else hold off."* Reserves the air |
| **CTS** (Clear to Send) | The reply granting it. RTS/CTS together solve the **hidden node problem** — two boards that can both hear the parent but not each other |
| **ACK** (Acknowledgement) | The receiver confirming *"got it"*, sent microseconds after a frame. **Has no sender address** — that's why the Source column is blank |
| **Block Ack / Block Ack Req** | Acknowledging a whole burst of frames in one go instead of one ACK each |

**Why ACK matters even though you ignore it:** the ACK is the entire mechanism behind the Retry
bit. Sender transmits → waits for ACK → no ACK arrives → sender re-sends the identical frame with
`Retry=1`. That is what our `MacRetryRate` counts. **Control frames themselves are never retried**
— in our capture their retry rate is exactly **0.0 %**.

---

## 7. Data frames — our actual traffic

| Term | Meaning |
|---|---|
| **QoS Data** | A normal data frame with a priority tag. The default for modern Wi-Fi — the ESP32 driver emits these for mesh traffic. **This is 99 % of our real data** |
| **Data** (plain) | The older, non-QoS variant. Rare here |
| **Null / QoS Null** | A data frame with **no payload** — a keepalive or power-management signal |
| **LLC** | Logical Link Control — the little header that says "a non-IP payload follows" |
| **SNAP** | Subnetwork Access Protocol — the part of that header carrying a vendor ID |
| **OUI `0x18FE34`** | Organizationally Unique Identifier — IEEE-assigned, **this one belongs to Espressif**. Its presence is what proves a frame is ESP-MESH traffic |
| **PID `0xEEEE`** | Espressif's internal protocol ID for mesh payloads |

**The filter that means "our traffic only":** `llc.oui == 0x18fe34`

### Direction: To DS / From DS

Two bits in the header say which way a frame is travelling:

| To DS | From DS | Direction | Frames in r2 |
|---|---|---|---|
| 1 | 0 | **Uplink** — child → parent, toward the root | **51,386** |
| 0 | 1 | **Downlink** — parent → child | 7,358 |

Uplink outnumbers downlink ~7:1, exactly as designed: probes flow up, only phase broadcasts
come down. Filter uplink only with `wlan.fc.tods == 1 && wlan.fc.fromds == 0`.

---

## 8. Header fields, decoded

### Addresses — and the trap

| Field | Meaning |
|---|---|
| **TA** — Transmitter Address | Who physically sent **this hop** |
| **RA** — Receiver Address | Who receives **this hop** |
| **SA** — Source Address | The original sender, many hops back |
| **DA** — Destination Address | The final target |
| **BSSID** | The identity of the Wi-Fi cell — here, the parent board's AP interface |

⚠️ **The hop-wise trap.** ESP-MESH forwards hop by hop, so `wlan.da` is the *next hop*, not the
root. A filter like `wlan.ta == <attacker> && wlan.da == <root>` returns **zero frames always**,
and reads as a perfect blackhole when nothing is wrong. Always pair `wlan.ta` with the parent's
**SoftAP** MAC. (This bit us before — see `WIRESHARK-GUIDE` filter #4.)

### Sequence, retry, flags

- **Sequence number** — the sender's own counter. **A retry reuses the same number**, which is how
  the receiver discards duplicates and how you spot a retry burst by eye: the same Seq repeating
  down consecutive rows.
- **Fragment number** — which piece of a split frame this is. Practically always 0 for us.
- **Duration** — microseconds the sender is reserving the air for. Ignore.
- **FCS** — Frame Check Sequence, the CRC. Ignore.

**The Flags string** (`Flags: ....R..T`). Eight positions, one per bit, a letter when set:

| Position | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| **Bit** | Order | Protected | More Data | Pwr Mgt | **Retry** | More Frag | From DS | To DS |
| **Letter** | O | p | D | P | **R** | M | F | T |

So `....R..T` = **Retry set + To DS set** = *a re-sent uplink frame*. And `....R...` on its own =
a re-sent management frame. `Protected` is always clear — see §10.

---

## 9. Radiotap — the radio metadata

A pseudo-header the **capture tool** adds; it is not part of 802.11 and never travelled through
the air.

| Field | Meaning |
|---|---|
| **Antenna signal (dBm)** | Signal strength as heard **by the sniffer**. −30 very close, −60 good, −71 usable, below −85 barely heard |
| **Channel frequency** | Must read **2462 MHz (channel 11)**. Anything else = wrong channel, useless capture |
| **Data rate / MCS** | Modulation. Not used in our analysis |
| **Antenna noise** | ⚠️ **Do not quote this.** The ESP32 sniffer does not measure a noise floor; the field is padding |

**dBm is negative and logarithmic.** −60 dBm is *ten times* stronger than −70 dBm, not 17 % stronger.

---

## 10. Reading our specific captures

**Every board appears as two MAC addresses, one apart.** Each ESP32 runs a Station interface and
its own SoftAP interface simultaneously (§1), and Espressif assigns the SoftAP the STA's MAC **+1**.

| Board | STA MAC | SoftAP MAC | Role in r2 |
|---|---|---|---|
| node1 | `b0:cb:d8:f3:32:18` | `…:19` | ROOT |
| node6 | `70:4b:ca:25:b7:68` | `…:69` | CHILD (not in attack path) |
| node2 | `f4:2d:c9:73:e6:18` | `…:19` | **BLACKHOLE attacker** |
| node3 | `20:50:0d:e7:1c:38` | `…:39` | CHILD (victim) |
| node5 | `28:05:a5:32:d7:b4` | `…:b5` | CHILD (victim) |
| node4 | `20:50:0d:e7:0c:80` | `…:81` | CHILD (victim) |

A child sends **from its STA MAC** and addresses **its parent's SoftAP MAC**. The SSID
`ESPM_F33218` is generated by ESP-IDF from the root's MAC tail (`b0:cb:d8:f3:32:18` → `F33218`).

**Other facts about our files:**
- **The payload is truncated on purpose.** `sniffer_main.c` keeps only the first **64 bytes** of a
  data frame (256 for management, 32 for control) to fit the USB link. That is why the details pane
  says e.g. *"111 bytes on wire, 83 bytes captured"* — 64 frame bytes + 19 radiotap bytes. You
  cannot read the full probe payload, and that is by design, not corruption.
- **Nothing is encrypted** (Protected bit = 0) — but see the truncation above.
- **The sniffer never transmits**, so its own MAC never appears in its own capture.
- **`P` pauses saving.** A paused stretch is a real gap; check the `.json` `pauses` before quoting.

---

## 11. The status bar = a free retry rate

Bottom right: **`Packets: 281356 · Displayed: 20086 (7.1%)`**

`Displayed` is how many frames match the filter currently in the bar. **That percentage is a live
measurement** — no script needed. To read a real retry rate in front of a panelist:

1. Type the denominator filter → note `Displayed`. e.g. `llc.oui == 0x18fe34` → **57,998**
2. Add `&& wlan.fc.retry == 1` → note it again → **20,035**
3. Divide: **34.5 %** of our mesh data frames in this capture were re-sends.

(All three numbers verified with tshark 4.x against this capture on sep. 30, 2026 — if you type
these filters you will get exactly these counts.)

⚠️ The 7.1 % above is **not** that number — that filter included management frames too. Always
add `llc.oui == 0x18fe34` when you want the figure that matches `MacRetryRate` in the feature table.

---

## 12. Patterns — what a shape on screen means

| What you see | What it means |
|---|---|
| Same **Seq** repeating on consecutive rows, all `Retry=1` | One frame being re-sent over and over because no ACK came back. Six identical Seq `34` deauths = the target was already gone |
| A burst of Auth + Assoc between two boards | A link forming or re-forming. Normal after a reboot or re-parent |
| Deauth with **reason 5** | A parent was full and shed a child. The child re-parents; nothing is broken |
| Retry rate high on **one link only** | That link is weak (distance/obstruction). Retries track **link quality**, not attack state |
| Mesh data volume **dips** for exactly the attack window | The blackhole working — fewer packets relayed. This is the signature, visible without any analysis script |
| RTS/CTS dominating the file | Normal. Hidden-node protection, not congestion |

---

## 13. Things that look alarming but are fine

- **73 % of the file is RTS/CTS/ACK.** Normal Wi-Fi overhead.
- **Deauthentication frames exist.** 26 in 11 minutes is churn, not an attack (§4).
- **Retry rate of 34.5 %.** High-ish, but it is a *link quality* figure on a 6-hop chain and it does
  **not** rise during the attack — which is our pre-registered finding (D-15), not a defect.
- **"Malformed packet" on some rows.** An artefact of the 64-byte truncation (§10), not bad data.
- **Frames from MACs not in our roster.** Neighbouring Wi-Fi on channel 11. Filter them out with
  `wlan.addr in {our MACs}`.

---

## 14. Filter cheat card

```
our mesh data only:      llc.oui == 0x18fe34
real re-transmissions:   wlan.fc.retry == 1
data-frame retries only: wlan.fc.retry == 1 && llc.oui == 0x18fe34
uplink only:             wlan.fc.tods == 1 && wlan.fc.fromds == 0
one board (both MACs):   wlan.addr in {20:50:0d:e7:1c:38, 20:50:0d:e7:1c:39}
joins:                   wlan.fc.type_subtype in {0x00, 0x02}
leaves:                  wlan.fc.type_subtype in {0x0a, 0x0c}
all membership churn:    wlan.fc.type_subtype in {0x00, 0x02, 0x0a, 0x0c}
beacons only:            wlan.fc.type_subtype == 0x08
hide beacons + ACKs:     !(wlan.fc.type_subtype in {0x08, 0x1d})
weak links:              radiotap.dbm_antsignal < -80
one phase:               frame.time_relative >= <start> && frame.time_relative < <end>
```

Type/subtype numbers: `0x00` Assoc Req · `0x01` Assoc Resp · `0x02` Reassoc Req · `0x04` Probe Req
· `0x05` Probe Resp · `0x08` Beacon · `0x0a` Disassoc · `0x0b` Auth · `0x0c` Deauth · `0x0d` Action
· `0x1b` RTS · `0x1c` CTS · `0x1d` ACK · `0x28` QoS Data

---

## 15. Glossary

**AP** — Access Point. The parent side of a link. Every mesh board is one. ·
**BSS / BSSID** — one AP's cell / its identifier. ·
**dBm** — signal strength, logarithmic, always negative here. ·
**DS** — Distribution System. "To DS" = toward the network core (the root). ·
**ESS** — several BSSs forming one logical network. ·
**FCS** — the frame's CRC. ·
**Frame** — one 802.11 transmission. The Wi-Fi equivalent of a packet. ·
**HT20** — 20 MHz channel width. Forced on, so captures are comparable. ·
**IE** — Information Element, a tagged field inside beacons/assoc frames. ·
**LLC / SNAP** — the headers that let a non-IP payload ride in a data frame. ·
**MCS** — modulation and coding scheme. ·
**Monitor / promiscuous mode** — receiving frames not addressed to you; what makes sniffing possible. ·
**OUI** — IEEE-assigned vendor prefix. Espressif's is `0x18FE34`. ·
**Radiotap** — the metadata header the capture tool prepends. ·
**RSSI** — received signal strength. ·
**SSID** — the network's name. Ours: `ESPM_<root MAC tail>`. ·
**STA** — Station. The client side of a link. Every mesh board is also one. ·
**Snap length** — how many bytes per frame the sniffer keeps (ours: 256 mgmt / 64 data / 32 control).

---

## See also

- [WIRESHARK-QUICKSTART.md](WIRESHARK-QUICKSTART.md) — the panes, columns and workflows
- [WIRESHARK-GUIDE.md](WIRESHARK-GUIDE.md) — what a sniffer can and cannot see; how to capture
- [DATA-DICTIONARY.md](../data-and-results/DATA-DICTIONARY.md) — the CSV columns (a different vocabulary — don't mix them up)
- [deviations-limitations/thesis-deviate.md](../deviations-limitations/thesis-deviate.md) **D-15** — why `RetryRate` in the CSVs
  is *not* a MAC retry counter, and why the sniffer is the only source for the real one
