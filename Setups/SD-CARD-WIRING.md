# ESP32 ↔ SD Card Reader — Wiring Reference

<!-- Pinout only. For the debugging story (why 3.3V failed, why the clock had
     to drop to 4 MHz), see Implementation Issues/SD-CARD-AND-WORMHOLE-WIRING.md. -->

Source of truth for the pin numbers: `ESP32-Environment/components/mesh_common/include/mesh_config.h:395-402`.

## Pin table (VSPI / SPI3_HOST)

| SD reader pin | ESP32 pin | Constant |
|---|---|---|
| CS | GPIO5 | `SD_PIN_CS` |
| SCK | GPIO18 | `SD_PIN_SCK` |
| MOSI | GPIO23 | `SD_PIN_MOSI` |
| MISO | GPIO19 | `SD_PIN_MISO` |
| GND | GND | — |
| VCC | **VIN / 5V** — not 3V3 | — |

38-pin boards silkscreen these as `G5/G18/G23/G19`; 30-pin boards as `D5/D18/D23/D19` — same GPIO numbers, different label prefix.

## The two gotchas that aren't obvious from the table

1. **VCC must go to VIN/5V, not 3V3.** This reader module has an onboard AMS1117-3.3 regulator between its VCC pin and the card itself. Feeding it 3.3V leaves the card at only ~2.0–2.2V after regulator dropout — below the ~2.7V an SD card needs to complete power-up. Symptom: mount fails with `ESP_ERR_TIMEOUT` at the `ACMD41` step. Safe to run VCC at 5V because the module's own level-shifter (74HC125) is powered from the regulator's 3.3V *output*, not the 5V input — so the ESP32's GPIOs never see 5V.
2. **SPI clock is capped at 4 MHz**, not the ESP-IDF SDSPI default of ~20 MHz — see `SD_MAX_FREQ_KHZ` at `mesh_config.h:402`. Jumper wires can't reliably carry a full data burst at 20 MHz; symptom at the default speed is `ESP_ERR_INVALID_CRC` on `sdmmc_check_scr`, a few milliseconds into mount, right after power-up succeeds.

## Quick continuity check before trusting a mount failure

If mount fails, isolate wiring from firmware first: a raw `CMD0` (`GO_IDLE_STATE`) probe that bypasses the `sdmmc`/FAT stack should return `R1 = 0x01` if the card is alive and wired correctly at the command level. If `CMD0` succeeds but mount still fails, the fault is power or clock (the two gotchas above), not the wiring itself.

## Related

- Full bring-up debugging narrative (three root causes, in order discovered): `Implementation Issues/SD-CARD-AND-WORMHOLE-WIRING.md`
- Boot-time SD check that consumes these pins: `ESP32-Environment/components/mesh_common/src/sd_status.c`
- Standalone bring-up test (writes one status file, no mesh firmware): `ESP32-Environment/sd_card_test/`
