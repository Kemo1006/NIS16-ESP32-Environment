/**
 * @file sd_status.h
 * @brief SD card boot check: mount, ensure the ATTACK x TOPOLOGY x LOCATION
 *        folder tree, and write a diagnostic status report into the folder
 *        matching this board's build attack, build topology, and recorded site.
 *
 * The tree mirrors exports/<attack>/<topology>/<location>/ on the host exactly,
 * so a card pulled from a node deployed somewhere without a laptop copies
 * straight into the analysis pipeline (see tools/import_sdcard.py).
 *
 * SPIFFS (csv_logger.c) remains the primary telemetry path, but on a successful
 * boot check the card is left MOUNTED so csv_logger.c can mirror each row onto
 * it; csv_logger_close() calls sd_status_unmount() at experiment end.
 *
 * Every entry point here is non-fatal: a missing, unmountable, or misconfigured
 * card must never stop an experiment run. See mesh_config.h SD CARD section
 * for pin/path constants.
 *
 * NIS16 — CTTHES3
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SD_STATUS_OK = 0,           /**< mounted, tree verified, report written */
    SD_STATUS_NO_CARD,          /**< SPI bus init or mount failed */
    SD_STATUS_NO_LOCATION_FILE, /**< mounted, but location.txt is absent */
    SD_STATUS_BAD_LOCATION,     /**< location.txt holds an unrecognised value */
    SD_STATUS_TREE_FAILED,      /**< mounted, but a folder could not be created */
    SD_STATUS_WRITE_FAILED,     /**< folder resolved, but the report write failed */
} sd_status_result_t;

/**
 * One-shot boot check. Call once, before mesh_setup_init() (which can block up
 * to ~60s waiting for a parent — a board that never joins should still get a
 * report). Mounts SPI3, walks/creates the 63-folder tree, reads location.txt,
 * writes the report into <attack>/<topology>/<location>/. Never aborts.
 *
 * On SD_STATUS_OK the card is left mounted (see sd_status_run_dir()); on every
 * other result it unmounts and frees SPI3 before returning.
 */
sd_status_result_t sd_status_run_boot_check(void);

/** Short human-readable description of a result, for a one-line log banner. */
const char *sd_status_result_str(sd_status_result_t result);

/** This build's MESH_TOPOLOGY as a folder name, e.g. "partial_mesh".
 *  Resolved here (not by callers) because MESH_TOPOLOGY is PRIVATE to
 *  mesh_common — the same macro read from root_main.c/victim_main.c would
 *  always see the #ifndef fallback (TREE), regardless of the actual build. */
const char *sd_status_topology_dirname(void);

/** This build's ACTIVE_ATTACK as a folder name: "baseline", "blackhole", or
 *  "wormhole". Resolved here for the same reason as the topology above —
 *  ACTIVE_ATTACK is PRIVATE per component, and mesh_common only sees the real
 *  build value via the ACTIVE_ATTACK block in its own CMakeLists.txt. */
const char *sd_status_attack_dirname(void);

/** Canonical spelling of the recorded location (e.g. "DLSU_Library"), or NULL
 *  if location.txt was missing/unrecognised on the last boot check. */
const char *sd_status_location(void);

/** This board's folder on the card — "/sdcard/<attack>/<topology>/<location>" —
 *  or NULL if the boot check did not reach SD_STATUS_OK (no card, bad location,
 *  failed tree) or the card has since been unmounted. csv_logger.c writes this
 *  run's CSVs here; a NULL simply means no SD mirror this run. */
const char *sd_status_run_dir(void);

/** How many times this board has booted into the folder sd_status_run_dir()
 *  names, counting this boot (1 on the first). Used to keep each power-cycle's
 *  CSVs in separate files. 0 if the boot check did not reach SD_STATUS_OK. */
int sd_status_boot_count(void);

/** This FIRMWARE IMAGE's build date+time as "YYYY-MM-DD HH:MM:SS", read from
 *  the app descriptor the build system stamps into every image (esp_app_desc.h).
 *  Never NULL — an unparseable descriptor yields "unknown".
 *
 *  This is the closest thing the board has to a calendar, and the reason it
 *  exists: an ESP32 with no RTC boots at 1970, so nothing it writes can say
 *  WHEN it ran. A build stamp cannot say that either — but it is baked into the
 *  binary at link time, so it is identical on every boot of this flash no matter
 *  how many times the board is power-cycled out in the field (which the
 *  mobility/powercycle scenarios do deliberately). That makes it the one field
 *  that answers "is this card's data from the firmware I flashed today, or left
 *  over from a session weeks ago?" — see csv_logger.c's runs.csv manifest, which
 *  records it per boot, and tools/import_sdcard.py, which shows it per file.
 *
 *  It is a BUILD time, not a capture time: every boot of one flash reports the
 *  same value, so pair it with sd_status_boot_count() for ordering within a
 *  flash. */
