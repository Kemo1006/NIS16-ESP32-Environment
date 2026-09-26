/**
 * @file sniffer_main.c
 * @brief Passive 802.11 sniffer that streams frames to the laptop over USB.
 *
 * Why this exists: Windows laptop Wi-Fi cannot do monitor mode, and the only
 * other sniffer (a teammate's MacBook) is not always available. Any spare
 * ESP32 flashed with this becomes a sniffer with NO extra hardware - no SD
 * card, no wiring. tools/sniff.py on the laptop turns the stream into a .pcap
 * that Wireshark opens (radiotap link type, so RSSI/rate/channel show up).
 *
 * The board is PASSIVE: WIFI_MODE_NULL + promiscuous, never scans, never
 * transmits, never joins the mesh. It cannot disturb the experiment.
 *
 * Wire format (UART0 at SNIFF_BAUD, little-endian), one record at a time:
 *
 *   A5 5A | type u8 | 0 u8 | body_len u16 | body[body_len] | fletcher16 u16
 *
 * The checksum covers type..body. The host resyncs on A5 5A and only accepts
 * a record whose checksum matches, so the boot-time 115200 text and any
 * corrupted byte are skipped instead of becoming fake packets.
 *
 *   type 1 HELLO  : boot_nonce u32, channel u8, snap_mgmt u16, snap_data u16,
 *                   then an ASCII version string. Sent first after boot and
 *                   every HELLO_PERIOD_MS, so a host that attaches late still
 *                   learns the config, and a new nonce means "board rebooted".
 *   type 2 FRAME  : rec_seq u32, ts_us u32, rssi i8, rate u8, sig_mode u8,
 *                   mcs u8, flags u8 (bit0 40 MHz, bit1 short GI, bit2 AMPDU),
 *                   channel u8, pkt_type u8, orig_len u16, noise_floor i8,
 *                   then the first cap bytes of the 802.11 frame (FCS
 *                   stripped). rec_seq
 *                   counts every frame the board QUEUED, so a gap on the host
 *                   = frames lost on the USB link, counted separately from...
 *   type 3 STATUS : uptime_ms u32, seen u32, queued u32, ring_dropped u32,
 *                   bad_fcs u32, ring_free u32 - ...frames the board itself
 *                   could not queue (ring full). Both loss counts end up in
 *                   the capture's .json sidecar, so a thesis figure built on a
 *                   capture can state exactly how complete it was.
 *
 * NIS16 - packet-capture verification (proposal section: Tools / Wireshark)
 */

#include <stdint.h>
#include <string.h>

#include "driver/uart.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/ringbuf.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "mesh_config.h"

static const char *TAG = "sniffer";

#define SNIFF_VERSION     "esp32-sniffer 1"

/* 921600 over the USB bridge = ~90 KB/s. At ~80 bytes per data frame that is
 * over 1000 frames/s, far more than the mesh sends. tools/sniff.py --baud must
 * match. Boot/bootloader text still comes out at the normal 115200 first; the
 * host skips it by checksum. */
#define SNIFF_BAUD        921600

/* Bytes of each frame kept (snap length). The mesh payload is encrypted, so
 * past the 802.11 header + CCMP header there is nothing readable in a DATA
 * frame; 64 covers the longest header (QoS + HT control + addr4). Management
 * frames keep more because beacons/association carry the readable IEs (SSID,
 * mesh vendor IE) used to confirm topology. Control frames are tiny anyway. */
#define SNAP_MGMT         256
#define SNAP_DATA         64
#define SNAP_CTRL         32

#define RING_BYTES        (64 * 1024)
#define UART_TX_BUF       (16 * 1024)
#define STATUS_PERIOD_MS  1000
#define HELLO_PERIOD_MS   5000

#define REC_HELLO         1
#define REC_FRAME         2
#define REC_STATUS        3

#define REC_HDR           6   /* magic(2) type(1) pad(1) len(2) */
#define REC_TRAILER       2   /* fletcher16 */
#define FRAME_FIXED       18  /* FRAME body before the frame bytes */
#define REC_MAX           (REC_HDR + FRAME_FIXED + SNAP_MGMT + REC_TRAILER)

