/*
 * test.c — host test of the wormhole A/B auto-switch (wormhole_victim.c).
 *
 * Two simulated boards (b1, b2: the REAL firmware file compiled twice, see
 * board.c) are wired back to back through a simulated UART cable, the root's
 * phase is driven by hand, and every scenario checks what the firmware
 * decided. Run:  bash tools/test_wormhole_autoswitch/run_test.sh   (-v = logs)
 *
 * b1 is built with fallback end B, b2 with fallback end A - deliberately the
 * WRONG way round for the depths used below, so a pass proves the boards
 * swapped themselves rather than keeping their build flags.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "mesh_config.h"           /* PHASE_ID_* */

int64_t g_now_us = 0;
uint8_t g_phase  = PHASE_ID_UNSET;
bool    g_terminated = false;
bool    g_verbose = false;

#define DECL(B) \
    void B##_boot(const uint8_t mac[6], int layer); void B##_set_layer(int); void B##_step(void); \
    size_t B##_take_tx(uint8_t *, size_t); void B##_deliver(const uint8_t *, size_t); \
    size_t B##_make_tunnel_frame(uint8_t *, uint32_t); char B##_end(void); char B##_hb_end(void); \
    const char *B##_csv_role(void); bool B##_locked(void); bool B##_fallback(void); \
    bool B##_conflict(void); bool B##_shortcut_lost(void); uint32_t B##_bad_windows(void); \
    uint32_t B##_tunnel_rx(void); void B##_force_peer_layer(int);
DECL(b1)
DECL(b2)

static const uint8_t MAC1[6] = {0x20, 0x50, 0x0D, 0xE7, 0x0C, 0x80};   /* lower  */
static const uint8_t MAC2[6] = {0x20, 0x50, 0x0D, 0xE7, 0x1C, 0x38};   /* higher */

static bool link_12 = true, link_21 = true;   /* each direction of the cable */
static int  noise   = 0;                       /* garbage bytes per transfer  */
static int  fails = 0, checks = 0;

#define CHECK(cond, ...) do { checks++; if (cond) { printf("    ok   "); } \
    else { fails++; printf("    FAIL "); } printf(__VA_ARGS__); printf("\n"); } while (0)

static void wire(void)
{
    uint8_t buf[8192]; size_t n;
    n = b1_take_tx(buf, sizeof buf);
    if (link_12 && n) {
        if (noise) { uint8_t g[64]; for (int i = 0; i < noise; i++) g[i] = (uint8_t)(0xA5 ^ i * 37); b2_deliver(g, noise); }
        b2_deliver(buf, n);
    }
    n = b2_take_tx(buf, sizeof buf);
    if (link_21 && n) {
        if (noise) { uint8_t g[64]; for (int i = 0; i < noise; i++) g[i] = (uint8_t)(0x5A ^ i * 53); b1_deliver(g, noise); }
        b1_deliver(buf, n);
    }
}

/* Advance the world by ms, one 100 ms role_task round per board per tick. */
static void run(int ms)
{
    for (int t = 0; t < ms; t += 100) {
        g_now_us += 100000;
        b1_step(); b2_step();
        wire();
    }
}

static void fresh(int l1, int l2)
{
    g_now_us += 60 * 1000000LL;          /* far from any earlier scenario */
    g_phase = PHASE_ID_UNSET; g_terminated = false;
    link_12 = link_21 = true; noise = 0;
    b1_boot(MAC1, l1); b2_boot(MAC2, l2);
}

