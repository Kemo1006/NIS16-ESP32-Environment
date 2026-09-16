# SD Card Reader Integration & Wormhole UART Wiring — Q&A

<!-- Panel-facing record of hardware bring-up struggles, sep. 2026. Written in
     Q&A form so it can be read almost verbatim if a panelist asks "what
     problems did you run into getting the hardware working?" -->

## Context

The adviser asked for a microSD card reader (SPI) to be added as a storage option
on the ESP32 boards, on top of the SPIFFS logging the firmware already does. This
is new, hardware-only bring-up work — separate from the CTTHES3 dataset-redesign
track, and not yet wired into the real mesh firmware. We have 8 physical ESP32
boards total: 4 are a 38-pin variant (silkscreen prefixes GPIOs with "G", e.g.
`G18`), 4 are a 30-pin variant (prefixes with "D", e.g. `D18`) — same underlying
GPIO numbers, different labels, and we mix/pair them depending on the topology
being tested.

---

## Q: Did wiring the SD card reader work on the first try?

No. It took three separate rounds of debugging, each with a distinct root cause —
and each one *looked* like a different kind of failure until we actually traced it.

## Q: What was the first problem?

**Total silence — the card never responded at all.** The mount call
(`esp_vfs_fat_sdspi_mount`) failed with `ESP_ERR_TIMEOUT` (`0x107`) at the
`ACMD41` power-negotiation step, after retrying for a full 3 seconds. Wiring
looked correct on inspection (CS→G5, SCK→G18, MOSI→G23, MISO→G19, GND→GND, VCC→3V3 —
the standard ESP32 VSPI pins).

To isolate "is this a wiring problem or a firmware problem," we wrote a
minimal raw-SPI test that sends only `CMD0` (`GO_IDLE_STATE`, the card's first
required reply) and prints the raw response byte — bypassing the whole
`sdmmc`/FAT mount stack entirely. That test got back `R1 = 0x01` ("idle state,
card alive") immediately. So the card and wiring were both electrically fine at
the command level; the failure was specifically in the *power-up* stage.

**Root cause: we had VCC wired to the ESP32's 3.3V pin, but this reader module
needs 5V.** The reader has an onboard AMS1117-3.3 regulator between its VCC pin
and the actual SD card — feeding it 3.3V leaves ~1.1–1.3V of regulator dropout,
so the card itself only sees roughly 2.0–2.2V, below the ~2.7V minimum SD cards
need to complete power-up. The card was awake enough to answer `CMD0`, but could
never finish `ACMD41` because it physically couldn't power its own flash array.
This is a well-known failure mode for this exact module type (AMS1117 + 74HC125
level-shifter, marketed for 5V-logic Arduino hosts) when someone assumes "ESP32
is 3.3V logic, so power it at 3.3V" — that instinct is *right* for the logic
pins but *wrong* for this specific module's VCC.

**Fix:** move VCC from the ESP32's `3V3` pin to its `VIN`/`5V` pin. This is safe
specifically because the reader's level-shifter chip (74HC125) is powered from
the regulator's *3.3V output*, not the 5V input — so 5V never reaches the ESP32's
GPIOs even though it reaches the reader's VCC.

## Q: Did the 5V fix solve it completely?

Not quite — it solved that specific problem, but uncovered a second, different one.

After moving VCC to 5V, the mount got dramatically further: instead of a 3-second
timeout at `ACMD41`, it now failed in about 9 milliseconds at a *later* command,
`sdmmc_check_scr` (reading the card's SCR register), with `ESP_ERR_INVALID_CRC`
(`0x109`). The much shorter failure time was itself the diagnostic clue — the
card was now powering up and initializing correctly; it only failed once the
driver tried to pull back an actual multi-byte data block instead of a single
status byte.

**Root cause: the SPI clock speed was too fast for our jumper-wire harness.**
Once a card clears identification, the ESP-IDF driver raises the SPI clock from
the conservative ~400 kHz used during power-up to its faster default (~20 MHz)
for real data transfers. Loose, unshielded jumper wires that carry single
command bytes fine at 400 kHz often can't reliably carry a full data burst at
20 MHz — bits flip, and the card's own CRC16 on the data block (always present
in the SD protocol, separate from whether command-CRC is enabled) catches it.

**Fix:** explicitly cap `host.max_freq_khz = 4000` (4 MHz) in the `sdmmc_host_t`
config before mounting. The CRC error disappeared — confirming it was a clock/wire
issue, not a further wiring mistake.

## Q: How do you know it wasn't just still a wiring mistake?

Because we verified the physical wiring independently, pin-by-pin, against
photographs of the actual boards and reader module, and every connection was
already correct (GND→GND, VCC→V5, MISO→G19, MOSI→G23, SCK→G18, CS→G5) *before*
the clock-speed fix — so the remaining failure couldn't have been a wiring
error, it had to be something about signal quality at speed, which is exactly
what capping the clock confirmed.

## Q: What about the wormhole attack's own wiring problem — was that related?

Different mechanism, same underlying wire-quality theme. The wormhole attack
requires a **physical UART cable between two attacker boards** (`WORMHOLE_UART_TX_PIN`
`GPIO17` → the other board's `GPIO16`, crossed, plus shared GND — see
`WORMHOLE-SETUP.md` in the code repo). Early on, wiring this with female-to-female
jumpers on one board pairing produced a link that "booted fine but delivered
nothing" — no crash, no error, just zero duplicate probes ever reaching root.

We initially suspected a WROVER/PSRAM pin conflict (GPIO16/17 are claimed
internally by PSRAM on some ESP32 module variants), since the 38-pin boards in
particular are the type that commonly carries a WROVER module. But once we
tested different physical board pairings, the failure didn't track board type —
it tracked which *specific cable/pairing* was used, which points at the same
root cause as the SD card: **marginal contact on female-to-female jumper wires**,
not a silicon-level pin conflict. The repo's own `uart_link_test/` standalone
loopback tool (built for exactly this) is the fast way to confirm a wormhole
link is solid before committing to an 11-minute full run.

## Q: What's the one-sentence takeaway if asked to summarize this?

Three separate failures that all *looked* like different problems (silence,
timeout, CRC corruption, "booted but empty") traced back to two root causes:
one wrong pin (VCC needed 5V, not 3.3V, because of this specific reader module's
onboard regulator) and one systemic wiring-quality issue (jumper wires are
unreliable at higher SPI/UART clock speeds and easy to blame on the wrong
thing first) — both fixed with hardware-specific tests (a raw-CMD0 probe, a
UART loopback tool) that isolated *which* layer was actually failing before
guessing at fixes.
