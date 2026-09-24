/**
 * @file csv_logger.c
 * @brief SPIFFS-backed CSV telemetry logger implementation.
 *
 * NIS16 — CTTHES2 Milestone 1 — Common Module
 */

#include "csv_logger.h"
#include "mesh_config.h"
#include "sd_status.h"
#include "blackhole_target.h"
#include "phase_listener.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>   /* strtoll(): SET_TIME=<unix_epoch> */
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_log.h"
#include "esp_spiffs.h"
#include "driver/uart.h"
#include "esp_timer.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "CSV_LOGGER";

static FILE    *s_log_fp          = NULL;   /* telemetry file (all roles)   */
static FILE    *s_arrivals_fp     = NULL;   /* probe arrivals (root only)   */
static char     s_filepath[128]   = {0};    /* path of telemetry file       */
static char     s_arrivals_path[128] = {0}; /* path of arrivals file        */
static uint32_t s_row_count       = 0;     /* telemetry rows since last flush */
static uint32_t s_arrivals_row_count = 0;  /* arrival rows since last flush — separate
                                             * because the telemetry path resets
                                             * s_row_count on its own cadence */
static uint32_t s_total_rows      = 0;     /* rows since boot, never reset by a flush —
                                             * s_row_count wraps to 0 every
                                             * LOGGER_FLUSH_RECORDS, so it can't
                                             * supply the row count runs.csv reports. */
static bool     s_mounted         = false;
static int64_t  s_boot_start_us   = 0;     /* esp_timer_get_time() at csv_logger_init(),
                                             * for the uptime column in runs.csv */

/* SD mirror — best-effort copies of the two files above, written into
 * sd_status_run_dir() so a board deployed on a powerbank with no laptop can be
 * recovered by pulling the card. NULL means no mirror open this run (not
 * attempted yet, no card, bad location.txt, or a write failed and we gave up);
 * SPIFFS is unaffected either way, so a bad card can never cost an 11-minute run.
 *
 * Opened LAZILY (see sd_mirror_ensure()) rather than at csv_logger_init(): the
 * card is full of boots that reset before logging anything — esptool connect/
 * reset cycles, the wizard's MAC read, a SET_LOCATION pass — and an eager fopen()
 * left every one of those as a permanent 0-byte file on the card, since FATFS
 * creates the directory entry at open but the header sits in the stdio buffer
 * until the first flush. Opening on the first row actually logged means a boot
 * that logs nothing leaves nothing on the card either. */
static FILE *s_sd_log_fp        = NULL;
static FILE *s_sd_arrivals_fp   = NULL;
static char  s_sd_log_path[192]      = {0};
static char  s_sd_arrivals_path[192] = {0};
static bool  s_sd_log_failed      = false;  /* latched: don't retry every row */
static bool  s_sd_arrivals_failed = false;

/* esp_timer_get_time() at the last sd_mirror_sync_due(). 0 = never synced this
 * boot, which makes the first call sync immediately — that is deliberate: it
 * gets a NON-ZERO size into the directory entry as early as possible, so even a
 * run that dies seconds in leaves a card file the host can still read. */
static int64_t s_sd_last_sync_us = 0;

/* sd_status_run_dir() goes NULL the moment csv_logger_close() unmounts the
 * card (sd_status_unmount() clears its own s_run_dir along with it) — but
 * csv_logger_archive_sd_now() runs from the serial export task, AFTER close()
 * already ran. Captured here, just before that unmount, so the path survives
 * for the host to request an archive of this boot's own run folder on demand
 * (see ARCHIVE_SD below). "" means this boot never had an SD run dir. */
static char s_last_sd_run_dir[96] = {0};

/* Captured at csv_logger_init() so sd_mirror_ensure() (called from the append
 * functions, which don't otherwise know node_id/role) and csv_logger_close()
 * (for the manifest's "clean" line) both have them without re-plumbing every
 * call site. s_role_str points at one of the two string literals below, never
 * copied — safe to hold for the process lifetime. */
static char        s_node_id[32] = {0};
static const char *s_role_str    = "victim";
static int         s_run_number  = 0;   /* this boot's r<N> — see sd_csv_path() */

/*
 * Set once, at the moment an export starts muting logging, and never cleared —
 * deliberately mirroring the esp_log_level_set("*", ESP_LOG_NONE) below, which
 * this file also never restores.
 *
 * The Command Center dashboard prints with printf(), which esp_log_level_set
 * does NOT gate, so without this flag a repaint could splice itself into the
 * framed CSV stream and reproduce I-001 ("never saw END_OF_FILE") exactly.
 * Latching rather than toggling makes the check race-free: the flag only ever
 * goes false->true, so a dashboard task that reads false cannot then be
 * preempted into printing during a transfer that had already begun.
 *
 * Consequence, by design: once a board has exported, its dashboard stays quiet
 * until reboot. The export is the last step of a run, so nothing is lost.
 */
static volatile bool s_export_in_progress = false;

/* UART port used for log export */
#define EXPORT_UART     UART_NUM_0
#define EXPORT_BUF_SIZE 512

/* ── CSV headers ─────────────────────────────────────────────────────────── */

/* Schema v2 (F3). The first 11 fields and their order are schema v1, untouched,
 * so a positional reader of an older capture is unaffected; the three relay
 * counters are appended. See csv_logger.h for what they mean and why they had
 * to exist. */
static const char *TELEMETRY_HEADER =
    "timestamp_us,node_id,role,layer,parent_mac,"
    "rssi_dbm,retry_count,tx_count,probes_count,"
    "phase_id,gt_label,"
    "recv_count,forward_count,drop_count\n";

static const char *PROBE_ARRIVAL_HEADER =
    "timestamp_us,node_id,role,layer,parent_mac,"
    "rssi_dbm,retry_count,tx_count,probes_received,"
    "phase_id,gt_label,src_mac,seq_num,latency_us\n";

/* ── Forward declarations ────────────────────────────────────────────────── */
static void serial_export_task(void *arg);

/* ── SD mirror helpers ───────────────────────────────────────────────────── */

/* Names — but does not open —
 * <run_dir>/<role>_<node_id>_r<run>_b<boot>_<kind>.csv.
 * The name carries role/node/run/boot because the card is read by a human and
 * by tools/import_sdcard.py with no other context — the folder path supplies
 * attack/topology/location, the name supplies the rest. Field order and the
 * _telem/_arrivals suffix match _make_filename() in tools/export_logs.py.
 *
 * TWO counters, deliberately, because they answer different questions:
 *
 *   r<run>  how many real, data-logging runs this node has done in this folder,
 *           counted gaplessly (r1, r2, r3...). This is the one to read when you
 *           want "which experiment run is this" — see
 *           sd_manifest_count_prior_runs().
 *   b<boot> the raw boot counter from sd_status.c, which also ticks for boots
 *           that never log anything: every esptool connect/reset around a
 *           flash, every MAC read, every SET_LOCATION pass. So b-numbers SKIP
 *           (b1, b5, b9...), and the size of each gap is itself the useful
 *           signal — it tells you how many times the board was reset in
 *           between.
 *
 * The boot count stays in the name (rather than being replaced by the run
 * count) because it is what guarantees uniqueness even on a card whose
 * runs.csv has been disturbed: boot numbers never repeat within a folder, so
 * two files can never collide even if a run number were recomputed low.
 *
 * One run, one file — actually opened by sd_mirror_ensure() below, on the
 * first row this boot has to log. */
static void sd_csv_path(char *out, size_t out_len, const char *kind,
                        const char *role_str, const char *node_id, int run_number)
{
    const char *run_dir = sd_status_run_dir();
    if (!run_dir) {
        out[0] = '\0';
        return;
    }
    snprintf(out, out_len, "%s/%s_%s_r%d_b%d_%s.csv",
             run_dir, role_str, node_id, run_number, sd_status_boot_count(), kind);
}

/* Removes any existing 0-byte *_telem.csv / *_arrivals.csv in run_dir.
 *
 * A 0-byte mirror is provably 0 rows — sd_mirror_ensure() below writes the
 * header and fflush()es in the same call that creates the file, so nothing
 * genuine is ever left empty. Leftovers here can only be pre-fix boots (this
 * fopen()'d eagerly and could die before the first flush) or a boot that
 * opened but never got a row before losing power. Either way there is nothing
 * to lose by clearing them, and it keeps a long-lived card from accumulating
 * one dead file per reset around every flash/MAC-read/SET_LOCATION cycle.
 *
 * Runs once per csv_logger_init(), before this boot's own files are named, so
 * it can never touch what this boot is about to write. Best-effort: any
 * failure to open/read the folder is logged and skipped, never fatal. */
static void sd_sweep_empty_mirrors(void)
{
    const char *run_dir = sd_status_run_dir();
    if (!run_dir) {
        return;
    }

    DIR *dir = opendir(run_dir);
    if (!dir) {
        return;
    }

    int removed = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        const char *name = ent->d_name;
        size_t len = strlen(name);
        bool is_mirror = (len > 10 && strcmp(name + len - 10, "_telem.csv") == 0)
                       || (len > 13 && strcmp(name + len - 13, "_arrivals.csv") == 0);
        if (!is_mirror) {
            continue;
        }

        /* run_dir is s_run_dir[96] (sd_status.c) and d_name can be as long as
         * the filesystem's NAME_MAX; sized for the worst case so GCC's
         * -Wformat-truncation can prove this never truncates. */
        char full_path[96 + 1 + 256];
        snprintf(full_path, sizeof(full_path), "%s/%s", run_dir, name);
        struct stat st;
        if (stat(full_path, &st) == 0 && st.st_size == 0) {
            if (remove(full_path) == 0) {
                removed++;
            }
        }
    }
    closedir(dir);

    if (removed > 0) {
        ESP_LOGI(TAG, "SD sweep: removed %d empty leftover CSV(s) from %s.", removed, run_dir);
    }
}

/* Moves any REMAINING (non-empty) *_telem.csv / *_arrivals.csv already sitting
 * in run_dir into run_dir/_archive/ before this boot's own files are named, so
 * a fresh run's folder shows only THIS run's output. Nothing is deleted — a
 * card that's been reused across weeks of sessions accumulates one set of
 * mirrors per repeat, and with no cleanup it becomes a guessing game which
 * file is the current run vs. three sessions ago. Archiving (not deleting)
 * matches this project's convention everywhere else derived data is at stake
 * (see ARCHIVE-RUNBOOK.md, trim_run.py's stale-output warnings) — captures
 * are irreplaceable, so the fix is "file it out of the way", never "delete".
 *
 * Runs once per csv_logger_init(), right after sd_sweep_empty_mirrors() (so
 * it never sees the 0-byte leftovers that sweep already cleared) and before
 * this boot's own files are named — it can never archive what this boot is
 * about to write. Best-effort like the sweep above: any failure to create the
 * archive folder or move a file is logged and skipped, never fatal; worst
 * case an old file is simply left where it was. runs.csv is NOT touched — it
 * is the manifest that gives every boot its run number, and archiving it
 * would break that count for boots still to come.
 *
 * Factored to take run_dir explicitly (rather than reading sd_status_run_dir()
 * itself) so csv_logger_archive_sd_now() below can reuse the exact same move
 * logic on demand, right after a run, using a path cached from BEFORE the
 * card was unmounted — sd_status_run_dir() itself has already gone NULL by
 * the time an on-demand archive is requested (see s_last_sd_run_dir). */
