/**
 * @file sd_status.c
 * @brief SD card boot check implementation. See sd_status.h.
 *
 * NIS16 — CTTHES3 — Common Module
 */

#include "sd_status.h"
#include "mesh_config.h"
#include "mesh_messages.h"   /* NODE_NICKNAME_LEN */

#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <stdlib.h>      /* sd_status_apply_clock_anchor(): strtoll */
#include <time.h>        /* sd_status_seed_clock(): mktime/struct tm/gmtime_r */
#include <sys/time.h>    /* settimeofday() - see the same function */
#include <sys/stat.h>

#include "esp_vfs_fat.h"
#include "sdmmc_cmd.h"
#include "driver/spi_common.h"
#include "esp_app_desc.h"    /* sd_status_build_stamp(): the image's own build date/time */
#include "esp_timer.h"   /* esp_timer_get_time(): uptime added to the build stamp */
#include "esp_chip_info.h"
#include "esp_idf_version.h"
#include "esp_mac.h"
#include "esp_system.h"   /* esp_reset_reason(): why THIS boot happened */
#include "esp_log.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "SD_STATUS";

/* Where the running clock came from. Tracked rather than recomputed so the
 * answer cannot drift from the settimeofday() call that actually made it
 * true, and so runs.csv can record HOW a timestamp was arrived at next to
 * the timestamp itself. See sd_clock_src_t in the header. */
static sd_clock_src_t s_clock_src = SD_CLOCK_SRC_NONE;

/* app_main's task stack is 3584B (CONFIG_ESP_MAIN_TASK_STACK_SIZE) — nothing
 * here is a local. s_report is 8192 because the folder walk grew from 20 lines
 * (topology x location) to 63 (attack x topology x location); rep() clamps, but
 * a report truncated mid-tree is exactly the wrong thing to hand someone during
 * hardware bring-up. */
static char   s_report[8192];
static size_t s_report_len;
static char   s_report_path[128] = {0};
static char   s_location[24]     = {0};
static bool   s_location_valid   = false;

/* Held across the run when the boot check succeeds: csv_logger.c mirrors each
 * telemetry row onto the card, so the mount must outlive this function. See
 * sd_status_run_dir() / sd_status_unmount(). NULL = not mounted. */
static sdmmc_card_t *s_card          = NULL;
static char          s_run_dir[96]   = {0};
static int           s_boot_count    = 0;

/* Command Center: cached /sdcard/node_config.txt values. Empty = not found. */
static char   s_cfg_nickname[NODE_NICKNAME_LEN] = {0};
static char   s_cfg_role[24]                    = {0};

/* 8.3-safe — never depends on CONFIG_FATFS_LFN_HEAP. */
#define SD_RW_TEST_PATH   SD_MOUNT_POINT "/sd_rw.tmp"
#define SD_RW_TEST_STRING "SD_CARD_INTEGRITY_CHECK_0123456789"

/* Index MUST match NIS_TOPO_STAR..NIS_TOPO_PARTIAL in mesh_config.h, and the
 * strings MUST stay byte-identical to _TOPOLOGY_DIR in tools/export_logs.py —
 * note PARTIAL's quirk ("partial_mesh", not "partial"), kept from the original
 * long names so it stays distinguishable from the --topology CLI value. */
static const char *const s_topo_dirs[4] = {
    "star", "tree", "linear", "partial_mesh",
};

static const char *const s_locations[4] = {
    SD_LOCATION_HOME, SD_LOCATION_G402, SD_LOCATION_DLSU_LIB, SD_LOCATION_GOKS,
};

/* Top level of the tree. MUST stay byte-identical to _subdir_for() in
 * tools/export_logs.py, which maps attack "none" to the "baseline" folder — the
 * export tree and the card tree are the same shape on purpose, so a card pulled
 * from a remote node copies straight into exports/<attack>/<topology>/<location>/.
 * Indexed by attack_index() below, NOT by ACTIVE_ATTACK (255 is not an index). */
static const char *const s_attack_dirs[3] = {
    "baseline", "blackhole", "wormhole",
};

typedef enum { LOC_OK, LOC_MISSING, LOC_BAD } loc_lookup_t;

/* ── Helpers ──────────────────────────────────────────────────────────────── */

/* ACTIVE_ATTACK is a value (255/1/2), not an index — map it to s_attack_dirs[].
 * Resolved HERE rather than by a caller for the same reason as MESH_TOPOLOGY:
 * the define is PRIVATE per component, and mesh_common only sees the real build
 * value because of the ACTIVE_ATTACK block in this component's CMakeLists.txt.
 * Read from root_main.c/victim_main.c it would be the main component's copy. */
static int attack_index(void)
{
    switch (ACTIVE_ATTACK) {
        case PHASE_ID_BLACKHOLE: return 1;
        case PHASE_ID_WORMHOLE:  return 2;
        default:                 return 0; /* ATTACK_NONE → baseline */
    }
}

/* Clamped append. NOTE: sd_card_test.c's `len += snprintf(buf+len, sizeof(buf)-len,...)`
 * idiom is unsafe here — snprintf returns the would-be length, so one truncated
 * call makes len > sizeof(buf) and the next call's `sizeof(buf)-len` wraps as a
 * huge size_t. This clamps s_report_len so it can never exceed sizeof(s_report)-1. */
static void rep(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

static void rep(const char *fmt, ...)
{
    if (s_report_len >= sizeof(s_report) - 1) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(s_report + s_report_len, sizeof(s_report) - s_report_len, fmt, ap);
    va_end(ap);
    if (n <= 0) {
        return;
    }
    size_t remaining = sizeof(s_report) - s_report_len - 1; /* space excluding NUL */
    size_t written = ((size_t)n < remaining) ? (size_t)n : remaining;
    s_report_len += written;
}

/* 1 = EXISTS, 0 = CREATED, -1 = FAIL (errno set). No mkdir -p in the FAT VFS,
 * so callers must create parents before children. EINVAL(22) here means
 * CONFIG_FATFS_LFN_HEAP is not enabled in this build's sdkconfig. */
static int ensure_dir(const char *path)
{
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 1 : -1;
    }
    if (mkdir(path, 0775) == 0) {
        return 0;
    }
    if (errno == EEXIST) {
        return 1;
    }
    return -1;
}

static int check_and_report_dir(const char *path, const char *label, const char *indent)
{
    errno = 0;
    int st = ensure_dir(path);
    if (st < 0) {
        rep("%s%-24s FAIL (errno=%d %s)\r\n", indent, label, errno, strerror(errno));
    } else {
        rep("%s%-24s %s\r\n", indent, label, (st > 0) ? "EXISTS" : "CREATED");
    }
    return st;
}

/* Reads /sdcard/location.txt, tolerating a trailing \r\n, surrounding spaces,
 * and a Notepad UTF-8 BOM. On LOC_OK, *idx_out is the matching s_locations[]
 * index; on LOC_BAD, raw_out carries the rejected string (quoted in the log). */
static loc_lookup_t read_location(char *canonical, size_t canonical_len,
                                   char *raw_out, size_t raw_len, int *idx_out)
{
    raw_out[0] = '\0';

    FILE *f = fopen(SD_LOCATION_FILE, "r");
    if (!f) {
        return LOC_MISSING;
    }
    char buf[64] = {0};
    char *got = fgets(buf, sizeof(buf), f);
    fclose(f);
    if (!got) {
        return LOC_MISSING;
    }

    char *p = buf;
    if ((unsigned char)p[0] == 0xEFU && (unsigned char)p[1] == 0xBBU && (unsigned char)p[2] == 0xBFU) {
        p += 3; /* strip UTF-8 BOM */
    }
    size_t len = strlen(p);
    while (len > 0 && (unsigned char)p[len - 1] <= (unsigned char)' ') {
        p[--len] = '\0'; /* trailing \r \n \t space */
    }
    while (*p == ' ' || *p == '\t') {
        p++; /* leading space/tab */
    }

    strlcpy(raw_out, p, raw_len);
    if (p[0] == '\0') {
        return LOC_BAD;
    }

    for (int i = 0; i < 4; i++) {
        if (strcasecmp(p, s_locations[i]) == 0) {
            strlcpy(canonical, s_locations[i], canonical_len);
            *idx_out = i;
            return LOC_OK;
        }
    }
    return LOC_BAD;
}

/* Multi-key reader for node_config.txt. read_location() above is a single-line,
 * fixed-vocabulary matcher and does not generalise, so this walks every line
 * looking for "key=value" — but keeps the same BOM/CRLF/whitespace tolerance,
 * since both files are hand-edited on Windows. A missing file, missing key, or
 * malformed line each leave the cache empty. Never fatal. */
static void read_node_config(void)
{
    s_cfg_nickname[0] = '\0';
    s_cfg_role[0]     = '\0';

    FILE *f = fopen(SD_NODE_CONFIG_FILE, "r");
    if (!f) {
        return;
    }

    char line[96];
    bool first = true;
    while (fgets(line, sizeof(line), f)) {
        char *p = line;

        if (first) {
            first = false;
            if ((unsigned char)p[0] == 0xEFU && (unsigned char)p[1] == 0xBBU &&
                (unsigned char)p[2] == 0xBFU) {
                p += 3; /* strip UTF-8 BOM */
            }
        }

        size_t len = strlen(p);
        while (len > 0 && (unsigned char)p[len - 1] <= (unsigned char)' ') {
            p[--len] = '\0'; /* trailing \r \n \t space */
        }
        while (*p == ' ' || *p == '\t') {
            p++; /* leading space/tab */
        }
        if (*p == '\0' || *p == '#') {
            continue; /* blank or comment */
        }

        char *eq = strchr(p, '=');
        if (!eq) {
            continue;
        }
        *eq = '\0';
        char *key = p;
        char *val = eq + 1;

        size_t klen = strlen(key);
        while (klen > 0 && (unsigned char)key[klen - 1] <= (unsigned char)' ') {
            key[--klen] = '\0'; /* space before '=' */
        }
        while (*val == ' ' || *val == '\t') {
            val++; /* space after '=' */
        }
        if (*val == '\0') {
            continue;
        }

        if (strcasecmp(key, "nickname") == 0) {
            strlcpy(s_cfg_nickname, val, sizeof(s_cfg_nickname));
        } else if (strcasecmp(key, "role") == 0) {
            strlcpy(s_cfg_role, val, sizeof(s_cfg_role));
        }
    }
    fclose(f);
}

/* ── Public API ───────────────────────────────────────────────────────────── */

const char *sd_status_get_config_nickname(void)
{
    return (s_cfg_nickname[0] != '\0') ? s_cfg_nickname : NULL;
}

const char *sd_status_get_config_role(void)
{
    return (s_cfg_role[0] != '\0') ? s_cfg_role : NULL;
}

const char *sd_status_result_str(sd_status_result_t result)
{
    switch (result) {
        case SD_STATUS_OK:                return "OK";
        case SD_STATUS_NO_CARD:           return "NO CARD (mount failed)";
        case SD_STATUS_NO_LOCATION_FILE:  return "NO LOCATION FILE (/sdcard/location.txt missing)";
        case SD_STATUS_BAD_LOCATION:      return "BAD LOCATION (unrecognised value in location.txt)";
        case SD_STATUS_TREE_FAILED:       return "FOLDER TREE FAILED (check CONFIG_FATFS_LFN_HEAP)";
        case SD_STATUS_WRITE_FAILED:      return "REPORT WRITE FAILED";
        default:                          return "UNKNOWN";
    }
}

const char *sd_status_topology_dirname(void)
{
    /* MESH_TOPOLOGY is PRIVATE to mesh_common (CMakeLists.txt) and this file is
     * part of that component, so it sees the real build value — unlike a caller
     * in root_main.c/victim_main.c, which would always see the #ifndef fallback. */
    return s_topo_dirs[MESH_TOPOLOGY];
}

const char *sd_status_attack_dirname(void)
{
    return s_attack_dirs[attack_index()];
}

const char *sd_status_location(void)
{
    return s_location_valid ? s_location : NULL;
}

const char *sd_status_run_dir(void)
{
    return (s_card && s_run_dir[0] != '\0') ? s_run_dir : NULL;
}

int sd_status_boot_count(void)
{
    return s_boot_count;
}

/* Why this boot happened, as one fixed word (no commas - it goes straight into
 * runs.csv). esp_reset_reason() is kept in RTC memory, so it survives the very
 * reset it describes.
 *
 * Exists so a card can say WHY a board rebooted (power cut vs brownout vs
 * crash) instead of leaving it to be guessed from file endings. A brownout at
 * radio start-up dies AFTER this boot check but BEFORE csv_logger_init(), so it
 * leaves no CSV - only a climbing boot count. Now every boot names its cause,
 * and the running BROWNOUT / CRASH totals below survive any number of loops. */
static const char *s_reset_reason = "UNKNOWN";
static bool        s_reset_is_brownout = false;
static bool        s_reset_is_crash = false;

static void read_reset_reason(void)
{
    esp_reset_reason_t r = esp_reset_reason();
    s_reset_is_brownout = (r == ESP_RST_BROWNOUT);
    s_reset_is_crash = (r == ESP_RST_PANIC || r == ESP_RST_INT_WDT ||
                        r == ESP_RST_TASK_WDT || r == ESP_RST_WDT);
    switch (r) {
        case ESP_RST_POWERON:   s_reset_reason = "POWERON";   break; /* plug-in, EN button, esptool/flash reset */
        case ESP_RST_EXT:       s_reset_reason = "EXT_PIN";   break;
        case ESP_RST_SW:        s_reset_reason = "SOFTWARE";  break; /* esp_restart() */
        case ESP_RST_PANIC:     s_reset_reason = "PANIC";     break; /* crash / abort() / failed ESP_ERROR_CHECK */
        case ESP_RST_INT_WDT:   s_reset_reason = "INT_WDT";   break;
        case ESP_RST_TASK_WDT:  s_reset_reason = "TASK_WDT";  break;
        case ESP_RST_WDT:       s_reset_reason = "WDT";       break;
        case ESP_RST_DEEPSLEEP: s_reset_reason = "DEEPSLEEP"; break;
        case ESP_RST_BROWNOUT:  s_reset_reason = "BROWNOUT";  break; /* supply sagged: weak powerbank/charger/cable */
        case ESP_RST_SDIO:      s_reset_reason = "SDIO";      break;
        default:                s_reset_reason = "OTHER";     break;
    }
    if (s_reset_is_brownout) {
        ESP_LOGE(TAG, "RESET REASON: BROWNOUT -- the supply sagged. Use a stronger powerbank/charger or a "
                      "shorter cable; a board stuck in a brownout loop never reaches logging.");
    } else if (s_reset_is_crash) {
        ESP_LOGE(TAG, "RESET REASON: %s -- the previous boot CRASHED; its capture was cut short "
                      "and this boot starts a new file.", s_reset_reason);
    } else {
        ESP_LOGI(TAG, "Reset reason: %s", s_reset_reason);
    }
}

const char *sd_status_reset_reason_str(void)
{
    return s_reset_reason;
}

