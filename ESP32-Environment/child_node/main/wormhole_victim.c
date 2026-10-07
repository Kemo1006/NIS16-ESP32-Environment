/**
 * @file wormhole_victim.c
 * @brief Combined Victim + Wormhole Attacker firmware — Milestone 2.
 *
 * The wormhole is a TWO-node colluding attack. Mesh traffic (probes to root,
 * phase broadcasts) still goes over normal esp_mesh_send/esp_mesh_recv — no
 * raw 802.11 frames are touched there. The A<->B tunnel itself, however, is a
 * PHYSICAL WIRED UART1 LINK directly between the two attacker boards
 * (see WORMHOLE_UART_* in mesh_config.h and wormhole_uart_init() below) — that
 * out-of-band, non-wireless channel is what makes this a wormhole rather than
 * ordinary mesh forwarding, per Milestone 2 and the thesis's Figure 4.9. One
 * board is Node A (exit / root-side), the other is Node B (entry / leaf-side).
 * This single file implements BOTH ends.
 *
 * WHICH END AM I — decided at RUN time (AUTO-SWITCH, oct. 7 2026)
 * ────────────────────────────────────────────────────────────────
 * Until oct. 7 the end was fixed at build time (-DWORMHOLE_END). A linear run
 * that day formed with B at H01 (next to the root) and A at H06: the tunnelled
 * copy then climbed back up from deep in the mesh and arrived SLOWER than B's
 * normal copy - no shortcut, no wormhole signature, and nothing failed. Mesh
 * placement is the stack's choice, not ours, so the end is now chosen from it:
 *
 *   - Both ends send a HELLO frame over the same UART wire once a second
 *     (their mesh layer, current role, and whether it is locked).
 *   - Until the root announces Phase 0 the role is PROVISIONAL and follows the
 *     depths: the DEEPER board is B (entry), the SHALLOWER one A (exit), so
 *     the tunnel is always a shortcut toward the root. Equal depth (no
 *     shortcut possible) is broken by MAC, and the root's EXPOSURE check flags
 *     it as "AT THE SAME DEPTH".
 *   - At the first real phase the role LOCKS for the rest of the run. It never
 *     follows the mesh after that: a swap mid-run would corrupt the capture.
 *   - A board that boots into a run already in progress (powercycle) takes
 *     the opposite of its peer's LOCKED role.
 *   - If both lock the same role (layers changed between two HELLOs), the
 *     board with the HIGHER MAC flips, once, and says so in the log.
 *   - No HELLO at all (cable fault, or a peer on pre-auto-switch firmware):
 *     fall back to the build-time WORMHOLE_END, exactly the old behaviour.
 *
 * The role goes into the heartbeat (node_identity_set_role, so the root's
 * dashboard shows it live) and into every telemetry row's role column.
 *
 * Behaviour (baseline/cooldown = ordinary victim on both ends):
 *   Node B (entry) — generates probes and ALWAYS forwards each one to the root
 *     over the mesh (the "slow"/normal copy). During the wormhole phase it
 *     ADDITIONALLY wraps each probe in a CRC32-protected frame and writes it
 *     out the wired UART link to Node A.
 *   Node A (exit)  — during the wormhole phase it reads tunnel frames off the
 *     wired UART link, validates their CRC, and RE-INJECTS the probe to the
 *     root as a SECOND ("fast") copy, tagged PROBE_MAGIC_WORMHOLE so the root
 *     can tell it apart from the normal copy and NOT de-dup it. The root
 *     therefore logs the same seq TWICE during the attack — once via B's
 *     normal mesh path, once via the tunnel — with a measurable latency
 *     mismatch. That duplicate + latency mismatch IS the wormhole signature
 *     (Milestone 2 / thesis Fig 4.10, §4.2.1.3 J).
 *   B only generates probes once its role is LOCKED (at Phase 0). Rows before
 *   that are pre-baseline and excluded from analysis anyway.
 *
 * Telemetry counter mapping (11-col schema has retry/tx/probes — we overload
 * them the same way blackhole_victim.c overloads retry_count for drops, so the
 * attack shows a crisp phase-correlated signature without a schema change):
 *   Node B: probes_count = probes generated (steady 1 Hz),
 *           tx_count      = probes forwarded DIRECT to root (climbs the WHOLE
 *                           run — B always sends the normal copy),
 *           retry_count   = probes ALSO TUNNELLED to A (0 in baseline, climbs
 *                           during the wormhole phase; also counts UART fails).
 *   Node A: probes_count = tunnelled probes RECEIVED from B over UART (0 until attack),
 *           tx_count      = probes RE-INJECTED to root as the fast copy (0 until attack),
 *           retry_count   = re-inject send failures.
 *
 * Build (same -DACTIVE_ATTACK=2 on all three boards). WORMHOLE_END is now only
 * the FALLBACK end used when no HELLO arrives from the peer:
 *     cd root_node   && idf.py -DACTIVE_ATTACK=2                  build flash
 *     cd child_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=0 build flash  # fallback A
 *     cd child_node && idf.py -DACTIVE_ATTACK=2 -DWORMHOLE_END=1 build flash  # fallback B
 * The victim CMakeLists selects THIS file when ACTIVE_ATTACK=2; the root
 * announces PHASE_ID_WORMHOLE during the attack window (root code is generic —
 * it broadcasts whatever ACTIVE_ATTACK is, so no root edit is needed).
 *
 * NIS16 — CTTHES2 Milestone 2 — Wormhole Attack
 */