static void sd_archive_mirrors_in(const char *run_dir)
{
    if (!run_dir || run_dir[0] == '\0') {
        return;
    }

    DIR *dir = opendir(run_dir);
    if (!dir) {
        return;
    }

    char archive_dir[96 + 1 + 8];
    snprintf(archive_dir, sizeof(archive_dir), "%s/_archive", run_dir);
    bool archive_ready = false;

    int moved = 0;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        const char *name = ent->d_name;
        size_t len = strlen(name);
        bool is_mirror = (len > 10 && strcmp(name + len - 10, "_telem.csv") == 0)
                       || (len > 13 && strcmp(name + len - 13, "_arrivals.csv") == 0);
        if (!is_mirror) {
            continue;
        }

        if (!archive_ready) {
            struct stat ast;
            if (stat(archive_dir, &ast) != 0) {
                if (mkdir(archive_dir, 0775) != 0 && errno != EEXIST) {
                    ESP_LOGW(TAG, "SD archive: could not create %s -- leaving prior captures in place.",
                             archive_dir);
                    closedir(dir);
                    return;
                }
            }
            archive_ready = true;
        }

        /* run_dir is s_run_dir[96] (sd_status.c) and d_name can be as long as
         * the filesystem's NAME_MAX; sized for the worst case, same as the
         * sweep above, so GCC's -Wformat-truncation can prove this never
         * truncates. */
        char src[96 + 1 + 256];
        char dst[96 + 1 + 8 + 1 + 256];
        snprintf(src, sizeof(src), "%s/%s", run_dir, name);
        snprintf(dst, sizeof(dst), "%s/%s", archive_dir, name);

        if (rename(src, dst) == 0) {
            moved++;
        } else {
            ESP_LOGW(TAG, "SD archive: could not move %s -- left in place.", name);
        }
    }
    closedir(dir);

    if (moved > 0) {
        ESP_LOGI(TAG, "SD archive: moved %d prior capture(s) from %s into _archive/ -- this run starts fresh.",
                 moved, run_dir);
    }
}

/* Thin wrapper over sd_archive_mirrors_in() for the boot-time call site —
 * see csv_logger_init(), which runs this before naming its own files. */
static void sd_archive_prior_run_mirrors(void)
{
    sd_archive_mirrors_in(sd_status_run_dir());
}

/* On-demand counterpart: archives THIS boot's own just-written mirror CSVs,
 * right after the host has confirmed it downloaded them over USB (see
 * ARCHIVE_SD below / tools/export_logs.py --archive-sd), instead of waiting
 * for the NEXT boot's sd_archive_prior_run_mirrors() to do it. Same
 * archive-never-delete policy, just triggered earlier so a run folder (e.g.
 * blackhole/linear/home/) doesn't sit cluttered with this run's CSVs between
 * sessions.
 *
 * csv_logger_close() already unmounted the card by the time the serial
 * export task can receive this command, so this remounts just long enough to
 * do the move (borrowing an existing mount if somehow one is still live) and
 * unmounts again afterward if it was the one to bring SPI3 up. */
esp_err_t csv_logger_archive_sd_now(void)
{
    if (s_last_sd_run_dir[0] == '\0') {
        return ESP_ERR_NOT_FOUND;  /* this boot never had an SD run dir */
    }

    bool took_mount = false;
    if (!sd_status_ensure_mounted("ARCHIVE_SD", &took_mount)) {
        return ESP_FAIL;
    }

    sd_archive_mirrors_in(s_last_sd_run_dir);

    if (took_mount) {
        sd_status_unmount();
    }
    return ESP_OK;
}

/* DELETE_SD_PATH=<rel> — the one deliberate exception to the archive-never-
 * delete policy above: an operator-requested, PERMANENT removal of a card
 * folder such as blackhole/linear/G402 (and everything under it). The host
 * side (run_wizard.ps1, export_logs.py --delete-sd-path) makes the operator
 * type the path back before sending. */
typedef enum {
    SD_DEL_OK,
    SD_DEL_BAD_PATH,
    SD_DEL_IN_USE,
    SD_DEL_NO_CARD,
    SD_DEL_NOT_FOUND,
    SD_DEL_FAILED,
} sd_delete_result_t;

/* Only <attack>[/<more>...] with [A-Za-z0-9_-] segments: no "..", no absolute
 * path, and the card root plus its location.txt / node_config.txt are
 * unreachable because the first segment must be an attack folder. */
static bool sd_rel_path_valid(const char *rel)
{
    static const char *const attack_dirs[] = { "baseline", "blackhole", "wormhole" };

    size_t len = strlen(rel);
    if (len == 0 || rel[0] == '/' || rel[len - 1] == '/') {
        return false;
    }

    int segments = 0;
    const char *seg = rel;
    while (true) {
        const char *slash = strchr(seg, '/');
        size_t seg_len = slash ? (size_t)(slash - seg) : strlen(seg);
        if (seg_len == 0) {
            return false;
        }
        for (size_t i = 0; i < seg_len; i++) {
            unsigned char c = (unsigned char)seg[i];
            if (!isalnum(c) && c != '_' && c != '-') {
                return false;
            }
        }
        if (segments == 0) {
            bool known = false;
            for (size_t i = 0; i < sizeof(attack_dirs) / sizeof(attack_dirs[0]); i++) {
                if (strlen(attack_dirs[i]) == seg_len &&
                    strncasecmp(seg, attack_dirs[i], seg_len) == 0) {
                    known = true;
                    break;
                }
            }
            if (!known) {
                return false;
            }
        }
        segments++;
        if (!slash) {
            break;
        }
        seg = slash + 1;
    }
    return segments <= 5;
}

/* True if `child` is `parent` or sits somewhere below it. Case-insensitive
 * because FAT is — "g402" and "G402" are the same folder on the card. */
static bool sd_path_contains(const char *parent, const char *child)
{
    size_t n = strlen(parent);
    return strncasecmp(parent, child, n) == 0 && (child[n] == '\0' || child[n] == '/');
}

/* One shared buffer instead of a path per recursion level: this runs on the
 * serial export task's 6 KB stack. */
static char s_del_path[256];

/* Empties and removes the directory named by s_del_path, leaving s_del_path
 * unchanged on return. Keeps going past a failed entry so one stuck file
 * doesn't leave the rest of the tree behind. */
static bool sd_remove_tree(int depth, int *files_removed)
{
    if (depth > 8) {
        return false;
    }
    DIR *dir = opendir(s_del_path);
    if (!dir) {
        return false;
    }

    size_t base_len = strlen(s_del_path);
    bool ok = true;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        const char *name = ent->d_name;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
            continue;
        }
        size_t name_len = strlen(name);
        if (base_len + 1 + name_len >= sizeof(s_del_path)) {
            ok = false;
            continue;
        }
        s_del_path[base_len] = '/';
        memcpy(s_del_path + base_len + 1, name, name_len + 1);

        struct stat st;
        if (stat(s_del_path, &st) == 0 && S_ISDIR(st.st_mode)) {
            if (!sd_remove_tree(depth + 1, files_removed)) {
                ok = false;
            }
        } else if (remove(s_del_path) == 0) {
            (*files_removed)++;
        } else {
            ESP_LOGW(TAG, "DELETE_SD_PATH: could not remove %s (errno %d)", s_del_path, errno);
            ok = false;
        }
        s_del_path[base_len] = '\0';
    }
    closedir(dir);

    if (ok && rmdir(s_del_path) != 0) {
        ESP_LOGW(TAG, "DELETE_SD_PATH: could not remove folder %s (errno %d)", s_del_path, errno);
        ok = false;
    }
    return ok;
}

static sd_delete_result_t sd_delete_rel_path(const char *rel, int *files_removed)
{
    *files_removed = 0;
    if (!sd_rel_path_valid(rel)) {
        return SD_DEL_BAD_PATH;
    }
    int n = snprintf(s_del_path, sizeof(s_del_path), "%s/%s", SD_MOUNT_POINT, rel);
    if (n < 0 || n >= (int)sizeof(s_del_path)) {
        return SD_DEL_BAD_PATH;
    }

    /* The export task accepts commands from boot (CSV_EXPORT_ON_INIT), so this
     * can arrive mid-run: never pull the folder out from under open mirrors. */
    const char *live = sd_status_run_dir();
    if (live && sd_path_contains(s_del_path, live)) {
        return SD_DEL_IN_USE;
    }

    bool took_mount = false;
    if (!sd_status_ensure_mounted("DELETE_SD_PATH", &took_mount)) {
        return SD_DEL_NO_CARD;
    }

    sd_delete_result_t result;
    struct stat st;
    if (stat(s_del_path, &st) != 0) {
        result = SD_DEL_NOT_FOUND;
    } else if (!S_ISDIR(st.st_mode)) {
        result = SD_DEL_BAD_PATH;
    } else {
        result = sd_remove_tree(0, files_removed) ? SD_DEL_OK : SD_DEL_FAILED;
    }

    if (took_mount) {
        sd_status_unmount();
    }
    return result;
}

/* ── LIST_SD / EXPORT_SD_PATH — reading the card over USB ─────────────────
 *
 * These exist so the "export straight off the board" path in run_wizard.ps1 can
 * show the SAME file list the pulled-card path shows, without anyone unseating
 * a card. They are strictly READ-ONLY; the one destructive card command remains
 * DELETE_SD_PATH above.
 *
 * Note what LIST_SD deliberately does NOT do: count rows. Counting means
 * reading every byte of every file, and a full 800 KB telemetry file off a
 * 4 MHz SPI card takes seconds — times every file on the card, that is minutes
 * of listing before the operator sees anything. Instead it reports each file's
 * SIZE (free, from stat()) and streams each leaf's runs.csv manifest verbatim,
 * which already carries the per-boot row count the firmware recorded. The host
 * joins the two by boot number using the same parsing it already uses for a
 * mounted card, and learns the TRUE row count when it actually streams a file —
 * at which point a disagreement with the manifest is itself a useful signal
 * (a truncated or reset-interrupted capture). */

