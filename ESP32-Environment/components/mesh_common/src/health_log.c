/**
 * @file health_log.c
 * @brief One "[HEALTH]" line on the serial port every HEALTH_LOG_INTERVAL_S:
 *        free heap, the lowest it has been, the largest free block, and how
 *        close each known task came to running out of stack.
 *
 * Why (oct. 18 2026, checklist C12 / D9): victims under the blackhole attacker
 * crashed (PANIC / INT_WDT) during the attack, twice, and nothing in the CSV
 * warned beforehand. The crash watch (run_gui.ps1) records this board's serial
 * output; these lines show whether memory or a stack was running out in the
 * minutes BEFORE a crash, next to the backtrace. Serial only - the telemetry
 * CSV is not touched, so the dataset and the method are unchanged.
 *
 * Runs at the lowest application priority so it never delays the 10 Hz
 * telemetry or the probe schedule. Started by heartbeat_start() on every board.
 *
 * NIS16 — CTTHES3
 */

#include "health_log.h"
#include "mesh_config.h"

#include <stdint.h>
#include <stdio.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_log.h"
#include "esp_system.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"

static const char *TAG = "HEALTH";

/* Settings (overridable with -D at build time; kept here so mesh_config.h, which
 * carries each laptop's local attacker MAC, does not have to change). 0 = off. */
#ifndef HEALTH_LOG_INTERVAL_S
#define HEALTH_LOG_INTERVAL_S 30
#endif
#ifndef HEALTH_LOW_HEAP_B
#define HEALTH_LOW_HEAP_B     20000U      /* warn when the free heap has been below this */
#endif
#ifndef HEALTH_LOW_STACK_B
#define HEALTH_LOW_STACK_B    512U        /* warn when a task has had less stack left than this */
#endif
#ifndef STACK_HEALTH
#define STACK_HEALTH          3072U
#endif
#ifndef TASK_PRIO_HEALTH
#define TASK_PRIO_HEALTH      1           /* lowest app priority: never delays telemetry / probes */
#endif

/* Every task this firmware may run (root, victim, attacker, wormhole end).
 * A name a given build does not have is simply skipped. */
static const char *const k_tasks[] = {
    "telemetry", "probe_gen", "probe_relay", "phase_listener", "phase_resync",
    "heartbeat", "csv_export", "arr_writer", "exp_ctrl",
    "wh_uart_rx", "wh_role", "wh_fwd", "wh_reinject",
};

static void health_task(void *arg)
{
    (void)arg;
    char line[320];
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(HEALTH_LOG_INTERVAL_S * 1000U));

        const uint32_t heap  = esp_get_free_heap_size();
        const uint32_t floor = esp_get_minimum_free_heap_size();
        const uint32_t big   = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
        int n = snprintf(line, sizeof(line), "up=%llus heap=%lu min=%lu big=%lu | stack free(B):",
                         (unsigned long long)(esp_timer_get_time() / 1000000LL),
                         (unsigned long)heap, (unsigned long)floor, (unsigned long)big);

        const char *low_task = NULL;
        uint32_t low_free = UINT32_MAX;
        for (size_t i = 0; i < sizeof(k_tasks) / sizeof(k_tasks[0]) && n > 0 && n < (int)sizeof(line); i++) {
            TaskHandle_t h = xTaskGetHandle(k_tasks[i]);
            if (!h) {
                continue;
            }
            /* ESP-IDF stacks are in bytes, so this is bytes never used so far. */
            const uint32_t left = (uint32_t)uxTaskGetStackHighWaterMark(h);
            n += snprintf(line + n, sizeof(line) - (size_t)n, " %s=%lu", k_tasks[i], (unsigned long)left);
            if (left < low_free) {
                low_free = left;
                low_task = k_tasks[i];
            }
        }
        ESP_LOGI(TAG, "[HEALTH] %s", line);

        /* Loud when something is close to the edge - the line the crash watch
         * and a person reading the log should not miss. */
        if (floor < HEALTH_LOW_HEAP_B) {
            ESP_LOGW(TAG, "[HEALTH] LOW HEAP: the free heap has been down to %lu B (largest block now %lu B)",
                     (unsigned long)floor, (unsigned long)big);
        }
        if (low_task && low_free < HEALTH_LOW_STACK_B) {
            ESP_LOGW(TAG, "[HEALTH] LOW STACK: task '%s' has had only %lu B of stack left",
                     low_task, (unsigned long)low_free);
        }
    }
}

esp_err_t health_log_start(void)
{
#if HEALTH_LOG_INTERVAL_S > 0
    static bool started = false;
    if (started) {
        return ESP_OK;
    }
    BaseType_t rc = xTaskCreate(health_task, "health", STACK_HEALTH, NULL, TASK_PRIO_HEALTH, NULL);
    if (rc != pdPASS) {
        ESP_LOGW(TAG, "Could not start the health log (not fatal - the run is unaffected)");
        return ESP_FAIL;
    }
    started = true;
    ESP_LOGI(TAG, "Health log: one [HEALTH] line every %u s (serial only, not in the CSV)",
             (unsigned)HEALTH_LOG_INTERVAL_S);
#endif
    return ESP_OK;
}