const char *sd_status_build_stamp(void);

/** Unmount the card and release SPI3. Safe to call when nothing is mounted.
 *  csv_logger_close() calls this; nothing else normally needs to. */
void sd_status_unmount(void);

/** Mount the card if it isn't already (borrowing an existing mount when one
 *  is live, same as the location.txt calls below), for a one-off operation
 *  requested after csv_logger_close() has already unmounted it. @p took_mount
 *  is set true iff this call brought SPI3 up itself, in which case the caller
 *  must call sd_status_unmount() when done; false means an existing mount was
 *  borrowed and must be left alone.
 *  @param what  command name, for the log line on failure. */
bool sd_status_ensure_mounted(const char *what, bool *took_mount);

/** Absolute path of the report written by the last boot check, or "" if none
 *  was written. */
const char *sd_status_report_path(void);

/* ── Standalone location.txt access over serial ───────────────────────────────
 * Both calls below work whether or not the boot check succeeded: they borrow
 * the existing mount when there is one, and otherwise bring SPI3 up just for
 * the one file operation and tear it back down again. They exist so a card
 * whose location.txt is missing or wrong can be inspected and fixed without
 * ever removing it from the board (see csv_logger.c's GET_LOCATION /
 * SET_LOCATION= commands and tools/export_logs.py).
 * ─────────────────────────────────────────────────────────────────────────── */

/** Why sd_status_write_location() did or did not write. Split out from a plain
 *  bool because "you named a site that doesn't exist" and "the card refused the
 *  write" need completely different fixes, and an operator staring at one
 *  merged failure string cannot tell which one they are looking at. */
typedef enum {
    SD_LOC_WRITE_OK = 0,     /**< location.txt now holds the canonical value */
    SD_LOC_WRITE_BAD_VALUE,  /**< not an accepted site name — card NOT touched */
    SD_LOC_WRITE_NO_CARD,    /**< SPI bus init or mount failed */
    SD_LOC_WRITE_IO_FAILED,  /**< mounted, but the write itself failed */
} sd_loc_write_t;

/** What sd_status_peek_location() found on the card. */
typedef enum {
    SD_LOC_READ_OK = 0,   /**< out[] holds the canonical spelling */
    SD_LOC_READ_MISSING,  /**< mounted, but location.txt is absent — out[] empty */
    SD_LOC_READ_INVALID,  /**< present but unrecognised — out[] holds the raw text */
    SD_LOC_READ_NO_CARD,  /**< SPI bus init or mount failed — out[] empty */
} sd_loc_read_t;

/** Read location.txt as it stands RIGHT NOW, without changing it.
 *
 *  Deliberately separate from sd_status_location(), which reports what the last
 *  boot check accepted and is NULL whenever that check failed — exactly the case
 *  where an operator most needs to see what is actually on the card. This one
 *  goes back to the file, so a rejected value comes back as raw text instead of
 *  disappearing.
 *
 *  @param out      receives the canonical spelling (SD_LOC_READ_OK) or the
 *                  rejected raw text (SD_LOC_READ_INVALID); "" otherwise.
 *  @param out_len  size of @p out; 40 bytes is enough for any accepted value. */
sd_loc_read_t sd_status_peek_location(char *out, size_t out_len);

/** Write/overwrite location.txt on the SD card with a canonical location
 *  string (case-insensitive; must be one of the accepted values).
 *
 *  Deliberately NOT called automatically: location must be RECORDED by an
 *  operator, never inferred or defaulted (thesis panel P4) — this only
 *  writes when explicitly asked to. Takes effect on the NEXT boot check,
 *  not retroactively for one that already ran and failed this boot.
 *
 *  An unrecognised value is rejected BEFORE the card is touched, so a typo
 *  can never destroy a location that was already correct. Callers that want
 *  "leave it alone if it already says this" should peek first — the firmware
 *  does not second-guess an explicit write request. */
sd_loc_write_t sd_status_write_location(const char *value);

/* ── Command Center: /sdcard/node_config.txt ──────────────────────────────────
 * Read during the boot check's mounted window and cached here for
 * node_identity.c. Still read THERE and not later: on any non-OK result the
 * card is unmounted and SPI3 freed before the check returns, so a later reader
 * would have to bring the bus up again with WiFi already live.
 * ─────────────────────────────────────────────────────────────────────────── */

/** "nickname=" from node_config.txt, or NULL if absent/unreadable/empty. */
const char *sd_status_get_config_nickname(void);

/** "role=" from node_config.txt, or NULL. Informational only — node_identity.c
 *  warns about it and ignores it, since role comes from the build flags. */
const char *sd_status_get_config_role(void);

#ifdef __cplusplus
}
#endif
