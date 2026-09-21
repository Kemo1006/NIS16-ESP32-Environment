/**
 * @file probe_relay.c
 * @brief Hop-by-hop application-layer probe relay. See probe_relay.h.
 *
 * NIS16 — CTTHES3 — C7 Option 1
 */

#include "probe_relay.h"
#include "mesh_config.h"
#include "mesh_setup.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_log.h"
#include "esp_mesh.h"

static const char *TAG = "PROBE_RELAY";

/* Sized like the blackhole attacker's old queue: a transient slow-mesh burst
 * (a node briefly re-scanning for its parent) must not overflow and force
 * congestion drops that would be indistinguishable from an attack drop in the
 * telemetry. If "Relay queue full" ever appears in a run, treat that run's
 * drop_count as contaminated. */
#define RELAY_QUEUE_SIZE 128

static QueueHandle_t s_queue = NULL;
static probe_relay_forward_decision_t s_decision = NULL;

/* Cumulative counters — paper Table 4.2 / F3 telemetry columns.
 * volatile: written by the relay task, read by the telemetry task. */
static volatile uint32_t s_recv      = 0;
static volatile uint32_t s_forward   = 0;
static volatile uint32_t s_drop      = 0;
static volatile uint32_t s_send_fail = 0;

uint32_t probe_relay_recv_count(void)      { return s_recv; }
uint32_t probe_relay_forward_count(void)   { return s_forward; }
uint32_t probe_relay_drop_count(void)      { return s_drop; }
uint32_t probe_relay_send_fail_count(void) { return s_send_fail; }


/* Send one probe to THIS node's parent.
 *
 * Direction is the loop guard: a relay hop only ever targets the node's own
 * parent, so traffic strictly ascends the tree and can never circulate. That is
 * why no TTL or visited-set is needed.
 *
 * A node whose parent is the ROOT still addresses that parent explicitly rather
 * than falling back to MESH_DATA_TODS — the root IS its parent, so P2P reaches
 * it in one hop, and keeping one code path means the last hop is counted
 * exactly like every other hop. */
static esp_err_t send_to_parent(probe_pkt_t *pkt)
{
    uint8_t pmac[6] = {0};
    if (!mesh_setup_get_parent_mac(pmac)) {
        return ESP_ERR_INVALID_STATE;       /* no parent right now */
    }

    mesh_addr_t dest = {0};
    memcpy(dest.addr, pmac, 6);

    mesh_data_t mdata = {
        .data  = (uint8_t *)pkt,
        .size  = sizeof(*pkt),
        .proto = MESH_PROTO_BIN,
        .tos   = MESH_TOS_P2P,
    };
    /* MESH_DATA_P2P is what paper Section 3.1.3.2 mandates for the forwarding
     * discipline; it addresses one specific neighbour instead of asking the
     * stack to route to the root on our behalf. */
    return esp_mesh_send(&dest, &mdata, MESH_DATA_P2P, NULL, 0);
}


esp_err_t probe_relay_send_own(probe_pkt_t *pkt)
{
    esp_err_t err = send_to_parent(pkt);
    if (err != ESP_OK) {
        s_send_fail++;
    }
    return err;
}


void probe_relay_ingest(const uint8_t *data, size_t len)
{
    if (len < sizeof(probe_pkt_t)) return;

    const probe_pkt_t *pkt = (const probe_pkt_t *)data;
    /* BOTH magics relay. PROBE_MAGIC_WORMHOLE is the tunnel duplicate, and if
     * an intermediate node refused to carry it the duplicate arrivals that ARE
     * the wormhole signature would never reach the root — the attack would
     * silently look like it never happened. See probe_relay.h. */
    if (pkt->magic != PROBE_MAGIC && pkt->magic != PROBE_MAGIC_WORMHOLE) {
        return;                              /* not a probe — not ours */
    }

    /* Counted the moment it is accepted for relay, BEFORE the forward/drop
     * decision. recv is "what arrived for me to carry", so recv == forward +
     * drop must hold for an honest relay; that identity is what makes
     * ForwardingRatio interpretable. */
    s_recv++;

    probe_pkt_t copy = *pkt;
    if (s_queue && xQueueSend(s_queue, &copy, 0) != pdTRUE) {
        /* Queue overflow is a DROP: the packet was accepted and then not
         * carried. Counting it anywhere else would make recv != forward + drop
         * and quietly inflate this node's ForwardingRatio. */
        s_drop++;
        ESP_LOGW(TAG, "Relay queue full - dropping probe seq=%lu",
                 (unsigned long)copy.seq_num);
    }
}


static void relay_task(void *arg)
{
    (void)arg;
    probe_pkt_t pkt;

    ESP_LOGI(TAG, "Relay task running (hop-by-hop, forwards to parent).");

    while (true) {
        if (xQueueReceive(s_queue, &pkt, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        /* The attacker's only divergence from an honest node lives here. */
        if (s_decision && !s_decision(&pkt)) {
            s_drop++;
            ESP_LOGD(TAG, "DROPPED probe seq=%lu (forward decision)",
                     (unsigned long)pkt.seq_num);
            continue;
        }

        esp_err_t err = send_to_parent(&pkt);
        if (err == ESP_OK) {
            s_forward++;
        } else {
            /* Not forwarded, so it IS a drop (keeps recv == forward + drop),
             * and separately a send failure for retry_count. A node with no
             * parent lands here, which is the honest reading: it could not
             * carry the packet. */
            s_drop++;
            s_send_fail++;
            ESP_LOGW(TAG, "Forward failed seq=%lu: %s",
                     (unsigned long)pkt.seq_num, esp_err_to_name(err));
        }
    }
}


esp_err_t probe_relay_start(probe_relay_forward_decision_t decision)
{
    s_decision = decision;

    s_queue = xQueueCreate(RELAY_QUEUE_SIZE, sizeof(probe_pkt_t));
    if (!s_queue) {
        ESP_LOGE(TAG, "Failed to create relay queue");
        return ESP_ERR_NO_MEM;
    }

    BaseType_t rc = xTaskCreate(relay_task, "probe_relay", STACK_PROBE_SINK,
                                NULL, TASK_PRIO_PROBE_SINK, NULL);
    if (rc != pdPASS) {
        ESP_LOGE(TAG, "Failed to create relay task");
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Probe relay started (%s).",
             decision ? "WITH a forward-decision hook (attacker)" : "honest relay");
    return ESP_OK;
}