const char *sd_status_build_stamp(void)
{
    /* Built once and cached: the app descriptor is a const blob in flash, so
     * this can never change while the image runs. Sized well past the 19 chars
     * "YYYY-MM-DD HH:MM:SS" needs — this component builds -Wall -Wextra -Werror,
     * and a tight buffer makes -Wformat-truncation reason about the widest int
     * %04d could print rather than the validated range below. */
    static char stamp[32] = {0};
    if (stamp[0] != '\0') {
        return stamp;
    }

    /* esp_app_desc_t.date/.time are the compiler's __DATE__/__TIME__ as the
     * build system stamped them at LINK time — "Sep 17 2026" / "14:32:07".
     * Taken from there rather than using __DATE__/__TIME__ here directly: a
     * macro in this file only updates when THIS file is recompiled, so an
     * incremental build that skips it would quietly report a stale date, which
     * is worse than no date at all for the one job this field has. */
    const esp_app_desc_t *desc = esp_app_get_description();
    char mon[4] = {0};
    int  day = 0, year = 0;
    if (desc && sscanf(desc->date, "%3s %d %d", mon, &day, &year) == 3
            && day >= 1 && day <= 31 && year >= 1970 && year <= 9999) {
        /* __DATE__ spells the month, and day is space-padded ("Sep  7 2026").
         * Normalised to YYYY-MM-DD here so every reader downstream (runs.csv ->
         * import_sdcard.py -> the wizards' file picker) gets one sortable,
         * locale-free shape instead of re-parsing a month name each time.
         * The range checks above are also what keeps a garbled descriptor from
         * producing a plausible-looking "0000-13-99". */
        static const char months[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
        const char *hit = strstr(months, mon);
        if (hit && ((hit - months) % 3) == 0) {
            snprintf(stamp, sizeof(stamp), "%04d-%02d-%02d %.8s",
                     year, (int)((hit - months) / 3) + 1, day, desc->time);
            return stamp;
        }
    }

    strlcpy(stamp, "unknown", sizeof(stamp));
    return stamp;
}

/* Give the system clock a plausible wall-clock time, derived from the
 * firmware BUILD timestamp plus how long this boot has been up.
 *
 * WHY: this board has no RTC and never reaches an NTP server, so time(NULL)
 * starts at the 1970 epoch. ESP-IDF's get_fattime() (components/fatfs/
 * diskio/diskio.c) feeds time(NULL) straight into every FAT directory entry
 * and clamps anything before 1980 — which is why EVERY file this board has
 * ever written shows "01/01/1980" in Windows Explorer, and why a card full
 * of captures cannot be sorted or dated by hand at all.
 *
 * Seeding the clock here fixes that for free: FatFs keeps calling the same
 * get_fattime(), it just finally gets a sane answer, so telem/arrivals CSVs,
 * runs.csv and location.txt all land with a real date.
 *
 * ACCURACY, stated honestly: this is BUILD time + uptime, not true wall
 * clock. A board flashed and run straight away is accurate to within the
 * flash+boot gap; a board reflashed days later and left powered will drift
 * by however long it sat. It is a dating aid, NOT a measurement — anything
 * that must be exact still uses the boot counter and runs.csv, which are
 * monotonic and do not depend on a clock at all. */
void sd_status_seed_clock(void)
{
    /* Timezone FIRST: mktime() below reads the build stamp as local time, and
     * every stamp after this (sd_status_now_stamp, FatFs get_fattime) renders
     * through it. See SD_CLOCK_TZ in mesh_config.h. */
    setenv("TZ", SD_CLOCK_TZ, 1);
    tzset();

    const char *stamp = sd_status_build_stamp();   /* "YYYY-MM-DD HH:MM:SS" */
    struct tm tmv = {0};
    if (sscanf(stamp, "%d-%d-%d %d:%d:%d",
               &tmv.tm_year, &tmv.tm_mon, &tmv.tm_mday,
               &tmv.tm_hour, &tmv.tm_min, &tmv.tm_sec) != 6) {
        ESP_LOGW(TAG, "clock seed: build stamp unparseable (\"%s\") - files will date to 1980.",
                 stamp);
        return;
    }
    tmv.tm_year -= 1900;
    tmv.tm_mon  -= 1;
    tmv.tm_isdst = -1;
    time_t built = mktime(&tmv);
    if (built == (time_t)-1) {
        ESP_LOGW(TAG, "clock seed: mktime failed - files will date to 1980.");
        return;
    }
    /* Add uptime so two files written minutes apart do not share a timestamp. */
    struct timeval tv = {
        .tv_sec  = built + (time_t)(esp_timer_get_time() / 1000000),
        .tv_usec = 0,
    };
    if (settimeofday(&tv, NULL) != 0) {
        ESP_LOGW(TAG, "clock seed: settimeofday failed (errno %d).", errno);
        return;
    }
    s_clock_src = SD_CLOCK_SRC_BUILD;
    ESP_LOGI(TAG, "clock seeded from build stamp %s (ESTIMATE) - refined from the card's "
                  "anchor next if it has one.", stamp);
}

/* The lower bound for a believable host epoch: 2025-01-01T00:00:00Z. Anything
 * below it is a host that never had a clock either, a truncated line, or a
 * stray digit - all of which would date captures to the 1970s and are better
 * refused than written to the card. The upper bound (year 2100) catches the
 * opposite slip: milliseconds passed where seconds were meant, which would
 * otherwise sail through and stamp every file ~50,000 years from now. */
#define SD_CLOCK_EPOCH_MIN  1735689600LL
#define SD_CLOCK_EPOCH_MAX  4102444800LL

/* Move the clock to `epoch` (+ this boot's uptime when `add_uptime`), but ONLY
 * forward.
 *
 * Forward-only is the whole safety property. Two things can set this clock (a
 * card anchor at boot, a SET_TIME over USB mid-session) and they can disagree:
 * a card that has been sitting in a drawer carries an older anchor than the
 * laptop that just pushed a fresh one. Letting the older value win would make a
 * capture appear to run BEFORE the run that preceded it, and FAT directory
 * entries would go backwards mid-session. So a candidate that is not newer than
 * what is already running is discarded, and the source tag is left alone. */
static bool clock_set_forward(time_t epoch, bool add_uptime, sd_clock_src_t src)
{
    time_t candidate = epoch;
    if (add_uptime) {
        candidate += (time_t)(esp_timer_get_time() / 1000000);
    }
    if (candidate <= time(NULL)) {
        return false;
    }
    struct timeval tv = { .tv_sec = candidate, .tv_usec = 0 };
    if (settimeofday(&tv, NULL) != 0) {
        ESP_LOGW(TAG, "clock: settimeofday failed (errno %d).", errno);
        return false;
    }
    s_clock_src = src;
    return true;
}

void sd_status_apply_clock_anchor(void)
{
    FILE *f = fopen(SD_CLOCK_FILE, "r");
    if (!f) {
        ESP_LOGI(TAG, "clock: no %s on this card - dates stay BUILD-TIME estimates. "
                      "Connect this board to a laptop once (any export / MAC read / "
                      "SET_LOCATION) to give it a real clock.", SD_CLOCK_FILE);
        return;
    }
    char line[64] = {0};
    char *got = fgets(line, sizeof(line), f);
    fclose(f);
    if (!got) {
        ESP_LOGW(TAG, "clock: %s is empty - keeping the build-stamp estimate.", SD_CLOCK_FILE);
        return;
    }

    errno = 0;
    char *end = NULL;
    long long epoch = strtoll(line, &end, 10);
    if (end == line || errno != 0
            || epoch < SD_CLOCK_EPOCH_MIN || epoch > SD_CLOCK_EPOCH_MAX) {
        ESP_LOGW(TAG, "clock: %s holds an implausible value - keeping the build-stamp "
                      "estimate.", SD_CLOCK_FILE);
        return;
    }

    if (!clock_set_forward((time_t)epoch, true, SD_CLOCK_SRC_HOST)) {
        /* Not an error: a board reflashed minutes ago already has a build stamp
         * NEWER than the card's last laptop contact, and that stamp is then the
         * better estimate of the two. Say which one won so the console is never
         * ambiguous about what dated the files. */
        ESP_LOGI(TAG, "clock: card anchor is older than the build stamp - keeping the "
                      "build stamp.");
        return;
    }

    char now[24];
    sd_status_now_stamp(now, sizeof(now));
    ESP_LOGI(TAG, "clock: set from the card's host anchor -> %s " SD_CLOCK_TZ_LABEL " (REAL time, plus "
                  "however long this board sat unpowered).", now);
}

bool sd_status_set_host_time(long long epoch)
{
    if (epoch < SD_CLOCK_EPOCH_MIN || epoch > SD_CLOCK_EPOCH_MAX) {
        ESP_LOGW(TAG, "SET_TIME: %lld is not a plausible epoch - ignored.", epoch);
        return false;
    }

    /* No uptime added: the host is telling us what time it is RIGHT NOW, not
     * what time this boot started. */
    if (!clock_set_forward((time_t)epoch, false, SD_CLOCK_SRC_HOST)) {
        /* The clock was already at or past this value. Still record the source
         * as HOST - the host really did vouch for it - and still persist below,
         * because the point of the file is the NEXT boot, not this one. */
        s_clock_src = SD_CLOCK_SRC_HOST;
    }

    /* Persist for the next boot. Best-effort and deliberately not fatal: a
     * read-only or absent card costs us the anchor, not the running clock.
     * Borrows an existing mount when the run is still live (same rule as the
     * location.txt helpers) so writing this can never end an SD mirror. */
    bool took_mount = false;
    if (sd_status_ensure_mounted("SET_TIME", &took_mount)) {
        errno = 0;
        FILE *wf = fopen(SD_CLOCK_FILE, "w");
        if (wf) {
            char now[24];
            sd_status_now_stamp(now, sizeof(now));
            /* Epoch alone on line 1 so the parser above never has to skip
             * anything; the human-readable line after it is for whoever opens
             * this file in Notepad wondering what the number means. */
            fprintf(wf, "%lld\n# %s " SD_CLOCK_TZ_LABEL " - written by SET_TIME over USB. Do not edit.\n",
                    epoch, now);
            fclose(wf);
            ESP_LOGI(TAG, "SET_TIME: clock = %s " SD_CLOCK_TZ_LABEL ", anchor saved to %s.", now, SD_CLOCK_FILE);
        } else {
            ESP_LOGW(TAG, "SET_TIME: clock set, but %s could not be written (errno %d) - "
                          "the next boot falls back to the build stamp.",
                     SD_CLOCK_FILE, errno);
        }
        if (took_mount) {
            sd_status_unmount();
        }
    } else {
        ESP_LOGW(TAG, "SET_TIME: clock set, but no card to save the anchor to - "
                      "the next boot falls back to the build stamp.");
    }
    return true;
}

sd_clock_src_t sd_status_clock_source(void)
{
    return s_clock_src;
}

const char *sd_status_clock_source_str(void)
{
    switch (s_clock_src) {
        case SD_CLOCK_SRC_HOST:  return "host";
        case SD_CLOCK_SRC_BUILD: return "build";
        case SD_CLOCK_SRC_NONE:
        default:                 return "none";
    }
}

bool sd_status_now_stamp(char *out, size_t len)
{
    if (!out || len == 0) {
        return false;
    }
    if (s_clock_src == SD_CLOCK_SRC_NONE) {
        strlcpy(out, "unknown", len);
        return false;
    }
    time_t now = time(NULL);
    struct tm tmv;
    /* localtime_r = Philippine time (SD_CLOCK_TZ, set in sd_status_seed_clock).
     * The epoch underneath is still true UTC, so two boards stay comparable;
     * only the printed wall clock is local, and it is labelled as such. */
    if (!localtime_r(&now, &tmv)) {
        strlcpy(out, "unknown", len);
        return false;
    }
    if (strftime(out, len, "%Y-%m-%d %H:%M:%S", &tmv) == 0) {
        strlcpy(out, "unknown", len);
        return false;
    }
    return true;
}

void sd_status_unmount(void)
{
    if (!s_card) {
        return;
    }
    esp_vfs_fat_sdcard_unmount(SD_MOUNT_POINT, s_card);
    spi_bus_free(SPI3_HOST);
    s_card = NULL;
    s_run_dir[0] = '\0';
}

const char *sd_status_report_path(void)
{
    return s_report_path;
}

/* Brings the card up for a one-off location.txt read/write requested over
 * serial, long after the boot check ran. If that check succeeded the card is
 * still mounted for csv_logger.c's row mirroring — borrow it and leave the
 * mount alone, since tearing it down here would silently end the SD mirror
 * mid-run. Otherwise mount fresh with the same config sd_status_run_boot_check()
 * uses, and set *took_mount so the caller unmounts again when it is done.
 * @param what  command name, for the log line on failure. */
static bool mount_for_location_op(const char *what, bool *took_mount)
{
    *took_mount = false;
    if (s_card != NULL) {
        return true;
    }

    spi_bus_config_t bus_cfg = {
        .mosi_io_num    = SD_PIN_MOSI,
        .miso_io_num    = SD_PIN_MISO,
        .sclk_io_num    = SD_PIN_SCK,
        .quadwp_io_num  = -1,
        .quadhd_io_num  = -1,
        .max_transfer_sz = 4000,
    };
    esp_err_t bus_ret = spi_bus_initialize(SPI3_HOST, &bus_cfg, SDSPI_DEFAULT_DMA);
    if (bus_ret != ESP_OK) {
        ESP_LOGE(TAG, "%s: SPI bus init failed (0x%x)", what, bus_ret);
        return false;
    }

    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = SPI3_HOST;
    host.max_freq_khz = SD_MAX_FREQ_KHZ;

    sdspi_device_config_t slot_cfg = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot_cfg.gpio_cs = SD_PIN_CS;
    slot_cfg.host_id = SPI3_HOST;

    esp_vfs_fat_sdmmc_mount_config_t mount_cfg = {
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024,
    };

    sdmmc_card_t *card = NULL;
    esp_err_t mount_ret = esp_vfs_fat_sdspi_mount(SD_MOUNT_POINT, &host, &slot_cfg, &mount_cfg, &card);
    if (mount_ret != ESP_OK) {
        ESP_LOGE(TAG, "%s: SD mount failed (0x%x) -- check wiring/power.", what, mount_ret);
        spi_bus_free(SPI3_HOST);
        return false;
    }

    s_card = card;  /* lets sd_status_unmount() tear this temp mount back down */
    *took_mount = true;
    return true;
}

bool sd_status_ensure_mounted(const char *what, bool *took_mount)
{
    return mount_for_location_op(what, took_mount);
}

sd_loc_read_t sd_status_peek_location(char *out, size_t out_len)
{
    if (!out || out_len == 0) {
        return SD_LOC_READ_NO_CARD;
    }
    out[0] = '\0';

    bool took_mount = false;
    if (!mount_for_location_op("GET_LOCATION", &took_mount)) {
        return SD_LOC_READ_NO_CARD;
    }

    char canonical[24] = {0};
    char raw[64]       = {0};
    int  idx           = 0;
    loc_lookup_t found = read_location(canonical, sizeof(canonical), raw, sizeof(raw), &idx);

    if (took_mount) {
        sd_status_unmount();
    }

    switch (found) {
        case LOC_OK:
            strlcpy(out, canonical, out_len);
            ESP_LOGI(TAG, "GET_LOCATION: location.txt holds \"%s\"", canonical);
            return SD_LOC_READ_OK;
        case LOC_BAD:
            /* Hand back the raw text, not just "bad" — seeing the actual
             * contents is the whole point of reading before overwriting. */
            strlcpy(out, raw, out_len);
            ESP_LOGW(TAG, "GET_LOCATION: location.txt holds unrecognised \"%s\"", raw);
            return SD_LOC_READ_INVALID;
        case LOC_MISSING:
        default:
            ESP_LOGW(TAG, "GET_LOCATION: %s is missing or empty", SD_LOCATION_FILE);
            return SD_LOC_READ_MISSING;
    }
}

sd_loc_write_t sd_status_write_location(const char *value)
{
    if (!value) {
        return SD_LOC_WRITE_BAD_VALUE;
    }

    /* Validate BEFORE mounting anything: a rejected name must leave whatever is
     * already on the card untouched, so a typo can never cost a location that
     * was correct. */
    char canonical[24] = {0};
    bool matched = false;
    for (int i = 0; i < 4; i++) {
        if (strcasecmp(value, s_locations[i]) == 0) {
            strlcpy(canonical, s_locations[i], sizeof(canonical));
            matched = true;
            break;
        }
    }
    if (!matched) {
        ESP_LOGE(TAG, "SET_LOCATION rejected: \"%s\" is not one of %s, %s, %s, %s"
                      " -- card NOT touched",
                 value, s_locations[0], s_locations[1], s_locations[2], s_locations[3]);
        return SD_LOC_WRITE_BAD_VALUE;
    }

    bool took_mount = false;
    if (!mount_for_location_op("SET_LOCATION", &took_mount)) {
        return SD_LOC_WRITE_NO_CARD;
    }

    errno = 0;
    FILE *f = fopen(SD_LOCATION_FILE, "w");
    bool ok = false;
    if (f) {
        ok = (fprintf(f, "%s\n", canonical) >= 0);
        fclose(f);
        if (!ok) {
            ESP_LOGE(TAG, "SET_LOCATION: write to %s failed", SD_LOCATION_FILE);
        }
    } else {
        ESP_LOGE(TAG, "SET_LOCATION: could not open %s: errno=%d (%s)",
                 SD_LOCATION_FILE, errno, strerror(errno));
    }


    /* HOT-SWAP RECOVERY. A failed write on a mount we did NOT take means we
     * borrowed the cached one from the boot check — and the overwhelmingly
     * common reason that mount suddenly refuses writes is that the card was
     * physically pulled and reinserted while this board kept running.
     * mount_for_location_op() returns early on `s_card != NULL` and cannot
     * notice, so every later SET_LOCATION fails until the board reboots.
     *
     * Only safe to rebuild when NO capture is in flight. sd_status_run_dir()
     * is non-NULL for the whole of a run, and csv_logger.c is holding mirror
     * FILE* handles against this very mount — unmounting under those would
     * end the SD mirror mid-experiment (see mount_for_location_op's comment).
     * So mid-run we do not touch it; we report STALE_MOUNT and let the
     * operator reboot, which is the only correct move anyway: a card pulled
     * mid-capture has already lost that run.
     *
     * Between runs — which is when the wizard's "write location.txt" option
     * is actually used — the retry below fixes the swap outright. */
    if (!ok && !took_mount && sd_status_run_dir() == NULL) {
        ESP_LOGW(TAG, "SET_LOCATION: cached mount refused the write - card was likely"
                      " removed and reinserted. Rebuilding the mount and retrying.");
        sd_status_unmount();            /* drop the stale handle + free SPI3 */
        bool retook = false;
        if (mount_for_location_op("SET_LOCATION(remount)", &retook)) {
            errno = 0;
            FILE *f2 = fopen(SD_LOCATION_FILE, "w");
            if (f2) {
                ok = (fprintf(f2, "%s\n", canonical) >= 0);
                fclose(f2);
            } else {
                ESP_LOGE(TAG, "SET_LOCATION: still cannot open %s after remount:"
                              " errno=%d (%s)", SD_LOCATION_FILE, errno, strerror(errno));
            }
            if (retook) {
                sd_status_unmount();
            }
            if (ok) {
                ESP_LOGI(TAG, "SET_LOCATION: recovered after remount.");
            }
        }
    }
    else if (!ok && !took_mount) {
        /* Capture in flight - refuse to rebuild the mount under it. */
        ESP_LOGE(TAG, "SET_LOCATION: cached mount refused the write while a capture is"
                      " running. Reboot this board; the card was pulled mid-run.");
        return SD_LOC_WRITE_STALE_MOUNT;
    }
    if (took_mount) {
        sd_status_unmount();  /* frees SPI3 + clears s_card from the temp mount above */
    }

    if (ok) {
        ESP_LOGI(TAG, "SET_LOCATION: location.txt set to \"%s\" -- takes effect on next boot.", canonical);
        return SD_LOC_WRITE_OK;
    }
    return SD_LOC_WRITE_IO_FAILED;
}

sd_status_result_t sd_status_run_boot_check(void)
{
    /* Before ANY file is created this boot: without it every SD directory
     * entry written below is stamped 1980 (see the function comment). This is
     * only the floor - sd_status_apply_clock_anchor() below replaces it with a
     * real host clock the moment the card is up, and it must stay BEFORE the
     * mount so a board with no card at all still reports a sane date. */
    sd_status_seed_clock();
    read_reset_reason();   /* before any early return: runs.csv wants it even if the card fails */

    s_report_len = 0;
    s_report[0] = '\0';
    s_report_path[0] = '\0';
    s_location[0] = '\0';
    s_location_valid = false;
    s_run_dir[0] = '\0';
    s_boot_count = 0;

    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA); /* eFuse read; works before mesh_setup_init() */
    char node_id[NODE_ID_LEN];
    snprintf(node_id, sizeof(node_id), "NODE_%02X%02X%02X%02X%02X%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    esp_chip_info_t chip;
    esp_chip_info(&chip);

    rep("=== SD CARD ENVIRONMENT REPORT (%s) ===\r\n\r\n", node_id);
    rep("[1] ESP32\r\n"
        "  Model: %s, rev v%d.%d, %d core(s)\r\n"
        "  Features: %s%s%s\r\n"
        "  IDF version: %s\r\n\r\n",
        (chip.model == CHIP_ESP32) ? "ESP32" : "other/unknown",
        chip.revision / 100, chip.revision % 100, chip.cores,
        (chip.features & CHIP_FEATURE_WIFI_BGN) ? "WiFi " : "",
        (chip.features & CHIP_FEATURE_BT) ? "BT " : "",
        (chip.features & CHIP_FEATURE_BLE) ? "BLE" : "",
        esp_get_idf_version());

    /* Mount config copied verbatim from sd_card_test/main/sd_card_test.c —
     * these values are hard-won on the lab's jumper-wire rig, do not tune. */
    spi_bus_config_t bus_cfg = {
        .mosi_io_num = SD_PIN_MOSI,
        .miso_io_num = SD_PIN_MISO,
        .sclk_io_num = SD_PIN_SCK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 4000,
    };
    esp_err_t bus_ret = spi_bus_initialize(SPI3_HOST, &bus_cfg, SDSPI_DEFAULT_DMA);

    sdmmc_host_t host = SDSPI_HOST_DEFAULT();
    host.slot = SPI3_HOST;
    host.max_freq_khz = SD_MAX_FREQ_KHZ;

    sdspi_device_config_t slot_cfg = SDSPI_DEVICE_CONFIG_DEFAULT();
    slot_cfg.gpio_cs = SD_PIN_CS;
    slot_cfg.host_id = SPI3_HOST;

    esp_vfs_fat_sdmmc_mount_config_t mount_cfg = {
        .format_if_mount_failed = false,
        .max_files = 5,
        .allocation_unit_size = 16 * 1024,
    };

    sdmmc_card_t *card = NULL;
    esp_err_t mount_ret = ESP_FAIL;
    if (bus_ret == ESP_OK) {
        mount_ret = esp_vfs_fat_sdspi_mount(SD_MOUNT_POINT, &host, &slot_cfg, &mount_cfg, &card);
    }
    s_card = (mount_ret == ESP_OK) ? card : NULL;

    if (bus_ret != ESP_OK || mount_ret != ESP_OK) {
        /* Never ESP_ERROR_CHECK here — that would abort() and kill an 11-minute run. */
        ESP_LOGE(TAG, "SD mount FAILED (bus=0x%x mount=0x%x)", bus_ret, mount_ret);
        ESP_LOGE(TAG, "Check: wiring (CS=%d/MOSI=%d/MISO=%d/SCK=%d), VCC on VIN/5V (not 3V3), card fully seated.",
                 SD_PIN_CS, SD_PIN_MOSI, SD_PIN_MISO, SD_PIN_SCK);
        if (bus_ret == ESP_OK) {
            spi_bus_free(SPI3_HOST);
        }
        return SD_STATUS_NO_CARD;
    }

    /* The card is up and NOTHING has been written to it yet. This is the only
     * correct moment to fix the clock: FatFs stamps every directory entry from
     * time(NULL) via get_fattime(), so the R/W test file, the 63-folder tree,
     * the status report and every CSV mirror below all inherit whatever the
     * clock says right here. One line earlier and the folders would carry the
     * build-time estimate; one line later and they would be wrong forever,
     * because a directory's creation date is written once. */
    sd_status_apply_clock_anchor();

    rep("[2] SD CARD\r\n"
        "  Name: %s\r\n"
        "  Type: %s\r\n"
        "  Speed: %lu kHz (limit %lu kHz)\r\n"
        "  Size: %llu MB\r\n\r\n",
        card->cid.name,
        (card->ocr & (1 << 30)) ? "SDHC/SDXC" : "SDSC",
        (unsigned long)card->real_freq_khz, (unsigned long)card->max_freq_khz,
        (unsigned long long)((uint64_t)card->csd.capacity) * card->csd.sector_size / (1024 * 1024));

    {
        char now[24];
        sd_status_now_stamp(now, sizeof(now));
        /* Spelled out rather than printed as a bare timestamp: a reader who
         * cannot tell a measured time from an extrapolated one will date a
         * capture wrongly, and this report is exactly what someone reads when
         * they pull an unfamiliar card. */
        rep("[2b] CLOCK\r\n"
            "  Boot time now: %s " SD_CLOCK_TZ_LABEL "\r\n"
            "  Source: %s\r\n\r\n",
            now,
            (sd_status_clock_source() == SD_CLOCK_SRC_HOST)
                ? "HOST anchor (" SD_CLOCK_FILE ") - a real clock, plus any time "
                  "this board sat unpowered"
                : "FIRMWARE BUILD TIME + uptime - AN ESTIMATE, not a capture time. "
                  "Connect this board to a laptop once to fix it.");
    }

    bool integrity_ok = false;
    {
        errno = 0;
        FILE *f = fopen(SD_RW_TEST_PATH, "w");
        if (f) {
            fprintf(f, "%s", SD_RW_TEST_STRING);
            fclose(f);
            f = fopen(SD_RW_TEST_PATH, "r");
            if (f) {
                char readback[64] = {0};
                if (fgets(readback, sizeof(readback), f)) {
                    integrity_ok = (strcmp(readback, SD_RW_TEST_STRING) == 0);
                }
                fclose(f);
            }
            remove(SD_RW_TEST_PATH);
        }
    }
    rep("[3] READ/WRITE INTEGRITY CHECK: %s\r\n\r\n", integrity_ok ? "MATCH" : "FAIL");

    /* Command Center identity, read HERE because on any non-OK result this
     * function unmounts the card and frees SPI3 before returning —
     * node_identity.c runs afterwards and could no longer reach the filesystem.
     * Optional file; absence is not an error. */
    read_node_config();
    rep("[3b] NODE CONFIG: nickname=%s\r\n\r\n",
        (s_cfg_nickname[0] != '\0') ? s_cfg_nickname : "(no node_config.txt)");

    /* No mkdir -p in the FAT VFS — parent before child: 3 attack dirs, each with
     * 4 topology children, each with 4 location children (63 folders). Mirrors
     * exports/<attack>/<topology>/<location>/ on the host exactly. Track every
     * result so the report/errno can call out the exact failing leaf, and so we
     * know below whether THIS board's own chosen folder actually exists. */
    rep("[4] ATTACK x TOPOLOGY x LOCATION FOLDER TREE\r\n");
    int attack_status[3] = {0};
    int topo_status[3][4] = {{0}};
    int leaf_status[3][4][4] = {{{0}}};
    for (int a = 0; a < 3; a++) {
        char attack_path[32];
        snprintf(attack_path, sizeof(attack_path), "%s/%s", SD_MOUNT_POINT, s_attack_dirs[a]);
        attack_status[a] = check_and_report_dir(attack_path, s_attack_dirs[a], "  ");
        for (int t = 0; t < 4; t++) {
            char topo_path[64];
            snprintf(topo_path, sizeof(topo_path), "%s/%s", attack_path, s_topo_dirs[t]);
            topo_status[a][t] = check_and_report_dir(topo_path, s_topo_dirs[t], "    ");
            for (int l = 0; l < 4; l++) {
                char leaf_path[96];
                snprintf(leaf_path, sizeof(leaf_path), "%s/%s", topo_path, s_locations[l]);
                leaf_status[a][t][l] = check_and_report_dir(leaf_path, s_locations[l], "      ");
            }
        }
    }
    rep("\r\n");

    char raw_loc[64];
    int loc_idx = -1;
    loc_lookup_t loc_result = read_location(s_location, sizeof(s_location), raw_loc, sizeof(raw_loc), &loc_idx);
    const char *topo_dir = s_topo_dirs[MESH_TOPOLOGY];
    const int   atk_idx  = attack_index();
    const char *atk_dir  = s_attack_dirs[atk_idx];

    sd_status_result_t result;

    if (loc_result != LOC_OK) {
        /* Environment must be RECORDED, never inferred (thesis panel P4) — no
         * default location, and the report goes to the card ROOT, never into
         * any topology folder, so nothing can be mistaken for a recorded site. */
        const char *reason = (loc_result == LOC_MISSING) ? "location.txt is missing"
                                                           : "location.txt holds an unrecognised value";
        rep("[5] ENVIRONMENT\r\n"
            "  Build attack: %s\r\n"
            "  Build topology: %s\r\n"
            "  Recorded location: NONE (%s)\r\n"
            "  Rejected raw value: \"%s\"\r\n"
            "  Accepted values: %s, %s, %s, %s\r\n\r\n",
            atk_dir, topo_dir, reason, raw_loc,
            s_locations[0], s_locations[1], s_locations[2], s_locations[3]);
        ESP_LOGE(TAG, "SD location: %s -- got \"%s\" -- expected one of: %s, %s, %s, %s",
                 reason, raw_loc, s_locations[0], s_locations[1], s_locations[2], s_locations[3]);

        errno = 0;
        FILE *wf = fopen(SD_LOCATION_ERR_FILE, "w");
        if (wf) {
            fprintf(wf, "%s", s_report);
            fclose(wf);
            strlcpy(s_report_path, SD_LOCATION_ERR_FILE, sizeof(s_report_path));
        } else {
            ESP_LOGE(TAG, "Could not write %s either: errno=%d (%s)", SD_LOCATION_ERR_FILE, errno, strerror(errno));
        }
        result = (loc_result == LOC_MISSING) ? SD_STATUS_NO_LOCATION_FILE : SD_STATUS_BAD_LOCATION;
    } else {
        s_location_valid = true;

        char node_mac_str[18];
        snprintf(node_mac_str, sizeof(node_mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        char started[24];
        sd_status_now_stamp(started, sizeof(started));
        /* "Firmware built" and "Run started" are two different questions and
         * used to have one answer between them. Both are printed, labelled,
         * with the clock's provenance attached to the one that claims to be a
         * capture time - see [2b] above. */
        rep("[5] ENVIRONMENT\r\n"
            "  Build attack: %s\r\n"
            "  Build topology: %s\r\n"
            "  Firmware built: %s\r\n"
            "  Run started: %s " SD_CLOCK_TZ_LABEL " (clock: %s)\r\n"
            "  Recorded location: %s\r\n"
            "  Node: %s (MAC %s)\r\n\r\n",
            atk_dir, topo_dir, sd_status_build_stamp(),
            started, sd_status_clock_source_str(),
            s_location, node_id, node_mac_str);

        /* The schedule that produced this data, written where a human pulling
         * the card can read it. PHASE_*_S live in mesh_config.h and are
         * -D-overridable at build time, while preprocess.py and
         * validate_integrity.py carry their own copies -- so a card and the
         * host tools can disagree about what "baseline" means. The host side
         * now detects that, but it cannot DERIVE the nominal: the jitter
         * profile extends phases by a random amount ON PURPOSE, so the measured
         * duration legitimately differs from the compiled one. Recording the
         * compiled value is the only way a card can state its own provenance.
         *
         * Free-form text on purpose -- nothing parses this file, so adding to
         * it cannot break a reader. */
        rep("[6] PHASE SCHEDULE (compiled into this firmware)\r\n"
            "  stabilise %us / baseline %us / attack %us / cooldown %us\r\n"
#if defined(TRAFFIC_PROFILE) && (TRAFFIC_PROFILE == TRAFFIC_PROFILE_JITTER)
            "  jitter ON (root): baseline +0..%us, attack +0..%us -- the MEASURED\r\n"
            "  durations will EXCEED the nominal above, by design.\r\n",
            (unsigned)PHASE_STABILISE_S, (unsigned)PHASE_BASELINE_S,
            (unsigned)PHASE_ATTACK_S, (unsigned)PHASE_COOLDOWN_S,
            (unsigned)JITTER_BASELINE_MAX_S, (unsigned)JITTER_ATTACK_MAX_S);
#else
            "  jitter OFF -- measured durations should match the nominal above.\r\n",
            (unsigned)PHASE_STABILISE_S, (unsigned)PHASE_BASELINE_S,
            (unsigned)PHASE_ATTACK_S, (unsigned)PHASE_COOLDOWN_S);
#endif
        /* RF width is part of the capture's conditions: HT40 and HT20 runs are
         * not strictly comparable (RSSI / background retries can shift), so
         * every report records which one this firmware enforces. Compiled
         * value - the report is written before Wi-Fi starts; the boot log's
         * "RF width (...)" line shows the live radio. */
        rep("  RF width: %s (channel %u)\r\n\r\n",
#if MESH_FORCE_HT20
            "20 MHz / HT20 (MESH_FORCE_HT20=1)",
#else
            "ESP32 default, 40 MHz / HT40 (MESH_FORCE_HT20=0)",
#endif
            (unsigned)MESH_CHANNEL);

        bool chosen_dir_ok = (attack_status[atk_idx] >= 0)
                          && (topo_status[atk_idx][MESH_TOPOLOGY] >= 0)
                          && (leaf_status[atk_idx][MESH_TOPOLOGY][loc_idx] >= 0);
        if (!chosen_dir_ok) {
            ESP_LOGE(TAG, "Selected folder %s/%s/%s could not be created -- CONFIG_FATFS_LFN_HEAP "
                          "may not be enabled in this build.", atk_dir, topo_dir, s_location);
            result = SD_STATUS_TREE_FAILED;
        } else {
            char dest_dir[96];
            snprintf(dest_dir, sizeof(dest_dir), "%s/%s/%s/%s",
                     SD_MOUNT_POINT, atk_dir, topo_dir, s_location);
            char dest_path[160];
            snprintf(dest_path, sizeof(dest_path), "%s/status_%s.txt", dest_dir, node_id);

            /* Boot count is per attack+topology+location folder, since it is read
             * back from the previous report AT the selected folder. csv_logger.c
             * also uses it to name this boot's CSVs, so power-cycling a board
             * never appends two runs into one file. */
            int boot_count = 1;
            /* Running totals, carried forward from the previous report exactly
             * like the boot count. Only resets that point at a PROBLEM are
             * counted - a plain POWERON is every normal plug-in and flash. */
            int brownouts = 0;
            int crashes = 0;
            FILE *rf = fopen(dest_path, "r");
            if (rf) {
                char old_line[96];
                while (fgets(old_line, sizeof(old_line), rf)) {
                    int parsed;
                    if (sscanf(old_line, "Boot count: %d", &parsed) == 1) {
                        boot_count = parsed + 1;
                    } else if (sscanf(old_line, "Brownout resets (total): %d", &parsed) == 1) {
                        brownouts = parsed;
                    } else if (sscanf(old_line, "Crash resets (total): %d", &parsed) == 1) {
                        crashes = parsed;
                    }
                }
                fclose(rf);
            }
            if (s_reset_is_brownout) brownouts++;
            if (s_reset_is_crash)    crashes++;
            rep("Boot count: %d\r\n", boot_count);
            rep("Reset reason (why THIS boot started): %s\r\n", s_reset_reason);
            rep("Brownout resets (total): %d\r\n", brownouts);
            rep("Crash resets (total): %d\r\n", crashes);

            errno = 0;
            FILE *wf = fopen(dest_path, "w");
            if (wf) {
                fprintf(wf, "%s", s_report);
                fclose(wf);
                strlcpy(s_report_path, dest_path, sizeof(s_report_path));
                strlcpy(s_run_dir, dest_dir, sizeof(s_run_dir));
                s_boot_count = boot_count;
                result = SD_STATUS_OK;
            } else {
                ESP_LOGE(TAG, "Report write FAILED at %s: errno=%d (%s)", dest_path, errno, strerror(errno));
                result = SD_STATUS_WRITE_FAILED;
            }
        }
    }

    puts(s_report);

    /* On success the card STAYS mounted: csv_logger.c mirrors telemetry into
     * s_run_dir for the whole run, and re-mounting later would mean bringing
     * SPI3 up again with WiFi and the mesh already live. csv_logger_close()
     * calls sd_status_unmount() at experiment end. Every other outcome has no
     * destination folder to write to, so release the bus here as before. */
    if (result != SD_STATUS_OK) {
        sd_status_unmount();
    }
    return result;
}
