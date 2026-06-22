/**
 * @file mesh_setup.c
 * @brief ESP-WIFI-MESH initialisation — common module.
 *
 * NIS16 — CTTHES2 Milestone 1
 */

#include "mesh_setup.h"
#include "mesh_config.h"

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"

#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_mac.h"
#include "esp_event.h"
#include "esp_mesh.h"
#include "esp_mesh_internal.h"
#include "esp_netif.h"
#include "nvs_flash.h"

/* ── Module-private state ────────────────────────────────────────────────── */

static const char *TAG = "MESH_SETUP";

/* Event group bit set when the node has a parent (or, for root, got IP). */
#define MESH_CONNECTED_BIT  BIT0
static EventGroupHandle_t s_mesh_event_group = NULL;

static mesh_node_role_t s_role        = MESH_ROLE_VICTIM;
static char             s_node_id[NODE_ID_LEN] = {0};
static bool             s_is_root     = false;

/* ── Forward declarations ────────────────────────────────────────────────── */
static void mesh_event_handler(void *arg, esp_event_base_t base,
                                int32_t id, void *data);
static void ip_event_handler(void *arg, esp_event_base_t base,
                              int32_t id, void *data);
static void build_node_id(void);

/* ═══════════════════════════════════════════════════════════════════════════
 * Public API
 * ═══════════════════════════════════════════════════════════════════════════ */

esp_err_t mesh_setup_init(mesh_node_role_t role)
{
    esp_err_t ret;
    s_role = role;

    /* ── 1. Non-volatile storage ─────────────────────────────────────────── */
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* ── 2. TCP/IP and event loop ─────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    /* ── 3. Wi-Fi driver ──────────────────────────────────────────────────── */
    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_FLASH));

    /* ── 4. Register event handlers ──────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_event_handler_register(MESH_EVENT, ESP_EVENT_ANY_ID,
                                               mesh_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               ip_event_handler, NULL));

    /* ── 5. Build node ID string from MAC address ─────────────────────────── */
    build_node_id();

    /* ── 6. Mesh initialisation ────────────────────────────────────────────── */
    ESP_ERROR_CHECK(esp_mesh_init());

    /* Network topology constraints */
    ESP_ERROR_CHECK(esp_mesh_set_max_layer(MESH_MAX_LAYER));

    /* Access point capacity: limit number of direct children */
    mesh_ap_cfg_t ap_cfg = {
        .max_connection = MESH_MAX_CHILDREN,
        .nonmesh_max_connection = 0,
    };
    strncpy((char *)ap_cfg.password, MESH_PASSWORD, sizeof(ap_cfg.password) - 1);
    ESP_ERROR_CHECK(esp_mesh_set_ap_authmode(WIFI_AUTH_WPA2_PSK));

#if !MESH_USE_ROUTER
    /*
     * Routerless (self-organized-without-router) mesh.
     *
     * esp_mesh_set_config() validates the router struct differently
     * depending on node role:
     *   - ROOT:     bypasses the router-struct check entirely once
     *               esp_mesh_fix_root(true) + esp_mesh_set_type(MESH_ROOT)
     *               have been called first. router.ssid_len MUST stay 0
     *               here — giving the root a non-zero SSID makes it
     *               actually try to associate with that SSID as a real
     *               AP, which fails repeatedly (disconnect reason 201
     *               loop), confirmed by testing.
     *   - NON-ROOT: esp_mesh_set_type(MESH_IDLE) alone does NOT bypass
     *               the check (confirmed by testing — still aborts with
     *               ESP_ERR_MESH_ARGUMENT). Non-root nodes do not use the
     *               router field to actually connect (their upstream
     *               link is chosen via mesh parent-selection / scanning),
     *               so a dummy non-zero SSID safely satisfies validation
     *               without causing connection attempts.
     */
    if (role == MESH_ROLE_ROOT) {
        ESP_ERROR_CHECK(esp_mesh_fix_root(true));
        ESP_ERROR_CHECK(esp_mesh_set_type(MESH_ROOT));
    } else {
        ESP_ERROR_CHECK(esp_mesh_set_type(MESH_IDLE));
    }
