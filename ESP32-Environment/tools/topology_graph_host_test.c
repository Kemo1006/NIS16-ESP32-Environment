/*
 * Host test for components/mesh_common/src/topology_graph.c (no ESP-IDF).
 *
 *   gcc -std=c11 -Wall -Wextra -Werror -I components/mesh_common/include ^
 *       components/mesh_common/src/topology_graph.c tools/topology_graph_host_test.c ^
 *       -o topo_test && topo_test
 *
 * Same cases as tools/test_topology_graph.py, so the firmware and the offline
 * checker are held to the same rules.
 */

#include "topology_graph.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int s_fail = 0;
static int s_pass = 0;

#define CHECK(cond, ...)                                  \
    do {                                                  \
        if (cond) {                                       \
            s_pass++;                                     \
        } else {                                          \
            s_fail++;                                     \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);   \
            printf(__VA_ARGS__);                          \
            printf("\n");                                 \
        }                                                 \
    } while (0)

/* STA MACs 4 apart, so a SoftAP BSSID (STA + 1) never equals another STA. */
static void sta(size_t i, uint8_t *out)
{
    uint64_t v = 0x020000000000ULL + (uint64_t)i * 4;
    for (int b = 5; b >= 0; b--) {
        out[b] = (uint8_t)(v & 0xff);
        v >>= 8;
    }
}

static void link_to(topo_node_t *nodes, size_t child, size_t parent)
{
    sta(parent, nodes[child].parent);
    uint64_t v = 0;
    for (int b = 0; b < 6; b++) {
        v = (v << 8) | nodes[child].parent[b];
    }
    v += 1;   /* the mesh reports the parent's SoftAP BSSID */
    for (int b = 5; b >= 0; b--) {
        nodes[child].parent[b] = (uint8_t)(v & 0xff);
        v >>= 8;
    }
}

static topo_node_t *make_nodes(size_t n)
{
    topo_node_t *nodes = calloc(n, sizeof(topo_node_t));
    for (size_t i = 0; i < n; i++) {
        sta(i, nodes[i].mac);
    }
    return nodes;
}

static topo_status_t run(topo_node_t *nodes, size_t n, topo_kind_t kind,
                         topo_graph_t *g, char *reason)
{
    topo_build(g, nodes, n);
    return topo_validate(g, nodes, kind, reason, 256);
}

/* ── generators ──────────────────────────────────────────────────────────── */

static topo_node_t *gen_linear(size_t n)
{
    topo_node_t *nodes = make_nodes(n);
    for (size_t i = 1; i < n; i++) {
        link_to(nodes, i, i - 1);
    }
    return nodes;
}

static topo_node_t *gen_star(size_t n)
{
    topo_node_t *nodes = make_nodes(n);
    for (size_t i = 1; i < n; i++) {
        link_to(nodes, i, 0);
    }
    return nodes;
}

/* Spine of `depth` layers, plus one side leaf on every spine node that still
 * has room below it - branched, and exactly `depth` layers deep. */
static topo_node_t *gen_tree(int depth, size_t *n_out)
{
    size_t n = (size_t)depth + (size_t)(depth > 1 ? depth - 1 : 0);
    topo_node_t *nodes = make_nodes(n);
    for (int i = 1; i < depth; i++) {
        link_to(nodes, (size_t)i, (size_t)(i - 1));
    }
    size_t next = (size_t)depth;
    for (int i = 0; i < depth - 1; i++) {
        link_to(nodes, next++, (size_t)i);
    }
    *n_out = n;
    return nodes;
}

/* ── tests ───────────────────────────────────────────────────────────────── */

static int s_walk_count;
static int s_walk_max_depth;
static void count_cb(void *ctx, int idx, int depth)
{
    (void)ctx;
    (void)idx;
    s_walk_count++;
    if (depth > s_walk_max_depth) {
        s_walk_max_depth = depth;
    }
}