#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_log.h"
#include "esp_mesh.h"
#include "esp_wifi.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "esp_rom_crc.h"
#include "driver/uart.h"

#include "mesh_config.h"
#include "mesh_setup.h"
#include "phase_listener.h"
#include "csv_logger.h"
#include "sd_status.h"
#include "node_identity.h"
#include "probe_relay.h"
#include "nvs.h"

static const char *TAG = "WORMHOLE";

/* Probe wire format and BOTH magics (PROBE_MAGIC, PROBE_MAGIC_WORMHOLE) now
 * come from probe_relay.h, shared with every other role. The tunnel formats
 * below are still private to this file - they never leave the UART wire. */

/* ── Tunnel wire format (A<->B UART link only — thesis Figure 4.9) ────────── */
typedef struct __attribute__((packed)) {
    uint32_t    magic;   /* WORMHOLE_TUNNEL_MAGIC                              */
    probe_pkt_t probe;   /* the captured probe, verbatim                       */
    uint32_t    crc;     /* CRC32 over magic+probe — detects UART bit errors,
                           * per Milestone 2's "CRC-protected" requirement      */
} tunnel_pkt_t;

/* ── HELLO frame (auto-switch) — same wire, same SIZE as a tunnel frame ─────
 * Equal size on purpose: the receiver reassembles fixed-size windows and
 * resyncs one byte at a time, so a second frame type of the same length needs
 * no change to that logic beyond checking a second magic. A pre-auto-switch
 * peer sees an unknown magic, slides past it and re-locks on real frames. */
#define WORMHOLE_HELLO_MAGIC   0x4C4C4548U          /* "HELL" little-endian */
typedef struct __attribute__((packed)) {
    uint32_t magic;      /* WORMHOLE_HELLO_MAGIC                               */
    uint8_t  mac[6];     /* sender's STA MAC (tie-break)                       */
    int16_t  layer;      /* sender's mesh layer; <= 0 = not in the mesh yet    */
    uint8_t  role;       /* node_role_t: NODE_ROLE_WORMHOLE_A / _B             */
    uint8_t  locked;     /* 1 once the sender's role is fixed for the run      */
    uint8_t  pad[sizeof(probe_pkt_t) - 10];
    uint32_t crc;        /* CRC32 over everything before it                    */
} hello_pkt_t;
_Static_assert(sizeof(hello_pkt_t) == sizeof(tunnel_pkt_t),
               "HELLO and tunnel frames must be the same size (see above)");

#define HELLO_PERIOD_MS        1000
#define PEER_FRESH_MS          5000   /* a HELLO older than this is "no peer"  */
#define LOCK_WAIT_FOR_PEER_MS  3000   /* booted into a running run: wait this
                                       * long for a HELLO before falling back  */

/* ── Shared state ─────────────────────────────────────────────────────────── */
static char     s_node_id[NODE_ID_LEN] = {0};
static char     s_run_id[RUN_ID_LEN]   = {0};
static uint8_t  s_self_mac[6]          = {0};

#define TUNNEL_QUEUE_SIZE 32

/* Role state. Written by role_task (and the peer fields by the UART RX task);
 * single-byte/word fields, read without a lock by the data-path tasks - a
 * stale read costs at most one probe routed by the previous role. */
static volatile uint8_t s_role        = NODE_ROLE_WORMHOLE_A;
static volatile bool    s_role_locked = false;
static volatile bool    s_peer_seen   = false;
static volatile int64_t s_peer_last_us = 0;
static volatile int16_t s_peer_layer  = 0;
static volatile uint8_t s_peer_role   = NODE_ROLE_WORMHOLE_A;
static volatile bool    s_peer_locked = false;
static uint8_t          s_peer_mac[6] = {0};

/* Error detection for the auto-switch (reported live and in the end-of-run
 * summary in app_main). */
static volatile uint32_t s_uart_bad_windows = 0; /* CRC/magic misses = resyncs */
static volatile bool     s_role_conflict    = false; /* both locked the same end */
static volatile bool     s_locked_fallback  = false; /* locked with no peer      */
static volatile bool     s_shortcut_lost    = false; /* mesh moved after lock    */

static inline bool is_b(void) { return s_role == NODE_ROLE_WORMHOLE_B; }
static inline const char *role_csv_str(void) { return is_b() ? "wormhole_b" : "wormhole_a"; }

/* Node B counters (see file header for the telemetry mapping). */
static volatile uint32_t s_probes_generated = 0;
static volatile uint32_t s_probes_to_root   = 0;  /* direct sends               */
static volatile uint32_t s_probes_tunneled  = 0;  /* tunnelled to A (attack)    */
static volatile uint32_t s_tunnel_fail      = 0;  /* failed sends of either     */
/* Node A counters. */
static volatile uint32_t s_tunnel_received   = 0; /* from B (attack)            */
static volatile uint32_t s_probes_reinjected = 0; /* re-sent to root (attack)   */
static volatile uint32_t s_reinject_fail     = 0; /* failed re-injects          */