/* Size in bytes and DATA-row count (header excluded) of a file, for the
 * LIST_FILES reply. Either output is -1 if the file cannot be read at all, and
 * rows is -1 rather than 0 for an unreadable file so the host can tell "empty"
 * from "unknown" — the same distinction the card listing draws. */
static void spiffs_file_stats(const char *path, long *bytes, long *rows)
{
    *bytes = -1;
    *rows  = -1;
    if (!path || path[0] == '\0') {
        return;
    }
    struct stat st;
    if (stat(path, &st) == 0) {
        *bytes = (long)st.st_size;
    }
    FILE *fp = fopen(path, "r");
    if (!fp) {
        return;
    }
    /* Block reads, not fgetc(): a full telemetry file is ~800 KB and this now
     * sits on the interactive path (the wizard's picker waits on it), so the
     * per-character call overhead is worth avoiding. 512 B keeps it off the
     * export task's 6 KB stack. */
    static char buf[512];
    long lines = 0;
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        for (size_t i = 0; i < n; i++) {
            if (buf[i] == '\n') {
                lines++;
            }
        }
        vTaskDelay(1);   /* one yield per block keeps the watchdog fed */
    }
    fclose(fp);
    *rows = lines > 0 ? lines - 1 : 0;   /* minus the header */
}

/* Like sd_rel_path_valid(), but for a FILE rather than a folder: the final
 * segment may additionally contain '.' so a CSV filename passes. Every other
 * rule — attack folder first, no "..", no absolute path, depth cap — is
 * unchanged, so the card root and its location.txt stay unreachable. */
static bool sd_rel_file_valid(const char *rel)
{
    const char *last_slash = strrchr(rel, '/');
    if (!last_slash || last_slash[1] == '\0') {
        return false;   /* a bare filename has no attack folder in front of it */
    }
    /* Validate the folder part with the existing rules. */
    char folder[192];
    size_t folder_len = (size_t)(last_slash - rel);
    if (folder_len == 0 || folder_len >= sizeof(folder)) {
        return false;
    }
    memcpy(folder, rel, folder_len);
    folder[folder_len] = '\0';
    if (!sd_rel_path_valid(folder)) {
        return false;
    }
    /* Then the filename itself: alnum, '_', '-' and '.' only. */
    for (const char *p = last_slash + 1; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (!isalnum(c) && c != '_' && c != '-' && c != '.') {
            return false;
        }
    }
    return strstr(rel, "..") == NULL;
}

/* Shared path buffer for the listing walk — the export task's stack is 6 KB,
 * so this stays static rather than one buffer per recursion level. */
static char s_list_path[256];

/* snprintf() returns the length it WOULD have written, which is larger than the
 * buffer when the text was truncated — handing that straight to
 * uart_write_bytes() would read off the end. Every framed line below goes
 * through here so a long filename can never turn into an over-read. */
static void uart_emit(const char *buf, int n, size_t cap)
{
    if (n < 0) {
        return;
    }
    if ((size_t)n >= cap) {
        n = (int)cap - 1;   /* truncated: send exactly what landed in the buffer */
    }
    uart_write_bytes(EXPORT_UART, buf, n);
}

/* True if `full_path` is one of the TWO mirror files this boot currently has
 * open (s_sd_log_path / s_sd_arrivals_path). Case-insensitive: FAT is.
 *
 * This is what tells "a run happening RIGHT NOW, mid-experiment" apart from "a
 * run that genuinely died". Both look identical in runs.csv — neither has a
 * "clean" row, because csv_logger_close() only writes one at TERMINATE. Without
 * this check, listing the card of a board that is simply still running labels
 * every file "ABORTED (started, never closed cleanly)" — the wrong claim:
 * nothing went wrong, the experiment just has not finished yet. */
static bool sd_is_live_mirror(const char *full_path)
{
    /* Gate on the FILE*, not just the path. csv_logger_close() nulls the
     * handles at TERMINATE but deliberately keeps the path strings (ARCHIVE_SD
     * and the close-time logging still need them), so a path-only test stayed
     * true for the rest of the boot: a run that finished perfectly cleanly kept
     * reporting STILL RUNNING, and the importer kept refusing it, until someone
     * power-cycled the board. An OPEN handle is what 'being written' means. */
    return (s_sd_log_fp != NULL && s_sd_log_path[0] != '\0'
                && strcasecmp(full_path, s_sd_log_path) == 0) ||
           (s_sd_arrivals_fp != NULL && s_sd_arrivals_path[0] != '\0'
                && strcasecmp(full_path, s_sd_arrivals_path) == 0);
}

/* DELETE_SD_FILE=<rel> — remove ONE capture CSV, rather than the whole folder
 * DELETE_SD_PATH takes. Exists because clearing a single aborted or unwanted
 * run off a card used to mean deleting every capture in that leaf beside it.
 *
 * Stricter than sd_rel_file_valid() (which EXPORT_SD_PATH uses, and which must
 * stay able to read runs.csv): deleting additionally requires the name to end
 * in _telem.csv or _arrivals.csv. That is what puts runs.csv — the manifest
 * recording every boot — plus location.txt, node_config.txt and the
 * status_*.txt reports out of this command's reach. Losing runs.csv would
 * leave every remaining capture on the card undatable and unattributable. */
static bool sd_rel_capture_file_valid(const char *rel)
{
    if (!sd_rel_file_valid(rel)) {
        return false;
    }
    size_t len = strlen(rel);
    return (len > 10 && strcasecmp(rel + len - 10, "_telem.csv") == 0) ||
           (len > 13 && strcasecmp(rel + len - 13, "_arrivals.csv") == 0);
}

static sd_delete_result_t sd_delete_rel_file(const char *rel)
{
    if (!sd_rel_capture_file_valid(rel)) {
        return SD_DEL_BAD_PATH;
    }
    int n = snprintf(s_del_path, sizeof(s_del_path), "%s/%s", SD_MOUNT_POINT, rel);
    if (n < 0 || n >= (int)sizeof(s_del_path)) {
        return SD_DEL_BAD_PATH;
    }

    /* The one guard that matters most: never unlink a file this boot still has
     * OPEN. The export task takes commands from boot (CSV_EXPORT_ON_INIT), so
     * this can arrive mid-run, and deleting the mirror out from under a live
     * FILE* loses the run in progress. Same reasoning as SD_DEL_IN_USE in
     * sd_delete_rel_path(), narrowed from "folder" to "this exact file". */
    if (sd_is_live_mirror(s_del_path)) {
        return SD_DEL_IN_USE;
    }

    bool took_mount = false;
    if (!sd_status_ensure_mounted("DELETE_SD_FILE", &took_mount)) {
        return SD_DEL_NO_CARD;
    }

    sd_delete_result_t result;
    struct stat st;
    if (stat(s_del_path, &st) != 0) {
        result = SD_DEL_NOT_FOUND;
    } else if (S_ISDIR(st.st_mode)) {
        result = SD_DEL_BAD_PATH;          /* a folder is DELETE_SD_PATH's job */
    } else if (remove(s_del_path) == 0) {
        result = SD_DEL_OK;
    } else {
        ESP_LOGW(TAG, "DELETE_SD_FILE: could not remove %s (errno %d)", s_del_path, errno);
        result = SD_DEL_FAILED;
    }

    if (took_mount) {
        sd_status_unmount();
    }
    return result;
}

/* Streams one leaf folder: its runs.csv manifest verbatim, then every CSV
 * capture file in it with its size. `leaf_rel` is the card-relative folder. */
static void sd_list_leaf(const char *leaf_rel)
{
    char out[320];
    DIR *dir = opendir(s_list_path);
    if (!dir) {
        return;
    }
    size_t base_len = strlen(s_list_path);

    /* Does this leaf hold anything at all? Only announce it if so — the
     * firmware creates the whole 63-folder tree on every boot, and listing 60
     * empty folders would bury the handful that matter. */
    bool announced = false;
    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        const char *name = ent->d_name;
        if (name[0] == '.') {
            continue;
        }
        size_t name_len = strlen(name);
        if (base_len + 1 + name_len >= sizeof(s_list_path)) {
            continue;
        }
        s_list_path[base_len] = '/';
        memcpy(s_list_path + base_len + 1, name, name_len + 1);

        struct stat st;
        bool is_file = (stat(s_list_path, &st) == 0 && !S_ISDIR(st.st_mode));
        s_list_path[base_len] = '\0';
        if (!is_file) {
            continue;   /* _archive/ and friends are not walked — same rule as the importer */
        }

        if (!announced) {
            uart_emit(out, snprintf(out, sizeof(out), "SDLEAF:%s\n", leaf_rel), sizeof(out));
            announced = true;
        }

        if (strcasecmp(name, "runs.csv") == 0) {
            /* Stream the manifest verbatim, one SDMAN: line per CSV line
             * (header included) — the host re-parses it with exactly the code
             * it uses on a mounted card. */
            s_list_path[base_len] = '/';
            memcpy(s_list_path + base_len + 1, name, name_len + 1);
            FILE *mf = fopen(s_list_path, "r");
            s_list_path[base_len] = '\0';
            if (mf) {
                char line[192];
                while (fgets(line, sizeof(line), mf)) {
                    line[strcspn(line, "\r\n")] = '\0';
                    if (line[0] == '\0') {
                        continue;
                    }
                    uart_emit(out, snprintf(out, sizeof(out), "SDMAN:%s\n", line), sizeof(out));
                }
                fclose(mf);
            }
            continue;
        }

        /* Third field: 1 = this boot still has the file OPEN (a run in
         * progress), 0 = closed, or left behind by an earlier boot. The host
         * uses it to say "STILL RUNNING" instead of falsely crying "ABORTED". */
        s_list_path[base_len] = '/';
        memcpy(s_list_path + base_len + 1, name, name_len + 1);
        int live = sd_is_live_mirror(s_list_path) ? 1 : 0;
        s_list_path[base_len] = '\0';
        uart_emit(out, snprintf(out, sizeof(out), "SDFILE:%s|%ld|%d\n",
                                name, (long)st.st_size, live), sizeof(out));
    }
    closedir(dir);
}

/* Walks <attack>/<topology>/<location> exactly as tools\import_sdcard.py's
 * _scan() walks a mounted card, so both paths see the same set of files. */
