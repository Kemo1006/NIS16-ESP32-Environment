/**
 * @file crash_record.h
 * @brief A crash's PC + backtrace and the last [HEALTH] reading, kept across
 *        the reboot in RTC memory and written to crashes_<node>.csv on the SD
 *        card at the next boot (checklist C12 / D9). See crash_record.c.
 *
 * NIS16 — CTTHES3
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/** health_log.c: remember the latest reading (RTC memory, survives a crash reboot). */
void crash_record_note_health(uint32_t up_s, uint32_t heap, uint32_t min_heap, uint32_t big,
                              const char *tight_task, uint32_t tight_free);

/** The column names of crashes_<node>.csv. */
const char *crash_record_csv_header(void);

/** Boot-time: when `crashed` (this boot's reset reason is a crash), format the
 *  record as one CSV row into `row` and return true. Always clears the record. */
bool crash_record_take(bool crashed, int boot, const char *reset_reason, char *row, size_t len);
