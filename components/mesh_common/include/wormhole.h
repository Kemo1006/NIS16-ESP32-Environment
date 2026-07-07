/**
 * @file wormhole.h
 * @brief Wormhole out-of-band UART tunnel — common module (Milestone 2).
 *
 * The wormhole attack uses two attacker boards joined by a WIRED UART link,
 * the out-of-band channel that distinguishes a wormhole from ordinary mesh
 * forwarding:
 *
 *   Attacker B (near victims) captures a victim's probe metadata off the mesh
 *   and ships {seq_num, src_mac, send_ts_us} to Attacker A through this UART
 *   tunnel, CRC-protected. Attacker A (near root) reads the tunnel, rebuilds a
 *   replica probe carrying the ORIGINAL identifiers, and re-injects it toward
 *   root by the legitimate mesh path.
 *
 * This module owns only the tunnel: UART bring-up plus CRC-framed send/recv of
 * one metadata record. The attacker mains supply the mesh-side glue.
 *
 * Wire format (little-endian, ESP32↔ESP32), 21 bytes:
 *   [SOF=0xA5][seq_num:u32][src_mac:6][send_ts_us:i64][crc16:u16]
 * CRC-16/CCITT-FALSE over the 18 bytes between SOF and CRC.
 *
 * NIS16 — CTTHES2 Milestone 2 — Common Module
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Probe wire format (must match root_main.c / victim_main.c exactly) ────── */

/** Magic cookie prefixing every probe packet ("PROB"). */
#define WORMHOLE_PROBE_MAGIC    0x50524F42U

/** On-the-wire probe packet — identical layout to the probe_pkt_t in the root
 *  and victim mains so an attacker can parse and reconstruct probes. */
typedef struct __attribute__((packed)) {
    uint32_t magic;         /**< WORMHOLE_PROBE_MAGIC                        */
    uint32_t seq_num;       /**< Victim's monotonic probe counter           */
    int64_t  send_ts_us;    /**< Victim esp_timer_get_time() at send        */
    uint8_t  src_mac[6];    /**< Victim STA MAC                             */
} wormhole_probe_pkt_t;

/* ── Tunnel API ──────────────────────────────────────────────────────────── */

/**
 * @brief Bring up the A↔B tunnel UART (pins/baud from mesh_config.h).
 *
 * Idempotent-safe to call once at startup on both attacker boards.
 * @return ESP_OK on success, or the underlying driver error.
 */
esp_err_t wormhole_uart_init(void);

/**
 * @brief (Attacker B) Push one probe's metadata into the tunnel toward A.
 *
 * Builds a CRC-framed record and writes it to the UART. Non-blocking beyond
 * the ~21-byte TX; safe to call from a task but NOT from an ISR.
 *
 * @return ESP_OK if the frame was queued to the UART, else an error.
 */
esp_err_t wormhole_tunnel_send(uint32_t seq_num,
                               const uint8_t src_mac[6],
                               int64_t send_ts_us);

/**
 * @brief (Attacker A) Read the next valid metadata record from the tunnel.
 *
 * Hunts for a start-of-frame byte, reads the fixed-length remainder, and
 * verifies the CRC. Corrupted or partial frames are dropped (returns false)
 * so the caller can simply retry.
 *
 * @param[out] seq_num      Original probe sequence number.
 * @param[out] src_mac      Original victim MAC (6 bytes).
 * @param[out] send_ts_us   Original victim send timestamp.
 * @param      timeout_ms   Max time to wait for a start-of-frame byte.
 * @return true if a CRC-valid record was decoded; false on timeout/corruption.
 */
bool wormhole_tunnel_recv(uint32_t *seq_num,
                          uint8_t src_mac[6],
                          int64_t *send_ts_us,
                          uint32_t timeout_ms);

/**
 * @brief CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over @p len bytes.
 *        Exposed for tests; used internally by the tunnel framing.
 */
uint16_t wormhole_crc16(const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif
