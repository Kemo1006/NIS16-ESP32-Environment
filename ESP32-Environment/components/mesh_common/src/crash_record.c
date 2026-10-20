/**
 * @file crash_record.c
 * @brief Keep a crash's location across the reboot, and the last [HEALTH]
 *        reading before it, so a board that crashed while running on a
 *        powerbank (no laptop listening) still tells us WHERE it crashed.
 *
 * Why (oct. 18 2026, checklist C12 / D9): the children run on powerbanks /
 * adapters - only the root is on the laptop - so a child's crash report on its
 * serial port is never seen. Victims under the blackhole attacker crashed twice
 * with no backtrace.
 *
 * How:
 *  1. The linker wraps esp_panic_handler (components/mesh_common/CMakeLists.txt,
 *     -Wl,--wrap=esp_panic_handler). On a PANIC / watchdog the wrapper copies
 *     the exception PC and up to CR_BT_MAX backtrace PCs into RTC_NOINIT memory
 *     - numbers only, no flash, no locks, nothing that can fail mid-crash - and
 *     hands over to the normal handler (which prints and reboots as before).
 *  2. health_log.c stores its latest reading in the same RTC memory every 30 s.
 *  3. On the next boot sd_status.c asks crash_record_take() for the record and
 *     appends ONE row to crashes_<node>.csv in the run folder on the SD card,
 *     and prints it. tools/fetch_crashes.py pulls it off (USB or card) and
 *     decodes the PCs with addr2line against that board's firmware .elf.
 * RTC_NOINIT memory survives a software / watchdog / panic reset but not a
 * power cut, which is exactly the case here (the board reboots by itself).
 * Diagnostics only - the telemetry CSV and the method are unchanged.
 *
 * NIS16 — CTTHES3
 */

#include "crash_record.h"

#include <stdio.h>
#include <string.h>

#include "esp_attr.h"
#include "esp_app_desc.h"   /* esp_app_get_elf_sha256(): WHICH build crashed */
#include "esp_debug_helpers.h"
#include "esp_private/panic_internal.h"
#include "xtensa_context.h"

#define CR_MAGIC     0x43524153u    /* "CRAS" */
#define CR_HMAGIC    0x4845414Cu    /* "HEAL" */
#define CR_BT_MAX    8

typedef struct {
    uint32_t magic;
    int32_t  exception;              /* panic_exception_t */
    int32_t  core;
    uint32_t pc;
    uint32_t bt[CR_BT_MAX];
    uint32_t nbt;
    uint32_t hmagic;                 /* the last [HEALTH] reading is valid */
    uint32_t h_up, h_heap, h_min, h_big, h_tight;
    char     h_task[16];
} crash_rtc_t;

static RTC_NOINIT_ATTR crash_rtc_t s_rtc;

void crash_record_note_health(uint32_t up_s, uint32_t heap, uint32_t min_heap, uint32_t big,
                              const char *tight_task, uint32_t tight_free)
{
    s_rtc.h_up = up_s; s_rtc.h_heap = heap; s_rtc.h_min = min_heap; s_rtc.h_big = big;
    s_rtc.h_tight = tight_free;
    strlcpy(s_rtc.h_task, tight_task ? tight_task : "-", sizeof(s_rtc.h_task));
    s_rtc.hmagic = CR_HMAGIC;
}

/* Windowed-ABI return address -> the address of the call (what addr2line wants);
 * same arithmetic as esp_cpu_process_stack_pc() on the ESP32. */
static inline uint32_t cr_stack_pc(uint32_t pc)
{
    if (pc & 0x80000000u) {
        pc = (pc & 0x3fffffffu) | 0x40000000u;
    }
    return pc - 3u;
}

/* --- the panic hook: numbers into RTC RAM, then the normal handler --------- */
void __real_esp_panic_handler(panic_info_t *info);

