/**
 * @file mesh_setup.c
 * @brief ESP-WIFI-MESH initialisation — common module.
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#include "health_log.h"
#include "mesh_setup.h"
#include "mesh_config.h"
#include "mesh_messages.h"
#include "node_identity.h"
#include "phase_listener.h"
#include "csv_logger.h"
#include "topology_graph.h"
#include "blackhole_target.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"

#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_mac.h"
#include "esp_event.h"
#include "esp_mesh.h"
#include "esp_mesh_internal.h"   /* parent-switch / RSSI thresholds (D-26) */
#include "esp_netif.h"
#include "esp_timer.h"
#include "nvs_flash.h"

/* ── D-26 STICKY PARENTS (tree only, oct. 19 2026) ───────────────────────── *
 * TREE is the only topology where ESP-MESH picks and changes parents by itself
 * (linear / star / partial pin them). With the stock thresholds a child starts
 * hunting for a "better" parent once its parent's RSSI drops into the -78 /
 * -82 / -85 dBm bands - and the campaign's links sit at a median of -71 to
 * -76 dBm with many boards below -78, so tree children changed parent mid-run
 * (verification #55). These shift ESP-MESH's OWN keep/switch defaults (read at
 * boot, never hard-coded absolutes) by STICKY_PARENT_DB dB weaker and make the
 * weak-link watch STICKY_PARENT_DURATION_X times longer - parent SELECTION
 * (select_rssi, RSSI bands) stays stock, see the call site: a child keeps its parent unless
 * the link is really bad for a long time. A parent that crashes / leaves still
 * makes its children move (that is the mesh healing itself, D-23).
 * Override any of these in mesh_config.h; TREE_STICKY_PARENTS 0 = stock ESP-MESH. */
#ifndef TREE_STICKY_PARENTS
#define TREE_STICKY_PARENTS        1
#endif
#ifndef STICKY_PARENT_DB
#define STICKY_PARENT_DB           6     /* dB the switch / weak thresholds move down */
#endif
#ifndef STICKY_PARENT_DURATION_X
#define STICKY_PARENT_DURATION_X   3     /* weak-link watch window multiplier          */
#endif

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "MESH_SETUP";

#define MESH_CONNECTED_BIT  BIT0
static EventGroupHandle_t s_mesh_event_group = NULL;

static mesh_node_role_t s_role    = MESH_ROLE_VICTIM;
static char   s_node_id[NODE_ID_LEN] = {0};
static bool   s_is_root           = false;

/* Heartbeat table readiness (root only — set by heartbeat_table_init(), see
 * the Command Center heartbeat section further down). Declared up here, not
 * down with the rest of that section's state, because mesh_event_handler's
 * MESH_EVENT_ROUTING_TABLE_REMOVE case reads it and that handler is defined
 * before the heartbeat section in this file. */
static bool s_table_ready = false;

/* ── Forward declarations ────────────────────────────────────────────────── */
static void mesh_event_handler(void *arg, esp_event_base_t base,
                                int32_t id, void *data);
static void ip_event_handler(void *arg, esp_event_base_t base,
                              int32_t id, void *data);
static void build_node_id(void);
static void log_mesh_status(void);
static void apply_rf_width(const char *when, bool only_if_ht40);
/* Declared this early (defs live down in the heartbeat section) so
 * mesh_event_handler can call them for instant disconnect reporting instead
 * of waiting on the heartbeat table's own staleness timer — see the
 * MESH_EVENT_CHILD_DISCONNECTED / MESH_EVENT_ROUTING_TABLE_REMOVE cases. */
static void heartbeat_table_print(void);
static void heartbeat_request_print(void);

/* Root: wormhole tunnel tests that arrived (mesh_setup_note_tunnel_test). */
static volatile uint32_t s_tuntest_count   = 0;
static volatile int64_t  s_tuntest_last_us = 0;
static void heartbeat_mark_offline(const uint8_t mac[6]);

/* ── STAR + BLACKHOLE: the attacker is the star's HUB (thesis-deviate D-16) ──
 * Thesis §4.2.2.1 (Fig. 4.17) makes the central node the blackhole. Our root
 * cannot be it: with no router the root is the probes' DESTINATION (nothing to
 * forward onward), it runs the phases, and PDR is measured there. And a plain
 * star (max layer 2) leaves a layer-2 attacker with no children, so nothing
 * ever transits it. So in this one build the star is rebuilt one hop down:
 *
 *     root (sink/referee) -> ATTACKER (hub, layer 2) -> every victim (layer 3)
 *
 * Victims do not self-organise here: they scan for the attacker's mesh SoftAP
 * (its STA MAC + 1, from blackhole_target_get) and pin it as their parent with
 * esp_mesh_set_parent() - the sequence of IDF's examples/mesh/manual_networking.
 * A victim that cannot find it keeps scanning and never joins the root
 * directly: a victim above the attacker would be a silent bystander. The root's
 * roster gate then holds Phase 0, so a wrong attacker MAC shows up before the
 * run instead of as an attack with no victims. The root and the attacker
 * self-organise as usual; only max_layer changes for them (2 -> 3). */
#define STAR_HUB_BLACKHOLE \
    (MESH_TOPOLOGY == NIS_TOPO_STAR && ACTIVE_ATTACK == PHASE_ID_BLACKHOLE)

/* ── STAR + WORMHOLE: wormhole end A is the star's HUB (thesis-deviate D-28) ──
 * A plain star puts every child 1 hop from the root, so both wormhole ends sit
 * at the same depth and the tunnel skips nothing (root: "SAME DEPTH", checklist
 * A24). Same fix as D-16, one hop down:
 *
 *     root (sink/referee) -> NODE A (hub, layer 2) -> every other board (layer 3)
 *
 * so B's normal copy takes 2 hops (B -> A -> root) and the tunnelled copy 1
 * (B =UART=> A -> root). The hub MAC comes from the same source as the
 * blackhole attacker (blackhole_target_get: run.ps1 -AttackerMac = the preset's
 * A board). Every non-root board that is NOT the hub pins it - B and the
 * controls alike; the hub itself self-organises and can only reach the root.
 * Auto-switch (wormhole_victim.c) then makes the hub A by itself: it is the
 * shallower end. */
#define STAR_HUB_WORMHOLE \
    (MESH_TOPOLOGY == NIS_TOPO_STAR && ACTIVE_ATTACK == PHASE_ID_WORMHOLE)
#define STAR_HUB (STAR_HUB_BLACKHOLE || STAR_HUB_WORMHOLE)
#if STAR_HUB_BLACKHOLE
#define STAR_HUB_WHO "attacker"
#else
#define STAR_HUB_WHO "wormhole A"
#endif

/* ── TREE / PARTIAL + WORMHOLE: end B never joins the root (thesis-deviate D-30) ──
 * Both tunnel ends hang off one UART cable, so they usually sit side by side
 * and ESP-MESH puts BOTH at H01 (it takes the shallowest parent it can still
 * hear): same depth, the tunnel skips nothing, and auto-switch cannot help (it
 * only renames the ends by depth). So the board FLASHED as B (preset's B row,
 * -DWORMHOLE_END=1 -> mesh_setup_init(MESH_ROLE_ATCK_WB)) does not
 * self-organise: it scans and pins the strongest mesh AP that is NOT the root
 * (layer >= 2), so it lands at H02 or deeper. Every other board forms the
 * tree as usual.
 *
 * Same depth was still possible (oct. 19 audit): A sits next to B, so A could
 * also end up under a child (A H02 + B H02), and in partial the root takes only
 * 2 children, so A may find it full. Hence two more rules, both before Phase 0:
 *   - the board FLASHED as A pins the SHALLOWEST open parent it hears well
 *     enough (WH_PIN_MIN_RSSI) - the root whenever it has room;
 *   - B's parent must be at least as deep as A (A's layer comes from its UART
 *     HELLO, mesh_setup_wormhole_peer_layer), so B is always >= 1 hop deeper,
 *     and B re-picks by itself if A moves and the depths meet (rate-limited).
 *
 * oct. 22 2026: "at least as deep as A" still let B pick A ITSELF (A at H01 is
 * layer 2 = the minimum), and A is always the loudest AP B hears - so B landed
 * under A on every attempt (A H01 -> B H02, B's normal copy relayed by A only).
 * B now also refuses A's mesh AP (A's STA MAC from the HELLO, + 1) and re-picks
 * if it already sits under A, so B always hangs under a VICTIM. TREE only:
 * partial keeps the oct. 19 rules unchanged. */
#define WH_B_NO_ROOT \
    (ACTIVE_ATTACK == PHASE_ID_WORMHOLE && \
     (MESH_TOPOLOGY == NIS_TOPO_TREE || MESH_TOPOLOGY == NIS_TOPO_PARTIAL))
#define WH_B_NOT_UNDER_A \
    (ACTIVE_ATTACK == PHASE_ID_WORMHOLE && MESH_TOPOLOGY == NIS_TOPO_TREE)
#define MANUAL_PARENT (STAR_HUB || WH_B_NO_ROOT)

#if MANUAL_PARENT
static bool     s_pin_to_hub  = false;  /* star: join ONLY s_hub_bssid                 */
static bool     s_pin_no_root = false;  /* wormhole B: strongest parent that is not root */
static bool     s_pin_shallow = false;  /* wormhole A: shallowest open parent (root first) */
static volatile int s_wh_peer_layer = 0;/* B: A's mesh layer from its HELLO (0 = unknown) */
static uint8_t  s_wh_peer_ap[6];        /* B: A's mesh SoftAP (STA MAC + 1) - never B's parent */
static volatile bool s_wh_peer_ap_known = false;
static volatile bool s_repick = false;  /* B: switch to a deeper parent on the next scan */
static int64_t  s_last_repick_us __attribute__((unused)) = 0;
#define WH_PIN_MIN_RSSI   (-85)         /* A: weaker parents only if nothing better       */
#define WH_REPICK_GAP_US  (15LL * 1000000LL)
static bool     s_have_parent = false;  /* own uplink (CONNECTED_BIT also covers children) */
static uint32_t s_parent_drops = 0;     /* drops since the last good join              */
static uint8_t  s_hub_bssid[6];
static uint32_t s_hub_scans  = 0;
static void star_hub_scan(void);
static void star_hub_scan_done(int num);
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t mesh_setup_init(mesh_node_role_t role)
{
    esp_err_t ret;
    s_role = role;

    /* ── 1. NVS ──────────────────────────────────────────────────────────── */
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* ── 2. TCP/IP + event loop ──────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    /* ── 3. Wi-Fi driver ─────────────────────────────────────────────────── */
    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_FLASH));
    /* Disable power-save before wifi_start so the mesh RSSI ladder
     * initialises correctly in routerless mode. */
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));

    /* ── 4. Event handlers ───────────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_event_handler_register(MESH_EVENT, ESP_EVENT_ANY_ID,
                                               mesh_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               ip_event_handler, NULL));

    /* ── 5. Node ID ──────────────────────────────────────────────────────── */
    build_node_id();

    /* ── 6. Wi-Fi start ──────────────────────────────────────────────────── */
    s_mesh_event_group = xEventGroupCreate();
#if MESH_FORCE_HT20
    /* Set 20 MHz BEFORE the radio starts, never after: forcing it after
     * esp_mesh_start() hit the scan/AP as they came up and no node joined
     * (sep. 23 2026). APSTA first so BOTH interfaces exist - in the default
     * mode the STA set fails with ESP_ERR_WIFI_IF and stays 40 MHz. The mesh
     * stack picks its own mode afterwards; the width is per-interface config
     * and carries over. The CONNECTED handlers re-check it (only_if_ht40). */
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    apply_rf_width("before wifi start", false);
#endif
    ESP_ERROR_CHECK(esp_wifi_start());

    /* ── 7. Mesh init ────────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_mesh_init());

    /*
     * M3 topology shaping (proposal §4.2.2 — all four deployment layouts).
     * Physical placement still does most of the work (the mesh self-organises by
     * RSSI); these knobs BIAS the stack toward the intended shape. Two levers:
     * max_layer (hop depth) and max_children (fan-out, applied to the mesh AP
     * config below). Defaults = NIS_TOPO_TREE = exact M1 behaviour.
     *
     *   STAR    (§4.2.2.1): cap depth at 2 → every node a direct child of root.
     *   TREE    (§4.2.2.2): native self-organising multi-hop tree (default).
     *   LINEAR  (§4.2.2.3): force a CHAIN + 1 child/node → hop-by-hop line.
     *   PARTIAL (§4.2.2.4): multi-hop like TREE but narrowed fan-out → nodes
     *                       branch across a subset of parents instead of all
     *                       crowding the root (adaptive partial-mesh shape).
     */
    /* max_layer here is the STRUCTURE (STAR) or the stack's own ceiling
     * (everything else) - never a board count. See mesh_config.h. */
    int max_layer    = MESH_STACK_MAX_LAYER_TREE;
    int max_children = MESH_MAX_CHILDREN;
    const char *topo_name = topo_kind_str((topo_kind_t)MESH_TOPOLOGY);
#if STAR_HUB
    max_layer = 3;                           /* root(L1) -> hub(L2) -> every other board(L3) */
    topo_name = STAR_HUB_BLACKHOLE ? "STAR (attacker hub)" : "STAR (wormhole A hub)";