#endif

    /* Mesh configuration */
    mesh_cfg_t cfg = MESH_INIT_CONFIG_DEFAULT();
    uint8_t mesh_id[] = MESH_ID;
    memcpy(cfg.mesh_id.addr, mesh_id, 6);

    /* Auth: mesh password */
    cfg.mesh_ap.max_connection = MESH_MAX_CHILDREN;
    memcpy(cfg.mesh_ap.password, MESH_PASSWORD, strlen(MESH_PASSWORD));

#if MESH_USE_ROUTER
    cfg.channel = 0;             /* 0 = auto-select channel from router scan */
    cfg.allow_channel_switch = false;
    cfg.router.ssid_len = strlen(ROUTER_SSID);
    memcpy(cfg.router.ssid,     ROUTER_SSID,     cfg.router.ssid_len);
    memcpy(cfg.router.password, ROUTER_PASSWORD,  strlen(ROUTER_PASSWORD));
#else
    cfg.channel = 6;             /* Fixed channel — no AP to scan. */
    cfg.allow_channel_switch = false;

    if (role == MESH_ROLE_ROOT) {
        /* Root: bypassed via fix_root + set_type above; keep struct empty. */
        cfg.router.ssid_len = 0;
    } else {
        /* Non-root: dummy SSID only to pass validation; never connected to. */
        static const char dummy_ssid[] = "MESH_NO_ROUTER";
        cfg.router.ssid_len = strlen(dummy_ssid);
        memcpy(cfg.router.ssid, dummy_ssid, cfg.router.ssid_len);
    }
#endif

    ESP_ERROR_CHECK(esp_mesh_set_config(&cfg));

    /* ── 7. Start mesh ─────────────────────────────────────────────────────── */
    s_mesh_event_group = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_wifi_start());

    /* Some ESP-IDF variants require disabling Wi-Fi power-save at the driver
     * level so mesh parent-selection RSSI ladder initialises correctly. Try
     * turning off PS explicitly; continue if unsupported. */
    esp_err_t _r = esp_wifi_set_ps(WIFI_PS_NONE);
    if (_r != ESP_OK) {
        ESP_LOGW(TAG, "esp_wifi_set_ps(WIFI_PS_NONE) failed: %s", esp_err_to_name(_r));
    }

    /*
     * Routerless-mesh stability settings.
     *
     * Multiple community reports (esp-idf #3966, esp32.com t=15022) show
     * that without disabling Wi-Fi power-save, the parent-selection RSSI
     * threshold ladder never initialises away from 0 in a no-router mesh,
     * which causes every candidate scan to log "[parent]not found,
     * rssi_threshold:0" indefinitely — exactly the symptom observed here.
     * These calls require Wi-Fi to already be started, so they must come
     * AFTER esp_wifi_start() and BEFORE esp_mesh_start().
     */