static void test_linear(void)
{
    const size_t sizes[] = {3, 5, 7, 8, 10, 15, 20, 50, 1000};
    for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        size_t n = sizes[s];
        topo_node_t *nodes = gen_linear(n);
        topo_graph_t g;
        char reason[256];
        topo_status_t st = run(nodes, n, TOPO_KIND_LINEAR, &g, reason);
        CHECK(st == TOPO_OK, "linear n=%zu: %s (%s)", n, topo_status_str(st), reason);
        CHECK(g.max_layer == (int)n, "linear n=%zu: max_layer %d", n, g.max_layer);
        CHECK(g.reachable == (int)n, "linear n=%zu: reachable %d", n, g.reachable);
        for (size_t i = 0; i < n; i++) {
            CHECK(g.layer[i] == (int)i + 1, "linear n=%zu node %zu layer %d", n, i, g.layer[i]);
        }
        s_walk_count = 0;
        s_walk_max_depth = 0;
        topo_walk(&g, count_cb, NULL);
        CHECK(s_walk_count == (int)n && s_walk_max_depth == (int)n - 1,
              "linear n=%zu walk %d/%d", n, s_walk_count, s_walk_max_depth);
        topo_free(&g);

        /* one extra child on the middle node = a branch */
        topo_node_t *b = make_nodes(n + 1);
        memcpy(b, nodes, n * sizeof(topo_node_t));
        sta(n, b[n].mac);
        link_to(b, n, n / 2);
        st = run(b, n + 1, TOPO_KIND_LINEAR, &g, reason);
        CHECK(st == TOPO_FAIL, "linear branch n=%zu: %s", n, topo_status_str(st));
        topo_free(&g);
        free(b);
        free(nodes);
    }
}

static void test_star(void)
{
    const size_t sizes[] = {3, 7, 10, 20, 50, 100};
    for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        size_t n = sizes[s];
        topo_node_t *nodes = gen_star(n);
        topo_graph_t g;
        char reason[256];
        topo_status_t st = run(nodes, n, TOPO_KIND_STAR, &g, reason);
        CHECK(st == TOPO_OK, "star n=%zu: %s (%s)", n, topo_status_str(st), reason);
        CHECK(g.max_layer == 2, "star n=%zu: max_layer %d", n, g.max_layer);
        CHECK(g.child_count[0] == (int)n - 1, "star n=%zu: center children %d", n, g.child_count[0]);
        topo_free(&g);

        /* re-hang the last node under another leaf = layer 3 */
        link_to(nodes, n - 1, 1);
        st = run(nodes, n, TOPO_KIND_STAR, &g, reason);
        CHECK(st == TOPO_FAIL, "star layer-3 n=%zu: %s", n, topo_status_str(st));
        topo_free(&g);
        free(nodes);
    }
}

static void test_tree(void)
{
    const int depths[] = {2, 3, 5, 10, 15, 25, 40};
    for (size_t s = 0; s < sizeof(depths) / sizeof(depths[0]); s++) {
        int d = depths[s];
        size_t n;
        topo_node_t *nodes = gen_tree(d, &n);
        topo_graph_t g;
        char reason[256];
        topo_status_t st = run(nodes, n, TOPO_KIND_TREE, &g, reason);
        CHECK(g.max_layer == d, "tree depth=%d: max_layer %d", d, g.max_layer);
        if (d <= 2) {
            CHECK(st == TOPO_WARN, "tree depth=%d should warn (flat): %s", d, topo_status_str(st));
        } else {
            CHECK(st == TOPO_OK, "tree depth=%d: %s (%s)", d, topo_status_str(st), reason);
        }
        topo_free(&g);
        free(nodes);
    }

    /* cycle: 1 -> 2 -> 1, root 0 alone */
    topo_node_t *c = make_nodes(3);
    link_to(c, 1, 2);
    link_to(c, 2, 1);
    topo_graph_t g;
    char reason[256];
    topo_status_t st = run(c, 3, TOPO_KIND_TREE, &g, reason);
    CHECK(st == TOPO_FAIL && g.cycle, "tree cycle: %s cycle=%d", topo_status_str(st), g.cycle);
    topo_free(&g);
    free(c);

    /* detached node: parent points at a MAC not in the set */
    topo_node_t *d = gen_linear(4);
    memset(d[3].parent, 0x7e, 6);
    st = run(d, 4, TOPO_KIND_TREE, &g, reason);
    CHECK(st == TOPO_WARN && g.reachable == 3 && g.unresolved == 1,
          "tree detached: %s reach=%d unres=%d", topo_status_str(st), g.reachable, g.unresolved);
    topo_free(&g);
    free(d);

    /* missing parent: chain 0 | gap | 1->2->3 hangs off a node not in the set.
     * The bigger fragment must not be taken for the root. */
    topo_node_t *m = gen_linear(4);
    memset(m[1].parent, 0x7e, 6);
    st = run(m, 4, TOPO_KIND_LINEAR, &g, reason);
    CHECK(st == TOPO_WARN && g.root == 0 && g.reachable == 1,
          "missing parent: %s root=%d reach=%d", topo_status_str(st), g.root, g.reachable);
    topo_free(&g);
    free(m);
}