static RingbufHandle_t s_ring;
static uint32_t s_boot_nonce;

/* Written only from the Wi-Fi task's callback; read by the writer task for
 * STATUS. 32-bit aligned loads/stores are atomic on the ESP32, and a status
 * line one frame stale is harmless. */
static volatile uint32_t s_seen;
static volatile uint32_t s_queued;
static volatile uint32_t s_ring_dropped;
static volatile uint32_t s_bad_fcs;

static void put_u16(uint8_t *p, uint16_t v) { p[0] = v & 0xFF; p[1] = v >> 8; }
static void put_u32(uint8_t *p, uint32_t v)
{
    p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; p[2] = (v >> 16) & 0xFF; p[3] = v >> 24;
}

static uint16_t fletcher16(const uint8_t *d, size_t n)
{
    uint16_t a = 0, b = 0;
    for (size_t i = 0; i < n; i++) {
        a = (a + d[i]) % 255;
        b = (b + a) % 255;
    }
    return (uint16_t)((b << 8) | a);
}

/* Fills header + trailer around a body already written at rec + REC_HDR.
 * Returns the full record length. */
static size_t seal_record(uint8_t *rec, uint8_t type, uint16_t body_len)
{
    rec[0] = 0xA5;
    rec[1] = 0x5A;
    rec[2] = type;
    rec[3] = 0;
    put_u16(rec + 4, body_len);
    uint16_t ck = fletcher16(rec + 2, 4 + body_len);
    put_u16(rec + REC_HDR + body_len, ck);
    return REC_HDR + body_len + REC_TRAILER;
}

static void sniff_cb(void *buf, wifi_promiscuous_pkt_type_t type)
{
    const wifi_promiscuous_pkt_t *pkt = (const wifi_promiscuous_pkt_t *)buf;
    const wifi_pkt_rx_ctrl_t *rx = &pkt->rx_ctrl;

    s_seen++;
    if (rx->rx_state != 0) {   /* failed FCS / PHY error: garbage bytes */
        s_bad_fcs++;
        return;
    }

    uint16_t sig = rx->sig_len;
    uint16_t orig = sig >= 4 ? sig - 4 : sig;   /* sig_len includes the FCS */
    uint16_t snap = type == WIFI_PKT_MGMT ? SNAP_MGMT
                  : type == WIFI_PKT_DATA ? SNAP_DATA : SNAP_CTRL;
    uint16_t cap = orig < snap ? orig : snap;

    uint8_t rec[REC_MAX];
    uint8_t *b = rec + REC_HDR;
    put_u32(b + 0, s_queued);           /* rec_seq: host detects USB loss */
    put_u32(b + 4, rx->timestamp);      /* us, radio's own RX timestamp */
    b[8]  = (uint8_t)(int8_t)rx->rssi;
    b[9]  = rx->rate;
    b[10] = rx->sig_mode;
    b[11] = rx->mcs;
    b[12] = (rx->cwb ? 0x01 : 0) | (rx->sgi ? 0x02 : 0) | (rx->aggregation ? 0x04 : 0);
    b[13] = rx->channel;
    b[14] = (uint8_t)type;
    put_u16(b + 15, orig);
    b[17] = (uint8_t)(int8_t)rx->noise_floor;   /* dBm: RSSI - noise = SNR */
    memcpy(b + FRAME_FIXED, pkt->payload, cap);

    size_t n = seal_record(rec, REC_FRAME, FRAME_FIXED + cap);
    if (xRingbufferSend(s_ring, rec, n, 0) == pdTRUE) {
        s_queued++;
    } else {
        s_ring_dropped++;
    }
}

static void send_hello(void)
{
    uint8_t rec[REC_HDR + 16 + 48 + REC_TRAILER];
    uint8_t *b = rec + REC_HDR;
    put_u32(b + 0, s_boot_nonce);
    b[4] = MESH_CHANNEL;
    put_u16(b + 5, SNAP_MGMT);
    put_u16(b + 7, SNAP_DATA);
    const char *ver = SNIFF_VERSION " built " __DATE__ " " __TIME__;
    size_t vlen = strlen(ver);
    if (vlen > 48) vlen = 48;
    memcpy(b + 9, ver, vlen);
    size_t n = seal_record(rec, REC_HELLO, 9 + vlen);
    uart_write_bytes(UART_NUM_0, rec, n);
}

