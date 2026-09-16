// Standalone UART tunnel-wire loopback test (NOT part of the mesh firmware).
// Flash this to BOTH attacker boards (COM25 + COM27). Each board continuously
// sends a "PING" out its tunnel TX pin (GPIO17) and listens on its tunnel RX
// pin (GPIO16). If a board RECEIVES pings, the wire feeding THAT board's RX
// works. When both boards are running and wired correctly (crossed 17<->16 +
// shared GND), BOTH print [LINK OK]. No mesh, no attack window — result in ~2s.
#include <stdio.h>
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
    uart_driver_install(PORT, 2048, 0, 0, NULL, 0);
    uart_param_config(PORT, &cfg);
    uart_set_pin(PORT, TX_PIN, RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);

    ESP_LOGI(TAG, "=== UART TUNNEL WIRE TEST ===");
    ESP_LOGI(TAG, "TX=GPIO%d  RX=GPIO%d  %d baud", TX_PIN, RX_PIN, BAUD);
    ESP_LOGI(TAG, "Flash this to BOTH boards, then watch 'RX received'.");
    ESP_LOGI(TAG, "  RX climbs  -> this board's RX (GPIO%d) is getting data = wire OK", RX_PIN);
    ESP_LOGI(TAG, "  RX stays 0 -> wire feeding this board's GPIO%d is broken (or GND missing)", RX_PIN);

    uint32_t tx_seq = 0, rx_count = 0;
    uint8_t buf[256];
    char out[48];
    int hb = 0;

    while (1) {
        int n = snprintf(out, sizeof(out), "%s%lu\n", MAGIC, (unsigned long)tx_seq++);
        uart_write_bytes(PORT, out, n);

        int len = uart_read_bytes(PORT, buf, sizeof(buf) - 1, 120 / portTICK_PERIOD_MS);
        if (len > 0) {
            buf[len] = 0;
            if (strstr((char *)buf, MAGIC)) {
                rx_count++;
                ESP_LOGI(TAG, ">>> RX OK: got a PING from the OTHER board (total RX=%lu)",
                         (unsigned long)rx_count);
            }
        }

        if (++hb >= 3) {
            hb = 0;
            if (rx_count == 0) {
                ESP_LOGW(TAG, "TX sent=%lu | RX received=0  <-- NO DATA on GPIO%d yet",
                         (unsigned long)tx_seq, RX_PIN);
            } else {
                ESP_LOGI(TAG, "TX sent=%lu | RX received=%lu  [LINK OK]",
                         (unsigned long)tx_seq, (unsigned long)rx_count);
            }
        }
        vTaskDelay(280 / portTICK_PERIOD_MS);
    }
}
