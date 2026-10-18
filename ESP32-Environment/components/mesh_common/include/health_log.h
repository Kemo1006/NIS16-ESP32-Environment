/**
 * @file health_log.h
 * @brief Periodic "[HEALTH]" serial line: heap + per-task stack headroom
 *        (crash diagnosis, checklist C12 / D9). Serial only - not in the CSV.
 *
 * NIS16 — CTTHES3
 */
#pragma once

#include "esp_err.h"

/** Start the health task (idempotent). A failure is logged and is not fatal. */
esp_err_t health_log_start(void);
