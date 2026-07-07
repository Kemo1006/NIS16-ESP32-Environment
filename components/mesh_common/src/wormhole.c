/**
 * @file wormhole.c
 * @brief Wormhole out-of-band UART tunnel implementation (Milestone 2).
 *
 * See wormhole.h for the frame layout and the role of each attacker board.
 *
 * NIS16 — CTTHES2 Milestone 2 — Common Module
 */

#include "wormhole.h"
#include "mesh_config.h"

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "esp_log.h"

static const char *TAG = "WORMHOLE";

/* ── On-wire tunnel frame ────────────────────────────────────────────────────
 * Packed so the byte layout is identical on both ESP32 boards. CRC covers the
 * 18 bytes between the SOF and the CRC field (seq_num + src_mac + send_ts_us).
 * ─────────────────────────────────────────────────────────────────────────── */
typedef struct __attribute__((packed)) {
    uint8_t  sof;           /* WORMHOLE_UART_SOF */
    uint32_t seq_num;
    uint8_t  src_mac[6];
    int64_t  send_ts_us;
    uint16_t crc16;
} wormhole_frame_t;

/* Bytes covered by the CRC: everything between sof and crc16. */
#define WORMHOLE_CRC_SPAN   (sizeof(wormhole_frame_t) - 3)   /* 21 - 3 = 18 */

static bool s_uart_ready = false;

/* ═══════════════════════════════════════════════════════════════════════════
 * CRC-16/CCITT-FALSE  (poly 0x1021, init 0xFFFF, no reflection, xorout 0x0000)
 * ═══════════════════════════════════════════════════════════════════════════ */
uint16_t wormhole_crc16(const uint8_t *data, size_t len)
{
    uint16_t crc = 0xFFFFU;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++) {
            crc = (crc & 0x8000U) ? (uint16_t)((crc << 1) ^ 0x1021U)
                                  : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * UART bring-up
 * ═══════════════════════════════════════════════════════════════════════════ */
esp_err_t wormhole_uart_init(void)
{
    if (s_uart_ready) {
        return ESP_OK;
    }

    const uart_config_t cfg = {
        .baud_rate = WORMHOLE_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_driver_install(WORMHOLE_UART_PORT,
                                        256 /* rx buf */, 0 /* tx buf */,
                                        0, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_driver_install failed: %s", esp_err_to_name(err));
        return err;
    }

    err = uart_param_config(WORMHOLE_UART_PORT, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_param_config failed: %s", esp_err_to_name(err));
        return err;
    }

    err = uart_set_pin(WORMHOLE_UART_PORT,
                       WORMHOLE_UART_TX_GPIO, WORMHOLE_UART_RX_GPIO,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_set_pin failed: %s", esp_err_to_name(err));
        return err;
    }

    s_uart_ready = true;
    ESP_LOGI(TAG, "Tunnel UART%d up @ %d baud (TX=%d RX=%d).",
             WORMHOLE_UART_PORT, WORMHOLE_UART_BAUD,
             WORMHOLE_UART_TX_GPIO, WORMHOLE_UART_RX_GPIO);
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Attacker B → tunnel
 * ═══════════════════════════════════════════════════════════════════════════ */
esp_err_t wormhole_tunnel_send(uint32_t seq_num,
                               const uint8_t src_mac[6],
                               int64_t send_ts_us)
{
    if (!s_uart_ready) {
        return ESP_ERR_INVALID_STATE;
    }

    wormhole_frame_t f;
    f.sof        = WORMHOLE_UART_SOF;
    f.seq_num    = seq_num;
    memcpy(f.src_mac, src_mac, 6);
    f.send_ts_us = send_ts_us;
    f.crc16      = wormhole_crc16((const uint8_t *)&f + 1, WORMHOLE_CRC_SPAN);

    int written = uart_write_bytes(WORMHOLE_UART_PORT,
                                   (const char *)&f, sizeof(f));
    if (written != (int)sizeof(f)) {
        ESP_LOGW(TAG, "tunnel_send short write (%d/%d)",
                 written, (int)sizeof(f));
        return ESP_FAIL;
    }
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * tunnel → Attacker A
 * ═══════════════════════════════════════════════════════════════════════════ */
bool wormhole_tunnel_recv(uint32_t *seq_num,
                          uint8_t src_mac[6],
                          int64_t *send_ts_us,
                          uint32_t timeout_ms)
{
    if (!s_uart_ready) {
        return false;
    }

    /* Hunt for the start-of-frame byte. */
    uint8_t sof = 0;
    int r = uart_read_bytes(WORMHOLE_UART_PORT, &sof, 1,
                            pdMS_TO_TICKS(timeout_ms));
    if (r != 1 || sof != WORMHOLE_UART_SOF) {
        return false;
    }

    /* Read the fixed-length remainder of the frame. */
    uint8_t rest[sizeof(wormhole_frame_t) - 1];
    r = uart_read_bytes(WORMHOLE_UART_PORT, rest, sizeof(rest),
                        pdMS_TO_TICKS(200));
    if (r != (int)sizeof(rest)) {
        return false;   /* partial frame — drop and resync on next call */
    }

    wormhole_frame_t f;
    f.sof = WORMHOLE_UART_SOF;
    memcpy((uint8_t *)&f + 1, rest, sizeof(rest));

    uint16_t want = wormhole_crc16((const uint8_t *)&f + 1, WORMHOLE_CRC_SPAN);
    if (want != f.crc16) {
        ESP_LOGW(TAG, "tunnel_recv CRC mismatch (got 0x%04X want 0x%04X)",
                 f.crc16, want);
        return false;
    }

    *seq_num    = f.seq_num;
    memcpy(src_mac, f.src_mac, 6);
    *send_ts_us = f.send_ts_us;
    return true;
}
