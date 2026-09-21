/**
 * @file probe_relay.h
 * @brief Hop-by-hop application-layer probe relay (C7 Option 1).
 *
 * WHAT THIS CHANGES
 * -----------------
 * Before: a victim sent its probe with `esp_mesh_send(NULL, ..., MESH_DATA_TODS)`
 * — "mesh, deliver this to the root". The ESP-IDF mesh stack then relayed it
 * BELOW the application layer, so an intermediate node's own code never saw the
 * traffic it was forwarding. Only the blackhole attacker saw transit packets,
 * and only because victims were compiled to address it explicitly by MAC.
 *
 * After: every node sends to ITS OWN PARENT with MESH_DATA_P2P, and every node
 * relays what it receives one hop further up. A probe therefore walks the tree
 * hop by hop until it reaches the root, and EVERY node on the path observes and
 * counts the traffic it carries.
 *
 * WHY — THIS IS THE PAPER'S OWN SPEC, NOT A DEVIATION
 * ---------------------------------------------------
 * Paper Section 3.1.3.2, "Forwarding Discipline":
 *
 *     "Intermediate nodes must receive packets with esp_mesh_recv() and forward
 *      them with esp_mesh_send(), setting the MESH_DATA_P2P flag. This mandatory
 *      forwarding requirement establishes the behavioral baseline against which
 *      deviations can be observed."
 *
 * And Table 4.2 already specifies the three counters this module maintains:
 * `recv_counter` (packets received), `forward_counter` (packets forwarded to
 * root), `drop_counter` (packets intentionally dropped). Those are exactly the
 * `recv_count` / `forward_count` / `drop_count` telemetry columns from F3.
 *
 * So the MESH_DATA_TODS behaviour was the deviation; this restores what Chapter
 * 3 always described. See thesis-deviate.md D-12.
 *
 * WHAT IT FIXES BEYOND COMPLIANCE
 * -------------------------------
 *  1. ForwardingRatio / IngressEgressDelta / ConsistencyScore stop being
 *     defined only on the attacker. Every relaying node produces them, so the
 *     attacker becomes an OUTLIER in a populated distribution instead of the
 *     only value present — which is the panel's single-feature objection
 *     (2:40-4:50) at its root cause.
 *  2. The attacker now intercepts traffic because of WHERE IT SITS, not because
 *     victims were compiled to address it. Attacker POSITION becomes a real
 *     experimental variable (panel 12:45-16:00), and BLACKHOLE_ATTACKER_MAC
 *     stops being load-bearing for targeting.
 *
 * NO LOOPS BY CONSTRUCTION
 * ------------------------
 * Every relay hop sends to the node's OWN PARENT, so traffic only ever moves
 * UP the tree. There is no path by which a probe can travel back down, so no
 * TTL or visited-set is required. A node with no parent cannot forward, and
 * counts the packet as dropped rather than discarding it silently.
 *
 * NIS16 — CTTHES3 — C7 Option 1
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Probe wire format. Shared by every role so the definition cannot drift —
 *  it used to be copy-pasted into victim_main.c, blackhole_victim.c,
 *  wormhole_victim.c and root_main.c independently. */
#define PROBE_MAGIC     0x50524F42U   /* "PROB" — an ordinary probe          */

/** "PROW" — the wormhole duplicate. Node A stamps this on the copy it
 *  re-injects out of the UART tunnel so the ROOT can tell it apart from Node
 *  B's own mesh-path copy and does NOT de-duplicate the two.
 *
 *  ⚠️ THE RELAY MUST FORWARD THIS TOO. Every intermediate node between A and
 *  the root now relays at the application layer (C7 Option 1), so a relay that
 *  only recognised PROBE_MAGIC would silently DROP the tunnel copy on its way
 *  up — and the duplicate arrivals that ARE the wormhole signature would never
 *  reach the root. The run would look clean and the attack would look like it
 *  never happened. */
#define PROBE_MAGIC_WORMHOLE 0x50524F57U

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t seq_num;
    int64_t  send_ts_us;
    uint8_t  src_mac[6];   /**< the ORIGINATOR, preserved across every hop */
} probe_pkt_t;

/**
 * @brief Decide whether this node forwards a given probe.
 *
 * Returning false means "drop it" and the packet is counted in drop_count.
 * This is the ONLY hook an attacker firmware needs: the blackhole returns false
 * while the attack phase is active and true otherwise. Honest nodes do not
 * install a callback at all and always forward.
 *
 * Runs on the relay task, so it may block briefly but should stay short.
 */
typedef bool (*probe_relay_forward_decision_t)(const probe_pkt_t *pkt);

/**
 * @brief Start the relay task and its queue. Call once, after the mesh is up.
 *
 * @param decision  NULL for an honest relay (always forwards), or a callback
 *                  that returns false for packets this node should drop.
 */
esp_err_t probe_relay_start(probe_relay_forward_decision_t decision);

/**
 * @brief Hand a received packet to the relay. Call from the phase-listener's
 *        data callback. Non-probe packets are ignored, so it is safe to pass
 *        everything.
 *
 * Short and non-blocking, per the data-callback contract: it copies the packet
 * and queues it, and the relay task does the forwarding.
 */
void probe_relay_ingest(const uint8_t *data, size_t len);

/**
 * @brief Send a probe this node ORIGINATED, to this node's parent.
 *
 * Counted in probes_count/tx_count (origination), NOT in recv/forward — a node
 * does not "relay" its own traffic, and conflating the two is what made
 * ForwardingRatio meaningless per-role in the first place.
 *
 * @return ESP_OK on success; ESP_ERR_INVALID_STATE if this node has no parent.
 */
esp_err_t probe_relay_send_own(probe_pkt_t *pkt);

/** Cumulative relay counters — the F3 telemetry columns / paper Table 4.2. */
uint32_t probe_relay_recv_count(void);
uint32_t probe_relay_forward_count(void);
uint32_t probe_relay_drop_count(void);

/** Cumulative failed esp_mesh_send() calls (the honest `retry_count`). */
uint32_t probe_relay_send_fail_count(void);

#ifdef __cplusplus
}
#endif