static void sd_list_card(void)
{
    static const char *const attack_dirs[] = { "baseline", "blackhole", "wormhole" };
    static const char *const topo_dirs[]   = { "star", "tree", "linear", "partial_mesh" };
    /* Must stay in step with LOCATIONS in tools\export_logs.py and
     * SD_LOCATION_* in mesh_config.h — the card's folder names are these. */
    static const char *const loc_dirs[]    = { "home", "G402", "DLSU_Library", "Goks" };

    char leaf_rel[128];
    for (size_t a = 0; a < sizeof(attack_dirs) / sizeof(attack_dirs[0]); a++) {
        for (size_t t = 0; t < sizeof(topo_dirs) / sizeof(topo_dirs[0]); t++) {
            for (size_t l = 0; l < sizeof(loc_dirs) / sizeof(loc_dirs[0]); l++) {
                int rn = snprintf(leaf_rel, sizeof(leaf_rel), "%s/%s/%s",
                                  attack_dirs[a], topo_dirs[t], loc_dirs[l]);
                if (rn < 0 || rn >= (int)sizeof(leaf_rel)) {
                    continue;
                }
                int pn = snprintf(s_list_path, sizeof(s_list_path), "%s/%s",
                                  SD_MOUNT_POINT, leaf_rel);
                if (pn < 0 || pn >= (int)sizeof(s_list_path)) {
                    continue;
                }
                struct stat st;
                if (stat(s_list_path, &st) != 0 || !S_ISDIR(st.st_mode)) {
                    continue;
                }
                sd_list_leaf(leaf_rel);
                /* Feed the watchdog between leaves — 48 of them with a manifest
                 * read each is long enough to matter. */
                uart_wait_tx_done(EXPORT_UART, pdMS_TO_TICKS(100));
                vTaskDelay(1);
            }
        }
    }
}

/* Appends one line to <run_dir>/runs.csv — the manifest that answers "which
 * boot was which experiment repeat", since the firmware has no other way to
 * record that (see file header). Writes the header first if the file is new
 * or empty. Opened, written, flushed and closed in one call rather than kept
 * open for the run's lifetime: two small writes per boot (start, then clean)
 * is cheap, and it means a crash between them can never corrupt a manifest
 * that was left open. Best-effort — a failure here never affects SPIFFS
 * logging or the telemetry mirror. */
static void sd_manifest_append(const char *node_id, const char *role_str,
                               int run_number, uint32_t rows, const char *event)
{
    const char *run_dir = sd_status_run_dir();
    if (!run_dir) {
        return;
    }

    char path[192];
    snprintf(path, sizeof(path), "%s/runs.csv", run_dir);

    struct stat st;
    bool need_header = (stat(path, &st) != 0) || (st.st_size == 0);

    FILE *f = fopen(path, "a");
    if (!f) {
        ESP_LOGW(TAG, "SD manifest unavailable (%s): fopen failed.", path);
        return;
    }
    if (need_header) {
        fputs("boot,run,node_id,role,rows,uptime_s,event,built,started,clock_src\n", f);
    }
    int64_t uptime_s = (esp_timer_get_time() - s_boot_start_us) / 1000000;

    /* "started" is the WALL CLOCK this run began. It exists because "built"
     * was the only date on a card and kept being read as one - it is not, and
     * no amount of labelling fixed that while it was the only thing on offer.
     *
     * Captured once, on the "start" row, and reused verbatim by the "clean"
     * row so both lines of one run agree; re-reading the clock for the second
     * line would record the time the run ENDED under a column named "started".
     *
     * It is only as good as sd_status.c's clock: a real time on a board that
     * has met a laptop (clock_src=host), an extrapolation from the build stamp
     * otherwise (clock_src=build). That is exactly why the source travels with
     * it in its own column instead of being inferred downstream - a reader must
     * never have to guess which of the two it is holding. */
    static char s_run_started[24] = {0};
    if (strcmp(event, "start") == 0 || s_run_started[0] == '\0') {
        sd_status_now_stamp(s_run_started, sizeof(s_run_started));
    }
    /* "built" is sd_status_build_stamp() — the date+time THIS FIRMWARE was
     * compiled, recorded per boot because it is the only calendar reference an
     * RTC-less board has (see sd_status.h for why a build stamp and not a clock).
     * It is what lets someone reading a pulled card tell which FLASH a capture
     * came from - a different question from when it ran, which "started" above
     * now answers properly.
     *
     * These three are APPENDED, never inserted: a card whose runs.csv was
     * started by older firmware keeps its original 7- or 8-column header
     * forever (a header is only written when the file is new), so newer boots
     * add fields with no name to land under and import_sdcard.py reads them
     * back positionally (_manifest_when() handles all three generations).
     * Appending also never disturbs the fields the firmware itself parses back
     * — sd_manifest_count_prior_runs() reads only the first two.
     * No quoting needed: the stamps are "YYYY-MM-DD HH:MM:SS" and the source is
     * one of host/build/none, so none of them can contain a comma. */
    fprintf(f, "%d,%d,%s,%s,%u,%lld,%s,%s,%s,%s\n",
            sd_status_boot_count(), run_number, node_id, role_str,
            (unsigned)rows, (long long)uptime_s, event,
            sd_status_build_stamp(), s_run_started, sd_status_clock_source_str());
    fflush(f);
    fclose(f);
}

/* How many DISTINCT boots already have a manifest entry for node_id — i.e. how
 * many real, data-logging runs this node has already done in this folder. This
 * boot's own run number is that count + 1, which is why it must be called
 * BEFORE this boot appends its own "start" line.
 *
 * The manifest is the counter. There is deliberately no separate run-count
 * file: runs.csv already records exactly one entry per real run, so deriving
 * the number from it cannot drift out of sync with the thing it describes,
 * and there is no second file to keep consistent on power loss.
 *
 * Parsed by hand with sscanf rather than a CSV reader — the same approach
 * sd_status.c already uses to read back its "Boot count:" line. Only the first
 * two fields are needed, so "%d,%31[^,]," is enough regardless of how many
 * columns follow.
 *
 * Counts DISTINCT boots, not lines, because a completed run writes two lines
 * ("start" then "clean"). Aborted runs still count: they have a "start" line,
 * they really happened, and they consume a number exactly as b<boot> does.
 *
 * Returns 0 on a missing/unreadable file, which is the safe direction — a run
 * number can only come out too LOW on a disturbed card, and the boot number in
 * the filename still guarantees no two files collide. */
static int sd_manifest_count_prior_runs(const char *node_id)
{
    const char *run_dir = sd_status_run_dir();
    if (!run_dir) {
        return 0;
    }

    char path[192];
    snprintf(path, sizeof(path), "%s/runs.csv", run_dir);

    FILE *f = fopen(path, "r");
    if (!f) {
        return 0;   /* no manifest yet — this is run 1 */
    }

    /* Bounded: a card that somehow exceeds this many runs in one folder stops
     * counting rather than growing the stack. The run number would then repeat,
     * but b<boot> still keeps the filenames unique. */
    int  seen[64];
    int  seen_count = 0;
    char line[160];

    if (fgets(line, sizeof(line), f) == NULL) {   /* header (or empty file) */
        fclose(f);
        return 0;
    }

    while (fgets(line, sizeof(line), f) != NULL) {
        int  boot;
        char node[32];
        if (sscanf(line, "%d,%*d,%31[^,],", &boot, node) != 2) {
            /* Also accept the pre-run-column layout (boot,node_id,...) so a
             * card written by the previous firmware still counts correctly
             * instead of silently restarting at r1. */
            if (sscanf(line, "%d,%31[^,],", &boot, node) != 2) {
                continue;   /* malformed — e.g. a line torn by power loss */
            }
        }
        if (strcmp(node, node_id) != 0) {
            continue;       /* another board's rows on a shared card */
        }
        bool already = false;
        for (int i = 0; i < seen_count; i++) {
            if (seen[i] == boot) {
                already = true;
                break;
            }
        }
        if (!already && seen_count < (int)(sizeof(seen) / sizeof(seen[0]))) {
            seen[seen_count++] = boot;
        }
    }
    fclose(f);
    return seen_count;
}

/* Opens *fp on first call (lazily — see the s_sd_log_fp/s_sd_arrivals_fp
 * docstring above), writes the header, and fflush()es immediately so the file
 * on the card always has at least a header the instant it exists. A no-op
 * once *fp is already open or *failed has latched true (mirroring
 * sd_mirror_drop()'s "don't retry every row against a card that has gone
 * away").
 *
 * write_manifest_start is true only for the telemetry mirror: every role logs
 * telemetry, but only the root also logs arrivals, and opening THAT mirror a
 * few rows later than telemetry's would append a second, slightly later
 * "start" line for the same boot — confusing rather than informative. One
 * mirror opening (telemetry) is enough to mark "this boot began logging". */
static void sd_mirror_ensure(FILE **fp, const char *path, const char *header,
                             bool *failed, const char *node_id, const char *role_str,
                             int run_number, bool write_manifest_start)
{
    if (*fp || *failed || path[0] == '\0') {
        return;
    }

    FILE *f = fopen(path, "w");
    if (!f) {
        ESP_LOGW(TAG, "SD mirror unavailable (%s): fopen failed — SPIFFS logging continues.", path);
        *failed = true;
        return;
    }
    if (fputs(header, f) < 0) {
        ESP_LOGW(TAG, "SD mirror unavailable (%s): header write failed.", path);
        fclose(f);
        *failed = true;
        return;
    }
    fflush(f);
    ESP_LOGI(TAG, "SD mirror: %s", path);
    *fp = f;
    if (write_manifest_start) {
        sd_manifest_append(node_id, role_str, run_number, 0, "start");
    }
}

/* Drop the mirror after a failed write rather than retrying every row — a card
 * that has gone away will not come back mid-run, and the log spam would itself
 * disturb the capture. */
static void sd_mirror_drop(FILE **fp, const char *what)
{
    if (*fp) {
        ESP_LOGW(TAG, "SD %s write failed — mirror disabled for the rest of this run.", what);
        fclose(*fp);
        *fp = NULL;
    }
}

/* Push one mirror file all the way down to the card, directory entry included.
 *
 * fflush() only empties the stdio buffer into FatFs; fsync() is what reaches
 * f_sync() through ESP-IDF's FAT VFS and rewrites the directory entry with the
 * file's real size. Without it a card pulled mid-run reads back as 0 bytes /
 * 0 rows on the laptop even though the data was written — see
 * LOGGER_SD_SYNC_INTERVAL_MS in mesh_config.h for the full story.
 *
 * Best-effort by design: a failed sync is logged and ignored, never allowed to
 * disturb SPIFFS logging, exactly like every other mirror operation. */
static void sd_mirror_sync(FILE *fp, const char *what)
{
    if (!fp) {
        return;
    }
    fflush(fp);
    if (fsync(fileno(fp)) != 0) {
        ESP_LOGW(TAG, "SD %s fsync failed (errno %d) — rows may not survive a reset.",
                 what, errno);
    }
}

/* Rate-limited sync of both mirrors, called from the row-append hot path.
 * Time-based so it keeps the same meaning whatever the sampling rate is. */
static void sd_mirror_sync_due(void)
{
    if (!s_sd_log_fp && !s_sd_arrivals_fp) {
        return;
    }
    int64_t now = esp_timer_get_time();
    if (s_sd_last_sync_us != 0 &&
        (now - s_sd_last_sync_us) < (int64_t)LOGGER_SD_SYNC_INTERVAL_MS * 1000) {
        return;
    }
    s_sd_last_sync_us = now;
    sd_mirror_sync(s_sd_log_fp, "telemetry");
    sd_mirror_sync(s_sd_arrivals_fp, "arrivals");
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Initialisation
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_init(const char *node_id, const char *run_id,
                           csv_logger_role_t role)
{
    esp_err_t ret;

    /* ── 1. Mount SPIFFS (once) ──────────────────────────────────────────── */
    if (!s_mounted) {
        esp_vfs_spiffs_conf_t spiffs_cfg = {
            .base_path              = FS_MOUNT_POINT,
            .partition_label        = FS_PARTITION_LABEL,
            .max_files              = 5,
            .format_if_mount_failed = true,
        };
        ret = esp_vfs_spiffs_register(&spiffs_cfg);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "SPIFFS mount failed: %s", esp_err_to_name(ret));
            return ret;
        }
        s_mounted = true;

        size_t total = 0, used = 0;
        esp_spiffs_info(FS_PARTITION_LABEL, &total, &used);
        ESP_LOGI(TAG, "SPIFFS mounted. Total: %u KB  Used: %u KB",
                 (unsigned)(total / 1024), (unsigned)(used / 1024));
    }

   /* ── 2. Open telemetry file ──────────────────────────────────────────── */
    snprintf(s_filepath, sizeof(s_filepath),
             "%s/telem.csv", FS_MOUNT_POINT);
    ESP_LOGI(TAG, "Telemetry file: %s", s_filepath);

    /* Use "a+" mode - creates if doesn't exist, appends if it does */
    s_log_fp = fopen(s_filepath, "a+");
    if (!s_log_fp) {
        ESP_LOGE(TAG, "Failed to open telemetry file: %s", s_filepath);
        return ESP_FAIL;
    }

    /* Check if file is empty or missing header */
    fseek(s_log_fp, 0, SEEK_SET);
    char header_check[64] = {0};
    fgets(header_check, sizeof(header_check), s_log_fp);
    if (strncmp(header_check, "timestamp_us", 12) != 0) {
        /* File is empty or has wrong header - write the header */
        fseek(s_log_fp, 0, SEEK_SET);
        fputs(TELEMETRY_HEADER, s_log_fp);
    }
    fseek(s_log_fp, 0, SEEK_END);

    /* ── 3. Open arrivals file (root only) ───────────────────────────────── */
    /* ── 3. Open arrivals file (root only) ───────────────────────────────── */
    if (role == CSV_ROLE_ROOT) {
        snprintf(s_arrivals_path, sizeof(s_arrivals_path),
                 "%s/arrivals.csv", FS_MOUNT_POINT);
        ESP_LOGI(TAG, "Arrivals file:  %s", s_arrivals_path);

        s_arrivals_fp = fopen(s_arrivals_path, "a+");
        if (!s_arrivals_fp) {
            ESP_LOGE(TAG, "Failed to open arrivals file: %s", s_arrivals_path);
            fclose(s_log_fp);
            s_log_fp = NULL;
            return ESP_FAIL;
        }

        /* Check if file is empty or missing header */
        fseek(s_arrivals_fp, 0, SEEK_SET);
        char header_check[64] = {0};
        fgets(header_check, sizeof(header_check), s_arrivals_fp);
        if (strncmp(header_check, "timestamp_us", 12) != 0) {
            fseek(s_arrivals_fp, 0, SEEK_SET);
            fputs(PROBE_ARRIVAL_HEADER, s_arrivals_fp);
        }
        fseek(s_arrivals_fp, 0, SEEK_END);
    }

    /* ── 4. Name the SD mirror paths (best-effort; not opened yet) ───────── */
    /* sd_status_run_boot_check() runs before this in app_main and leaves the
     * card mounted on success, so the folder is already there. The mirror
     * files themselves are opened lazily by sd_mirror_ensure() on the first
     * row this boot actually logs — see that function's docstring for why. */
    s_boot_start_us = esp_timer_get_time();
    strlcpy(s_node_id, node_id, sizeof(s_node_id));
    s_role_str = (role == CSV_ROLE_ROOT) ? "root" : "victim";

    sd_sweep_empty_mirrors();
    sd_archive_prior_run_mirrors();

    /* Counted BEFORE this boot writes its own manifest lines, so the count of
     * prior runs + 1 is this run's number. */
    s_run_number = sd_manifest_count_prior_runs(node_id) + 1;

    sd_csv_path(s_sd_log_path, sizeof(s_sd_log_path), "telem", s_role_str, node_id, s_run_number);
    s_sd_log_failed = false;
    if (role == CSV_ROLE_ROOT) {
        sd_csv_path(s_sd_arrivals_path, sizeof(s_sd_arrivals_path), "arrivals",
                    s_role_str, node_id, s_run_number);
        s_sd_arrivals_failed = false;
    }
    if (s_sd_log_path[0] == '\0') {
        ESP_LOGW(TAG, "No SD mirror this run — this board's data can only be "
                      "recovered over USB.");
    }

    s_row_count = 0;
    s_arrivals_row_count = 0;
    s_total_rows = 0;
    ESP_LOGI(TAG, "Logger ready. Role: %s", s_role_str);

#if CSV_EXPORT_ON_INIT
    esp_err_t rc = csv_logger_start_export_task();
    if (rc == ESP_OK) {
        ESP_LOGI(TAG, "CSV export task started on init (debug).");
    } else {
        ESP_LOGW(TAG, "CSV export task failed to start: %s", esp_err_to_name(rc));
    }
#endif

    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Append rows
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_append_telemetry(
    int64_t     timestamp_us,
    const char *node_id,
    const char *role_str,
    int         layer,
    uint8_t     parent_mac[6],
    int         rssi_dbm,
    uint32_t    retry_count,
    uint32_t    tx_count,
    uint32_t    probes_count,
    uint8_t     phase_id,
    uint8_t     gt_label,
    uint32_t    recv_count,
    uint32_t    forward_count,
    uint32_t    drop_count)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;

    char parent_str[18];
    snprintf(parent_str, sizeof(parent_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             parent_mac[0], parent_mac[1], parent_mac[2],
             parent_mac[3], parent_mac[4], parent_mac[5]);

    /* Format once, write the same bytes to SPIFFS and to the SD mirror, so the
     * two copies are identical row for row and either can be used as the run. */
    char row[LOGGER_BUF_SIZE];
    int n = snprintf(row, sizeof(row),
        "%lld,%s,%s,%d,%s,%d,%lu,%lu,%lu,%u,%u,%lu,%lu,%lu\n",
        (long long)timestamp_us,
        node_id,
        role_str,
        layer,
        parent_str,
        rssi_dbm,
        (unsigned long)retry_count,
        (unsigned long)tx_count,
        (unsigned long)probes_count,
        (unsigned)phase_id,
        (unsigned)gt_label,
        (unsigned long)recv_count,
        (unsigned long)forward_count,
        (unsigned long)drop_count
    );

    if (n < 0 || n >= (int)sizeof(row)) {
        ESP_LOGE(TAG, "telemetry row did not fit LOGGER_BUF_SIZE");
        return ESP_FAIL;
    }

    if (fputs(row, s_log_fp) < 0) {
        ESP_LOGE(TAG, "fputs (telemetry) failed");
        return ESP_FAIL;
    }

    sd_mirror_ensure(&s_sd_log_fp, s_sd_log_path, TELEMETRY_HEADER,
                     &s_sd_log_failed, s_node_id, s_role_str, s_run_number, true);
    if (s_sd_log_fp && fputs(row, s_sd_log_fp) < 0) {
        sd_mirror_drop(&s_sd_log_fp, "telemetry");
    }

    s_row_count++;
    s_total_rows++;
    if (s_row_count >= LOGGER_FLUSH_RECORDS) {
        fflush(s_log_fp);
        if (s_sd_log_fp) {
            fflush(s_sd_log_fp);
        }
        /* fflush() above does not update the card's directory entry, so on its
         * own it leaves a reset-interrupted run reading back as 0 rows. */
        sd_mirror_sync_due();
        s_row_count = 0;
    }

    return ESP_OK;
}

esp_err_t csv_logger_append_probe_arrival(
    int64_t     timestamp_us,
    const char *node_id,
    int         layer,
    uint8_t     parent_mac[6],
    int         rssi_dbm,
    uint32_t    retry_count,
    uint32_t    tx_count,
    uint32_t    probes_received,
    uint8_t     phase_id,
    uint8_t     gt_label,
    uint8_t     src_mac[6],
    uint32_t    seq_num,
    int64_t     latency_us)
{
    if (!s_arrivals_fp) {
        ESP_LOGE(TAG, "append_probe_arrival called but arrivals file not open "
                      "(was csv_logger_init called with CSV_ROLE_ROOT?)");
        return ESP_ERR_INVALID_STATE;
    }

    char parent_str[18], src_str[18];
    snprintf(parent_str, sizeof(parent_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             parent_mac[0], parent_mac[1], parent_mac[2],
             parent_mac[3], parent_mac[4], parent_mac[5]);
    snprintf(src_str, sizeof(src_str),
             "%02X:%02X:%02X:%02X:%02X:%02X",
             src_mac[0], src_mac[1], src_mac[2],
             src_mac[3], src_mac[4], src_mac[5]);

    /* Format once, write to both — see csv_logger_append_telemetry(). */
    char row[LOGGER_BUF_SIZE];
    int n = snprintf(row, sizeof(row),
        "%lld,%s,root,%d,%s,%d,%lu,%lu,%lu,%u,%u,%s,%lu,%lld\n",
        (long long)timestamp_us,
        node_id,
        layer,
        parent_str,
        rssi_dbm,
        (unsigned long)retry_count,
        (unsigned long)tx_count,
        (unsigned long)probes_received,
        (unsigned)phase_id,
        (unsigned)gt_label,
        src_str,
        (unsigned long)seq_num,
        (long long)latency_us
    );

    if (n < 0 || n >= (int)sizeof(row)) {
        ESP_LOGE(TAG, "probe-arrival row did not fit LOGGER_BUF_SIZE");
        return ESP_FAIL;
    }

    if (fputs(row, s_arrivals_fp) < 0) {
        ESP_LOGE(TAG, "fputs (probe arrival) failed");
        return ESP_FAIL;
    }

    sd_mirror_ensure(&s_sd_arrivals_fp, s_sd_arrivals_path, PROBE_ARRIVAL_HEADER,
                     &s_sd_arrivals_failed, s_node_id, s_role_str, s_run_number, false);
    if (s_sd_arrivals_fp && fputs(row, s_sd_arrivals_fp) < 0) {
        sd_mirror_drop(&s_sd_arrivals_fp, "arrivals");
    }

    s_arrivals_row_count++;
    if (s_arrivals_row_count >= LOGGER_FLUSH_RECORDS) {
        fflush(s_arrivals_fp);
        if (s_sd_arrivals_fp) {
            fflush(s_sd_arrivals_fp);
        }
        sd_mirror_sync_due();   /* see the telemetry path — fflush is not durable */
        s_arrivals_row_count = 0;
    }

    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API — Flush / close
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t csv_logger_flush(void)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;
    fflush(s_log_fp);
    if (s_arrivals_fp) fflush(s_arrivals_fp);
    /* An explicit flush is a phase boundary (the node mains call it when a run
     * phase ends), not a hot-path tick — so the mirrors are synced
     * UNCONDITIONALLY here, bypassing the LOGGER_SD_SYNC_INTERVAL_MS rate limit.
     * These are exactly the checkpoints worth paying a card write for. */
    sd_mirror_sync(s_sd_log_fp, "telemetry");
    sd_mirror_sync(s_sd_arrivals_fp, "arrivals");
    s_sd_last_sync_us = esp_timer_get_time();
    s_row_count = 0;
    s_arrivals_row_count = 0;
    return ESP_OK;
}

esp_err_t csv_logger_close(void)
{
    if (!s_log_fp) return ESP_ERR_INVALID_STATE;

    fflush(s_log_fp);
    fclose(s_log_fp);
    s_log_fp = NULL;
    ESP_LOGI(TAG, "Telemetry file closed: %s", s_filepath);

    if (s_arrivals_fp) {
        fflush(s_arrivals_fp);
        fclose(s_arrivals_fp);
        s_arrivals_fp = NULL;
        ESP_LOGI(TAG, "Arrivals file closed: %s", s_arrivals_path);
    }

    /* Close the mirror and release the card. Past this point the card is safe to
     * pull — which is the whole point of the mirror, since this runs at the end
     * of the experiment, right before the "you can ctrl + ]" banner.
     *
     * The "clean" manifest line is written only when the telemetry mirror is
     * still open right here: that means sd_mirror_ensure() wrote a matching
     * "start" line earlier AND nothing dropped it mid-run (sd_mirror_drop() on
     * a write failure already NULLs it). A boot with no mirror ever opened (no
     * card, or zero rows logged) gets neither line, which is correct — there is
     * nothing to report either way. A boot that DID drop mid-run is left with a
     * "start" and no "clean", the same shape as a hard power-loss abort, which
     * is an honest description: the card stopped receiving that boot's data. */
    if (s_sd_log_fp) {
        fflush(s_sd_log_fp);
        fclose(s_sd_log_fp);
        s_sd_log_fp = NULL;
        /* The run's data is complete either way, so it still gets "clean";
         * the extra row keeps a watchdog ending visible on the card instead of
         * passing it off as a normal TERMINATE. The importer ignores events it
         * does not know. */
        if (phase_listener_terminate_timed_out()) {
            sd_manifest_append(s_node_id, s_role_str, s_run_number, s_total_rows,
                               "term_timeout");
        }
        sd_manifest_append(s_node_id, s_role_str, s_run_number, s_total_rows, "clean");
    }
    if (s_sd_arrivals_fp) {
        fflush(s_sd_arrivals_fp);
        fclose(s_sd_arrivals_fp);
        s_sd_arrivals_fp = NULL;
    }
    /* fclose() above reaches f_close(), which writes the directory entry — so
     * a cleanly closed mirror never needs the fsync path. Reset the rate-limit
     * clock so a re-init in the same boot syncs immediately again. */
    s_sd_last_sync_us = 0;
    if (sd_status_run_dir()) {
        /* Cache the path BEFORE unmounting — sd_status_unmount() clears
         * sd_status.c's own copy along with the mount, but ARCHIVE_SD (see
         * csv_logger_archive_sd_now()) needs to find this folder again after
         * the serial export task's later commands have already run past this
         * point. */
        strlcpy(s_last_sd_run_dir, sd_status_run_dir(), sizeof(s_last_sd_run_dir));
        sd_status_unmount();
        ESP_LOGI(TAG, "SD card unmounted — safe to remove.");
    }

    return ESP_OK;
}

const char *csv_logger_get_filepath(void)
{
    return s_filepath;
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Serial export task
 * ═══════════════════════════════════════════════════════════════════════════ */

static bool s_export_task_started = false;

bool csv_logger_export_in_progress(void)
{
    return s_export_in_progress;
}

esp_err_t csv_logger_start_export_task(void)
{
    if (s_export_task_started) {
        /* Already running (e.g. started at csv_logger_init() via
         * CSV_EXPORT_ON_INIT, then requested again at experiment end) —
         * starting a second copy would race both tasks over the same UART0
         * byte stream and corrupt every incoming command. */
        return ESP_OK;
    }

    BaseType_t rc = xTaskCreate(
        serial_export_task,
        "csv_export",
        STACK_SERIAL_EXPORT,
        NULL,
        TASK_PRIO_SERIAL_EXPORT,
        NULL
    );
    if (rc != pdPASS) {
        ESP_LOGE(TAG, "Failed to create serial export task");
        return ESP_FAIL;
    }
    s_export_task_started = true;
    return ESP_OK;
}

/* ── Serial export task ──────────────────────────────────────────────────── */

static void serial_export_task(void *arg)
{
    /*
     * Install the UART0 driver before reading. The ESP-IDF console uses UART0
     * for log output but does NOT install the interrupt-driven driver, so
     * uart_read_bytes() fails on every call and the driver floods the console
     * with "uart driver error" until this is done. Installing an RX buffer
     * makes both reads (host commands) and writes (CSV stream) work.
     */
    if (!uart_is_driver_installed(EXPORT_UART)) {
        esp_err_t derr = uart_driver_install(
            EXPORT_UART, EXPORT_BUF_SIZE * 2, 0, 0, NULL, 0);
        if (derr != ESP_OK) {
            ESP_LOGE(TAG, "uart_driver_install failed: %s — export disabled",
                     esp_err_to_name(derr));
            vTaskDelete(NULL);
            return;
        }
    }

    ESP_LOGI(TAG, "Serial export task ready. Commands: "
                  "EXPORT_LOGS | EXPORT_ARRIVALS | DELETE_LOGS | ARCHIVE_SD | LIST_FILES | LIST_SD | "
                  "EXPORT_SD_PATH=<rel> | DELETE_SD_FILE=<rel> | SET_LOCATION=<value> | GET_LOCATION | "
                  "SET_ATTACKER_MAC=<aa:bb:cc:dd:ee:ff> | GET_ATTACKER_MAC | CLEAR_ATTACKER_MAC | "
                  "DELETE_SD_PATH=<attack>/<topology>/<location> | SET_TIME=<unix_epoch> | GET_TIME");

    /* End-of-run call-to-action. This task only starts AFTER the experiment
     * completes (app_main -> csv_logger_start_export_task), so the banner appears
     * only on a finished run — never on an early Ctrl+]. Raw printf (no
     * "I (...) TAG:" prefix) so it reads as a clean banner; prints for every role
     * since they all start this one export task. Ctrl+] leaves idf.py monitor,
     * which run.ps1 -Export turns into an auto-export of this board's CSVs. */
    printf("\n===========You can ctrl + ] to export the data=========\n\n");
    fflush(stdout);

    /* Sized for the LONGEST command, now DELETE_SD_FILE=<attack>/<topology>/
     * <location>/<scenario>/<file>.csv. A capture filename alone is ~43 chars
     * (victim_NODE_<12 hex>_r<n>_b<n>_arrivals.csv), so the old 96 left almost
     * no margin and a long site name would have truncated it. A truncated line
     * is rejected below, never dispatched. */
    char cmd_buf[192] = {0};
    int  cmd_idx      = 0;
    bool cmd_overflow = false;

    while (true) {
        uint8_t ch = 0;
        /* Use non-blocking read with shorter timeout */
        int len = uart_read_bytes(EXPORT_UART, &ch, 1, pdMS_TO_TICKS(50));
        if (len <= 0) {
            /* Wait a bit before trying again to avoid flooding */
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        if (ch == '\n' || ch == '\r') {
            cmd_buf[cmd_idx] = '\0';

            /* A truncated line is never dispatched: cut at a '/', a
             * DELETE_SD_PATH would name the PARENT folder. */
            if (cmd_overflow) {
                uart_write_bytes(EXPORT_UART, "ERROR:COMMAND_TOO_LONG\n", 23);

            /* ── EXPORT_LOGS — stream telemetry CSV ───────────────────── */
            } else if (strcmp(cmd_buf, "EXPORT_LOGS") == 0) {
                /* Mute ALL logging for the duration of the transfer. This is the
                 * moment the host starts capturing the framed CSV, so from here
                 * on any esp_log_* output (this node's own ESP_LOGW, or the
                 * ESP-IDF mesh stack's chatter) must NOT interleave with the
                 * stream — a log fragment splicing into the "END_OF_FILE\n"
                 * marker is what made attacker exports fail with "never saw
                 * END_OF_FILE" even though the whole file arrived (see
                 * esp32-issues-Part3.md I-001). Silencing HERE — not at task
                 * start — keeps the full experiment visible on the console even
                 * when CSV_EXPORT_ON_INIT starts this task at boot; only the
                 * actual export goes quiet. The raw READY/CSV/END_OF_FILE writes
                 * below use uart_write_bytes directly and are unaffected. */
                esp_log_level_set("*", ESP_LOG_NONE);
                s_export_in_progress = true;   /* silences the CC dashboard too */
                ESP_LOGI(TAG, "EXPORT_LOGS — streaming %s", s_filepath);
                FILE *fp = fopen(s_filepath, "r");
                if (!fp) {
                    uart_write_bytes(EXPORT_UART, "ERROR:FILE_NOT_FOUND\n", 21);
                } else {
                    /* Announce the file's byte size on the READY marker so the
                     * host can render a % progress bar (READY_TO_SEND:<bytes>).
                     * Old hosts that expect a bare "READY_TO_SEND" still match
                     * on the prefix. */
                    fseek(fp, 0, SEEK_END);
                    long fsize = ftell(fp);
                    fseek(fp, 0, SEEK_SET);
                    char ready[40];
                    int rlen = snprintf(ready, sizeof(ready),
                                        "READY_TO_SEND:%ld\n", fsize);
                    uart_write_bytes(EXPORT_UART, ready, rlen);
                    char line[256];
                    uint32_t streamed = 0;
                    while (fgets(line, sizeof(line), fp)) {
                        uart_write_bytes(EXPORT_UART, line, strlen(line));
                        /* Yield every few dozen lines so the idle task runs and
                         * the task watchdog is fed. A large telem.csv streamed in
                         * one tight loop (with logging muted) can otherwise starve
                         * idle and trip a watchdog reset partway through — the
                         * stream then goes silent with no END_OF_FILE and the host
                         * times out at a deterministic ~50%. */
                        if ((++streamed & 0x3F) == 0) {
                            uart_wait_tx_done(EXPORT_UART, pdMS_TO_TICKS(100));
                            vTaskDelay(1);
                        }
                    }
                    fclose(fp);
                    uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                    ESP_LOGI(TAG, "Telemetry file streamed.");
                }

            /* ── EXPORT_ARRIVALS — stream arrivals CSV (root only) ────── */
            } else if (strcmp(cmd_buf, "EXPORT_ARRIVALS") == 0) {
                /* Mute logging for the transfer — see the EXPORT_LOGS branch. */
                esp_log_level_set("*", ESP_LOG_NONE);
                s_export_in_progress = true;   /* silences the CC dashboard too */
                ESP_LOGI(TAG, "EXPORT_ARRIVALS — streaming %s", s_arrivals_path);
                if (s_arrivals_path[0] == '\0') {
                    uart_write_bytes(EXPORT_UART, "ERROR:NOT_ROOT_NODE\n", 20);
                } else {
                    FILE *fp = fopen(s_arrivals_path, "r");
                    if (!fp) {
                        uart_write_bytes(EXPORT_UART, "ERROR:FILE_NOT_FOUND\n", 21);
                    } else {
                        /* Announce byte size for the host progress bar (see
                         * the EXPORT_LOGS block above). */
                        fseek(fp, 0, SEEK_END);
                        long fsize = ftell(fp);
                        fseek(fp, 0, SEEK_SET);
                        char ready[40];
                        int rlen = snprintf(ready, sizeof(ready),
                                            "READY_TO_SEND:%ld\n", fsize);
                        uart_write_bytes(EXPORT_UART, ready, rlen);
                        char line[256];
                        uint32_t streamed = 0;
                        while (fgets(line, sizeof(line), fp)) {
                            uart_write_bytes(EXPORT_UART, line, strlen(line));
                            /* Yield periodically to feed the watchdog — see the
                             * EXPORT_LOGS streaming loop above. */
                            if ((++streamed & 0x3F) == 0) {
                                uart_wait_tx_done(EXPORT_UART, pdMS_TO_TICKS(100));
                                vTaskDelay(1);
                            }
                        }
                        fclose(fp);
                        uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                        ESP_LOGI(TAG, "Arrivals file streamed.");
                    }
                }

            /* ── DELETE_LOGS — FULL WIPE: format the whole SPIFFS partition ──
             * A plain remove() only unlinks the files; SPIFFS does not reclaim
             * their space promptly, so across many wipe/run cycles the flash
             * creeps toward full and every write slows to a crawl (seconds per
             * fflush — that starved the attacker's telemetry to <1 Hz and
             * corrupted its own CSV; see esp32-issues I-016/I-017). Formatting
             * resets "Used" to ~0 on every -Wipe, so the flash stays healthy and
             * a manual `idf.py erase-flash` is never needed.
             *
             * Close any open log handles first — formatting with files open is
             * undefined. Between runs these are already NULL (csv_logger_close()
             * ran at experiment end), so this is normally a no-op; it just makes
             * a mid-run wipe safe too. We do NOT reopen: -Wipe always precedes a
             * reflash/reboot, and csv_logger_init() recreates the files with
             * fresh headers on the next boot. */
            } else if (strcmp(cmd_buf, "DELETE_LOGS") == 0) {
                if (s_log_fp)      { fclose(s_log_fp);      s_log_fp = NULL; }
                if (s_arrivals_fp) { fclose(s_arrivals_fp); s_arrivals_fp = NULL; }
                esp_err_t ferr = esp_spiffs_format(FS_PARTITION_LABEL);
                if (ferr == ESP_OK) {
                    uart_write_bytes(EXPORT_UART, "LOGS_DELETED\n", 13);
                    ESP_LOGI(TAG, "SPIFFS formatted — full wipe, Used reset to ~0.");
                } else {
                    uart_write_bytes(EXPORT_UART, "ERROR:DELETE_FAILED\n", 20);
                    ESP_LOGE(TAG, "SPIFFS format failed: %s", esp_err_to_name(ferr));
                }

            /* ── ARCHIVE_SD — move this boot's own SD mirror CSVs into
             * run_dir/_archive/, on demand. Host sends this right after a
             * confirmed EXPORT_LOGS/EXPORT_ARRIVALS download (see
             * tools/export_logs.py --archive-sd), so a run's folder on the
             * card (e.g. blackhole/linear/home/) doesn't sit cluttered with
             * this run's CSVs until the NEXT boot's own archive sweep gets to
             * it. Archives, never deletes — same policy as
             * sd_archive_prior_run_mirrors(), just triggered earlier. ── */
            } else if (strcmp(cmd_buf, "ARCHIVE_SD") == 0) {
                switch (csv_logger_archive_sd_now()) {
                    case ESP_OK:
                        uart_write_bytes(EXPORT_UART, "SD_ARCHIVED\n", 12);
                        break;
                    case ESP_ERR_NOT_FOUND:
                        uart_write_bytes(EXPORT_UART, "ERROR:NO_SD_RUN\n", 17);
                        break;
                    default:
                        uart_write_bytes(EXPORT_UART, "ERROR:SD_ARCHIVE_FAILED\n", 25);
                        break;
                }

            /* ── SET_TIME=<unix_epoch> — hand the board a real clock.
             *
             * This board has no RTC and never reaches NTP, so left alone it
             * dates every file it writes from the firmware's BUILD timestamp —
             * which is identical on every boot of one flash and therefore says
             * nothing about when a capture actually ran. That is the bug this
             * command exists to close.
             *
             * The value is applied immediately AND persisted to the card
             * (SD_CLOCK_FILE), so the benefit is not confined to this session:
             * the NEXT boot starts its clock from that anchor instead of the
             * build stamp, which is what finally makes runs.csv's "started"
             * column, the status report, and Explorer's "Date modified" on
             * every folder and CSV tell the truth.
             *
             * Sent automatically by tools/export_logs.py on EVERY connection
             * (_push_host_time), so the anchor is refreshed by every export,
             * MAC read and SET_LOCATION pass rather than needing anyone to
             * remember it. Unknown commands are ignored by older firmware, so
             * the host can send it blindly. ── */
            } else if (strncmp(cmd_buf, "SET_TIME=", 9) == 0) {
                const char *value = cmd_buf + 9;
                char *end = NULL;
                errno = 0;
                long long epoch = strtoll(value, &end, 10);
                if (end == value || errno != 0) {
                    uart_write_bytes(EXPORT_UART, "ERROR:BAD_TIME\n", 15);
                } else if (!sd_status_set_host_time(epoch)) {
                    uart_write_bytes(EXPORT_UART, "ERROR:BAD_TIME\n", 15);
                } else {
                    char out[64];
                    char now[24];
                    sd_status_now_stamp(now, sizeof(now));
                    snprintf(out, sizeof(out), "TIME_SET:%s\n", now);
                    uart_write_bytes(EXPORT_UART, out, strlen(out));
                }

            /* ── GET_TIME — what the board thinks the time is, and whether that
             * is a real clock or an extrapolation from the build stamp. Reports
             * the SOURCE alongside the value because the two readings mean
             * different things and a host that cannot tell them apart would
             * file an estimate as a measurement. ── */
            } else if (strcmp(cmd_buf, "GET_TIME") == 0) {
                char out[64];
                char now[24];
                sd_status_now_stamp(now, sizeof(now));
                snprintf(out, sizeof(out), "TIME:%s:%s\n",
                         now, sd_status_clock_source_str());
                uart_write_bytes(EXPORT_UART, out, strlen(out));

            /* ── SET_LOCATION=<value> — write/overwrite location.txt on the
             * SD card over the SAME USB link already used to flash/export,
             * so a card missing location.txt (SD_STATUS_NO_LOCATION_FILE at
             * boot) can be fixed without ever removing it from the board —
             * see tools/export_logs.py --set-location. Takes effect on the
             * NEXT boot check, not this one (it already ran and failed). ── */
            } else if (strncmp(cmd_buf, "SET_LOCATION=", 13) == 0) {
                const char *value = cmd_buf + 13;
                /* One reply per failure mode. The old single
                 * ERROR:BAD_LOCATION_OR_WRITE_FAILED covered a rejected name
                 * AND an unwritable card, which are opposite problems: one is
                 * fixed by typing a different site, the other by reseating the
                 * card. Nobody could tell them apart from the host side. */
                switch (sd_status_write_location(value)) {
                    case SD_LOC_WRITE_OK:
                        uart_write_bytes(EXPORT_UART, "LOCATION_SET\n", 13);
                        break;
                    case SD_LOC_WRITE_BAD_VALUE:
                        uart_write_bytes(EXPORT_UART, "ERROR:BAD_LOCATION\n", 19);
                        break;
                    case SD_LOC_WRITE_NO_CARD:
                        uart_write_bytes(EXPORT_UART, "ERROR:LOCATION_NO_CARD\n", 23);
                        break;
                    case SD_LOC_WRITE_STALE_MOUNT:
                        uart_write_bytes(EXPORT_UART, "ERROR:LOCATION_STALE_MOUNT\n", 27);
                        break;
                    case SD_LOC_WRITE_IO_FAILED:
                    default:
                        uart_write_bytes(EXPORT_UART, "ERROR:LOCATION_WRITE_FAILED\n", 28);
                        break;
                }

            /* ── GET_LOCATION — report what location.txt says right now,
             * changing nothing. Without this the host has no way to see a
             * board's recorded site, so every fix was a blind overwrite:
             * run_wizard.ps1 could only warn that it was about to clobber a
             * value it could not show you. Reads the FILE rather than the boot
             * check's cached result, so a card the check rejected still
             * reports its actual contents. ── */
            } else if (strcmp(cmd_buf, "GET_LOCATION") == 0) {
                char loc[40] = {0};
                char out[80];
                switch (sd_status_peek_location(loc, sizeof(loc))) {
                    case SD_LOC_READ_OK:
                        snprintf(out, sizeof(out), "LOCATION:%s\n", loc);
                        break;
                    case SD_LOC_READ_MISSING:
                        snprintf(out, sizeof(out), "LOCATION:NONE\n");
                        break;
                    case SD_LOC_READ_INVALID:
                        snprintf(out, sizeof(out), "LOCATION:INVALID:%s\n", loc);
                        break;
                    case SD_LOC_READ_NO_CARD:
                    default:
                        snprintf(out, sizeof(out), "ERROR:LOCATION_NO_CARD\n");
                        break;
                }
                uart_write_bytes(EXPORT_UART, out, strlen(out));

            /* ── SET_ATTACKER_MAC=<aa:bb:cc:dd:ee:ff> / GET_ATTACKER_MAC /
             * CLEAR_ATTACKER_MAC — F2. Retarget a blackhole VICTIM over the
             * same USB link already used to flash and export, instead of
             * recompiling it.
             *
             * Before this, the attacker's MAC existed only as a #define baked
             * into every victim binary, so moving the attacker one hop meant
             * re-flashing the whole fleet. That cost is why r1-r3 differ only
             * in RF noise, and why the panel's "different position of the
             * attackers" (12:45-16:00) was never attempted. Reading the value
             * at boot instead makes attacker position a RUN PARAMETER.
             *
             * Applies on the NEXT boot: victim_main.c resolves the target once
             * before its probe loop starts, so a board cannot change target
             * mid-phase and split one run across two topologies. ── */
            } else if (strncmp(cmd_buf, "SET_ATTACKER_MAC=", 17) == 0) {
                uint8_t mac[6];
                if (!blackhole_target_parse(cmd_buf + 17, mac)) {
                    uart_write_bytes(EXPORT_UART, "ERROR:BAD_MAC\n", 14);
                } else if (blackhole_target_set(mac) == ESP_OK) {
                    uart_write_bytes(EXPORT_UART, "ATTACKER_MAC_SET\n", 17);
                } else {
                    uart_write_bytes(EXPORT_UART, "ERROR:MAC_WRITE_FAILED\n", 23);
                }

            } else if (strcmp(cmd_buf, "GET_ATTACKER_MAC") == 0) {
                uint8_t mac[6] = {0};
                bh_target_source_t src = blackhole_target_get(mac);
                char out[64];
                snprintf(out, sizeof(out),
                         "ATTACKER_MAC:%02x:%02x:%02x:%02x:%02x:%02x (%s)\n",
                         mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                         blackhole_target_source_str(src));
                uart_write_bytes(EXPORT_UART, out, strlen(out));

            } else if (strcmp(cmd_buf, "CLEAR_ATTACKER_MAC") == 0) {
                if (blackhole_target_clear() == ESP_OK) {
                    uart_write_bytes(EXPORT_UART, "ATTACKER_MAC_CLEARED\n", 21);
                } else {
                    uart_write_bytes(EXPORT_UART, "ERROR:MAC_CLEAR_FAILED\n", 23);
                }

            /* ── LIST_FILES — the two LIVE files this boot is writing ──
             * Now reports size and row count too (FILE:<path>|<bytes>|<rows>),
             * so the wizard's "export from the board" picker can show what it
             * is about to pull instead of two bare paths. Counting rows is
             * affordable here and only here: these are SPIFFS files on internal
             * flash and there are exactly two of them — see the LIST_SD comment
             * for why the CARD listing refuses to do the same thing. A host that
             * predates the extra fields still matches on the "FILE:" prefix. */
            } else if (strcmp(cmd_buf, "LIST_FILES") == 0) {
                char out[200];
                long bytes; long rows;
                spiffs_file_stats(s_filepath, &bytes, &rows);
                snprintf(out, sizeof(out), "FILE:%s|%ld|%ld\n", s_filepath, bytes, rows);
                uart_write_bytes(EXPORT_UART, out, strlen(out));
                if (s_arrivals_path[0] != '\0') {
                    spiffs_file_stats(s_arrivals_path, &bytes, &rows);
                    snprintf(out, sizeof(out), "FILE:%s|%ld|%ld\n",
                             s_arrivals_path, bytes, rows);
                    uart_write_bytes(EXPORT_UART, out, strlen(out));
                }
                uart_write_bytes(EXPORT_UART, "END_LIST\n", 9);

            /* ── LIST_SD — read-only listing of the whole card over USB ──
             * The "export from the board" counterpart to pulling the card and
             * running import_sdcard.py --list-json. See sd_list_card(). */
            } else if (strcmp(cmd_buf, "LIST_SD") == 0) {
                bool took_mount = false;
                if (!sd_status_ensure_mounted("LIST_SD", &took_mount)) {
                    uart_write_bytes(EXPORT_UART, "ERROR:SD_NO_CARD\n", 17);
                } else {
                    uart_write_bytes(EXPORT_UART, "SDLIST_BEGIN\n", 13);
                    sd_list_card();
                    uart_write_bytes(EXPORT_UART, "SDLIST_END\n", 11);
                    if (took_mount) {
                        sd_status_unmount();
                    }
                }

            /* ── EXPORT_SD_PATH=<rel> — stream one file off the CARD ────
             * Same READY_TO_SEND/END_OF_FILE framing as EXPORT_LOGS, so the
             * host reuses its existing capture path byte for byte. Read-only:
             * deleting a card path is still DELETE_SD_PATH's job alone. */
            } else if (strncmp(cmd_buf, "EXPORT_SD_PATH=", 15) == 0) {
                const char *rel = cmd_buf + 15;
                if (!sd_rel_file_valid(rel)) {
                    uart_write_bytes(EXPORT_UART, "ERROR:BAD_SD_PATH\n", 18);
                } else {
                    bool took_mount = false;
                    if (!sd_status_ensure_mounted("EXPORT_SD_PATH", &took_mount)) {
                        uart_write_bytes(EXPORT_UART, "ERROR:SD_NO_CARD\n", 17);
                    } else {
                        /* Mute logging for the transfer — see EXPORT_LOGS. */
                        esp_log_level_set("*", ESP_LOG_NONE);
                        s_export_in_progress = true;
                        snprintf(s_list_path, sizeof(s_list_path), "%s/%s",
                                 SD_MOUNT_POINT, rel);
                        FILE *fp = fopen(s_list_path, "r");
                        if (!fp) {
                            uart_write_bytes(EXPORT_UART, "ERROR:FILE_NOT_FOUND\n", 21);
                        } else {
                            fseek(fp, 0, SEEK_END);
                            long fsize = ftell(fp);
                            fseek(fp, 0, SEEK_SET);
                            char ready[40];
                            int rlen = snprintf(ready, sizeof(ready),
                                                "READY_TO_SEND:%ld\n", fsize);
                            uart_write_bytes(EXPORT_UART, ready, rlen);
                            char line[256];
                            uint32_t streamed = 0;
                            while (fgets(line, sizeof(line), fp)) {
                                uart_write_bytes(EXPORT_UART, line, strlen(line));
                                if ((++streamed & 0x3F) == 0) {
                                    uart_wait_tx_done(EXPORT_UART, pdMS_TO_TICKS(100));
                                    vTaskDelay(1);
                                }
                            }
                            fclose(fp);
                            uart_write_bytes(EXPORT_UART, "END_OF_FILE\n", 12);
                        }
                        if (took_mount) {
                            sd_status_unmount();
                        }
                    }
                }

            /* ── DELETE_SD_PATH=<rel> — PERMANENTLY delete a card folder,
             * e.g. blackhole/linear/G402. See sd_delete_rel_path(). ── */
            } else if (strncmp(cmd_buf, "DELETE_SD_PATH=", 15) == 0) {
                const char *rel = cmd_buf + 15;
                int removed = 0;
                char out[48];
                switch (sd_delete_rel_path(rel, &removed)) {
                    case SD_DEL_OK:
                        snprintf(out, sizeof(out), "SD_PATH_DELETED:%d\n", removed);
                        ESP_LOGI(TAG, "DELETE_SD_PATH: deleted %s (%d file(s)).", rel, removed);
                        break;
                    case SD_DEL_BAD_PATH:
                        snprintf(out, sizeof(out), "ERROR:BAD_SD_PATH\n");
                        break;
                    case SD_DEL_IN_USE:
                        snprintf(out, sizeof(out), "ERROR:SD_PATH_IN_USE\n");
                        break;
                    case SD_DEL_NO_CARD:
                        snprintf(out, sizeof(out), "ERROR:SD_NO_CARD\n");
                        break;
                    case SD_DEL_NOT_FOUND:
                        snprintf(out, sizeof(out), "ERROR:SD_PATH_NOT_FOUND\n");
                        break;
                    case SD_DEL_FAILED:
                    default:
                        snprintf(out, sizeof(out), "ERROR:SD_DELETE_FAILED:%d\n", removed);
                        break;
                }
                uart_write_bytes(EXPORT_UART, out, strlen(out));
            /* -- DELETE_SD_FILE=<rel> -- PERMANENTLY delete ONE capture CSV.
             * The per-file counterpart to DELETE_SD_PATH above, so an aborted
             * or unwanted run can be cleared without taking every other
             * capture in the same leaf folder with it. Refuses anything that
             * is not a *_telem.csv / *_arrivals.csv, which is what keeps
             * runs.csv and location.txt safe -- see sd_rel_file_valid(). */
            } else if (strncmp(cmd_buf, "DELETE_SD_FILE=", 15) == 0) {
                const char *rel = cmd_buf + 15;
                char out[48];
                switch (sd_delete_rel_file(rel)) {
                    case SD_DEL_OK:
                        snprintf(out, sizeof(out), "SD_FILE_DELETED\n");
                        ESP_LOGI(TAG, "DELETE_SD_FILE: deleted %s", rel);
                        break;
                    case SD_DEL_BAD_PATH:
                        snprintf(out, sizeof(out), "ERROR:BAD_SD_FILE\n");
                        break;
                    case SD_DEL_IN_USE:
                        snprintf(out, sizeof(out), "ERROR:SD_FILE_IN_USE\n");
                        break;
                    case SD_DEL_NO_CARD:
                        snprintf(out, sizeof(out), "ERROR:SD_NO_CARD\n");
                        break;
                    case SD_DEL_NOT_FOUND:
                        snprintf(out, sizeof(out), "ERROR:SD_FILE_NOT_FOUND\n");
                        break;
                    case SD_DEL_FAILED:
                    default:
                        snprintf(out, sizeof(out), "ERROR:SD_DELETE_FAILED\n");
                        break;
                }
                uart_write_bytes(EXPORT_UART, out, strlen(out));
            }

            cmd_idx = 0;
            cmd_overflow = false;
            memset(cmd_buf, 0, sizeof(cmd_buf));

        } else if (cmd_idx < (int)sizeof(cmd_buf) - 1) {
            cmd_buf[cmd_idx++] = (char)ch;
        } else {
            cmd_overflow = true;
        }
    }
}