void __wrap_esp_panic_handler(panic_info_t *info)
{
    if (info) {
        s_rtc.exception = (int32_t)info->exception;
        s_rtc.core = (int32_t)info->core;
        s_rtc.pc = 0; s_rtc.nbt = 0;
        const XtExcFrame *f = (const XtExcFrame *)info->frame;
        if (f) {
            s_rtc.pc = (uint32_t)f->pc;
            esp_backtrace_frame_t fr = { .pc = (uint32_t)f->pc, .sp = (uint32_t)f->a1,
                                         .next_pc = (uint32_t)f->a0, .exc_frame = f };
            s_rtc.bt[s_rtc.nbt++] = (uint32_t)f->pc;
            while (s_rtc.nbt < CR_BT_MAX && fr.next_pc != 0 && esp_backtrace_get_next_frame(&fr)) {
                s_rtc.bt[s_rtc.nbt++] = cr_stack_pc(fr.pc);
            }
        }
        s_rtc.magic = CR_MAGIC;
    }
    __real_esp_panic_handler(info);
}

static const char *cr_exception_name(int32_t e)
{
    switch (e) {
        case PANIC_EXCEPTION_DEBUG:     return "DEBUG";
        case PANIC_EXCEPTION_IWDT:      return "INT_WDT";
        case PANIC_EXCEPTION_TWDT:      return "TASK_WDT";
        case PANIC_EXCEPTION_ABORT:     return "ABORT";
        case PANIC_EXCEPTION_FAULT:     return "FAULT";
        default:                        return "OTHER";
    }
}

const char *crash_record_csv_header(void)
{
    /* elf_sha (oct. 20 2026, appended): first 16 hex of the firmware's ELF
     * SHA-256 - the PCs only decode against THAT build (the oct. 18-19 records
     * could not be decoded: the boards' build folders were gone). run.ps1 keeps
     * every flashed .elf in %LOCALAPPDATA%/NIS16/elf_archive/<sha16>_<proj>.elf
     * and fetch_crashes.py looks there first. */
    return "boot,reset_reason,exception,core,pc,backtrace,health_uptime_s,heap,min_heap,big_block,tightest_task,tightest_stack_b,elf_sha";
}

bool crash_record_take(bool crashed, int boot, const char *reset_reason, char *row, size_t len)
{
    const bool have = (s_rtc.magic == CR_MAGIC);
    const bool health = (s_rtc.hmagic == CR_HMAGIC);
    bool out = false;
    if (crashed && row && len) {
        char bt[CR_BT_MAX * 11 + 1] = "";
        size_t n = 0;
        for (uint32_t i = 0; have && i < s_rtc.nbt && i < CR_BT_MAX && n + 12 < sizeof(bt); i++) {
            n += (size_t)snprintf(bt + n, sizeof(bt) - n, "%s0x%08lx", i ? " " : "", (unsigned long)s_rtc.bt[i]);
        }
        char sha[17] = "";
        esp_app_get_elf_sha256(sha, sizeof(sha));
        snprintf(row, len, "%d,%s,%s,%ld,0x%08lx,%s,%lu,%lu,%lu,%lu,%s,%lu,%s",
                 boot, reset_reason ? reset_reason : "?",
                 have ? cr_exception_name(s_rtc.exception) : "not-captured",
                 have ? (long)s_rtc.core : -1L, (unsigned long)(have ? s_rtc.pc : 0u), have ? bt : "-",
                 (unsigned long)(health ? s_rtc.h_up : 0u), (unsigned long)(health ? s_rtc.h_heap : 0u),
                 (unsigned long)(health ? s_rtc.h_min : 0u), (unsigned long)(health ? s_rtc.h_big : 0u),
                 health ? s_rtc.h_task : "-", (unsigned long)(health ? s_rtc.h_tight : 0u),
                 sha[0] ? sha : "-");
        out = true;
    }
    /* one record per crash: forget it once read (and on any normal boot) */
    s_rtc.magic = 0;
    s_rtc.hmagic = 0;
    return out;
}