static QueueHandle_t s_probe_queue    = NULL;    /* B: generator -> forwarder  */
static QueueHandle_t s_reinject_queue = NULL;    /* A: UART RX -> re-inject    */

/* ── Forward declarations ─────────────────────────────────────────────────── */
static void telemetry_task(void *arg);
static void build_run_id(char *buf, size_t len);
static void role_task(void *arg);
static void probe_gen_task(void *arg);
static void tunnel_forwarder_task(void *arg);
static void uart_tunnel_rx_task(void *arg);
static void reinject_task(void *arg);

/* C7 Option 1: both wormhole ends are ALSO ordinary relays for everyone else's
 * traffic. This is not optional - a wormhole node sitting mid-chain that did
 * not forward transit probes would silently swallow everything from the nodes
 * below it, producing a BLACKHOLE signature inside a WORMHOLE run. Forwards
 * both PROBE_MAGIC and PROBE_MAGIC_WORMHOLE (see probe_relay.h). */
static void wh_recv_cb(const uint8_t *data, size_t len,
                       const uint8_t from_addr[6])
{
    (void)from_addr;
    probe_relay_ingest(data, len);
}

/*
 * Shared by both ends: bring up the physical UART1 link used as the wormhole's
 * out-of-band tunnel (Milestone 2 requirement). This is a SEPARATE port from
 * UART0 (console / csv_logger's serial-export task), and a separate physical
 * cable from the USB connection to your laptop — it only ever talks to the
 * other attacker board, wired directly GPIO-to-GPIO.
 */
