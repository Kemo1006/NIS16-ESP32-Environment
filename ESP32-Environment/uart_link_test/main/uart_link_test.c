// Standalone UART tunnel-wire loopback test (NOT part of the mesh firmware).
// Flash this to BOTH attacker boards (Node A + Node B). Each board continuously
// sends numbered pings out its tunnel TX pin (GPIO17) and listens on its tunnel
// RX pin (GPIO16). If a board RECEIVES pings, the wire feeding THAT board's RX
// works. When both boards are running and wired correctly (crossed 17<->16 +
// shared GND), BOTH print [LINK OK]. No mesh, no attack window - result in ~2s.
//
// Every ping carries a sequence number and a checksum, so the receiver can
// tell a LOST ping (sequence gap) from a GARBLED one (bad checksum / broken
// line). That is what makes a long soak meaningful for extended jumper chains:
// a loose joint shows up as a loss rate, not just "it worked once".
//
// Once a second each board prints, on its USB console:
//   TX sent=.. | RX received=..  [LINK OK]          (human-readable)
//   LINKSTAT tx=.. rx=.. lost=.. bad=..              (parsed by run_wizard.ps1)
// The counters are cumulative since boot; the wizard diffs two LINKSTAT lines.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "esp_log.h"

#define TAG      "UART_LINK_TEST"
#define PORT     UART_NUM_1     // same peripheral the wormhole tunnel uses
#define TX_PIN   17             // WORMHOLE_UART_TX_PIN
#define RX_PIN   16             // WORMHOLE_UART_RX_PIN
#define BAUD     115200
#define MAGIC    "LINKPING:"

// One ping every 50 ms (20/s). Each line is ~56 bytes, so the link runs at
// roughly 10% of what 115200 baud can carry - busy enough that a flaky joint
// gets many chances to drop something, without saturating the UART.
#define PING_INTERVAL_MS  50
// Fixed filler so a ping is about as long as a real tunnel frame - a short
// "PING" can survive a marginal wire that a few dozen bytes would not.
#define FILLER   "0123456789ABCDEFGHIJKLMNOPQRSTUV"

static volatile uint32_t s_tx   = 0;   // pings sent
static volatile uint32_t s_rx   = 0;   // good pings received
static volatile uint32_t s_lost = 0;   // sequence numbers skipped
static volatile uint32_t s_bad  = 0;   // garbled lines (bad checksum/format)

static uint8_t line_checksum(const char *s, size_t n)
{
    uint8_t c = 0;
    for (size_t i = 0; i < n; i++) c ^= (uint8_t)s[i];
    return c;
}

static void tx_task(void *arg)
{
    char out[96];
    uint32_t seq = 0;
    while (1) {
        // LINKPING:<seq hex8>:<filler>:<xor hex2>\n - checksum covers
        // everything before the last ':'.
        int n = snprintf(out, sizeof(out), "%s%08lX:%s:", MAGIC, (unsigned long)seq, FILLER);
        n += snprintf(out + n, sizeof(out) - n, "%02X\n", line_checksum(out, n));
        uart_write_bytes(PORT, out, n);
        seq++;
        s_tx = seq;
        vTaskDelay(pdMS_TO_TICKS(PING_INTERVAL_MS));
    }
}

// Validates one received line (newline already stripped). Returns 1 and sets
// *seq on a good ping, 0 on a garbled one.
static int parse_ping(const char *line, size_t len, uint32_t *seq)
{
    const size_t magic_len = strlen(MAGIC);
    // MAGIC + 8 hex + ':' + filler + ':' + 2 hex
    const size_t want = magic_len + 8 + 1 + strlen(FILLER) + 1 + 2;
    if (len != want || strncmp(line, MAGIC, magic_len) != 0) return 0;
    if (line[magic_len + 8] != ':' || line[len - 3] != ':') return 0;
    if (strncmp(line + magic_len + 9, FILLER, strlen(FILLER)) != 0) return 0;

    char hex[9];
    memcpy(hex, line + magic_len, 8);
    hex[8] = 0;
    char *end = NULL;
    unsigned long s = strtoul(hex, &end, 16);
    if (end != hex + 8) return 0;

    char ck[3] = { line[len - 2], line[len - 1], 0 };
    unsigned long c = strtoul(ck, &end, 16);
    if (end != ck + 2 || (uint8_t)c != line_checksum(line, len - 2)) return 0;

    *seq = (uint32_t)s;
    return 1;
}

static void rx_task(void *arg)
{
    uint8_t buf[128];
    char line[128];
    size_t used = 0;
    int have_last = 0;
    uint32_t last = 0;

    while (1) {
        int len = uart_read_bytes(PORT, buf, sizeof(buf), pdMS_TO_TICKS(100));
        for (int i = 0; i < len; i++) {
            char ch = (char)buf[i];
            if (ch != '\n') {
                if (used < sizeof(line) - 1) line[used++] = ch;
                else { used = 0; s_bad++; }       // runaway line - no newline seen
                continue;
            }
            line[used] = 0;
            if (used > 0) {
                uint32_t seq;
                if (!parse_ping(line, used, &seq)) {
                    s_bad++;
                } else {
                    s_rx++;
                    if (have_last && seq > last + 1) {
                        s_lost += seq - last - 1;
                    } else if (have_last && seq <= last) {
                        // The other board rebooted (re-flashed / reset) and
                        // started counting from 0 again - not a loss.
                        ESP_LOGW(TAG, "peer sequence restarted (%lu -> %lu) - other board rebooted",
                                 (unsigned long)last, (unsigned long)seq);
                    }
                    last = seq;
                    have_last = 1;
                }
            }
            used = 0;
        }
    }
}

void app_main(void)
{
    uart_config_t cfg = {
        .baud_rate  = BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    uart_driver_install(PORT, 2048, 2048, 0, NULL, 0);
    uart_param_config(PORT, &cfg);
    uart_set_pin(PORT, TX_PIN, RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);

    ESP_LOGI(TAG, "=== UART TUNNEL WIRE TEST ===");
    ESP_LOGI(TAG, "TX=GPIO%d  RX=GPIO%d  %d baud  ping every %d ms", TX_PIN, RX_PIN, BAUD, PING_INTERVAL_MS);
    ESP_LOGI(TAG, "Flash this to BOTH boards, then watch 'RX received'.");
    ESP_LOGI(TAG, "  RX climbs  -> this board's RX (GPIO%d) is getting data = wire OK", RX_PIN);
    ESP_LOGI(TAG, "  RX stays 0 -> wire feeding this board's GPIO%d is broken (or GND missing)", RX_PIN);

    xTaskCreate(rx_task, "link_rx", 4096, NULL, 6, NULL);
    xTaskCreate(tx_task, "link_tx", 3072, NULL, 5, NULL);

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        uint32_t tx = s_tx, rx = s_rx, lost = s_lost, bad = s_bad;
        if (rx == 0) {
            ESP_LOGW(TAG, "TX sent=%lu | RX received=0  <-- NO DATA on GPIO%d yet",
                     (unsigned long)tx, RX_PIN);
        } else {
            ESP_LOGI(TAG, "TX sent=%lu | RX received=%lu lost=%lu garbled=%lu  [LINK OK]",
                     (unsigned long)tx, (unsigned long)rx, (unsigned long)lost, (unsigned long)bad);
        }
        // Plain printf, no log prefix/colour: the wizard matches this exact line.
        printf("LINKSTAT tx=%lu rx=%lu lost=%lu bad=%lu\n",
               (unsigned long)tx, (unsigned long)rx, (unsigned long)lost, (unsigned long)bad);
    }
}