static void test_root_is_dynamic(void)
{
    /* chain 0..5 rebuilt with node 5 as the root: layers follow, IDs don't */
    size_t n = 6;
    topo_node_t *nodes = make_nodes(n);
    for (size_t i = 0; i < n - 1; i++) {
        link_to(nodes, i, i + 1);
    }
    topo_graph_t g;
    char reason[256];
    topo_status_t st = run(nodes, n, TOPO_KIND_LINEAR, &g, reason);
    CHECK(st == TOPO_OK && g.root == 5, "reversed chain root=%d %s", g.root, topo_status_str(st));
    CHECK(g.layer[5] == 1 && g.layer[0] == 6, "reversed chain layers %d %d", g.layer[5], g.layer[0]);
    topo_free(&g);
    free(nodes);
}

static void test_partial(void)
{
    const size_t sizes[] = {4, 6, 9, 16, 30};
    for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        size_t n = sizes[s];
        /* snapshot: binary-ish tree (parent = (i-1)/2) */
        topo_node_t *nodes = make_nodes(n);
        for (size_t i = 1; i < n; i++) {
            link_to(nodes, i, (i - 1) / 2);
        }
        topo_graph_t g;
        char reason[256];
        topo_status_t st = run(nodes, n, TOPO_KIND_PARTIAL, &g, reason);
        CHECK(st == TOPO_WARN, "partial n=%zu no history should warn: %s", n, topo_status_str(st));
        topo_free(&g);

        /* history: every odd node was once under the root too */
        uint8_t *hist = calloc(n, 6);
        for (size_t i = 3; i < n; i += 2) {
            topo_node_t tmp = {0};
            link_to(&tmp, 0, 0);   /* fills tmp.parent with root's BSSID */
            memcpy(hist + 6 * i, tmp.parent, 6);
            nodes[i].seen_parents = hist + 6 * i;
            nodes[i].seen_count = 1;
        }
        st = run(nodes, n, TOPO_KIND_PARTIAL, &g, reason);
        CHECK(st == TOPO_OK, "partial n=%zu with alternates: %s (%s)", n, topo_status_str(st), reason);
        topo_free(&g);

        /* links removed again -> recalculated back to a plain tree */
        for (size_t i = 0; i < n; i++) {
            nodes[i].seen_count = 0;
        }
        st = run(nodes, n, TOPO_KIND_PARTIAL, &g, reason);
        CHECK(st == TOPO_WARN, "partial n=%zu history removed: %s", n, topo_status_str(st));
        topo_free(&g);
        free(hist);
        free(nodes);
    }

    /* full mesh of 4: every node seen under every other node */
    size_t n = 4;
    topo_node_t *nodes = gen_linear(n);
    uint8_t *hist = calloc(n * n, 6);
    for (size_t i = 0; i < n; i++) {
        size_t k = 0;
        for (size_t j = 0; j < n; j++) {
            if (j == i) {
                continue;
            }
            topo_node_t tmp = {0};
            link_to(&tmp, 0, j);
            memcpy(hist + 6 * (i * n + k), tmp.parent, 6);
            k++;
        }
        nodes[i].seen_parents = hist + 6 * i * n;
        nodes[i].seen_count = n - 1;
    }
    topo_graph_t g;
    char reason[256];
    topo_status_t st = run(nodes, n, TOPO_KIND_PARTIAL, &g, reason);
    CHECK(st == TOPO_WARN && strstr(reason, "full mesh"), "full mesh: %s (%s)", topo_status_str(st), reason);
    topo_free(&g);
    free(hist);
    free(nodes);
}

int main(void)
{
    test_linear();
    test_star();
    test_tree();
    test_root_is_dynamic();
    test_partial();
    printf("%d passed, %d failed\n", s_pass, s_fail);
    return s_fail ? 1 : 0;
}