#elif (MESH_TOPOLOGY == NIS_TOPO_STAR)
    max_layer = 2;                           /* structural: center(L1) + direct nodes(L2) */
#elif (MESH_TOPOLOGY == NIS_TOPO_LINEAR)
    ESP_ERROR_CHECK(esp_mesh_set_topology(MESH_TOPO_CHAIN));
    max_layer    = MESH_STACK_MAX_LAYER_CHAIN;
    max_children = MESH_LINEAR_MAX_CHILDREN; /* 1 child/node → strict chain     */
#elif (MESH_TOPOLOGY == NIS_TOPO_PARTIAL)
    max_children = MESH_PARTIAL_MAX_CHILDREN;/* narrowed fan-out → branched mesh */
#endif
    ESP_ERROR_CHECK(esp_mesh_set_max_layer(max_layer));
    ESP_LOGI(TAG, "Topology shaping: %s (max_layer=%d, max_children=%d)",
             topo_name, max_layer, max_children);

    ESP_ERROR_CHECK(esp_mesh_set_vote_percentage(1));
    ESP_ERROR_CHECK(esp_mesh_set_ap_assoc_expire(10));
    ESP_ERROR_CHECK(esp_mesh_disable_ps());

#if !MESH_USE_ROUTER
    /*
     * Routerless mesh setup — confirmed working sequence:
     *
     * ROOT:     fix_root(true) makes the stack skip the router-struct
     *           validation inside esp_mesh_set_config(), so router fields
     *           can stay zeroed. The root never tries to associate with
     *           any AP — it just sits ready for children.
     *
     * NON-ROOT: fix_root(false) alone does NOT skip router validation —
     *           confirmed by repeated testing. A non-empty dummy SSID
     *           is the only way to satisfy the validator without a real
     *           router. Non-root nodes never connect to this SSID; their
     *           uplink is chosen by mesh parent-selection scanning.
     *           (If the root also got this dummy SSID it would try to
     *           connect to it as a real AP and fail — reason-201 loop.)
     */
    if (role == MESH_ROLE_ROOT) {
        ESP_ERROR_CHECK(esp_mesh_fix_root(true));
        ESP_ERROR_CHECK(esp_mesh_set_self_organized(false, false));
        /* Mark this node as the active root so its mesh AP advertises as
         * available (idle:0) rather than idle (idle:1). Without this call
         * the root's AP is visible to children but refuses connections. */
        ESP_ERROR_CHECK(esp_mesh_set_type(MESH_ROOT));
    }
#endif

    /* ── 8. Mesh configuration ───────────────────────────────────────────── */
    mesh_cfg_t cfg;
    memset(&cfg, 0, sizeof(cfg));   /* MUST be zeroed — MESH_INIT_CONFIG_DEFAULT()
                                     * does not reliably clear all fields, leaving
                                     * garbage in the RSSI threshold array and
                                     * causing [parent]not found / rssi:0 loops.
                                     * See esp-idf issue #12193. */

    uint8_t mesh_id[] = MESH_ID;
    memcpy(cfg.mesh_id.addr, mesh_id, 6);
    cfg.mesh_ap.max_connection      = max_children;   /* per-topology fan-out */
    cfg.mesh_ap.nonmesh_max_connection = 0;
    memcpy(cfg.mesh_ap.password, MESH_PASSWORD, strlen(MESH_PASSWORD));

#if MESH_USE_ROUTER
    cfg.channel = 0;
    cfg.allow_channel_switch = false;
    cfg.router.ssid_len = strlen(ROUTER_SSID);
    memcpy(cfg.router.ssid,     ROUTER_SSID,    cfg.router.ssid_len);
    memcpy(cfg.router.password, ROUTER_PASSWORD, strlen(ROUTER_PASSWORD));
#else
    cfg.channel = MESH_CHANNEL;
    cfg.allow_channel_switch = false;

    if (role == MESH_ROLE_ROOT) {
        /* Router struct stays zeroed — fix_root(true) bypasses validation. */
        cfg.router.ssid_len = 0;
    } else {
        /* Dummy SSID to satisfy the validator on non-root nodes. */
        static const char dummy[] = "MESH_NO_ROUTER";
        cfg.router.ssid_len = strlen(dummy);
        memcpy(cfg.router.ssid, dummy, cfg.router.ssid_len);
    }
#endif

    ESP_ERROR_CHECK(esp_mesh_set_config(&cfg));

#if (MESH_TOPOLOGY == NIS_TOPO_TREE) && TREE_STICKY_PARENTS
    if (role != MESH_ROLE_ROOT) {
        /* D-26: shift ESP-MESH's own defaults - never fatal, every value logged.
         * ONLY the "keep / leave the parent I have" side. oct. 19 2026 (afternoon):
         * the first version also lowered select_rssi and the high/medium/low RSSI
         * bands - but those are what a board uses when it FIRST picks a parent, so
         * the root counted as "good enough" from 6 dB farther away, more boards
         * joined it directly, the tree went flat (depth 2, 'flat like a star' x37)
         * and the attacker-child gate waited 417 s. Selection is stock again. */
        mesh_switch_parent_t sp;
        if (esp_mesh_get_switch_parent_paras(&sp) == ESP_OK) {
            const mesh_switch_parent_t was = sp;
            sp.duration_ms *= STICKY_PARENT_DURATION_X;
            sp.cnx_rssi    -= STICKY_PARENT_DB;
            sp.switch_rssi -= STICKY_PARENT_DB;
            esp_err_t e = esp_mesh_set_switch_parent_paras(&sp);
            ESP_LOGW(TAG, "STICKY PARENTS (D-26): switch %s - watch %d->%d ms, keep %d->%d, "
                     "switch %d->%d dBm (parent SELECTION left stock: select %d dBm)",
                     e == ESP_OK ? "set" : esp_err_to_name(e),
                     (int)was.duration_ms, (int)sp.duration_ms, (int)was.cnx_rssi, (int)sp.cnx_rssi,
                     (int)was.switch_rssi, (int)sp.switch_rssi, (int)sp.select_rssi);
        }
    }
#endif

#if STAR_HUB
    /* Blackhole: only victims pin (the attacker is the hub). Wormhole: every
     * non-root board but the hub. */
    if (STAR_HUB_BLACKHOLE ? role == MESH_ROLE_VICTIM : role != MESH_ROLE_ROOT) {
        uint8_t atk[6];
        bh_target_source_t src = blackhole_target_get(atk);
        bool pin = true;
#if STAR_HUB_WORMHOLE
        /* Wormhole: both ends run one image, so the hub is told apart by MAC. */
        uint8_t me[6];
        esp_read_mac(me, ESP_MAC_WIFI_STA);
        pin = memcmp(me, atk, 6) != 0;
        if (!pin) {
            ESP_LOGW(TAG, "STAR HUB: this board IS the hub (wormhole A, %s) - it joins "
                     "the root; every other board joins it.", blackhole_target_source_str(src));
        }
#endif
        if (pin) {
            /* Mesh SoftAP BSSID = STA MAC + 1 (with carry), as in parent_mac. */
            memcpy(s_hub_bssid, atk, 6);
            for (int i = 5; i >= 0 && ++s_hub_bssid[i] == 0; i--) {
            }
            s_pin_to_hub = true;
            ESP_LOGW(TAG, "STAR HUB: this board joins ONLY the " STAR_HUB_WHO " hub " MACSTR
                     " (%s; its mesh AP " MACSTR "), never the root directly.",
                     MAC2STR(atk), blackhole_target_source_str(src), MAC2STR(s_hub_bssid));
        }
    }
#endif
#if WH_B_NO_ROOT
    if (role == MESH_ROLE_ATCK_WB) {
        s_pin_no_root = true;
        ESP_LOGW(TAG, "WORMHOLE B (D-30): this board never takes the ROOT as parent and "
                 "always sits deeper than A - it joins the strongest node at least as deep "
                 "as A, so the tunnel to A skips at least one hop.");
    } else if (role == MESH_ROLE_ATCK_WA) {
        s_pin_shallow = true;
        ESP_LOGW(TAG, "WORMHOLE A (D-30): this board joins the SHALLOWEST parent it hears "
                 "(the root whenever it has room), so it stays above B.");
    }
#endif

    /* Root only: a deeper mesh RX queue (must be set before esp_mesh_start).
     * Every probe in the mesh ends at the root, so it is the one node whose
     * queue fills under highload - see ROOT_MESH_XON_QSIZE. Not fatal: the
     * default 32 still works, only with less headroom. */
    if (role == MESH_ROLE_ROOT) {
        esp_err_t xe = esp_mesh_set_xon_qsize(ROOT_MESH_XON_QSIZE);
        if (xe == ESP_OK) {
            ESP_LOGI(TAG, "Root mesh RX queue: %d (default 32).", ROOT_MESH_XON_QSIZE);
        } else {
            ESP_LOGW(TAG, "esp_mesh_set_xon_qsize(%d) failed: %s - keeping the default 32.",
                     ROOT_MESH_XON_QSIZE, esp_err_to_name(xe));
        }
    }

    /* ── 9. Start mesh ───────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_mesh_start());
    /* No width change here - see "before wifi start" above. */

    ESP_LOGI(TAG, "Mesh started. Node ID: %s  Role: %d", s_node_id, (int)s_role);

    /* ESP-IDF's own mesh lib logs its internal retry/routing chatter at Info
     * level under tag "mesh" — both the pre-connect "[FIND] fail to find a
     * network ... look_for_nwk_count:N" loop a child spams every ~140 ms while
     * hunting for its parent/root, and later the routine forwarding noise
     * (e.g. "no route found, force to increase/decrease") once traffic starts,
     * worst under blackhole where routes keep failing. The library logs per-
     * retry, not per-state, so there's no vendor hook to say it once instead —
     * we say it ourselves, once, then mute the tag so the retries that follow
     * stay silent instead of spamming. esp_mesh_start() has already logged its
     * one-time nvs/IO/config/root-designation lines synchronously above this
     * point, so those still show as before. */
    if (role != MESH_ROLE_ROOT) {
        ESP_LOGI(TAG, "Searching for parent/root ... (retry log suppressed, connect/timeout banner below still prints)");
    }
    esp_log_level_set("mesh", ESP_LOG_WARN);

    /* ── 10. Wait for connection ─────────────────────────────────────────── */
    EventBits_t bits = xEventGroupWaitBits(
        s_mesh_event_group,
        MESH_CONNECTED_BIT,
        pdFALSE,
        pdFALSE,
        pdMS_TO_TICKS(PHASE_STABILISE_S * 1000)
    );

    if (bits & MESH_CONNECTED_BIT) {
        ESP_LOGI(TAG, "Mesh connected. Layer: %d  Root: %s",
                 esp_mesh_get_layer(),
                 s_is_root ? "YES" : "NO");
    } else {
        ESP_LOGW(TAG, "Mesh connection timeout after %u s — continuing anyway.",
                 PHASE_STABILISE_S);
    }

    return ESP_OK;
}

void mesh_setup_get_node_id(char *buf)
{
    strlcpy(buf, s_node_id, NODE_ID_LEN);
}

int mesh_setup_get_layer(void)
{
    return esp_mesh_get_layer();
}

bool mesh_setup_get_parent_mac(uint8_t mac[6])
{
    if (s_is_root) {
        memset(mac, 0, 6);
        return false;
    }
    mesh_addr_t parent = {0};
    if (esp_mesh_get_parent_bssid(&parent) == ESP_OK) {
        memcpy(mac, parent.addr, 6);
        return true;
    }
    memset(mac, 0, 6);
    return false;
}

bool mesh_setup_is_root(void)
{
    return s_is_root;
}

/* ── Private helpers ─────────────────────────────────────────────────────── */