static void send_status(void)
{
    uint8_t rec[REC_HDR + 24 + REC_TRAILER];
    uint8_t *b = rec + REC_HDR;
    put_u32(b + 0,  (uint32_t)(esp_timer_get_time() / 1000));
    put_u32(b + 4,  s_seen);
    put_u32(b + 8,  s_queued);
    put_u32(b + 12, s_ring_dropped);
    put_u32(b + 16, s_bad_fcs);
    put_u32(b + 20, (uint32_t)xRingbufferGetCurFreeSize(s_ring));
    size_t n = seal_record(rec, REC_STATUS, 24);
    uart_write_bytes(UART_NUM_0, rec, n);
}

/* The ONLY task that writes UART0 after start-up, so records never interleave.
 * HELLO/STATUS are checked BEFORE draining the ring, so the very first record
 * of every boot is a HELLO and the host anchors on it before any frame. */
static void writer_task(void *arg)
{
    (void)arg;
    int64_t next_status = 0, next_hello = 0;
    for (;;) {
        int64_t now = esp_timer_get_time() / 1000;
        if (now >= next_hello) {
            send_hello();
            next_hello = now + HELLO_PERIOD_MS;
        }
        if (now >= next_status) {
            send_status();
            next_status = now + STATUS_PERIOD_MS;
        }
        size_t len = 0;
        void *item = xRingbufferReceive(s_ring, &len, pdMS_TO_TICKS(50));
        if (item) {
            uart_write_bytes(UART_NUM_0, item, len);
            vRingbufferReturnItem(s_ring, item);
        }
    }
}

void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    s_boot_nonce = esp_random();
    s_ring = xRingbufferCreate(RING_BYTES, RINGBUF_TYPE_NOSPLIT);
    if (!s_ring) {
        ESP_LOGE(TAG, "ring buffer alloc failed");
        abort();
    }

    ESP_ERROR_CHECK(esp_event_loop_create_default());
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_NULL));
    ESP_ERROR_CHECK(esp_wifi_start());

    /* Primary channel only, 20 MHz: the mesh runs HT20 (MESH_FORCE_HT20), so
     * this hears its data frames as well as its beacons. */
    ESP_ERROR_CHECK(esp_wifi_set_channel(MESH_CHANNEL, WIFI_SECOND_CHAN_NONE));

    wifi_promiscuous_filter_t filt = {
        .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT | WIFI_PROMIS_FILTER_MASK_DATA |
                       WIFI_PROMIS_FILTER_MASK_CTRL,
    };
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous_filter(&filt));
    wifi_promiscuous_filter_t ctrl = { .filter_mask = WIFI_PROMIS_CTRL_FILTER_MASK_ALL };
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous_ctrl_filter(&ctrl));
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous_rx_cb(sniff_cb));

    ESP_LOGI(TAG, "=== SNIFFER NODE (passive, never joins the mesh) ===");
    ESP_LOGI(TAG, "channel %d, 20 MHz, snap mgmt/data/ctrl %d/%d/%d bytes",
             MESH_CHANNEL, SNAP_MGMT, SNAP_DATA, SNAP_CTRL);
    ESP_LOGI(TAG, "switching this port to %d baud BINARY - read it with tools/sniff.py,",
             SNIFF_BAUD);
    ESP_LOGI(TAG, "not idf.py monitor (which shows only garbage from here on).");

    /* From here on UART0 carries the binary stream only: silence every log
     * (Wi-Fi driver included) so no text lands between records, then take the
     * console UART over at the fast baud. */
    uart_wait_tx_idle_polling(UART_NUM_0);
    esp_log_level_set("*", ESP_LOG_NONE);
    ESP_ERROR_CHECK(uart_driver_install(UART_NUM_0, 256, UART_TX_BUF, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_set_baudrate(UART_NUM_0, SNIFF_BAUD));

    xTaskCreatePinnedToCore(writer_task, "sniff_writer", 4096, NULL, 5, NULL, 1);
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(true));
}