static void opposite_and_consistent(const char *when)
{
    CHECK(b1_end() != b2_end(), "%s: ends are opposite (b1=%c, b2=%c)", when, b1_end(), b2_end());
    CHECK(b1_hb_end() == b1_end() && b2_hb_end() == b2_end(),
          "%s: heartbeat role follows the decision", when);
    CHECK(strcmp(b1_csv_role(), b1_end() == 'B' ? "wormhole_b" : "wormhole_a") == 0
          && strcmp(b2_csv_role(), b2_end() == 'B' ? "wormhole_b" : "wormhole_a") == 0,
          "%s: CSV role column follows the decision", when);
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "-v") == 0) g_verbose = true;

    printf("\n[1] Normal run, boards built the WRONG way (b1 fallback B is shallow H1,"
           " b2 fallback A is deep H6)\n");
    fresh(1, 6);
    run(3000);
    CHECK(!b1_locked() && !b2_locked(), "not locked before Phase 0");
    CHECK(b1_end() == 'A' && b2_end() == 'B', "provisional: shallow b1 = A, deep b2 = B");
    g_phase = PHASE_ID_BASELINE; run(500);
    CHECK(b1_locked() && b2_locked(), "both locked at Phase 0");
    CHECK(b1_end() == 'A' && b2_end() == 'B', "locked: b1 = A (exit), b2 = B (entry)");
    CHECK(!b1_fallback() && !b2_fallback() && !b1_conflict() && !b2_conflict(),
          "no fallback, no conflict");
    opposite_and_consistent("[1]");
    b1_set_layer(6); b2_set_layer(1); g_phase = PHASE_ID_WORMHOLE; run(3000);
    CHECK(b1_end() == 'A' && b2_end() == 'B', "mesh flipped after the lock -> roles do NOT follow");
    CHECK(b1_shortcut_lost() || b2_shortcut_lost(), "...but 'no longer a shortcut' is flagged");

    printf("\n[2] Same depth (H3 / H3): no shortcut possible -> opposite ends by MAC\n");
    fresh(3, 3); run(2000); g_phase = PHASE_ID_BASELINE; run(500);
    CHECK(b1_end() == 'A' && b2_end() == 'B', "lower MAC (b1) = A, higher MAC (b2) = B");
    opposite_and_consistent("[2]");

    printf("\n[3] Cable unplugged: no HELLO either way\n");
    fresh(1, 6); link_12 = link_21 = false;
    run(2000); g_phase = PHASE_ID_BASELINE; run(4000);
    CHECK(b1_locked() && b2_locked(), "both still lock (run is not blocked)");
    CHECK(b1_fallback() && b2_fallback(), "both report 'locked from BUILD FALLBACK'");
    CHECK(b1_end() == 'B' && b2_end() == 'A', "each kept its build flag (b1 B, b2 A)");

    printf("\n[4] Board reboots mid-run (powercycle) where its depth would now say the opposite\n");
    fresh(1, 6); run(2000); g_phase = PHASE_ID_BASELINE; run(500);
    CHECK(b1_end() == 'A' && b2_end() == 'B', "before reboot: b1 A, b2 B");
    b2_boot(MAC2, 1);                 /* b2 comes back SHALLOWER than b1 (H1 vs H1)... */
    b1_set_layer(6);                  /* ...and b1 is now deep */
    run(3000);
    CHECK(b2_locked() && b2_end() == 'B', "rebooted b2 mirrors b1's LOCKED role -> stays B");
    CHECK(b1_end() == 'A', "b1 untouched");
    opposite_and_consistent("[4]");

    printf("\n[5] Both lock the SAME end (stale layers at lock time) -> exactly one switches\n");
    fresh(1, 6); run(2000);
    link_12 = link_21 = false;        /* last HELLOs are now frozen        */
    b1_force_peer_layer(9); b2_force_peer_layer(9);   /* each thinks it is shallower */
    g_now_us += 0;                    /* still fresh (< 5 s)               */
    g_phase = PHASE_ID_BASELINE; b1_step(); b2_step();
    CHECK(b1_locked() && b2_locked() && b1_end() == 'A' && b2_end() == 'A',
          "setup: both locked as A");
    link_12 = link_21 = true; run(3000);
    CHECK(b1_conflict() && b2_conflict(), "both detect the conflict");
    CHECK(b1_end() == 'A' && b2_end() == 'B', "only the higher MAC (b2) switched, to B");
    opposite_and_consistent("[5]");

    printf("\n[6] Noisy cable: garbage bytes between every transfer\n");
    fresh(1, 6); noise = 7; run(3000); g_phase = PHASE_ID_BASELINE; run(500);
    CHECK(b1_end() == 'A' && b2_end() == 'B' && !b1_fallback() && !b2_fallback(),
          "HELLOs still get through (resync works)");
    CHECK(b1_bad_windows() > 0 && b2_bad_windows() > 0,
          "bad windows counted (b1 %u, b2 %u)", b1_bad_windows(), b2_bad_windows());

    printf("\n[7] Tunnel frames: accepted by A, ignored by B; HELLOs never mistaken for them\n");
    fresh(1, 6); run(2000); g_phase = PHASE_ID_BASELINE; run(500);
    uint8_t fr[64]; size_t n;
    for (uint32_t s = 1; s <= 5; s++) { n = b2_make_tunnel_frame(fr, s); b1_deliver(fr, n); }
    CHECK(b1_tunnel_rx() == 5, "A (b1) accepted 5 tunnel frames from B");
    for (uint32_t s = 1; s <= 3; s++) { n = b1_make_tunnel_frame(fr, s); b2_deliver(fr, n); }
    CHECK(b2_tunnel_rx() == 0, "B (b2) ignored tunnel frames");
    run(3000);
    CHECK(b1_tunnel_rx() == 5, "3 s of HELLOs did not count as tunnel frames");

    printf("\n[8] One direction of the cable broken (b2 -> b1 dead)\n");
    fresh(1, 6); link_21 = false; run(2000); g_phase = PHASE_ID_BASELINE; run(4000);
    CHECK(b1_fallback() && !b2_fallback(), "b1 (deaf) reports BUILD FALLBACK; b2 heard b1");
    printf("    note b1=%c b2=%c - a one-way cable cannot be fixed by software; the fallback"
           " error on b1 and the root's REVERSED/duplicate check are what catch it\n",
           b1_end(), b2_end());

    printf("\n%d check(s), %d failure(s)\n", checks, fails);
    return fails ? 1 : 0;
}