static void build_node_id(void)
{
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_node_id, sizeof(s_node_id),
             "NODE_%02X%02X%02X%02X%02X%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

/* Distinct, greppable banner - separate from the wall of routine ESP_LOGI
 * mesh chatter, so "how many nodes are actually connected right now" is
 * readable at a glance in idf.py monitor instead of buried among hundreds
 * of [FIND]/routing-table lines. esp_mesh_get_routing_table_size() counts
 * this node PLUS every descendant it currently has a path to - so on the
 * root it is the whole mesh's live count; on a child it is usually 1
 * (itself) unless it has its own children in a deeper topology. */
/* Pin both interfaces to 20 MHz (see MESH_FORCE_HT20) and log what the radio
 * actually uses. Non-fatal on purpose: the mesh stack toggles STA / STA+AP
 * modes, so an interface can be disabled at call time (ESP_ERR_WIFI_IF). With
 * only_if_ht40, an interface already at 20 MHz is left alone - re-setting a
 * connected link for nothing isn't worth the risk of a renegotiation. */
static void apply_rf_width(const char *when, bool only_if_ht40)
{
#if MESH_FORCE_HT20
    const wifi_interface_t ifs[2] = { WIFI_IF_STA, WIFI_IF_AP };
    for (int i = 0; i < 2; i++) {
        wifi_bandwidth_t bw;
        if (only_if_ht40 &&
            (esp_wifi_get_bandwidth(ifs[i], &bw) != ESP_OK || bw != WIFI_BW_HT40)) {
            continue;
        }
        esp_err_t err = esp_wifi_set_bandwidth(ifs[i], WIFI_BW_HT20);
        if (only_if_ht40) {
            ESP_LOGW(TAG, "RF width: %s was back at 40 MHz (%s) - forced to 20 MHz: %s",
                     i ? "AP" : "STA", when, esp_err_to_name(err));
        }
    }
#endif
    wifi_bandwidth_t sta_bw = 0, ap_bw = 0;
    bool sta_ok = esp_wifi_get_bandwidth(WIFI_IF_STA, &sta_bw) == ESP_OK;
    bool ap_ok  = esp_wifi_get_bandwidth(WIFI_IF_AP, &ap_bw) == ESP_OK;
    uint8_t prim = 0;
    wifi_second_chan_t sec = WIFI_SECOND_CHAN_NONE;
    esp_wifi_get_channel(&prim, &sec);
    ESP_LOGI(TAG, "RF width (%s): STA %s, AP %s, channel %u%s", when,
             !sta_ok ? "off" : (sta_bw == WIFI_BW_HT40 ? "40 MHz" : "20 MHz"),
             !ap_ok  ? "off" : (ap_bw  == WIFI_BW_HT40 ? "40 MHz" : "20 MHz"),
             (unsigned)prim,
             sec == WIFI_SECOND_CHAN_NONE ? "" : " (+secondary 40 MHz half)");
}

static void log_mesh_status(void)
{
    int n = esp_mesh_get_routing_table_size();
    ESP_LOGI(TAG, "==============================");
    ESP_LOGI(TAG, "  MESH CONNECTED: %d node(s)", n);
    ESP_LOGI(TAG, "==============================");
}

static void mesh_event_handler(void *arg, esp_event_base_t base,
                                int32_t id, void *data)
{
    switch ((mesh_event_id_t)id) {

    case MESH_EVENT_STARTED:
        ESP_LOGI(TAG, "Mesh stack started.");
        s_is_root = false;
#if MANUAL_PARENT
        if (s_pin_to_hub || s_pin_no_root || s_pin_shallow) {
            ESP_ERROR_CHECK(esp_mesh_set_self_organized(false, false));
            star_hub_scan();
        }
#endif
        break;

#if MANUAL_PARENT
    case MESH_EVENT_SCAN_DONE:
        if (s_pin_to_hub || s_pin_no_root || s_pin_shallow) {
            star_hub_scan_done(((mesh_event_scan_done_t *)data)->number);
        }
        break;
#endif

    case MESH_EVENT_ROOT_ADDRESS: {
        mesh_event_root_address_t *ra = (mesh_event_root_address_t *)data;
        ESP_LOGI(TAG, "Root address: " MACSTR, MAC2STR(ra->addr));
        break;
    }

    case MESH_EVENT_PARENT_CONNECTED: {
        mesh_event_connected_t *ec = (mesh_event_connected_t *)data;
        int layer = ec->self_layer;
        s_is_root = (layer == MESH_ROOT);
        uint8_t pmac[6];
        memcpy(pmac, ec->connected.bssid, 6);
        ESP_LOGI(TAG, "Parent connected. Layer=%d  ParentMAC=" MACSTR "  IsRoot=%s",
                 layer, MAC2STR(pmac), s_is_root ? "YES" : "NO");
#if MANUAL_PARENT
        s_have_parent  = true;
        s_parent_drops = 0;
#endif
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        log_mesh_status();
        apply_rf_width("connected", true);
        break;
    }

    case MESH_EVENT_PARENT_DISCONNECTED: {
        mesh_event_disconnected_t *ed = (mesh_event_disconnected_t *)data;
        ESP_LOGW(TAG, "Parent disconnected — reason %d.", (int)ed->reason);
        s_is_root = false;
        xEventGroupClearBits(s_mesh_event_group, MESH_CONNECTED_BIT);
#if MANUAL_PARENT
        s_have_parent = false;
        /* The stack keeps retrying a pinned parent by itself; only a full AP
         * needs a fresh scan (as in IDF's manual_networking example). */
        if (s_pin_to_hub && ed->reason == WIFI_REASON_ASSOC_TOOMANY) {
            ESP_LOGW(TAG, "STAR HUB: the " STAR_HUB_WHO " hub's AP is full (max_connection) - rescanning.");
            star_hub_scan();
        }
        /* Wormhole B has no single fixed parent: a full AP, or a parent that
         * keeps failing (rebooted / moved away), means pick another one. */
        if ((s_pin_no_root || s_pin_shallow) &&
            (ed->reason == WIFI_REASON_ASSOC_TOOMANY || ++s_parent_drops >= 3)) {
            ESP_LOGW(TAG, "WORMHOLE %s (D-30): parent lost (reason %d) - looking for another "
                     "parent.", s_pin_no_root ? "B" : "A", (int)ed->reason);
            s_parent_drops = 0;
            star_hub_scan();
        }
#endif
        break;
    }

    case MESH_EVENT_CHILD_CONNECTED: {
        mesh_event_child_connected_t *cc = (mesh_event_child_connected_t *)data;
        ESP_LOGI(TAG, "Child connected: aid=%d MAC=" MACSTR,
                 (int)cc->aid, MAC2STR(cc->mac));
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        log_mesh_status();
        apply_rf_width("connected", true);
        break;
    }

    case MESH_EVENT_CHILD_DISCONNECTED: {
        mesh_event_child_disconnected_t *cd = (mesh_event_child_disconnected_t *)data;
        ESP_LOGI(TAG, "Child disconnected: aid=%d MAC=" MACSTR,
                 (int)cd->aid, MAC2STR(cd->mac));
        log_mesh_status();
        /* This is the one disconnect the mesh names a specific MAC for — a
         * node dropping straight off the ROOT. Evict + reprint right now
         * instead of waiting up to HEARTBEAT_STALE_MS (three missed
         * heartbeats) for the table's own staleness sweep to notice. A no-op
         * on any node other than the root (s_table_ready guard inside). */
        heartbeat_mark_offline(cd->mac);
        break;
    }

    case MESH_EVENT_ROUTING_TABLE_ADD:
        ESP_LOGI(TAG, "Routing table updated (node added).");
        log_mesh_status();
        break;

    case MESH_EVENT_ROUTING_TABLE_REMOVE:
        ESP_LOGI(TAG, "Routing table shrunk (node removed).");
        log_mesh_status();
        /* Unlike CHILD_DISCONNECTED this carries no MAC (just a table-size
         * delta), so it can't name which row to evict — but it DOES fire for
         * a multi-hop node dropping off deeper in the tree, which no other
         * event does (see heartbeat_table_print's own comment on this gap).
         * Forcing an immediate stale-sweep print here means a node that had
         * already crossed HEARTBEAT_STALE_MS gets reported the moment the
         * mesh notices, not up to HEARTBEAT_TABLE_REPRINT_MS later. It does
         * NOT shrink the staleness floor itself — three missed heartbeats is
         * still what tells a real drop apart from one lost frame. */
        heartbeat_request_print();
        break;

    case MESH_EVENT_ROOT_SWITCH_REQ:
        ESP_LOGI(TAG, "Root switch request received.");
        break;

    case MESH_EVENT_ROOT_SWITCH_ACK:
        ESP_LOGI(TAG, "Root switch acknowledged — now root.");
        s_is_root = true;
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        break;

    case MESH_EVENT_STOPPED:
        ESP_LOGW(TAG, "Mesh stack stopped.");
        break;

    default:
        ESP_LOGD(TAG, "Unhandled mesh event id=%d", (int)id);
        break;
    }
}

#if MANUAL_PARENT
static void star_hub_scan(void)
{
    wifi_scan_config_t sc = {0};
    sc.show_hidden = 1;                     /* mesh SoftAPs are hidden */
    sc.scan_type   = WIFI_SCAN_TYPE_PASSIVE;
    esp_wifi_scan_stop();
    esp_err_t err = esp_wifi_scan_start(&sc, false);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "STAR HUB: scan start failed: %s", esp_err_to_name(err));
    }
}

static void star_hub_scan_done(int num)
{
    static const uint8_t our_mesh[6] = MESH_ID;
    mesh_assoc_t assoc, hub_assoc = {0}, any_assoc = {0};
    wifi_ap_record_t rec, hub_rec = {0}, any_rec = {0};
    bool seen = false, joinable = false, root_only = false, too_shallow = false, any = false;
    bool a_seen = false, other_deep = false;/* B: A heard / another deep-enough AP heard */
    /* B's parent must sit at least as deep as A (layer units: root = 1). */
    const int min_layer = (s_wh_peer_layer > 2) ? s_wh_peer_layer : 2;

    /* Every record must be read out before the flush, match or not. */
    for (int i = 0; i < num; i++) {
        int ie_len = 0;
        esp_mesh_scan_get_ap_ie_len(&ie_len);
        esp_mesh_scan_get_ap_record(&rec, &assoc);
        if (ie_len != sizeof(assoc)) {
            continue;
        }
        /* An AP only takes children once it has joined the mesh, and while it has room. */
        bool open = assoc.mesh_type != MESH_IDLE && assoc.layer_cap && assoc.assoc < assoc.assoc_cap;
        if (s_pin_no_root) {
            /* Wormhole B: our mesh only, never the root, never shallower than A;
             * strongest wins. */
            if (memcmp(assoc.mesh_id, our_mesh, 6) != 0) {
                continue;
            }
            seen = true;
            if (assoc.layer < min_layer) {
                if (assoc.layer < 2) root_only = true;
                else                 too_shallow = true;
                continue;
            }
            if (s_wh_peer_ap_known && memcmp(rec.bssid, s_wh_peer_ap, 6) == 0) {
                a_seen = true;              /* never B's parent - see the D-30 note */
                continue;
            }
            other_deep = true;
            if (open && (!joinable || rec.rssi > hub_rec.rssi)) {
                joinable  = true;
                hub_rec   = rec;
                hub_assoc = assoc;
            }
            continue;
        }
        if (s_pin_shallow) {
            /* Wormhole A: shallowest open parent heard well enough, then the
             * strongest at that depth; if none is good enough, the strongest. */
            if (memcmp(assoc.mesh_id, our_mesh, 6) != 0 || !open) {
                continue;
            }
            seen = true;
            if (!any || rec.rssi > any_rec.rssi) {
                any = true; any_rec = rec; any_assoc = assoc;
            }
            if (rec.rssi >= WH_PIN_MIN_RSSI &&
                (!joinable || assoc.layer < hub_assoc.layer ||
                 (assoc.layer == hub_assoc.layer && rec.rssi > hub_rec.rssi))) {
                joinable = true; hub_rec = rec; hub_assoc = assoc;
            }
            continue;
        }
        if (memcmp(rec.bssid, s_hub_bssid, 6) != 0) {
            continue;
        }
        seen = true;
        if (open) {
            joinable  = true;
            hub_rec   = rec;
            hub_assoc = assoc;
        }
    }
    esp_mesh_flush_scan_result();
    if (s_pin_shallow && !joinable && any) {
        joinable = true; hub_rec = any_rec; hub_assoc = any_assoc;   /* weak, but in the mesh */
    }
    /* A rescan that lands after the join already succeeded: never re-pin.
     * Own uplink only - MESH_CONNECTED_BIT is also set by a child joining us.
     * Exception: B asked to move deeper than A (mesh_setup_wormhole_peer_layer). */
    bool repick = s_repick;
    s_repick = false;
    if (s_have_parent && !repick) {
        return;
    }
    if (s_have_parent) {
        uint8_t cur[6] = {0};
        mesh_setup_get_parent_mac(cur);
        if (!joinable || memcmp(cur, hub_rec.bssid, 6) == 0) {
            bool under_a = s_wh_peer_ap_known && memcmp(cur, s_wh_peer_ap, 6) == 0;
            ESP_LOGW(TAG, "WORMHOLE B (D-30): %s - staying. %s",
                     under_a ? "B is still UNDER A and no other victim is in reach"
                             : "no deeper parent than A in reach yet",
                     under_a ? "Put a victim (H01/H02) within reach of B; B moves on its own."
                             : "Move B away from A's parent (or a child next to B).");
            return;
        }
    }
    s_hub_scans++;

    if (!joinable && (s_pin_no_root || s_pin_shallow)) {
        if (s_hub_scans == 1 || s_hub_scans % 10 == 0) {
            if (s_pin_no_root) {
                ESP_LOGW(TAG, "WORMHOLE B (D-30): scan %lu - no parent deeper than A yet (%s). "
                         "Waiting: another board must be in the mesh within reach of B "
                         "(move a child, not A, closer to B).", (unsigned long)s_hub_scans,
                         !seen ? "no mesh node heard"
                         : a_seen && !other_deep && !too_shallow ? "only A itself is in reach - B never joins A"
                         : root_only && !too_shallow ? "only the root is in reach"
                         : too_shallow ? "only nodes as shallow as A are in reach" : "the ones in reach are full");
            } else {
                ESP_LOGW(TAG, "WORMHOLE A (D-30): scan %lu - no open parent heard yet (%s).",
                         (unsigned long)s_hub_scans, seen ? "all full" : "no mesh node heard");
            }
        }
        star_hub_scan();
        return;
    }
    if (!joinable) {
        /* Once, then every 10th scan - a missing attacker must be loud but
         * not flood the monitor. */
        if (s_hub_scans == 1 || s_hub_scans % 10 == 0) {
            ESP_LOGW(TAG, "STAR HUB: scan %lu - " STAR_HUB_WHO " hub AP " MACSTR " %s. Waiting "
                     "(check the " STAR_HUB_WHO " board is powered + in the mesh, and the "
                     "run's -AttackerMac / SET_ATTACKER_MAC names it).",
                     (unsigned long)s_hub_scans, MAC2STR(s_hub_bssid),
                     seen ? "seen but not joinable yet (not in the mesh / full)"
                          : "not seen");
        }
        star_hub_scan();
        return;
    }

    wifi_config_t parent = {0};
    parent.sta.channel   = hub_rec.primary;
    memcpy(parent.sta.ssid, hub_rec.ssid, sizeof(hub_rec.ssid));
    parent.sta.bssid_set = 1;
    memcpy(parent.sta.bssid, hub_rec.bssid, 6);
    esp_mesh_set_ap_authmode(hub_rec.authmode);
    if (hub_rec.authmode != WIFI_AUTH_OPEN) {
        memcpy(parent.sta.password, MESH_PASSWORD, strlen(MESH_PASSWORD));
    }
    mesh_type_t my_type = (hub_assoc.layer_cap != 1) ? MESH_NODE : MESH_LEAF;
    int my_layer = hub_assoc.layer + 1;
    ESP_LOGW(TAG, "%s " MACSTR " (layer %d, rssi %d, ch %u) as layer %d.",
             s_pin_no_root ? (repick ? "WORMHOLE B (D-30): moving deeper than A, to"
                                     : "WORMHOLE B (D-30): joining non-root parent")
             : s_pin_shallow ? "WORMHOLE A (D-30): joining shallowest parent"
                             : "STAR HUB: joining " STAR_HUB_WHO,
             MAC2STR(hub_rec.bssid), hub_assoc.layer, hub_rec.rssi,
             (unsigned)hub_rec.primary, my_layer);
    /* Not ESP_ERROR_CHECK: a refused parent is a retry, not a reboot. */
    esp_err_t err = esp_mesh_set_parent(&parent, (mesh_addr_t *)&hub_assoc.mesh_id,
                                        my_type, my_layer);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "%s: esp_mesh_set_parent failed (%s) - rescanning.",
                 s_pin_no_root ? "WORMHOLE B" : s_pin_shallow ? "WORMHOLE A" : "STAR HUB",
                 esp_err_to_name(err));
        star_hub_scan();
    }
}
#endif

