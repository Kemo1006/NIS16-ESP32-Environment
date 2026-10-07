/*
 * board.c — ONE simulated wormhole board running the REAL firmware file.
 *
 * Compiled twice by run_test.sh (-DBOARD=b1 / -DBOARD=b2, each with its own
 * -DWORMHOLE_END fallback). wormhole_victim.c is #included verbatim, so what
 * runs here is the code that gets flashed; only ESP-IDF/FreeRTOS are stood in
 * by sim.h. Every non-static name is prefixed with the board, so two copies
 * link side by side as two independent boards.
 */
#define CAT2(a, b) a##_##b
#define CAT(a, b)  CAT2(a, b)
#define SYM(n)     CAT(BOARD, n)
#define STR2(x) #x
#define STR(x)  STR2(x)
#define BOARD_NAME STR(BOARD)

/* project functions declared non-static in the real headers */
#define app_main                   SYM(app_main)
#define node_identity_resolve      SYM(node_identity_resolve)
#define node_identity_get          SYM(node_identity_get)
#define node_identity_nickname     SYM(node_identity_nickname)
#define node_identity_role         SYM(node_identity_role)
#define node_identity_set_role     SYM(node_identity_set_role)
#define probe_relay_start          SYM(probe_relay_start)
#define probe_relay_ingest         SYM(probe_relay_ingest)
#define probe_relay_send_own       SYM(probe_relay_send_own)
#define probe_relay_recv_count     SYM(probe_relay_recv_count)
#define probe_relay_forward_count  SYM(probe_relay_forward_count)
#define probe_relay_drop_count     SYM(probe_relay_drop_count)
#define probe_relay_send_fail_count SYM(probe_relay_send_fail_count)

#include "sim.h"
#include "../../child_node/main/wormhole_victim.c"

/* ── the renamed project functions ──────────────────────────────────────── */
static uint8_t s_hb_role = 0xFF;        /* what the heartbeat would report */
void node_identity_resolve(uint8_t r) { s_hb_role = r; }
void node_identity_set_role(uint8_t r) { s_hb_role = r; }
uint8_t node_identity_role(void) { return s_hb_role; }
esp_err_t probe_relay_start(probe_relay_forward_decision_t d) { (void)d; return ESP_OK; }
void probe_relay_ingest(const uint8_t *d, size_t l) { (void)d; (void)l; }
esp_err_t probe_relay_send_own(probe_pkt_t *p) { (void)p; return ESP_OK; }
uint32_t probe_relay_recv_count(void) { return 0; }
uint32_t probe_relay_forward_count(void) { return 0; }
uint32_t probe_relay_drop_count(void) { return 0; }
uint32_t probe_relay_send_fail_count(void) { return 0; }

/* ── control API used by test.c ─────────────────────────────────────────── */

static wh_frame_t s_dv_f;      /* receiver's partial frame, like the RX task's */
static size_t     s_dv_got;

/* Power-on: fresh state, as after a reset. */
void SYM(boot)(const uint8_t mac[6], int layer)
{
    memcpy(s_sim_mac, mac, 6);
    memcpy(s_self_mac, mac, 6);
    s_sim_layer = layer;
    s_role = (WORMHOLE_END == WORMHOLE_END_B) ? NODE_ROLE_WORMHOLE_B : NODE_ROLE_WORMHOLE_A;
    node_identity_resolve(s_role);
    s_role_locked = false; s_peer_seen = false; s_peer_last_us = 0;
    s_peer_layer = 0; s_peer_locked = false; memset(s_peer_mac, 0, 6);
    s_uart_bad_windows = 0; s_role_conflict = false; s_locked_fallback = false;
    s_shortcut_lost = false; s_tunnel_received = 0;
    s_rt_started_us = esp_timer_get_time(); s_rt_next_hello_us = 0;
    s_rt_conflict_fixed = false; s_rt_lost_warned = false; s_rt_shortcut_warned = false;
    s_rt_next_noise_warn = 64;
    s_tx_len = 0; s_rx_len = 0; s_rx_pos = 0; s_queued = 0; s_dv_got = 0;
    if (!s_reinject_queue) s_reinject_queue = xQueueCreate(1, 1);
}

void SYM(set_layer)(int layer) { s_sim_layer = layer; }
void SYM(step)(void) { role_step(); }

/* What this board put on its TX wire since the last call. */
size_t SYM(take_tx)(uint8_t *dst, size_t cap)
{
    size_t n = s_tx_len < cap ? s_tx_len : cap;
    memcpy(dst, s_tx, n); s_tx_len = 0; return n;
}

/* Bytes arriving on this board's RX wire, then the receiver runs exactly as
 * uart_tunnel_rx_task does (same reassembly + one-byte resync, same
 * rx_handle_window) until the buffer is drained. */
void SYM(deliver)(const uint8_t *src, size_t n)
{
    memmove(s_rx, s_rx + s_rx_pos, s_rx_len - s_rx_pos);
    s_rx_len -= s_rx_pos; s_rx_pos = 0;
    memcpy(s_rx + s_rx_len, src, n); s_rx_len += n;

    wh_frame_t *fp = &s_dv_f; size_t got = s_dv_got;
    #define f (*fp)
    for (;;) {
        int r = uart_read_bytes(WORMHOLE_UART_PORT, f.raw + got, sizeof(f.raw) - got, 0);
        if (r <= 0) break;
        got += (size_t)r;
        if (got < sizeof(f.raw)) break;
        if (rx_handle_window(&f)) {
            got = 0;
        } else {
            s_uart_bad_windows++;
            memmove(f.raw, f.raw + 1, sizeof(f.raw) - 1);
            got = sizeof(f.raw) - 1;
        }
    }
    #undef f
    s_dv_got = got;
}

/* A tunnel frame exactly as tunnel_forwarder_task builds it. */
size_t SYM(make_tunnel_frame)(uint8_t *dst, uint32_t seq)
{
    tunnel_pkt_t tp = { .magic = WORMHOLE_TUNNEL_MAGIC };
    tp.probe.magic = PROBE_MAGIC; tp.probe.seq_num = seq;
    memcpy(tp.probe.src_mac, s_self_mac, 6);
    tp.crc = esp_rom_crc32_le(0, (const uint8_t *)&tp, offsetof(tunnel_pkt_t, crc));
    memcpy(dst, &tp, sizeof(tp)); return sizeof(tp);
}

char     SYM(end)(void)          { return is_b() ? 'B' : 'A'; }
char     SYM(hb_end)(void)       { return s_hb_role == NODE_ROLE_WORMHOLE_B ? 'B' : 'A'; }
const char *SYM(csv_role)(void)  { return role_csv_str(); }
bool     SYM(locked)(void)       { return s_role_locked; }
bool     SYM(fallback)(void)     { return s_locked_fallback; }
bool     SYM(conflict)(void)     { return s_role_conflict; }
bool     SYM(shortcut_lost)(void){ return s_shortcut_lost; }
uint32_t SYM(bad_windows)(void)  { return s_uart_bad_windows; }
uint32_t SYM(tunnel_rx)(void)    { return s_tunnel_received; }
void     SYM(force_peer_layer)(int l) { s_peer_layer = (int16_t)l; }
