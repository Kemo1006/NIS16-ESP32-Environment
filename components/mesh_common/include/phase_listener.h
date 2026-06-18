/**
 * @file phase_listener.h
 * @brief Phase-listener background task — common to all node roles.
 *
 * The root node broadcasts phase-transition messages (phase_id + seq_num +
 * timestamp) to every mesh node.  This module:
 *
 *  • Runs a FreeRTOS task that continuously calls esp_mesh_recv() and
 *    filters for phase-broadcast messages.
 *  • Applies sequence-number deduplication so repeated broadcasts are
 *    idempotent (thesis spec: root broadcasts each phase 5 times).
 *  • Maintains global current_phase_id and ground_truth_label variables
 *    protected by a FreeRTOS mutex.
 *  • Exposes get_current_label() and get_current_phase_id() for use by
 *    the telemetry sampler and (later) the attacker relay logic.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ── Wire format of a phase broadcast message ────────────────────────────── */

/** Magic cookie — first 4 bytes of every phase-broadcast payload. */
#define PHASE_MSG_MAGIC     0x50485345U   /* "PHSE" */

/** On-wire structure; packed to avoid padding differences across compilers. */
typedef struct __attribute__((packed)) {
    uint32_t magic;         /**< PHASE_MSG_MAGIC                           */
    uint8_t  phase_id;      /**< Phase identifier (0–4, see mesh_config.h) */
    uint32_t seq_num;       /**< Monotonically increasing broadcast counter */
    int64_t  timestamp_us;  /**< Root's esp_timer_get_time() at broadcast   */
} phase_msg_t;

/* ── Public API ──────────────────────────────────────────────────────────── */

/**
 * @brief Start the phase-listener FreeRTOS task.
 *
 * Must be called after mesh_setup_init().  Safe to call on both root and
 * non-root nodes; the root will still receive its own broadcasts if it
 * forwards them into the mesh receive queue.
 *
 * @return ESP_OK on success.
 */
esp_err_t phase_listener_start(void);

/**
 * @brief Return the ground-truth label for the current phase.
 *
 * Thread-safe.  Returns:
 *   0 — Baseline / Cooldown / Terminate
 *   1 — Blackhole manipulation
 *   2 — Wormhole manipulation
 */
uint8_t phase_listener_get_label(void);

/**
 * @brief Return the raw phase ID currently active (0–4).
 *
 * Thread-safe.
 */
uint8_t phase_listener_get_phase_id(void);

/**
 * @brief Return true if the experiment has ended (phase ID == TERMINATE).
 */
bool phase_listener_is_terminated(void);

/**
 * @brief Block the calling task until the experiment terminates.
 *
 * Used by root_main to hold app_main() alive while the experiment runs.
 */
void phase_listener_wait_for_terminate(void);

/* ── Root-side broadcast helper (used only by root_main.c) ───────────────── */

/**
 * @brief Broadcast a phase message to all mesh nodes.
 *
 * Sends PHASE_BROADCAST_REPEAT copies with PHASE_BROADCAST_GAP_MS delays
 * between them.  Increments an internal sequence counter automatically.
 *
 * @param phase_id   Phase to broadcast (0–4).
 */
void phase_listener_broadcast(uint8_t phase_id);

#ifdef __cplusplus
}
#endif