/**
 * @file mesh_setup.c
 * @brief ESP-WIFI-MESH initialisation — common module.
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#include "mesh_setup.h"
#include "mesh_config.h"
#include "mesh_messages.h"
#include "node_identity.h"
#include "phase_listener.h"
#include "topology_graph.h"

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
#include "esp_netif.h"
#include "esp_timer.h"
#include "nvs_flash.h"

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
/* Declared this early (defs live down in the heartbeat section) so
 * mesh_event_handler can call them for instant disconnect reporting instead
 * of waiting on the heartbeat table's own staleness timer — see the
 * MESH_EVENT_CHILD_DISCONNECTED / MESH_EVENT_ROUTING_TABLE_REMOVE cases. */
static void heartbeat_table_print(void);
static void heartbeat_request_print(void);
static void heartbeat_mark_offline(const uint8_t mac[6]);

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
#if (MESH_TOPOLOGY == NIS_TOPO_STAR)
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

    /* ── 9. Start mesh ───────────────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_mesh_start());

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
        break;

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
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        log_mesh_status();
        break;
    }

    case MESH_EVENT_PARENT_DISCONNECTED: {
        mesh_event_disconnected_t *ed = (mesh_event_disconnected_t *)data;
        ESP_LOGW(TAG, "Parent disconnected — reason %d.", (int)ed->reason);
        s_is_root = false;
        xEventGroupClearBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        break;
    }

    case MESH_EVENT_CHILD_CONNECTED: {
        mesh_event_child_connected_t *cc = (mesh_event_child_connected_t *)data;
        ESP_LOGI(TAG, "Child connected: aid=%d MAC=" MACSTR,
                 (int)cc->aid, MAC2STR(cc->mac));
        xEventGroupSetBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        log_mesh_status();
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

    while (true) {
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
            next_send_us = esp_timer_get_time() + (int64_t)HEARTBEAT_INTERVAL_MS * 1000;
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
    int64_t  last_seen_us;
    uint8_t *seen_parents;    /* PARTIAL only: every distinct parent observed  */
    size_t   seen_count;
} heartbeat_entry_t;

static heartbeat_entry_t *s_nodes      = NULL;
static size_t             s_node_count = 0;
static size_t             s_node_cap   = 0;
static SemaphoreHandle_t  s_table_mutex = NULL;

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

/* Indentation is display-only and stops growing at 24 levels so a long chain
 * stays readable; the printed L<n> is always the real layer. */
static void tree_line_cb(void *ctx, int idx, int depth)
{
    (void)ctx;
    const heartbeat_entry_t *e = &s_nodes[idx];
    int indent = depth < 24 ? depth : 24;
    ESP_LOGI(TAG, "  %*sL%-3d " MACSTR "  %-10s %s", indent * 2, "",
             depth + 1, MAC2STR(e->mac), node_role_to_str(e->role), e->nickname);
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
        if (age_ms > HEARTBEAT_STALE_MS) {
            ESP_LOGW(TAG, "Node OFFLINE — no heartbeat for %u s: " MACSTR " (%s)",
                     (unsigned)(age_ms / 1000U), MAC2STR(e->mac), e->nickname);
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
    ESP_LOGI(TAG, "============ MESH TOPOLOGY: %s, %u node%s, %d layer%s ============",
             topo_kind_str(kind), (unsigned)n, n == 1 ? "" : "s",
             g.max_layer, g.max_layer == 1 ? "" : "s");
    ESP_LOGI(TAG, "%-5s %-18s %-11s %-16s %-6s %-6s %-6s",
             "LYR", "MAC", "ROLE", "NICKNAME", "RSSI", "PHASE", "AGE_S");
    bool mismatch = false;
    for (size_t i = 0; i < n; i++) {
        int k = order[i];
        const heartbeat_entry_t *e = &s_nodes[k];
        char lyr[12];
        if (g.layer[k] > 0) {
            bool differs = (e->layer != g.layer[k]);
            mismatch |= differs;
            snprintf(lyr, sizeof(lyr), "%d%s", g.layer[k], differs ? "*" : "");
        } else {
            snprintf(lyr, sizeof(lyr), "-");
        }
        uint32_t age_s = (uint32_t)((now - e->last_seen_us) / 1000000LL);
        ESP_LOGI(TAG, "%-5s " MACSTR "  %-11s %-16s %-6d %-6u %-6lu",
                 lyr, MAC2STR(e->mac), node_role_to_str(e->role),
                 e->nickname, (int)e->parent_rssi, (unsigned)e->current_phase,
                 (unsigned long)age_s);
    }
    if (mismatch) {
        ESP_LOGI(TAG, "  * the node's own stack reported a different layer (it is re-parenting)");
    }
    if (n > 1 && g.root >= 0) {
        ESP_LOGI(TAG, "---- parent/child structure ----");
        topo_walk(&g, tree_line_cb, NULL);
    }

    char reason[192];
    topo_status_t st = topo_validate(&g, tn, kind, reason, sizeof(reason));
    if (st == TOPO_OK) {
        ESP_LOGI(TAG, "TOPOLOGY CHECK: %s OK — %s", topo_kind_str(kind), reason);
    } else if (st == TOPO_WARN) {
        ESP_LOGW(TAG, "TOPOLOGY CHECK: %s WARN — %s", topo_kind_str(kind), reason);
    } else {
        ESP_LOGE(TAG, "TOPOLOGY CHECK: %s FAIL — %s", topo_kind_str(kind), reason);
    }
    ESP_LOGI(TAG, "=====================================================================");

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
        ESP_LOGW(TAG, "Node OFFLINE (child-disconnected event) — " MACSTR " (%s)",
                 MAC2STR(s_nodes[i].mac), s_nodes[i].nickname);
        entry_remove(i);
        table_unlock();
        heartbeat_request_print();
        return;
    }
    table_unlock();
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
        e->current_phase = PHASE_ID_BASELINE;
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
    if (magic != HEARTBEAT_MSG_MAGIC || len < sizeof(node_heartbeat_pkt_t) || !s_table_ready) {
        return magic == HEARTBEAT_MSG_MAGIC;
    }
    const node_heartbeat_pkt_t *pkt = (const node_heartbeat_pkt_t *)data;

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
                || strncmp(hit->nickname, pkt->nickname, NODE_NICKNAME_LEN) != 0;

    strlcpy(hit->nickname, pkt->nickname, NODE_NICKNAME_LEN);
    memcpy(hit->parent_mac, pkt->parent_mac, 6);
    hit->role          = pkt->assigned_role;
    hit->layer         = pkt->layer;
    hit->parent_rssi   = pkt->parent_rssi;
    hit->uptime_sec    = pkt->uptime_sec;
    hit->current_phase = pkt->current_phase;
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