static void wormhole_uart_init(void)
{
    const uart_config_t uart_cfg = {
        .baud_rate  = WORMHOLE_UART_BAUD,
        .data_bits  = UART_DATA_8_BITS,
        .parity     = UART_PARITY_DISABLE,
        .stop_bits  = UART_STOP_BITS_1,
        .flow_ctrl  = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_driver_install(WORMHOLE_UART_PORT, 512, 512, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(WORMHOLE_UART_PORT, &uart_cfg));
    ESP_ERROR_CHECK(uart_set_pin(WORMHOLE_UART_PORT,
                                  WORMHOLE_UART_TX_PIN, WORMHOLE_UART_RX_PIN,
                                  UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
    ESP_LOGI(TAG, "Wormhole UART tunnel ready: UART%d  TX=GPIO%d  RX=GPIO%d  %d baud",
             WORMHOLE_UART_PORT, WORMHOLE_UART_TX_PIN, WORMHOLE_UART_RX_PIN,
             WORMHOLE_UART_BAUD);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * app_main — one image, both ends
 * ═══════════════════════════════════════════════════════════════════════════ */

void app_main(void)
{
    s_role = (WORMHOLE_END == WORMHOLE_END_B) ? NODE_ROLE_WORMHOLE_B
                                              : NODE_ROLE_WORMHOLE_A;
    ESP_LOGI(TAG, "=== WORMHOLE NODE STARTING (auto-switch; fallback end %s) ===",
             is_b() ? "B" : "A");

    /* ── 0. SD environment check (non-fatal; telemetry stays on SPIFFS) ───── */
    sd_status_result_t sdres = sd_status_run_boot_check();
    if (sdres == SD_STATUS_OK) {
        ESP_LOGI(TAG, "SD ENV: OK -- %s", sd_status_report_path());
    } else {
        ESP_LOGE(TAG, "SD ENV: %s -- RUN CONTINUES, SPIFFS logging unaffected",
                 sd_status_result_str(sdres));
    }

    ESP_ERROR_CHECK(mesh_setup_init(is_b() ? MESH_ROLE_ATCK_WB : MESH_ROLE_ATCK_WA));
    mesh_setup_get_node_id(s_node_id);
    esp_read_mac(s_self_mac, ESP_MAC_WIFI_STA);
    build_run_id(s_run_id, sizeof(s_run_id));
    ESP_LOGI(TAG, "Node ID: %s   Run ID: %s", s_node_id, s_run_id);
    wormhole_uart_init();

    /* Identity (nickname) — after the SD boot check, which caches
     * node_config.txt while the card is still mounted. The role given here is
     * the fallback; role_task replaces it once the peer is heard. */
    node_identity_resolve(s_role);

    s_probe_queue    = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    s_reinject_queue = xQueueCreate(TUNNEL_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_probe_queue || !s_reinject_queue) {
        ESP_LOGE(TAG, "Failed to create tunnel queues");
        return;
    }

    ESP_ERROR_CHECK(phase_listener_start());
    /* Honest relay (NULL decision): a wormhole endpoint never drops other
     * nodes' traffic - its manipulation is DUPLICATION via the UART tunnel,
     * not suppression. */
    ESP_ERROR_CHECK(probe_relay_start(NULL));
    phase_listener_set_data_cb(wh_recv_cb);
    ESP_ERROR_CHECK(csv_logger_init(s_node_id, s_run_id, CSV_ROLE_VICTIM));
    ESP_LOGI(TAG, "Logging to: %s", csv_logger_get_filepath());

    /* Every task of BOTH ends runs on both boards; each one checks the role
     * before acting, so the board behaves as whichever end it ends up being. */
    xTaskCreate(uart_tunnel_rx_task,   "wh_uart_rx",  STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    xTaskCreate(role_task,             "wh_role",     STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    xTaskCreate(probe_gen_task,        "probe_gen",   STACK_PROBE_GEN,  NULL, TASK_PRIO_PROBE_GEN,  NULL);
    xTaskCreate(tunnel_forwarder_task, "wh_fwd",      STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    xTaskCreate(reinject_task,         "wh_reinject", STACK_PROBE_SINK, NULL, TASK_PRIO_PROBE_SINK, NULL);
    /* Telemetry ABOVE the tunnel tasks so it isn't starved — see
     * TASK_PRIO_ATTACKER_TELEMETRY in mesh_config.h. */
    xTaskCreate(telemetry_task,        "telemetry",   STACK_TELEMETRY,  NULL, TASK_PRIO_ATTACKER_TELEMETRY, NULL);
    ESP_ERROR_CHECK(heartbeat_start());

    phase_listener_wait_for_terminate();

    /* ── Auto-switch summary: one place that says whether the end decision
     *    can be trusted for this capture. ─────────────────────────────────── */
    bool clean = s_role_locked && !s_locked_fallback && !s_role_conflict && !s_shortcut_lost;
    if (clean) {
        ESP_LOGI(TAG, "AUTO-SWITCH: OK - ran as NODE %s, decided by depth, peer heard,"
                      " no conflict, shortcut held. UART bad windows: %lu.",
                 is_b() ? "B (entry)" : "A (exit)", (unsigned long)s_uart_bad_windows);
    } else {
        ESP_LOGE(TAG, "*********************************************************");
        ESP_LOGE(TAG, "*** AUTO-SWITCH PROBLEMS IN THIS RUN - CHECK BEFORE USE ***");
        ESP_LOGE(TAG, "  Ended as NODE %s.", is_b() ? "B (entry)" : "A (exit)");
        if (!s_role_locked)    ESP_LOGE(TAG, "  - role never locked (no real phase was reached)");
        if (s_locked_fallback) ESP_LOGE(TAG, "  - locked from the BUILD FALLBACK: peer never heard over UART");
        if (s_role_conflict)   ESP_LOGE(TAG, "  - both ends locked the SAME end; one switched at run time"
                                             " (rows before the switch carry the wrong role)");
        if (s_shortcut_lost)   ESP_LOGE(TAG, "  - mesh moved after the lock: the tunnel stopped being a"
                                             " shortcut for part of the run");
        ESP_LOGE(TAG, "  UART bad windows: %lu.", (unsigned long)s_uart_bad_windows);
        ESP_LOGE(TAG, "*********************************************************");
    }

    if (is_b()) {
        ESP_LOGI(TAG, "Experiment complete as NODE B. Generated: %lu  ToRoot: %lu  "
                      "Tunnelled: %lu  Fail: %lu",
                 (unsigned long)s_probes_generated, (unsigned long)s_probes_to_root,
                 (unsigned long)s_probes_tunneled,  (unsigned long)s_tunnel_fail);
    } else {
        ESP_LOGI(TAG, "Experiment complete as NODE A. Received: %lu  Re-injected: %lu  Fail: %lu",
                 (unsigned long)s_tunnel_received, (unsigned long)s_probes_reinjected,
                 (unsigned long)s_reinject_fail);

        /* Loud post-flight, mirroring the blackhole attacker's MAC check: if
         * NOTHING ever came down the wire, the wormhole did not happen and this
         * capture cannot show the tunnel signature (TunnelIntensity/TunnelBytes/
         * TunnelLatency all empty) — while both boards still look healthy and
         * log full telemetry.
         *
         * This check belongs on NODE A specifically. On node B a disconnected
         * or mis-wired TX line is UNDETECTABLE: uart_write_bytes() happily
         * succeeds into an unterminated line, so B's "Tunnelled" counter climbs
         * either way. Node A is the only end that can prove a frame crossed. */
        if (s_tunnel_received == 0) {
            ESP_LOGE(TAG, "*********************************************************");
            ESP_LOGE(TAG, "*** WORMHOLE TUNNEL CARRIED NOTHING - RUN IS UNUSABLE ***");
            ESP_LOGE(TAG, "*********************************************************");
            ESP_LOGE(TAG, "  Node A received ZERO tunnelled frames from node B over UART%d.",
                     WORMHOLE_UART_PORT);
            ESP_LOGE(TAG, "  The tunnel never opened, so no wormhole signature exists:");
            ESP_LOGE(TAG, "  TunnelIntensity / TunnelBytes / TunnelLatency will be empty.");
            ESP_LOGE(TAG, "  CHECK: the physical A<->B UART wiring (B's TX -> A's RX, and a");
            ESP_LOGE(TAG, "  COMMON GROUND between the two boards) and re-run. %s",
                     s_peer_seen ? "" : "No HELLO was ever heard from the peer either.");
            ESP_LOGE(TAG, "  Bring-up test: wizard MAINTENANCE > Wormhole UART tunnel test.");
            ESP_LOGE(TAG, "*********************************************************");
        }
    }

    csv_logger_flush();
    csv_logger_close();
    csv_logger_start_export_task();
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Role decision (auto-switch) — see "WHICH END AM I" in the file header
 * ═══════════════════════════════════════════════════════════════════════════ */

static bool peer_fresh(void)
{
    return s_peer_seen && (esp_timer_get_time() - s_peer_last_us) < (PEER_FRESH_MS * 1000LL);
}

/* true when MY MAC sorts below the peer's - the deterministic tie-break both
 * boards compute identically (lower MAC = A). */
static bool my_mac_lower(void)
{
    return memcmp(s_self_mac, s_peer_mac, 6) < 0;
}

/* The role this board SHOULD have right now, from what it knows. */
static uint8_t decide_role(int my_layer)
{
    const uint8_t fallback = (WORMHOLE_END == WORMHOLE_END_B) ? NODE_ROLE_WORMHOLE_B
                                                              : NODE_ROLE_WORMHOLE_A;
    if (!peer_fresh()) {
        return fallback;
    }
    if (s_peer_locked) {
        /* Peer already committed (we rebooted into a running run): mirror it. */
        return (s_peer_role == NODE_ROLE_WORMHOLE_B) ? NODE_ROLE_WORMHOLE_A
                                                     : NODE_ROLE_WORMHOLE_B;
    }
    if (my_layer > 0 && s_peer_layer > 0 && my_layer != s_peer_layer) {
        /* The deeper board is the ENTRY (B): the tunnel then skips hops. */
        return (my_layer > s_peer_layer) ? NODE_ROLE_WORMHOLE_B : NODE_ROLE_WORMHOLE_A;
    }
    /* Same depth (no shortcut possible - the root flags it) or a layer not
     * known yet: still guarantee OPPOSITE ends. */
    return my_mac_lower() ? NODE_ROLE_WORMHOLE_A : NODE_ROLE_WORMHOLE_B;
}

static void apply_role(uint8_t role, const char *why)
{
    if (role != s_role) {
        ESP_LOGW(TAG, "Wormhole end %s -> %s (%s)",
                 is_b() ? "B" : "A", role == NODE_ROLE_WORMHOLE_B ? "B" : "A", why);
        s_role = role;
        node_identity_set_role(role);
    }
}

static void send_hello(int my_layer)
{
    hello_pkt_t h = {
        .magic  = WORMHOLE_HELLO_MAGIC,
        .layer  = (int16_t)my_layer,
        .role   = s_role,
        .locked = s_role_locked ? 1 : 0,
    };
    memcpy(h.mac, s_self_mac, 6);
    h.crc = esp_rom_crc32_le(0, (const uint8_t *)&h, offsetof(hello_pkt_t, crc));
    uart_write_bytes(WORMHOLE_UART_PORT, (const char *)&h, sizeof(h));
}

static void role_task(void *arg)
{
    (void)arg;
    const int64_t started_us = esp_timer_get_time();
    int64_t next_hello_us = 0;
    bool conflict_fixed = false, lost_warned = false, shortcut_warned = false;
    uint32_t next_noise_warn = 64;

    while (!phase_listener_is_terminated()) {
        int my_layer = mesh_setup_get_layer();
        int64_t now = esp_timer_get_time();

        if (now >= next_hello_us) {
            send_hello(my_layer);
            next_hello_us = now + HELLO_PERIOD_MS * 1000LL;
        }

        uint8_t phase = phase_listener_get_phase_id();
        bool real_phase = (phase != PHASE_ID_UNSET && phase != PHASE_ID_PREPARE);

        if (!s_role_locked) {
            apply_role(decide_role(my_layer), peer_fresh() ? "depth vs peer" : "no peer - build fallback");
            /* Lock at the first real phase. A board that boots straight into
             * one gives the peer a few HELLOs' worth of time first. */
            if (real_phase && (peer_fresh()
                               || now - started_us > LOCK_WAIT_FOR_PEER_MS * 1000LL)) {
                s_role_locked = true;
                if (peer_fresh()) {
                    ESP_LOGW(TAG, "LOCKED as NODE %s (exit/entry by depth: mine L%d, peer L%d)"
                                  " - fixed for the rest of the run.",
                             is_b() ? "B (entry)" : "A (exit)", my_layer, (int)s_peer_layer);
                } else {
                    s_locked_fallback = true;
                    ESP_LOGE(TAG, "LOCKED as NODE %s from the BUILD FALLBACK - no HELLO from"
                                  " the peer. Check the UART cable (or the peer runs firmware"
                                  " without auto-switch).", is_b() ? "B" : "A");
                }
                send_hello(my_layer);           /* tell the peer straight away */
            }
        } else if (!conflict_fixed && peer_fresh() && s_peer_locked
                   && s_peer_role == s_role) {
            /* Both locked the same end. Exactly one must move: the higher MAC. */
            s_role_conflict = true;
            if (!my_mac_lower()) {
                uint8_t other = is_b() ? NODE_ROLE_WORMHOLE_A : NODE_ROLE_WORMHOLE_B;
                ESP_LOGE(TAG, "Both ends locked as %s - this board (higher MAC) switches.",
                         is_b() ? "B" : "A");
                apply_role(other, "conflict with peer");
                send_hello(my_layer);
            }
            conflict_fixed = true;
        }

        /* SHORTCUT CHECK after the lock: the mesh may re-parent mid-run. The
         * role must NOT follow it (a swap mid-run corrupts the capture), but a
         * tunnel that no longer skips hops makes the attack windows suspect -
         * say so loudly, once per episode, and keep it for the summary. */
        if (s_role_locked && peer_fresh() && my_layer > 0 && s_peer_layer > 0
                && s_peer_role != s_role) {
            int a_layer = is_b() ? s_peer_layer : my_layer;
            int b_layer = is_b() ? my_layer     : s_peer_layer;
            bool lost = (a_layer >= b_layer);
            if (lost && !shortcut_warned) {
                s_shortcut_lost = true;
                ESP_LOGE(TAG, "!! TUNNEL IS NO LONGER A SHORTCUT: A (exit) now at L%d, B (entry)"
                              " at L%d (phase %u). The mesh moved after the lock; roles stay"
                              " fixed. Treat this run's attack windows as SUSPECT.",
                         a_layer, b_layer, (unsigned)phase);
                shortcut_warned = true;
            } else if (!lost && shortcut_warned) {
                ESP_LOGW(TAG, "Tunnel is a shortcut again: A at L%d, B at L%d.", a_layer, b_layer);
                shortcut_warned = false;
            }
        }

        /* NOISY CABLE: every CRC/magic miss costs a one-byte resync. A handful
         * at boot is normal (the two boards start mid-frame); a steady stream
         * means a loose jumper or missing common ground. */
        if (s_uart_bad_windows >= next_noise_warn) {
            ESP_LOGW(TAG, "UART link noisy: %lu bad frame windows so far - check the jumpers"
                          " and the common GND.", (unsigned long)s_uart_bad_windows);
            next_noise_warn *= 4;
        }

        if (s_role_locked && s_peer_seen && !peer_fresh() && !lost_warned) {
            ESP_LOGW(TAG, "No HELLO from the peer for %d s - is the UART cable still"
                          " connected? (role stays locked)", PEER_FRESH_MS / 1000);
            lost_warned = true;
        } else if (peer_fresh()) {
            lost_warned = false;
        }

        vTaskDelay(pdMS_TO_TICKS(100));
    }
    vTaskDelete(NULL);
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Node B duties — entry / leaf-side (captures probes, tunnels to A during attack)
 * ═══════════════════════════════════════════════════════════════════════════ */

/* Generate a probe every PROBE_INTERVAL_MS — only while this board is a
 * LOCKED Node B; Node A originates nothing (it relays and re-injects). */
static void probe_gen_task(void *arg)
{
    ESP_LOGI(TAG, "Probe generator ready at %u ms interval (runs only as locked Node B).",
             PROBE_INTERVAL_MS);

    probe_pkt_t pkt = { .magic = PROBE_MAGIC };
    memcpy(pkt.src_mac, s_self_mac, 6);
    uint32_t seq = 0;

    while (!phase_listener_is_terminated()) {
        if (s_role_locked && is_b()) {
            pkt.seq_num    = ++seq;
            pkt.send_ts_us = esp_timer_get_time();
            s_probes_generated++;

            if (xQueueSend(s_probe_queue, &pkt, pdMS_TO_TICKS(10)) != pdTRUE) {
                ESP_LOGW(TAG, "Probe queue full! seq=%lu dropped at source",
                         (unsigned long)seq);
            }
        }
        vTaskDelay(pdMS_TO_TICKS(PROBE_INTERVAL_MS));
    }
    ESP_LOGI(TAG, "Probe generator exiting.");
    vTaskDelete(NULL);
}

/*
 * Forwarder: every phase → send the probe to the root over the mesh (hop by
 * hop, C7 Option 1). Wormhole phase → ALSO wrap it in a tunnel packet, CRC it,
 * and write it out the wired UART link to Node A — NOT the mesh. That physical
 * separation from the wireless path is what makes this a wormhole shortcut
 * rather than ordinary forwarding.
 */
static void tunnel_forwarder_task(void *arg)
{
    probe_pkt_t pkt;

    /* Tunnel-to-A frame (wormhole phase) — sent over UART1, not the mesh. */
    tunnel_pkt_t tp = { .magic = WORMHOLE_TUNNEL_MAGIC };

    ESP_LOGI(TAG, "Tunnel forwarder running.");

    while (true) {
        if (xQueueReceive(s_probe_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        /* ── Step 1: ALWAYS forward the probe to root over the mesh ────────
         * This is the normal "slow" copy the root receives in every phase.
         * During the attack it becomes the first of the two duplicate
         * arrivals (the tunnel copy from A is the second). */
        esp_err_t err = probe_relay_send_own(&pkt);
        if (err == ESP_OK) {
            s_probes_to_root++;
        } else {
            s_tunnel_fail++;
            ESP_LOGW(TAG, "Direct send failed seq=%lu: %s",
                     (unsigned long)pkt.seq_num, esp_err_to_name(err));
        }

        /* ── Step 2: during the wormhole phase, ADDITIONALLY tunnel the probe
         * to Node A over the wired UART. A re-injects it as the "fast" copy,
         * so root gets the same seq twice with a latency mismatch. */
        if (phase_listener_get_phase_id() == PHASE_ID_WORMHOLE) {
            tp.probe = pkt;
            tp.crc = esp_rom_crc32_le(0, (const uint8_t *)&tp,
                                       offsetof(tunnel_pkt_t, crc));
            int written = uart_write_bytes(WORMHOLE_UART_PORT,
                                            (const char *)&tp, sizeof(tp));
            if (written == (int)sizeof(tp)) {
                s_probes_tunneled++;
                ESP_LOGD(TAG, "Tunnelled probe seq=%lu -> Node A via UART",
                         (unsigned long)pkt.seq_num);
            } else {
                s_tunnel_fail++;
                ESP_LOGW(TAG, "UART tunnel send failed seq=%lu (wrote %d/%u bytes)",
                         (unsigned long)pkt.seq_num, written, (unsigned)sizeof(tp));
            }
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * UART receiver (both ends: HELLOs always; tunnel frames matter on Node A)
 * ═══════════════════════════════════════════════════════════════════════════ */

/*
 * Reassembles fixed-size frames off the wired UART1 link (NOT the mesh — see
 * wormhole_uart_init() and mesh_config.h). Two frame types share the size:
 * tunnel frames (B -> A, attack phase) and HELLOs (both ways, once a second).
 * Each is accepted only if its magic AND CRC32 match (Milestone 2's
 * "CRC-protected to detect errors").
 *
 * SELF-RESYNCHRONISING: a raw UART link has no packet boundaries, so a single
 * dropped/spurious byte (loose jumper, noise) would otherwise misalign every
 * subsequent frame forever. When a full-frame window fails validation we slide
 * the buffer forward ONE byte and retry, so the receiver re-locks onto the next
 * real frame instead of staying permanently desynced.
 */
static void uart_tunnel_rx_task(void *arg)
{
    union {
        tunnel_pkt_t t;
        hello_pkt_t  h;
        uint8_t      raw[sizeof(tunnel_pkt_t)];
    } f;
    size_t got = 0;

    ESP_LOGI(TAG, "UART tunnel receiver running.");

    while (true) {
        /* Top up the buffer to a full frame's worth of bytes. */
        int n = uart_read_bytes(WORMHOLE_UART_PORT, f.raw + got,
                                 sizeof(f.raw) - got, pdMS_TO_TICKS(100));
        if (n <= 0) {
            continue;
        }
        got += (size_t)n;
        if (got < sizeof(f.raw)) {
            continue;   /* wait for the rest of this frame */
        }

        uint32_t crc = esp_rom_crc32_le(0, f.raw, offsetof(tunnel_pkt_t, crc));
        bool tunnel_ok = (f.t.magic == WORMHOLE_TUNNEL_MAGIC) &&
                         (f.t.probe.magic == PROBE_MAGIC) && (crc == f.t.crc);
        bool hello_ok  = (f.h.magic == WORMHOLE_HELLO_MAGIC) && (crc == f.h.crc);

        if (hello_ok) {
            memcpy(s_peer_mac, f.h.mac, 6);
            s_peer_layer   = f.h.layer;
            s_peer_role    = f.h.role;
            s_peer_locked  = (f.h.locked != 0);
            s_peer_last_us = esp_timer_get_time();
            if (!s_peer_seen) {
                ESP_LOGI(TAG, "Peer heard over UART: " MACSTR "  layer %d  end %s%s",
                         MAC2STR(f.h.mac), (int)f.h.layer,
                         f.h.role == NODE_ROLE_WORMHOLE_B ? "B" : "A",
                         f.h.locked ? " (locked)" : "");
            }
            s_peer_seen = true;
            got = 0;
        } else if (tunnel_ok) {
            if (is_b()) {
                /* Only possible while the two ends disagree (see role_task's
                 * conflict rule); re-injecting here would duplicate from the
                 * wrong place. */
                ESP_LOGW(TAG, "Tunnel frame received while acting as Node B - ignored");
            } else {
                s_tunnel_received++;
                probe_pkt_t inner = f.t.probe;
                if (xQueueSend(s_reinject_queue, &inner, 0) != pdTRUE) {
                    ESP_LOGW(TAG, "Re-inject queue full — dropping tunnelled seq=%lu",
                             (unsigned long)inner.seq_num);
                }
            }
            got = 0;    /* consumed a good frame — start the next one fresh */
        } else {
            /* Bad window: drop the oldest byte and slide the rest down, so the
             * next uart_read_bytes() only tops up by 1 and we re-test at the
             * next byte offset until magic+CRC re-align. */
            s_uart_bad_windows++;
            ESP_LOGD(TAG, "UART tunnel: window invalid (magic/CRC) — resyncing");
            memmove(f.raw, f.raw + 1, sizeof(f.raw) - 1);
            got = sizeof(f.raw) - 1;
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Node A duty — exit / root-side (re-injects tunnelled probes)
 * ═══════════════════════════════════════════════════════════════════════════ */

/*
 * Re-inject task: for each tunnelled probe from B, re-send the ORIGINAL probe
 * to the root. The payload keeps B's src_mac and B's original send timestamp,
 * so the root logs the probe as B's — but via the tunnel's path. That latency
 * difference, plus the tunnel traffic on A and B, is the wormhole signature.
 */
static void reinject_task(void *arg)
{
    probe_pkt_t pkt;

    ESP_LOGI(TAG, "Re-inject task running.");

    while (true) {
        if (xQueueReceive(s_reinject_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        /* Tag this as the tunnel ("fast") copy: root recognises PROBE_MAGIC_WORMHOLE
         * and logs it as a SECOND arrival for the same (src_mac, seq_num) instead
         * of de-duping it against B's normal copy. src_mac and seq_num stay B's,
         * so the two rows correlate — same probe, two latencies. */
        pkt.magic = PROBE_MAGIC_WORMHOLE;
        /* C7 Option 1: re-inject via our parent, hop by hop. This still meets
         * the Milestone Form's "re-injects toward root via the legitimate mesh
         * path" - more literally than before, since it now traverses the real
         * forwarding path rather than being handed to the stack. Every relay in
         * between forwards PROBE_MAGIC_WORMHOLE (see probe_relay.h). */
        esp_err_t err = probe_relay_send_own(&pkt);
        if (err == ESP_OK) {
            s_probes_reinjected++;
            ESP_LOGD(TAG, "Re-injected probe src=" MACSTR " seq=%lu",
                     MAC2STR(pkt.src_mac), (unsigned long)pkt.seq_num);
        } else {
            s_reinject_fail++;
            ESP_LOGW(TAG, "Re-inject failed seq=%lu: %s",
                     (unsigned long)pkt.seq_num, esp_err_to_name(err));
        }
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Telemetry task — cross-layer sampler (both ends)
 *
 * Uses the shared schema. The retry/tx/probes columns carry the counters of
 * whichever end this board CURRENTLY is (file header), and the role column
 * says which, so a row is always self-describing.
 * ═══════════════════════════════════════════════════════════════════════════ */

static void telemetry_task(void *arg)
{
    ESP_LOGI(TAG, "Telemetry task running at %u ms interval.", SAMPLING_INTERVAL_MS);

    /* Fixed-PERIOD sampling anchor. vTaskDelay() below used to sleep
     * SAMPLING_INTERVAL_MS *after* the body finished, so the real period was
     * body_time + 100ms. With CONFIG_FREERTOS_HZ=100 the tick is 10ms, so any
     * non-zero body time pushed the wake to the next tick and the node sampled
     * at 110ms = 9.09Hz. Measured on the 2026-09-22 home capture: the root sat
     * at exactly 110.0ms median and scored 93.6% against validate_integrity.py's
     * 10Hz expectation -- the M5 "95% of expected samples" blocker. Nothing was
     * being dropped (longest gap in the whole run: 0.36s); the cadence was just
     * slower than nominal, and no node whose body takes >0ms could ever pass.
     *
     * xTaskDelayUntil() sleeps until anchor + period instead, so the body's
     * duration is absorbed and the period is a true SAMPLING_INTERVAL_MS. */
    TickType_t next_sample = xTaskGetTickCount();
    while (!phase_listener_is_terminated()) {
        int64_t ts = esp_timer_get_time();

        int rssi = 0;
        esp_wifi_sta_get_rssi(&rssi);
        int layer = mesh_setup_get_layer();
        uint8_t pmac[6] = {0};
        mesh_setup_get_parent_mac(pmac);

        uint32_t retry_col, tx_col, probes_col;
        if (is_b()) {
            retry_col  = s_probes_tunneled;   /* attack-phase tunnel count */
            tx_col     = s_probes_to_root;    /* direct sends              */
            probes_col = s_probes_generated;
        } else {
            retry_col  = s_reinject_fail;
            tx_col     = s_probes_reinjected; /* re-injected to root       */
            probes_col = s_tunnel_received;   /* received from B           */
        }
        /* C7 Option 1: recv/forward/drop mean MESH RELAY on every role,
         * identically. Each end's TUNNEL activity stays in the three columns
         * above, where the Tunnel* features read it - keeping the two
         * measurements separate is what stops the relay columns meaning
         * something different on this board. */
        uint32_t recv_col = probe_relay_recv_count();
        uint32_t fwd_col  = probe_relay_forward_count();
        uint32_t drop_col = probe_relay_drop_count();

        csv_logger_append_telemetry(
            ts,
            s_node_id,
            role_csv_str(),
            layer,
            pmac,
            rssi,
            retry_col,
            tx_col,
            probes_col,
            phase_listener_get_phase_id(),
            phase_listener_get_label(),
            recv_col,
            fwd_col,
            drop_col
        );

        ESP_LOGD(TAG, "Sample: ts=%lld rssi=%d layer=%d phase=%u label=%u "
                      "retry=%lu tx=%lu probes=%lu",
                 (long long)ts, rssi, layer,
                 phase_listener_get_phase_id(), phase_listener_get_label(),
                 (unsigned long)retry_col, (unsigned long)tx_col,
                 (unsigned long)probes_col);

        xTaskDelayUntil(&next_sample, pdMS_TO_TICKS(SAMPLING_INTERVAL_MS));
    }
    ESP_LOGI(TAG, "Telemetry task exiting.");
    vTaskDelete(NULL);
}

/* ── Utility ─────────────────────────────────────────────────────────────── */

static void build_run_id(char *buf, size_t len)
{
    nvs_handle_t h;
    uint32_t run_num = 0;

    esp_err_t err = nvs_open("nis16", NVS_READWRITE, &h);
    if (err == ESP_OK) {
        nvs_get_u32(h, "run_num", &run_num);
        run_num++;
        nvs_set_u32(h, "run_num", run_num);
        nvs_commit(h);
        nvs_close(h);
    } else {
        run_num = (uint32_t)(esp_timer_get_time() / 1000000LL);
    }
    snprintf(buf, len, "RUN_%03lu", (unsigned long)run_num);
}