static void ip_event_handler(void *arg, esp_event_base_t base,
                              int32_t id, void *data)
{
    if (id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = (ip_event_got_ip_t *)data;
        ESP_LOGI(TAG, "Root got IP: " IPSTR, IP2STR(&ev->ip_info.ip));
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
 * Command Center heartbeat — sender (every node) + root-side node table
 *
 * mesh_messages.h/node_identity.h already defined the wire format
 * (node_heartbeat_pkt_t) and a "call heartbeat_start()" note for this — it
 * just didn't exist yet. Lives here (not a separate module) because it's
 * fundamentally an extension of "what does mesh_setup know about the mesh's
 * shape": log_mesh_status() above already answers "how many nodes"; this
 * answers "which ones, at what layer" — the per-node detail needed to tell
 * whether the connected nodes are actually following the built topology.
 *
 * NIS16 — CTTHES3 — Command Center
 * ═══════════════════════════════════════════════════════════════════════════ */

/* s_table_ready itself now lives up in the module-private state block at the
 * top of the file (mesh_event_handler's ROUTING_TABLE_REMOVE case needs to
 * read it, and that's defined well before this section). Only the node that
 * called heartbeat_table_init() (the root, from root_main) owns a node
 * table. Gating on this rather than on mesh_setup_is_root(): that flag is
 * only set by MESH_EVENT_PARENT_CONNECTED, which a fixed root in a
 * routerless mesh never receives. */

/* Reset by every table print, change-triggered ones included, so a periodic
 * print never lands right on top of one a change just produced. */
static int64_t s_last_print_us = 0;

/* The heartbeat task does every table print that doesn't already run on a
 * roomy stack. mesh_event_handler runs on the system event task (2304 bytes
 * in this sdkconfig) - too small to also build the graph, render the tree
 * and validate it - so it only asks for a print (heartbeat_request_print). */
static TaskHandle_t s_heartbeat_task = NULL;

static void heartbeat_request_print(void)
{
    if (s_table_ready && s_heartbeat_task) {
        xTaskNotifyGive(s_heartbeat_task);
    }
}

static void heartbeat_task(void *arg)
{
    (void)arg;

    node_heartbeat_pkt_t pkt = {
        .magic    = HEARTBEAT_MSG_MAGIC,
        .msg_type = MSG_TYPE_HEARTBEAT,
    };
    esp_read_mac(pkt.src_mac, ESP_MAC_WIFI_STA);
    strlcpy(pkt.nickname, node_identity_nickname(), NODE_NICKNAME_LEN);
    pkt.assigned_role  = node_identity_role();
    pkt.export_status  = EXPORT_STATUS_IDLE;
    pkt.export_percent = 0;

    mesh_data_t mdata = {
        .data  = (uint8_t *)&pkt,
        .size  = sizeof(pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };

    int64_t boot_us = esp_timer_get_time();

    ESP_LOGI(TAG, "Heartbeat sender running at %u ms interval.",
             HEARTBEAT_INTERVAL_MS);

    int64_t next_send_us = 0;
    int     final_sends  = 0;

    while (true) {
        /* The table owner is the root even when s_is_root was never set
         * (a fixed routerless root gets no PARENT_CONNECTED event). */
        bool owns_table = mesh_setup_is_root() || s_table_ready;
        bool log_closed = csv_logger_is_closed();

        /* CLEAN STOP for child nodes once the experiment is over.
         *
         * Everything else a child runs already ends itself at TERMINATE:
         * probe_gen_task and telemetry_task both loop on
         * phase_listener_is_terminated(), and relay_task parks on an empty
         * queue. This task did not — it is timer-driven, so it kept putting a
         * mesh packet on the air every HEARTBEAT_INTERVAL_MS forever after the
         * run had finished, which is radio traffic and power spent on an
         * experiment that is over.
         *
         * The ROOT deliberately keeps beating: it owns the member table and is
         * the node the operator still watches after a run. A child leaving is
         * safe for that table — this is an APP-level packet, so stopping it
         * does not leave the mesh or drop the ESP-MESH association, and the
         * board stays reachable over USB for LIST_SD / EXPORT_SD_PATH /
         * SET_LOCATION exactly as before.
         *
         * Before going quiet, a child waits for its log to CLOSE and then sends
         * HEARTBEAT_FINAL_SENDS beats with export_status = LOG_CLOSED, so the
         * root's dashboard can say "safe to export" for it. The root keeps that
         * row instead of aging it out (heartbeat_table_print). If the log never
         * closes, the child keeps beating as a still-running node, which is
         * what it is. */
        if (phase_listener_is_terminated() && !owns_table && log_closed
                && final_sends >= HEARTBEAT_FINAL_SENDS) {
            ESP_LOGI(TAG, "Heartbeat task exiting - log closed and reported (child node); "
                          "the board stays up for serial export commands.");
            vTaskDelete(NULL);
        }
        if (esp_timer_get_time() >= next_send_us) {
            bool is_root = mesh_setup_is_root();
            /* The table owner is the root even when s_is_root was never set
             * (a fixed routerless root gets no PARENT_CONNECTED event). */
            bool no_parent = is_root || s_table_ready || esp_mesh_is_root();

            int8_t rssi = 0;
            memset(pkt.parent_mac, 0, sizeof(pkt.parent_mac));
            if (!no_parent && mesh_setup_get_parent_mac(pkt.parent_mac)) {
                int r = 0;
                esp_wifi_sta_get_rssi(&r);
                rssi = (int8_t)r;
            }

            pkt.parent_rssi   = rssi;
            pkt.layer         = (int16_t)mesh_setup_get_layer();
            pkt.uptime_sec    = (uint32_t)((esp_timer_get_time() - boot_us) / 1000000LL);
            pkt.current_phase = phase_listener_get_phase_id();
            pkt.export_status = log_closed ? EXPORT_STATUS_LOG_CLOSED
                                           : EXPORT_STATUS_IDLE;
            pkt.wh_link       = node_identity_wh_link();
            pkt.sd_log        = csv_logger_sd_state();

            /* Mirrors phase_listener_broadcast()'s root self-loopback (FROMDS) vs
             * a non-root node's upward send (TODS) — see the routerless-mesh
             * comments earlier in this file. */
            esp_err_t err = esp_mesh_send(NULL, &mdata,
                                          is_root ? MESH_DATA_FROMDS : MESH_DATA_TODS,
                                          NULL, 0);
            if (err != ESP_OK) {
                ESP_LOGD(TAG, "Heartbeat send failed: %s", esp_err_to_name(err));
            }

            if (s_table_ready) {
                /* Feed our own row in locally instead of relying on the send above
                 * looping back — the root's row would otherwise age out forever. */
                heartbeat_ingest((const uint8_t *)&pkt, sizeof(pkt));

                if (esp_timer_get_time() - s_last_print_us >=
                        (int64_t)HEARTBEAT_TABLE_REPRINT_MS * 1000) {
                    heartbeat_table_print();
                }
            }
            /* A child's closing beats go out 1 s apart, so one lost frame
             * doesn't leave the root without the "log closed" report. */
            uint32_t gap_ms = HEARTBEAT_INTERVAL_MS;
            if (log_closed && !owns_table && phase_listener_is_terminated()) {
                final_sends++;
                gap_ms = 1000;
            }
            next_send_us = esp_timer_get_time() + (int64_t)gap_ms * 1000;
        }

        int64_t wait_us = next_send_us - esp_timer_get_time();
        TickType_t wait = wait_us > 0 ? pdMS_TO_TICKS(wait_us / 1000) : 0;
        if (ulTaskNotifyTake(pdTRUE, wait) > 0) {
            heartbeat_table_print();
        }
    }
}

esp_err_t heartbeat_start(void)
{
    /* every board calls this once - the [HEALTH] serial line rides along (oct. 18
     * 2026, crash diagnosis C12 / D9; not fatal if it cannot start) */
    (void)health_log_start();
    BaseType_t rc = xTaskCreate(heartbeat_task, "heartbeat",
                                STACK_HEARTBEAT, NULL,
                                TASK_PRIO_HEARTBEAT, &s_heartbeat_task);
    if (rc != pdPASS) {
        ESP_LOGE(TAG, "Failed to create heartbeat task");
        return ESP_FAIL;
    }
    return ESP_OK;
}

/* ── Root-side node table ────────────────────────────────────────────────── */

/* Grows with the mesh - no node cap. Every access holds s_table_mutex: rows
 * are added from the phase-listener task, evicted from the system event task,
 * and printed from the heartbeat task, and a realloc under a concurrent reader
 * would be a use-after-free. Recursive, because ingest prints while already
 * holding it. */
typedef struct {
    uint8_t  mac[6];
    uint8_t  parent_mac[6];   /* parent's SoftAP BSSID; all-zero = no parent  */
    char     nickname[NODE_NICKNAME_LEN];
    uint8_t  role;
    int16_t  layer;           /* as the node's OWN stack reported it           */
    int8_t   parent_rssi;
    uint32_t uptime_sec;
    uint8_t  current_phase;
    uint8_t  export_status;   /* EXPORT_STATUS_LOG_CLOSED = safe to export     */
    uint8_t  wh_link;         /* wh_link_t: wormhole end's UART link state     */
    uint8_t  sd_log;          /* sd_log_state_t: is its SD card taking rows    */
    int64_t  last_seen_us;
    uint8_t *seen_parents;    /* PARTIAL only: every distinct parent observed  */
    size_t   seen_count;
} heartbeat_entry_t;

static heartbeat_entry_t *s_nodes      = NULL;
static size_t             s_node_count = 0;
static size_t             s_node_cap   = 0;
static SemaphoreHandle_t  s_table_mutex = NULL;

/* A wormhole end's UART link (heartbeat wh_link), as the dashboard prints it. */
static const char *wh_link_str(uint8_t s)
{
    switch (s) {
        case WH_LINK_OK:      return "UART OK";
        case WH_LINK_NONE:    return "UART NO SIGNAL";
        case WH_LINK_LOST:    return "UART LOST";
        case WH_LINK_WAITING: return "UART checking";
        case WH_LINK_ONEWAY:  return "UART ONE-WAY";
        case WH_LINK_ECHO:    return "UART ECHO (own TX->RX)";
        default:              return "UART ? (old fw)";
    }
}

static bool wh_link_bad(uint8_t s)
{
    return s == WH_LINK_NONE || s == WH_LINK_LOST || s == WH_LINK_ONEWAY || s == WH_LINK_ECHO;
}

static void table_lock(void)   { xSemaphoreTakeRecursive(s_table_mutex, portMAX_DELAY); }
static void table_unlock(void) { xSemaphoreGiveRecursive(s_table_mutex); }

static void entry_remove(size_t i)
{
    free(s_nodes[i].seen_parents);
    s_nodes[i] = s_nodes[s_node_count - 1];
    s_node_count--;
}

static heartbeat_entry_t *entry_add(const uint8_t mac[6])
{
    if (s_node_count == s_node_cap) {
        size_t cap = s_node_cap ? s_node_cap * 2 : 8;
        heartbeat_entry_t *grown = realloc(s_nodes, cap * sizeof(*grown));
        if (!grown) {
            return NULL;
        }
        s_nodes = grown;
        s_node_cap = cap;
    }
    heartbeat_entry_t *e = &s_nodes[s_node_count++];
    memset(e, 0, sizeof(*e));
    memcpy(e->mac, mac, 6);
    return e;
}

#if (MESH_TOPOLOGY == NIS_TOPO_PARTIAL)
/* A partial mesh is defined by nodes having alternative parents over time, so
 * the root remembers every distinct parent each node has reported. */
static void entry_note_parent(heartbeat_entry_t *e)
{
    static const uint8_t zero[6] = {0};
    if (memcmp(e->parent_mac, zero, 6) == 0) {
        return;
    }
    for (size_t k = 0; k < e->seen_count; k++) {
        if (memcmp(e->seen_parents + 6 * k, e->parent_mac, 6) == 0) {
            return;
        }
    }
    uint8_t *grown = realloc(e->seen_parents, 6 * (e->seen_count + 1));
    if (!grown) {
        return;
    }
    memcpy(grown + 6 * e->seen_count, e->parent_mac, 6);
    e->seen_parents = grown;
    e->seen_count++;
}
#endif

/* qsort has no context argument; only ever read under s_table_mutex. */
static const topo_graph_t *s_sort_graph = NULL;

static int order_cmp(const void *pa, const void *pb)
{
    int a = *(const int *)pa, b = *(const int *)pb;
    int la = s_sort_graph->layer[a] > 0 ? s_sort_graph->layer[a] : 0x7fffffff;
    int lb = s_sort_graph->layer[b] > 0 ? s_sort_graph->layer[b] : 0x7fffffff;
    if (la != lb) {
        return la < lb ? -1 : 1;
    }
    return memcmp(s_nodes[a].mac, s_nodes[b].mac, 6);
}

/* ── Table rendering ─────────────────────────────────────────────────────────
 * Protocol-dump style: fixed columns, uppercase MACs, hex identifiers/counters
 * (layer, phase ID, node/layer counts), decimal for measurements (RSSI dBm,
 * age in seconds). No width is fixed in advance - every column is sized from
 * the rows being printed, so 8 nodes and 1000 nodes both stay aligned. */

#define MACSTR_UC  "%02X:%02X:%02X:%02X:%02X:%02X"
#define MAC_NONE   "--:--:--:--:--:--"
#define MAC_W      17

/* Hex digits needed for v, at least 2 so small values read as 0x01 / L01. */
static int hex_width(unsigned v)
{
    int d = 1;
    while (v >>= 4) {
        d++;
    }
    return d < 2 ? 2 : d;
}

static const char *phase_id_str(uint8_t id)
{
    switch (id) {
    case PHASE_ID_BASELINE:  return "BASELINE";
    case PHASE_ID_BLACKHOLE: return "BLACKHOLE";
    case PHASE_ID_WORMHOLE:  return "WORMHOLE";
    case PHASE_ID_COOLDOWN:  return "COOLDOWN";
    case PHASE_ID_TERMINATE: return "TERMINATE";
    /* Distinct from UNKNOWN on purpose: UNSET is an expected, correct state
     * (no phase broadcast heard yet), and on the live heartbeat table it is
     * the fastest way to see that a node is up but the root is not driving it
     * yet. UNKNOWN stays for a genuinely out-of-range value. */
    case PHASE_ID_UNSET:     return "UNSET";
    default:                 return "UNKNOWN";
    }
}

/* "H00" for the root, "H01" for its children, ... or "H--" (same width) for a
 * node not reachable from the root.
 *
 * WHY HOP AND NOT LAYER (adviser, sep. 22, 2026): "layer" reads as an OSI layer
 * to anyone taught the OSI model, and this number is nothing of the sort -
 * ESP-WIFI-MESH runs BELOW IP and this is a node's depth in the mesh TREE.
 *
 * The OFF-BY-ONE is deliberate and must stay: ESP-WIFI-MESH numbers the ROOT as
 * layer 1, so hop = layer - 1 and the root is 0 hops from itself. That is the
 * same conversion analysis/preprocess.py:768 already applies when it derives the
 * `hop` column (D-11), so this console now agrees with the dataset and the paper
 * instead of being one off from both. */
static void fmt_hop(char *buf, size_t len, int layer, int w)
{
    if (layer > 0) {
        snprintf(buf, len, "H%0*X", w, (unsigned)(layer - 1));
    } else {
        snprintf(buf, len, "H%.*s", w, "--------");
    }
}

static void log_rule(char ch, int width)
{
    char line[161];
    if (width > (int)sizeof(line) - 1) {
        width = (int)sizeof(line) - 1;
    }
    memset(line, ch, (size_t)width);
    line[width] = '\0';
    ESP_LOGI(TAG, "%s", line);
}

typedef struct {
    const topo_graph_t *g;
    int lyr_w;     /* hex digits in the layer ID  */
    int role_w;
    int cnt_w;     /* hex digits in counters      */
} tree_fmt_t;

/* One row per node in depth-first order from the root, so each node follows
 * its parent. UPLINK names the resolved parent and DN its child count, which
 * states the structure explicitly instead of by indentation. The printed
 * layer is always the real one (depth + 1). */
static void tree_line_cb(void *ctx, int idx, int depth)
{
    const tree_fmt_t *f = (const tree_fmt_t *)ctx;
    const heartbeat_entry_t *e = &s_nodes[idx];
    char lyr[16];
    fmt_hop(lyr, sizeof(lyr), depth + 1, f->lyr_w);
    int p = f->g->parent[idx];
    char uplink[MAC_W + 1];
    if (p >= 0) {
        const uint8_t *m = s_nodes[p].mac;
        snprintf(uplink, sizeof(uplink), MACSTR_UC, MAC2STR(m));
    } else {
        strlcpy(uplink, MAC_NONE, sizeof(uplink));
    }
    ESP_LOGI(TAG, " %-*s  " MACSTR_UC "  %-*s  %s  0x%0*X",
             f->lyr_w + 2, lyr, MAC2STR(e->mac),
             f->role_w, node_role_to_str(e->role),
             uplink, f->cnt_w, (unsigned)f->g->child_count[idx]);
}

/* Levels drawn with connectors. ESP-WIFI-MESH caps at 25 layers; anything
 * deeper than this keeps printing, just without further indentation. */
#define TREE_ART_MAX_DEPTH 16

typedef struct {
    const topo_graph_t *g;
    int  lyr_w;
    int  role_w;
    /* last[d] = the node at depth d on the path currently being walked is its
     * parent's LAST child, so its column carries no more branches below it.
     * topo_walk() is depth-first pre-order, so by the time a node at depth d is
     * drawn, entries 1..d-1 already describe its own ancestors. */
    bool last[TREE_ART_MAX_DEPTH + 1];
} art_fmt_t;

/* ADDITIONAL view, printed BELOW the PARENT/CHILD table above, which is left
 * exactly as it was. That table states the structure by naming each node's
 * UPLINK; this one draws the same walk as a shape, so depth and who-sits-under-
 * whom are readable at a glance while a run is in progress.
 *
 * Drawn as real branches (+-- / `-- / |) rather than plain indentation: with
 * indentation alone, children of different parents at the same depth print in
 * the same column and nothing on the line says which one is whose - the shape
 * has to be reconstructed by eye against the UPLINK table. The trunk removes
 * that step.
 *
 * ASCII only, deliberately: the wizard's console is cp1252 and box-drawing
 * characters arrive there as mojibake - the same reason tools/command_center.py
 * is ASCII-only. */
static void tree_art_cb(void *ctx, int idx, int depth)
{
    art_fmt_t *f = (art_fmt_t *)ctx;
    const heartbeat_entry_t *e = &s_nodes[idx];
    char hop[16];
    /* fmt_hop() takes a LAYER (root = 1), not a tree DEPTH (root = 0) - same
     * conversion tree_line_cb already applies. Passing depth directly made the
     * root hit fmt_hop's layer<=0 branch and print "H--" here (unreachable)
     * while the PARENT/CHILD table above correctly printed "H00" for it. */
    fmt_hop(hop, sizeof(hop), depth + 1, f->lyr_w);

    bool is_last = (f->g->next_sibling[idx] < 0);
    if (depth <= TREE_ART_MAX_DEPTH) {
        f->last[depth] = is_last;
    }

    /* One 4-char column per ancestor level, then this node's own connector.
     * An ancestor that was a last child has nothing more hanging off it, so its
     * column is blank; any other keeps a '|' so the trunk stays traceable past
     * a nested subtree. */
    char pre[TREE_ART_MAX_DEPTH * 4 + 8];
    size_t w = 0;
    int stem = depth < TREE_ART_MAX_DEPTH ? depth : TREE_ART_MAX_DEPTH;
    for (int d = 1; d < stem; d++) {
        memcpy(pre + w, f->last[d] ? "    " : "|   ", 4);
        w += 4;
    }
    if (depth > 0) {
        memcpy(pre + w, is_last ? "`-- " : "+-- ", 4);
        w += 4;
    }
    pre[w] = '\0';

    /* Why the marker: since C7 Option 1 the blackhole is positional - it drops
     * only what its DESCENDANTS route through it. Marking it in the shape makes
     * "is anything actually under the attacker?" answerable from the root
     * console, before the capture is analysed. */
    const char *mark = (e->role == NODE_ROLE_BLACKHOLE)
                     ? "  <== BLACKHOLE (DROPS EVERYTHING BRANCHING BELOW IT)"
                     : "";
    ESP_LOGI(TAG, " %s[%s] %-*s  " MACSTR_UC "%s",
             pre, hop, f->role_w, node_role_to_str(e->role),
             MAC2STR(e->mac), mark);
}

static void heartbeat_table_print(void)
{
    if (!s_table_ready) {
        return;
    }
    table_lock();

    int64_t now = esp_timer_get_time();
    s_last_print_us = now;

    /* Drop nodes that stopped reporting, so the printed count reflects what is
     * actually reachable. Nothing else evicts: a mesh disconnect event only
     * names the direct child, while a node several hops down goes silent with
     * no event at all — going by "has it reported recently" catches both. */
    for (size_t i = 0; i < s_node_count;) {
        heartbeat_entry_t *e = &s_nodes[i];
        uint32_t age_ms = (uint32_t)((now - e->last_seen_us) / 1000LL);
        /* A node that reported its log closed goes quiet on purpose. Keep its
         * row so the dashboard can keep saying it is safe to export. */
        if (age_ms > HEARTBEAT_STALE_MS
                && e->export_status != EXPORT_STATUS_LOG_CLOSED) {
            ESP_LOGW(TAG, "Node OFFLINE — no heartbeat for %u s: " MACSTR,
                     (unsigned)(age_ms / 1000U), MAC2STR(e->mac));
            entry_remove(i);
            continue;
        }
        i++;
    }

    /* Layers shown are derived from the parent links (BFS from the root the
     * links themselves identify), not taken on trust from each row. */
    size_t n = s_node_count;
    topo_node_t *tn = calloc(n ? n : 1, sizeof(topo_node_t));
    int *order = malloc((n ? n : 1) * sizeof(int));
    topo_graph_t g;
    if (!tn || !order) {
        ESP_LOGE(TAG, "Out of memory drawing the topology (%u nodes)", (unsigned)n);
        free(tn);
        free(order);
        table_unlock();
        return;
    }
    for (size_t i = 0; i < n; i++) {
        memcpy(tn[i].mac, s_nodes[i].mac, 6);
        memcpy(tn[i].parent, s_nodes[i].parent_mac, 6);
        tn[i].seen_parents = s_nodes[i].seen_parents;
        tn[i].seen_count   = s_nodes[i].seen_count;
        order[i] = (int)i;
    }
    if (!topo_build(&g, tn, n)) {
        ESP_LOGE(TAG, "Out of memory building the topology graph (%u nodes)", (unsigned)n);
        free(tn);
        free(order);
        table_unlock();
        return;
    }
    s_sort_graph = &g;
    qsort(order, n, sizeof(int), order_cmp);

    topo_kind_t kind = (topo_kind_t)MESH_TOPOLOGY;
    char reason[192];
    topo_status_t st = topo_validate(&g, tn, kind, reason, sizeof(reason));

    /* Column widths, sized from this print's actual rows. */
    int lyr_w  = hex_width(g.max_layer > 0 ? (unsigned)g.max_layer : 0);
    int cnt_w  = hex_width((unsigned)(n > (size_t)g.max_layer ? n : (size_t)g.max_layer));
    int role_w = (int)strlen("ROLE");
    int rssi_w = (int)strlen("RSSI");
    int ph_w   = 0;
    int age_w  = (int)strlen("AGE(s)");
    char num[16];
    for (size_t i = 0; i < n; i++) {
        const heartbeat_entry_t *e = &s_nodes[i];
        int w = (int)strlen(node_role_to_str(e->role));
        role_w = w > role_w ? w : role_w;
        w = snprintf(num, sizeof(num), "%d", (int)e->parent_rssi);
        rssi_w = w > rssi_w ? w : rssi_w;
        w = (int)strlen(phase_id_str(e->current_phase));
        ph_w = w > ph_w ? w : ph_w;
        w = snprintf(num, sizeof(num), "%lu",
                     (unsigned long)((now - e->last_seen_us) / 1000000LL));
        age_w = w > age_w ? w : age_w;
    }
    /* PHASE cell = "0xNN NAME" */
    int phase_w = 4 + 1 + ph_w;
    if (phase_w < (int)strlen("PHASE")) {
        phase_w = (int)strlen("PHASE");
    }
    int lyr_col = lyr_w + 2;   /* 'L' + digits + mismatch flag */
    int row_w = 1 + lyr_col + 2 + MAC_W + 2 + role_w + 2 + rssi_w + 2 + phase_w + 2 + age_w
                + 2 + (int)strlen("not yet");   /* EXPORT column */
    int tree_w = 1 + lyr_col + 2 + MAC_W + 2 + role_w + 2 + MAC_W + 2 + 2 + cnt_w;
    int rule_w = row_w > tree_w ? row_w : tree_w;

    log_rule('=', rule_w);
    ESP_LOGI(TAG, " MESH TOPOLOGY");
    ESP_LOGI(TAG, " TYPE        : %s", topo_kind_str(kind));
    ESP_LOGI(TAG, " NODE COUNT  : 0x%0*X (%u)", cnt_w, (unsigned)n, (unsigned)n);
    /* Depth in HOPS, so it matches the HOP column below and the dataset's `hop`:
     * a 4-layer chain is 3 hops deep. */
    ESP_LOGI(TAG, " HOP DEPTH   : 0x%0*X (%d)", cnt_w,
             (unsigned)(g.max_layer > 0 ? g.max_layer - 1 : 0),
             g.max_layer > 0 ? g.max_layer - 1 : 0);
    ESP_LOGI(TAG, " REACHABLE   : 0x%0*X (%d)", cnt_w, (unsigned)g.reachable, g.reachable);
    if (st == TOPO_OK) {
        ESP_LOGI(TAG, " STATUS      : %s", topo_status_str(st));
    } else if (st == TOPO_WARN) {
        ESP_LOGW(TAG, " STATUS      : %s", topo_status_str(st));
    } else {
        ESP_LOGE(TAG, " STATUS      : %s", topo_status_str(st));
    }
    ESP_LOGI(TAG, " DETAIL      : %s", reason);

    /* EXPORT: a board is safe to export once its heartbeat says its log is
     * closed. Only boards in this table are counted, so the line says so. */
    size_t done = 0;
    for (size_t i = 0; i < n; i++) {
        if (s_nodes[i].export_status == EXPORT_STATUS_LOG_CLOSED) {
            done++;
        }
    }
    if (n > 0 && done == n) {
        ESP_LOGI(TAG, " EXPORT      : ALL %u BOARDS DONE - SAFE TO EXPORT "
                      "(a board missing from this table is not covered)", (unsigned)n);
    } else if (done > 0) {
        ESP_LOGW(TAG, " EXPORT      : %u/%u boards done - WAIT, rows marked 'not yet' "
                      "are still writing", (unsigned)done, (unsigned)n);
    } else {
        ESP_LOGI(TAG, " EXPORT      : not yet - run in progress, do not export");
    }
    /* SD LOGGING (oct. 19 2026): a board whose card is not taking rows still sends
     * probes - the root sees it as healthy - but its telemetry exists only in its
     * internal flash (wiped by the next flash). Say so while it can still be fixed. */
    {
        char bad[320] = "";
        size_t ok = 0, old = 0, nbad = 0;
        for (size_t i = 0; i < n; i++) {
            const heartbeat_entry_t *e = &s_nodes[i];
            if (e->sd_log == SD_LOG_OK || e->sd_log == SD_LOG_WAITING) {
                ok++;
            } else if (e->sd_log == SD_LOG_NA) {
                old++;
            } else {
                char one[64];
                snprintf(one, sizeof(one), "%s%02X:%02X %s", nbad ? ", " : "", e->mac[0], e->mac[5],
                         e->sd_log == SD_LOG_NO_CARD ? "NO CARD" :
                         e->sd_log == SD_LOG_FAILED  ? "CARD GIVEN UP" :
                         e->sd_log == SD_LOG_INCOMPLETE ? "INCOMPLETE (card recovered, rows missed)"
                                                        : "STALLED/RECOVERING");
                strlcat(bad, one, sizeof(bad));
                nbad++;
            }
        }
        if (nbad) {
            ESP_LOGE(TAG, " SD LOGGING  : NOT WRITING on %u board(s): %s - their telemetry is complete ONLY in "
                          "internal flash: fix the card (reseat / replace, then reset that board) "
                          "BEFORE START, or export it over USB (EXPORT_LOGS) before it is re-flashed",
                     (unsigned)nbad, bad);
        } else if (n > 0) {
            ESP_LOGI(TAG, " SD LOGGING  : %u/%u board(s) writing to their SD card%s", (unsigned)ok, (unsigned)n,
                     old ? " (the rest run older firmware - not reported)" : "");
        }
        /* oct. 20 2026: one machine-readable line per board for the GUI's live board
         * panel (SD card, UART tunnel, how long since it was heard, uptime). Words, not
         * numbers, so an older GUI can ignore them and a person can still read them. */
        int64_t now_us = esp_timer_get_time();
        for (size_t i = 0; i < n; i++) {
            const heartbeat_entry_t *e = &s_nodes[i];
            const char *sd = e->sd_log == SD_LOG_OK ? "OK" : e->sd_log == SD_LOG_WAITING ? "WAITING" :
                             e->sd_log == SD_LOG_NO_CARD ? "NO_CARD" : e->sd_log == SD_LOG_FAILED ? "GIVEN_UP" :
                             e->sd_log == SD_LOG_STALLED ? "STALLED" : e->sd_log == SD_LOG_INCOMPLETE ? "INCOMPLETE" : "NA";
            const char *wh = e->wh_link == WH_LINK_OK ? "OK" : e->wh_link == WH_LINK_NONE ? "NO_SIGNAL" :
                             e->wh_link == WH_LINK_LOST ? "LOST" : e->wh_link == WH_LINK_WAITING ? "CHECKING" :
                             e->wh_link == WH_LINK_ONEWAY ? "ONE_WAY" : e->wh_link == WH_LINK_ECHO ? "ECHO" : "NA";
            ESP_LOGI(TAG, " NODESTAT %02X:%02X:%02X:%02X:%02X:%02X sd=%s uart=%s age=%lld up=%lu rssi=%d",
                     MAC2STR(e->mac), sd, wh, (long long)((now_us - e->last_seen_us) / 1000000),
                     (unsigned long)e->uptime_sec, (int)e->parent_rssi);
        }
    }
    log_rule('-', rule_w);

    ESP_LOGI(TAG, " %-*s  %-*s  %-*s  %*s  %-*s  %*s  %s",
             lyr_col, "HOP", MAC_W, "MAC ADDRESS", role_w, "ROLE",
             rssi_w, "RSSI", phase_w, "PHASE", age_w, "AGE(s)", "EXPORT");
    bool mismatch = false;
    bool no_rssi  = false;
    for (size_t i = 0; i < n; i++) {
        int k = order[i];
        const heartbeat_entry_t *e = &s_nodes[k];
        char lyr[16];
        fmt_hop(lyr, sizeof(lyr), g.layer[k], lyr_w);
        if (g.layer[k] > 0 && e->layer != g.layer[k]) {
            mismatch = true;
            strlcat(lyr, "*", sizeof(lyr));
        }
        /* The sender reports 0 when it has no parent link to measure
         * (the root) - that is "no reading", not 0 dBm. */
        char rssi[8];
        if (e->parent_rssi == 0) {
            strlcpy(rssi, "n/a", sizeof(rssi));
            no_rssi = true;
        } else {
            snprintf(rssi, sizeof(rssi), "%d", (int)e->parent_rssi);
        }
        char phase[24];
        snprintf(phase, sizeof(phase), "0x%02X %s",
                 (unsigned)e->current_phase, phase_id_str(e->current_phase));
        uint32_t age_s = (uint32_t)((now - e->last_seen_us) / 1000000LL);
        ESP_LOGI(TAG, " %-*s  " MACSTR_UC "  %-*s  %*s  %-*s  %*lu  %s",
                 lyr_col, lyr, MAC2STR(e->mac),
                 role_w, node_role_to_str(e->role),
                 rssi_w, rssi, phase_w, phase, age_w, (unsigned long)age_s,
                 e->export_status == EXPORT_STATUS_LOG_CLOSED ? "SAFE" : "not yet");
    }
    if (mismatch) {
        ESP_LOGI(TAG, " * node's own stack reports a different depth (re-parenting)");
    }
    if (no_rssi) {
        ESP_LOGI(TAG, " n/a = no parent link to measure (root)");
    }
    if (n > 1 && g.root >= 0) {
        log_rule('-', rule_w);
        ESP_LOGI(TAG, " PARENT/CHILD STRUCTURE (depth-first from root)");
        ESP_LOGI(TAG, " %-*s  %-*s  %-*s  %-*s  %s",
                 lyr_col, "HOP", MAC_W, "MAC ADDRESS", role_w, "ROLE",
                 MAC_W, "UPLINK", "DN");
        tree_fmt_t f = { .g = &g, .lyr_w = lyr_w, .role_w = role_w, .cnt_w = cnt_w };
        topo_walk(&g, tree_line_cb, &f);

        /* ---- ADDITIONAL: the same walk drawn as a shape ------------------- */
        log_rule('-', rule_w);
        ESP_LOGI(TAG, " TOPOLOGY TREE (branches = who sits under whom; probes flow UP toward the root)");
        art_fmt_t af = { .g = &g, .lyr_w = lyr_w, .role_w = role_w };
        topo_walk(&g, tree_art_cb, &af);

        /* Root-side leaf/off-path guard. The attacker's own firmware warns when
         * nothing transits it (blackhole_victim.c, LEAF_WARN_AFTER_MS), but the
         * ROOT is the only node that sees the WHOLE tree - so it can say so
         * before the attack window even opens. A blackhole with no descendants
         * drops nothing, and that capture passes every downstream check while
         * containing no attack at all. */
        /* ---- WHO IS ACTUALLY A VICTIM, decided live from the tree --------
         *
         * A child is a VICTIM only if an attacker sits between it and the root;
         * one ABOVE the attacker reaches the root without transiting it and is
         * untouched for the whole run. The analysis side derives exactly this
         * after the fact (analysis/exposure.py -> the `exposure` column), but
         * after the fact is too late to DO anything about it: a badly placed
         * attacker costs a full run before anyone finds out. The root is the
         * one node that sees the whole tree, so it can say it now.
         *
         * Same rule as exposure.py, just walked upward: from each node follow
         * parents to the root and look for an attacker on the way. The step
         * counter is a cycle guard -- topo_build() flags cycles, but this must
         * not be the thing that hangs a live run if one slips through. */
        bool any_attacker = false;
        int  wh_a = -1, wh_b = -1, n_wh_a = 0, n_wh_b = 0;
        for (size_t i = 0; i < n; i++) {
            if (s_nodes[i].role == NODE_ROLE_BLACKHOLE
                    || s_nodes[i].role == NODE_ROLE_WORMHOLE_A
                    || s_nodes[i].role == NODE_ROLE_WORMHOLE_B) {
                any_attacker = true;
            }
            if (s_nodes[i].role == NODE_ROLE_WORMHOLE_A) { wh_a = (int)i; n_wh_a++; }
            if (s_nodes[i].role == NODE_ROLE_WORMHOLE_B) { wh_b = (int)i; n_wh_b++; }
        }

        /* ---- WORMHOLE: a different rule from the blackhole below ---------
         *
         * The blackhole's "anything under an attacker is a victim" does not
         * apply here. wormhole_victim.c tunnels ONLY Node B's OWN probes: B
         * sends each one up the mesh as normal AND (attack phase) copies it
         * over the UART wire to A, which re-injects it at A's position. Every
         * other child's traffic is relayed exactly as in baseline, wherever it
         * sits. So: B is the only node whose data carries the attack.
         *
         * Placement matters as much as for the blackhole: A is the EXIT (root
         * side), B the ENTRY (leaf side). The tunnel is a shortcut only when A
         * is FEWER hops from the root than B. Reversed (oct. 7 2026 linear
         * run: B at H01, A at H06) the tunnelled copy climbs back up from deep
         * in the mesh and arrives SLOWER than B's normal copy - the opposite of
         * the wormhole signature - and every check downstream still passes. */
        if (wh_a >= 0 || wh_b >= 0) {
            /* Hops to the root for every node, walked up the same parent links
             * as the tables above (-1 = chain does not reach the root). The
             * step counter is the same cycle guard as the blackhole walk. */
            int hop_of[n > 0 ? n : 1];
            for (size_t i = 0; i < n; i++) {
                int hops = 0, cur = (int)i;
                for (size_t steps = 0; cur >= 0 && cur != g.root && steps <= n; steps++) {
                    cur = g.parent[cur];
                    hops++;
                }
                hop_of[i] = (cur == g.root) ? hops : -1;
            }
            int hop_a = (wh_a >= 0) ? hop_of[wh_a] : -1;
            int hop_b = (wh_b >= 0) ? hop_of[wh_b] : -1;

            /* Nodes that carry B's NORMAL copy: B's ancestors below the root.
             * They are honest relays - named so nobody mistakes them for
             * victims, and because their forwarding is what the normal-copy
             * latency is made of. */
            bool on_b_path[n > 0 ? n : 1];
            memset(on_b_path, 0, sizeof(on_b_path));
            if (wh_b >= 0) {
                int cur = g.parent[wh_b];
                for (size_t steps = 0; cur >= 0 && cur != g.root && steps <= n; steps++) {
                    on_b_path[cur] = true;
                    cur = g.parent[cur];
                }
            }

            log_rule('-', rule_w);
            ESP_LOGI(TAG, " WORMHOLE TUNNEL (only Node B's OWN probes go through it;"
                          " every other node is relayed as in baseline)");
            for (int k = 0; k < 2; k++) {
                int i = (k == 0) ? wh_b : wh_a;
                const char *what = (k == 0) ? "ENTRY  B" : "EXIT   A";
                if (i < 0) {
                    ESP_LOGE(TAG, "   %s  -- not in the mesh / not reported --", what);
                    continue;
                }
                char hop_s[16];     /* "H" + any int: sized for -Wformat-truncation */
                if (hop_of[i] >= 0) snprintf(hop_s, sizeof(hop_s), "H%02d", hop_of[i]);
                else                snprintf(hop_s, sizeof(hop_s), "H??");
                esp_log_level_t lvl = wh_link_bad(s_nodes[i].wh_link) ? ESP_LOG_ERROR : ESP_LOG_INFO;
                ESP_LOG_LEVEL(lvl, TAG, "   %s  " MACSTR_UC "  %s  RSSI %4d  phase 0x%02X %-9s  %s  \"%s\"",
                         what, MAC2STR(s_nodes[i].mac), hop_s, (int)s_nodes[i].parent_rssi,
                         s_nodes[i].current_phase, phase_id_str(s_nodes[i].current_phase),
                         wh_link_str(s_nodes[i].wh_link), s_nodes[i].nickname);
            }

            /* The two routes B's probe takes during the attack, drawn hop by
             * hop (last two MAC bytes keep the line short). */
            if (hop_a >= 0 && hop_b >= 0) {
                char path[192];
                int  len = snprintf(path, sizeof(path), "B %02X%02X",
                                    s_nodes[wh_b].mac[4], s_nodes[wh_b].mac[5]);
                int cur = g.parent[wh_b];
                for (size_t steps = 0; cur >= 0 && cur != g.root && steps <= n
                         && len < (int)sizeof(path) - 16; steps++) {
                    len += snprintf(path + len, sizeof(path) - len, " > %02X%02X%s",
                                    s_nodes[cur].mac[4], s_nodes[cur].mac[5],
                                    cur == wh_a ? "(A)" : "");
                    cur = g.parent[cur];
                }
                snprintf(path + len, sizeof(path) - len, " > ROOT");
                ESP_LOGI(TAG, "   Normal copy : %s  = %d hop(s) over the mesh", path, hop_b);
                ESP_LOGI(TAG, "   Tunnel copy : B %02X%02X =UART=> A %02X%02X > ROOT"
                              "  = wire + %d hop(s)",
                         s_nodes[wh_b].mac[4], s_nodes[wh_b].mac[5],
                         s_nodes[wh_a].mac[4], s_nodes[wh_a].mac[5], hop_a);
                if (hop_a < hop_b) {
                    ESP_LOGI(TAG, "   Shortcut    : the tunnel skips %d hop(s)", hop_b - hop_a);
                } else {
                    ESP_LOGE(TAG, "   Shortcut    : NONE - the tunnel copy travels %d hop(s),"
                                  " B's normal copy %d", hop_a, hop_b);
                }
            }
            /* TUNNEL TEST (before Phase 0): UART OK only proves the wire; this
             * proves wire + A's re-injection + the mesh path up to here. */
            if (s_tuntest_count > 0) {
                ESP_LOGI(TAG, "   Tunnel test : OK - %lu test(s) came B -> UART -> A -> root,"
                              " last %lld s ago", (unsigned long)s_tuntest_count,
                         (long long)((esp_timer_get_time() - s_tuntest_last_us) / 1000000LL));
            } else {
                ESP_LOGW(TAG, "   Tunnel test : none arrived yet (B sends one every 10 s before"
                              " Phase 0 once UART is OK; none = A's re-injection or the mesh"
                              " path is broken, or older firmware)");
            }

            log_rule('-', rule_w);
            ESP_LOGI(TAG, " EXPOSURE (wormhole: no victims - the attack is DUPLICATION of B's probes)");
            int relays = 0, uninvolved = 0;
            for (size_t i = 0; i < n; i++) {
                if ((int)i == g.root) {
                    continue;
                }
                if ((int)i == wh_b) {
                    ESP_LOGI(TAG, "   " MACSTR_UC "  ATTACKER (WORMHOLE_B, entry) - its OWN"
                                  " probes are copied to A over UART", MAC2STR(s_nodes[i].mac));
                } else if ((int)i == wh_a) {
                    ESP_LOGI(TAG, "   " MACSTR_UC "  ATTACKER (WORMHOLE_A, exit)  - re-injects"
                                  " B's probes from here", MAC2STR(s_nodes[i].mac));
                } else if (s_nodes[i].role == NODE_ROLE_WORMHOLE_A
                           || s_nodes[i].role == NODE_ROLE_WORMHOLE_B) {
                    /* its link state is the clue to WHY two boards claim one end */
                    ESP_LOGE(TAG, "   " MACSTR_UC "  EXTRA %s - a second board claims this end  (%s)",
                             MAC2STR(s_nodes[i].mac), node_role_to_str(s_nodes[i].role),
                             wh_link_str(s_nodes[i].wh_link));
                } else if (on_b_path[i]) {
                    relays++;
                    ESP_LOGI(TAG, "   " MACSTR_UC "  relays B's normal copy - honest, unaffected",
                             MAC2STR(s_nodes[i].mac));
                } else {
                    uninvolved++;
                    ESP_LOGI(TAG, "   " MACSTR_UC "  not involved - relayed as in baseline",
                             MAC2STR(s_nodes[i].mac));
                }
            }

            int in_mesh = esp_mesh_get_routing_table_size();
            /* SAFETY NET (oct. 14 2026): each end reports whether it hears the
             * other over the wire. A dead wire is the ROOT CAUSE of reversed /
             * same-end roles (each end falls back to its build default) AND
             * means no tunnel copy can arrive - say so first and plainly. */
            int ends_bad = 0, ends_seen = 0;
            for (size_t i = 0; i < n; i++) {
                if (s_nodes[i].role == NODE_ROLE_WORMHOLE_A || s_nodes[i].role == NODE_ROLE_WORMHOLE_B) {
                    ends_seen++;
                    if (wh_link_bad(s_nodes[i].wh_link)) ends_bad++;
                }
            }
            if (ends_bad > 0) {
                log_rule('!', rule_w);
                ESP_LOGE(TAG, " !! UART TUNNEL NOT WORKING - the wormhole boards cannot hear each"
                              " other over the wire (%s).",
                         (ends_bad >= 2 || ends_seen < 2) ? "no signal at the end(s) reporting"
                             : "only ONE direction works - one TX->RX jumper is bad");
                ESP_LOGE(TAG, "    Without it they keep their BUILD-DEFAULT A/B roles (can be reversed)"
                              " and NO tunnel copy reaches the root. Do NOT start / keep this run.");
                ESP_LOGE(TAG, "    Fix: GPIO%d (TX) -> other board's GPIO%d (RX), both ways (crossed),"
                              " + GND -> GND. Then Wizard > MAINTENANCE > Wormhole UART tunnel test,"
                              " and re-run.", WORMHOLE_UART_TX_PIN, WORMHOLE_UART_RX_PIN);
                log_rule('!', rule_w);
            }
            if ((int)n < in_mesh) {
                ESP_LOGI(TAG, " (%d of %d node(s) reported so far - verdict waits"
                              " for the rest)", (int)n, in_mesh);
            } else if (n_wh_a > 1 || n_wh_b > 1) {
                /* Auto-switch boards settle on OPPOSITE ends over the UART
                 * HELLO; two of the same end means they cannot hear each other
                 * (each fell back to its build default) or a third board was
                 * flashed as a wormhole end. */
                ESP_LOGE(TAG, " !! %d boards report WORMHOLE_A and %d report WORMHOLE_B -"
                              " there must be exactly one of each.", n_wh_a, n_wh_b);
                ESP_LOGE(TAG, "    Check the A<->B UART cable (crossed TX/RX + common GND):"
                              " the ends pick opposite roles only when they hear each other.");
            } else if (hop_a < 0 || hop_b < 0) {
                ESP_LOGE(TAG, " !! WORMHOLE NEEDS BOTH ENDS IN THE MESH - Node %s is"
                              " missing or not connected to the root.",
                         (hop_a < 0 && hop_b < 0) ? "A and Node B"
                                                  : (hop_a < 0 ? "A" : "B"));
            } else if (hop_a >= hop_b) {
                ESP_LOGE(TAG, " !! WORMHOLE ENDS %s: A (exit) is at H%02d, B (entry) at"
                              " H%02d. The tunnelled copy would NOT be a shortcut -"
                              " it arrives no faster than B's normal copy.",
                         hop_a > hop_b ? "REVERSED" : "AT THE SAME DEPTH", hop_a, hop_b);
                if (hop_a > hop_b) {
                    ESP_LOGE(TAG, "    A must be CLOSER to the root than B. Auto-switch boards"
                                  " swap the names themselves before Phase 0 when they hear each"
                                  " other over UART - if it persists, check the cable."
                                  " Pre-auto-switch firmware: reflash both.");
                } else {
                    /* Auto-switch only renames the ends by depth; equal depth has no
                     * deeper end to call B, so only a different layout fixes it. */
                    ESP_LOGE(TAG, "    Auto-switch CANNOT fix this - it only swaps the names A/B,"
                                  " and both ends are at the same depth. Move ONE end (B) farther"
                                  " from the root, where the root is weak (about -80 dBm or worse)"
                                  " but another child is strong, then press that board's EN/RST"
                                  " button so it picks a new parent. Moving it without a reset does"
                                  " nothing: ESP-MESH keeps a working parent.");
                }
                /* oct. 14 2026: a run that reached the attack like this was
                 * analysed, pushed and only then found invalid. */
                ESP_LOGE(TAG, "    >> If this shows AFTER Phase 0 started: STOP and restart the run."
                              " Roles are locked for the run, so it cannot fix itself, and the"
                              " verifier will mark it 'DUPLICATION ONLY - SETUP INVALID'.");
            } else {
                ESP_LOGI(TAG, " OK: A (exit) at H%02d, B (entry) at H%02d - the tunnel skips"
                              " %d hop(s). %d relay(s) carry B's normal copy, %d node(s) not"
                              " involved.", hop_a, hop_b, hop_b - hop_a, relays, uninvolved);
                ESP_LOGI(TAG, "    EXPECT during the attack: the root logs every Node B probe"
                              " TWICE (normal + tunnel copy, tunnel copy faster). Report B's"
                              " duplicates + latency, not PDR.");
            }
        } else if (any_attacker) {
            log_rule('-', rule_w);
            ESP_LOGI(TAG, " EXPOSURE (who this run's attack can actually reach)");
            int victims = 0, bystanders = 0;
            for (size_t i = 0; i < n; i++) {
                if ((int)i == g.root) {
                    continue;
                }
                if (s_nodes[i].role == NODE_ROLE_BLACKHOLE
                        || s_nodes[i].role == NODE_ROLE_WORMHOLE_A
                        || s_nodes[i].role == NODE_ROLE_WORMHOLE_B) {
                    ESP_LOGI(TAG, "   " MACSTR_UC "  ATTACKER (%s)",
                             MAC2STR(s_nodes[i].mac),
                             node_role_to_str(s_nodes[i].role));
                    continue;
                }
                int cur = g.parent[i];
                bool downstream = false;
                for (size_t steps = 0; cur >= 0 && steps <= n; steps++) {
                    if (s_nodes[cur].role == NODE_ROLE_BLACKHOLE
                            || s_nodes[cur].role == NODE_ROLE_WORMHOLE_A
                            || s_nodes[cur].role == NODE_ROLE_WORMHOLE_B) {
                        downstream = true;
                        break;
                    }
                    cur = g.parent[cur];
                }
                if (downstream) {
                    victims++;
                    ESP_LOGI(TAG, "   " MACSTR_UC "  VICTIM - its traffic transits"
                                  " the attacker", MAC2STR(s_nodes[i].mac));
                } else {
                    bystanders++;
                    ESP_LOGI(TAG, "   " MACSTR_UC "  not in the attack path -"
                                  " above the attacker, will be UNAFFECTED",
                             MAC2STR(s_nodes[i].mac));
                }
            }
            /* The table fills one heartbeat at a time, so the first prints
             * after boot see only PART of the tree (sep. 23 2026: the attacker
             * reported before its parent and the victim below it, and the root
             * printed this error twice in its first 7 s for a layout that was
             * correct). No verdict until every node the mesh stack knows about
             * has reported; the routing table counts the root itself. */
            int in_mesh = esp_mesh_get_routing_table_size();
            if ((int)n < in_mesh) {
                ESP_LOGI(TAG, " (%d of %d node(s) reported so far - verdict waits"
                              " for the rest)", (int)n, in_mesh);
            } else if (victims == 0) {
                ESP_LOGE(TAG, " !! NO NODE IS DOWNSTREAM OF THE ATTACKER -"
                              " it will drop NOTHING and this run will look"
                              " benign. Move a child below it, then re-run.");
            } else {
                ESP_LOGI(TAG, " %d victim(s), %d bystander(s). Only the victims"
                              " can show the attack; report PDR per node.",
                         victims, bystanders);
            }
        }
    }
    log_rule('=', rule_w);

    s_sort_graph = NULL;
    topo_free(&g);
    free(tn);
    free(order);
    table_unlock();
}

/* Instant counterpart to heartbeat_table_print()'s age-based staleness sweep
 * (see MESH_EVENT_CHILD_DISCONNECTED above): evicts one row the moment the
 * mesh names its MAC, rather than waiting up to HEARTBEAT_STALE_MS for the
 * age check to notice it stopped reporting. A no-op if the table isn't ready
 * (mesh_event_handler runs on every node; only the root owns a table) or the
 * MAC isn't a row we're tracking (already evicted, or never made it in). */
static void heartbeat_mark_offline(const uint8_t mac[6])
{
    if (!s_table_ready) {
        return;
    }
    table_lock();
    for (size_t i = 0; i < s_node_count; i++) {
        if (memcmp(s_nodes[i].mac, mac, 6) != 0) {
            continue;
        }
        ESP_LOGW(TAG, "Node OFFLINE (child-disconnected event) — " MACSTR,
                 MAC2STR(s_nodes[i].mac));
        entry_remove(i);
        table_unlock();
        heartbeat_request_print();
        return;
    }
    table_unlock();
}

bool heartbeat_tree_gate_active(void)
{
#if (MESH_TOPOLOGY == NIS_TOPO_TREE && ACTIVE_ATTACK == PHASE_ID_BLACKHOLE)
    return true;
#else
    return false;
#endif
}

int heartbeat_attacker_child_count(void)
{
    if (!s_table_mutex) {
        return -1;
    }
    const int64_t now = esp_timer_get_time();
    int result = -1;
    table_lock();
    topo_node_t *tn = calloc(s_node_count ? s_node_count : 1, sizeof(topo_node_t));
    if (!tn) {
        table_unlock();
        return -1;
    }
    size_t n = 0;
    int atk = -1;
    for (size_t i = 0; i < s_node_count; i++) {
        const heartbeat_entry_t *e = &s_nodes[i];
        const uint32_t age_ms = (uint32_t)((now - e->last_seen_us) / 1000LL);
        if (age_ms > HEARTBEAT_STALE_MS && e->export_status != EXPORT_STATUS_LOG_CLOSED) {
            continue;   /* gone quiet: not part of the mesh any more */
        }
        memcpy(tn[n].mac, e->mac, 6);
        memcpy(tn[n].parent, e->parent_mac, 6);
        if (e->role == NODE_ROLE_BLACKHOLE) {
            atk = (int)n;
        }
        n++;
    }
    if (atk >= 0) {
        topo_graph_t g;
        if (topo_build(&g, tn, n)) {
            result = g.child_count[atk];
            topo_free(&g);
        }
    }
    free(tn);
    table_unlock();
    return result;
}

bool heartbeat_wormhole_gate_active(void)
{
#if (ACTIVE_ATTACK == PHASE_ID_WORMHOLE)
    return true;
#else
    return false;
#endif
}

/* WORMHOLE SETUP GATE (oct. 16 2026). The root printed every one of these
 * problems already (EXPOSURE box) but still started Phase 0, where the ends
 * LOCK - so a wrong setup could only be fixed by restarting the run. Checked
 * on fresh heartbeats only, in the order an operator should fix them. */
void mesh_setup_wormhole_peer_layer(int peer_layer, const uint8_t peer_mac[6], bool may_repick)
{
#if WH_B_NO_ROOT
    s_wh_peer_layer = peer_layer;
#if WH_B_NOT_UNDER_A
    /* Tree only. Elsewhere s_wh_peer_ap_known stays false, so the "never
     * under A" checks in star_hub_scan_done and below never fire. */
    if (s_pin_no_root && peer_mac) {
        /* Mesh SoftAP BSSID = STA MAC + 1 (with carry), as in parent_mac. Built
         * locally and stored only when it changes: a scan reads it from another
         * task, so it must never see the half-incremented value. */
        uint8_t ap[6];
        memcpy(ap, peer_mac, 6);
        for (int i = 5; i >= 0 && ++ap[i] == 0; i--) {
        }
        if (!s_wh_peer_ap_known || memcmp(ap, s_wh_peer_ap, 6) != 0) {
            s_wh_peer_ap_known = false;
            memcpy(s_wh_peer_ap, ap, 6);
            s_wh_peer_ap_known = true;
        }
    }
#else
    (void)peer_mac;
#endif
    if (!s_pin_no_root || !may_repick || peer_layer <= 0 || !s_have_parent) {
        return;
    }
    int me = mesh_setup_get_layer();
    uint8_t cur[6] = {0};
    bool under_a = s_wh_peer_ap_known && mesh_setup_get_parent_mac(cur) &&
                   memcmp(cur, s_wh_peer_ap, 6) == 0;
    int64_t now = esp_timer_get_time();
    if (me > 0 && (me <= peer_layer || under_a) && now - s_last_repick_us > WH_REPICK_GAP_US) {
        s_last_repick_us = now;
        s_repick = true;
        if (under_a) {
            ESP_LOGW(TAG, "WORMHOLE B (D-30): B's parent is A itself (" MACSTR ") - the ends sit "
                     "side by side. Looking for a victim parent instead.", MAC2STR(peer_mac));
        } else {
            ESP_LOGW(TAG, "WORMHOLE B (D-30): B is at layer %d, A at layer %d - not deeper than A. "
                     "Looking for a deeper parent.", me, peer_layer);
        }
        star_hub_scan();
    }
#else
    (void)peer_layer;
    (void)peer_mac;
    (void)may_repick;
#endif
}

uint32_t mesh_setup_note_tunnel_test(const uint8_t src_mac[6])
{
    (void)src_mac;
    s_tuntest_last_us = esp_timer_get_time();
    return ++s_tuntest_count;
}

bool heartbeat_wormhole_ready(char *why, size_t len)
{
    if (len) {
        why[0] = '\0';
    }
    if (!s_table_mutex) {
        snprintf(why, len, "no heartbeats yet");
        return false;
    }
    const int64_t now = esp_timer_get_time();
    bool ok = false;
    table_lock();
    const size_t cap = s_node_count ? s_node_count : 1;
    topo_node_t *tn = calloc(cap, sizeof(topo_node_t));
    int *map = calloc(cap, sizeof(int));
    if (!tn || !map) {
        free(tn);
        free(map);
        table_unlock();
        snprintf(why, len, "out of memory");
        return false;
    }
    size_t n = 0;
    int a = -1, b = -1, n_a = 0, n_b = 0;
    for (size_t i = 0; i < s_node_count; i++) {
        const heartbeat_entry_t *e = &s_nodes[i];
        if ((uint32_t)((now - e->last_seen_us) / 1000LL) > HEARTBEAT_STALE_MS) {
            continue;
        }
        memcpy(tn[n].mac, e->mac, 6);
        memcpy(tn[n].parent, e->parent_mac, 6);
        map[n] = (int)i;
        if (e->role == NODE_ROLE_WORMHOLE_A) { a = (int)n; n_a++; }
        if (e->role == NODE_ROLE_WORMHOLE_B) { b = (int)n; n_b++; }
        n++;
    }
    if (n_a != 1 || n_b != 1) {
        /* name every end's link so the cause is on the same line */
        char links[96] = "";
        size_t used = 0;
        for (size_t k = 0; k < n && used < sizeof(links); k++) {
            const heartbeat_entry_t *e = &s_nodes[map[k]];
            if (e->role != NODE_ROLE_WORMHOLE_A && e->role != NODE_ROLE_WORMHOLE_B) continue;
            int w = snprintf(links + used, sizeof(links) - used, "%s%02X%02X %s",
                             used ? ", " : "", e->mac[4], e->mac[5], wh_link_str(e->wh_link));
            if (w > 0) used += (size_t)w;
        }
        snprintf(why, len, "%d board(s) report WORMHOLE_A and %d WORMHOLE_B - need exactly one"
                 " of each (%s; a one-way, echoing or loose UART jumper makes both pick the"
                 " same end)", n_a, n_b, links);
    } else if (s_nodes[map[a]].wh_link != WH_LINK_OK || s_nodes[map[b]].wh_link != WH_LINK_OK) {
        snprintf(why, len, "UART link not OK both ways (A: %s, B: %s) - re-seat TX->RX on both"
                 " jumpers + GND", wh_link_str(s_nodes[map[a]].wh_link),
                 wh_link_str(s_nodes[map[b]].wh_link));
    } else {
        topo_graph_t g;
        if (!topo_build(&g, tn, n)) {
            snprintf(why, len, "topology not built yet");
        } else {
            int la = g.layer[a], lb = g.layer[b];
            if (la <= 0 || lb <= 0) {
                snprintf(why, len, "a wormhole end is not attached to the root yet");
            } else if (la >= lb) {
                snprintf(why, len, "A (exit) at H%02d is not closer to the root than B (entry) at"
                         " H%02d - no shortcut. The ends follow depth until Phase 0, so wait"
                         " a few seconds, or move a board", la - 1, lb - 1);
            } else {
                snprintf(why, len, "A at H%02d, B at H%02d: tunnel skips %d hop(s), UART OK",
                         la - 1, lb - 1, lb - la);
                ok = true;
            }
            topo_free(&g);
        }
    }
    free(map);
    free(tn);
    table_unlock();
    return ok;
}

void heartbeat_table_init(void)
{
    s_table_mutex = xSemaphoreCreateRecursiveMutex();
    if (!s_table_mutex) {
        ESP_LOGE(TAG, "Could not create the node-table mutex - table disabled");
        return;
    }

    /* Seed the root's own row directly — it never has to wait for its own
     * heartbeat to round-trip through the mesh before it can be listed. */
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    heartbeat_entry_t *e = entry_add(mac);
    if (e) {
        strlcpy(e->nickname, node_identity_nickname(), NODE_NICKNAME_LEN);
        e->role          = node_identity_role();
        e->layer         = (int16_t)mesh_setup_get_layer();
        /* The root has not announced anything yet at this point, so seeding
         * BASELINE here would show a phase it never broadcast. */
        e->current_phase = PHASE_ID_UNSET;
        e->last_seen_us  = esp_timer_get_time();
    }

    s_table_ready = true;

    heartbeat_table_print();
}

bool heartbeat_ingest(const uint8_t *data, size_t len)
{
    if (len < sizeof(uint32_t)) {
        return false;
    }
    uint32_t magic;
    memcpy(&magic, data, sizeof(magic));
    if (magic == HEARTBEAT_MSG_MAGIC_V1) {
        static bool warned = false;
        if (!warned) {
            warned = true;
            ESP_LOGW(TAG, "A board is sending the OLD heartbeat format - re-flash every "
                          "board with this build or it won't appear in the topology.");
        }
        return true;
    }
    /* Pre-oct-14 boards send the beat WITHOUT the trailing wh_link byte:
     * accept them, and read wh_link only when it is there. */
    if (magic != HEARTBEAT_MSG_MAGIC || len < offsetof(node_heartbeat_pkt_t, wh_link)
            || !s_table_ready) {
        return magic == HEARTBEAT_MSG_MAGIC;
    }
    const node_heartbeat_pkt_t *pkt = (const node_heartbeat_pkt_t *)data;
    uint8_t wh_link = (len > offsetof(node_heartbeat_pkt_t, wh_link)) ? pkt->wh_link : WH_LINK_NA;
    uint8_t sd_log  = (len > offsetof(node_heartbeat_pkt_t, sd_log)) ? pkt->sd_log : SD_LOG_NA;

    table_lock();

    heartbeat_entry_t *hit = NULL;
    for (size_t i = 0; i < s_node_count; i++) {
        if (memcmp(s_nodes[i].mac, pkt->src_mac, 6) == 0) {
            hit = &s_nodes[i];
            break;
        }
    }

    bool is_new = false;
    if (!hit) {
        hit = entry_add(pkt->src_mac);
        if (!hit) {
            ESP_LOGE(TAG, "Out of memory adding node " MACSTR, MAC2STR(pkt->src_mac));
            table_unlock();
            return true;
        }
        is_new = true;
    }

    bool changed = is_new
                || hit->layer != pkt->layer
                || memcmp(hit->parent_mac, pkt->parent_mac, 6) != 0
                || hit->role  != pkt->assigned_role
                || hit->export_status != pkt->export_status
                || hit->wh_link != wh_link
                || hit->sd_log != sd_log
                || strncmp(hit->nickname, pkt->nickname, NODE_NICKNAME_LEN) != 0;

    strlcpy(hit->nickname, pkt->nickname, NODE_NICKNAME_LEN);
    memcpy(hit->parent_mac, pkt->parent_mac, 6);
    hit->role          = pkt->assigned_role;
    hit->layer         = pkt->layer;
    hit->parent_rssi   = pkt->parent_rssi;
    hit->uptime_sec    = pkt->uptime_sec;
    hit->current_phase = pkt->current_phase;
    hit->export_status = pkt->export_status;
    hit->wh_link       = wh_link;
    hit->sd_log        = sd_log;
    hit->last_seen_us  = esp_timer_get_time();
#if (MESH_TOPOLOGY == NIS_TOPO_PARTIAL)
    entry_note_parent(hit);
#endif

    if (changed) {
        heartbeat_table_print();
    }
    table_unlock();
    return true;
}