#if !MESH_USE_ROUTER
    ESP_ERROR_CHECK(esp_mesh_disable_ps());
    ESP_ERROR_CHECK(esp_mesh_set_ap_assoc_expire(10));
    ESP_ERROR_CHECK(esp_mesh_set_vote_percentage(1.0));

    /*
     * Root cause of the "[parent]not found, rssi_threshold:0" infinite
     * loop: mesh_switch_parent_t (which governs the parent-selection RSSI
     * ladder logged as "try rssi_threshold:X, backoff times:N, max:5
     * <select,switch,backoff>") was being read back as all-zero at
     * runtime in this routerless configuration, instead of its documented
     * negative-dBm defaults. Reference logs from working routerless mesh
     * deployments show a ladder like <-78,-82,-85>; ours showed <0,0,0>.
     * Setting this explicitly with sane negative thresholds, per
     * Espressif's documented field meanings (esp_mesh_internal.h),
     * resolves it. Must be called after esp_wifi_start(), before
     * esp_mesh_start().
     */
    /*
    * Explicitly set the RSSI threshold ladder for parent selection.
    * In routerless mode on ESP-IDF 5.x the defaults do not initialize
    * correctly — the ladder stays at <0,0,0> causing the victim to reject
    * every parent candidate.
    */
    mesh_switch_parent_t switch_paras = {
        .select_rssi  = -78,   /* preferred parent threshold (Table 3.2) */
        .backoff_rssi = -85,   /* trigger parent switching below this    */
    };
    esp_err_t _sp = esp_mesh_set_switch_parent_paras(&switch_paras);
    if (_sp != ESP_OK) {
        ESP_LOGW(TAG, "esp_mesh_set_switch_parent_paras failed: %s",
                esp_err_to_name(_sp));
    } else {
        ESP_LOGI(TAG, "RSSI ladder set: select=%d backoff=%d",
                switch_paras.select_rssi,
                switch_paras.backoff_rssi);
    }
#endif

    ESP_ERROR_CHECK(esp_mesh_start());

    ESP_LOGI(TAG, "Mesh started. Node ID: %s  Role: %d", s_node_id, (int)s_role);

    /* ── 8. Wait for connection (max PHASE_STABILISE_S seconds) ─────────── */
    EventBits_t bits = xEventGroupWaitBits(
        s_mesh_event_group,
        MESH_CONNECTED_BIT,
        pdFALSE,
        pdFALSE,
        pdMS_TO_TICKS(PHASE_STABILISE_S * 1000)
    );

    if (bits & MESH_CONNECTED_BIT) {
        ESP_LOGI(TAG, "Mesh connected. Layer: %d  Parent: %s  Root: %s",
                 esp_mesh_get_layer(),
                 s_is_root ? "N/A (this is root)" : "see event log",
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

/* ═══════════════════════════════════════════════════════════════════════════
 * Private helpers
 * ═══════════════════════════════════════════════════════════════════════════ */

static void build_node_id(void)
{
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_node_id, sizeof(s_node_id),
             "NODE_%02X%02X%02X%02X%02X%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

/* ── Event handlers ──────────────────────────────────────────────────────── */

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
        break;
    }

    case MESH_EVENT_PARENT_DISCONNECTED: {
        mesh_event_disconnected_t *ed = (mesh_event_disconnected_t *)data;
        ESP_LOGW(TAG, "Parent disconnected — reason %d. Will re-associate.",
                 (int)ed->reason);
        s_is_root = false;
        xEventGroupClearBits(s_mesh_event_group, MESH_CONNECTED_BIT);
        break;
    }

    case MESH_EVENT_CHILD_CONNECTED: {
        mesh_event_child_connected_t *cc = (mesh_event_child_connected_t *)data;
        ESP_LOGI(TAG, "Child connected: aid=%d MAC=" MACSTR,
                 (int)cc->aid, MAC2STR(cc->mac));
        break;
    }

    case MESH_EVENT_CHILD_DISCONNECTED: {
        mesh_event_child_disconnected_t *cd = (mesh_event_child_disconnected_t *)data;
        ESP_LOGI(TAG, "Child disconnected: aid=%d MAC=" MACSTR,
                 (int)cd->aid, MAC2STR(cd->mac));
        break;
    }

    case MESH_EVENT_ROUTING_TABLE_ADD:
        ESP_LOGI(TAG, "Routing table updated — nodes in mesh: %d",
                 esp_mesh_get_routing_table_size());
        break;

    case MESH_EVENT_ROUTING_TABLE_REMOVE:
        ESP_LOGI(TAG, "Routing table shrunk — nodes in mesh: %d",
                 esp_mesh_get_routing_table_size());
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