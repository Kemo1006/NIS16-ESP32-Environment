/**
 * @file topology_graph.c
 * @brief See topology_graph.h. Pure C - builds on the host for tests
 *        (tools/topology_graph_host_test.c).
 */

#include "topology_graph.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── helpers ─────────────────────────────────────────────────────────────── */

static uint64_t mac48(const uint8_t *m)
{
    uint64_t v = 0;
    for (int i = 0; i < 6; i++) {
        v = (v << 8) | m[i];
    }
    return v;
}

static bool mac_is_zero(const uint8_t *m)
{
    for (int i = 0; i < 6; i++) {
        if (m[i] != 0) {
            return false;
        }
    }
    return true;
}

static void mac_str(const uint8_t *m, char *out)
{
    snprintf(out, 18, "%02x:%02x:%02x:%02x:%02x:%02x",
             m[0], m[1], m[2], m[3], m[4], m[5]);
}

/* A parent link is the parent's SoftAP BSSID, which on the ESP32 is its STA
 * MAC + 1. An exact STA match is accepted too, so callers that already hold
 * STA MACs work unchanged. */
static int resolve(const topo_node_t *nodes, size_t n, const uint8_t *link)
{
    if (mac_is_zero(link)) {
        return -1;
    }
    uint64_t p = mac48(link);
    for (size_t j = 0; j < n; j++) {
        uint64_t v = mac48(nodes[j].mac);
        if (v + 1 == p || v == p) {
            return (int)j;
        }
    }
    return -1;
}

/* Nodes reachable from @p start over child lists; fills layer[] if given. */
static int bfs_from(const topo_graph_t *g, int start, int *queue, int *layer)
{
    int head = 0, tail = 0, count = 0;
    queue[tail++] = start;
    if (layer) {
        layer[start] = 1;
    }
    while (head < tail) {
        int u = queue[head++];
        count++;
        for (int c = g->first_child[u]; c >= 0; c = g->next_sibling[c]) {
            if (layer) {
                layer[c] = layer[u] + 1;
            }
            queue[tail++] = c;
        }
    }
    return count;
}

/* ── build ───────────────────────────────────────────────────────────────── */

bool topo_build(topo_graph_t *g, const topo_node_t *nodes, size_t n)
{
    memset(g, 0, sizeof(*g));
    g->n = n;
    g->root = -1;
    if (n == 0) {
        return true;
    }

    g->parent       = malloc(n * sizeof(int));
    g->layer        = calloc(n, sizeof(int));
    g->child_count  = calloc(n, sizeof(int));
    g->first_child  = malloc(n * sizeof(int));
    g->next_sibling = malloc(n * sizeof(int));
    int *queue      = malloc(n * sizeof(int));
    if (!g->parent || !g->layer || !g->child_count || !g->first_child ||
        !g->next_sibling || !queue) {
        free(queue);
        topo_free(g);
        return false;
    }

    for (size_t i = 0; i < n; i++) {
        g->first_child[i]  = -1;
        g->next_sibling[i] = -1;
        int p = resolve(nodes, n, nodes[i].parent);
        if (p == (int)i) {
            p = -1;   /* a node can't parent itself; treat as a broken link */
            g->cycle = true;
        }
        if (p < 0 && !mac_is_zero(nodes[i].parent)) {
            g->unresolved++;
        }
        g->parent[i] = p;
    }

    /* Child lists in ascending index order: prepend while walking backwards. */
    for (size_t k = n; k-- > 0;) {
        int p = g->parent[k];
        if (p >= 0) {
            g->next_sibling[k] = g->first_child[p];
            g->first_child[p]  = (int)k;
            g->child_count[p]++;
        }
    }

    /* A parent chain that never reaches a parentless node is a cycle. */
    for (size_t i = 0; i < n && !g->cycle; i++) {
        int cur = (int)i;
        size_t steps = 0;
        while (cur >= 0 && steps <= n) {
            cur = g->parent[cur];
            steps++;
        }
        if (cur >= 0) {
            g->cycle = true;
        }
    }

    /* Root = the parentless node that carries the most of the mesh. Nothing
     * about its ID or position is assumed; a node that hasn't joined yet is
     * also parentless but reaches only itself. A node whose parent exists but
     * isn't in the set (not reported yet) is not a root - it only competes if
     * no genuinely parentless node exists. */
    int best = -1, best_count = 0;
    for (int allow_missing = 0; allow_missing <= 1 && best < 0; allow_missing++) {
        for (size_t i = 0; i < n; i++) {
            if (g->parent[i] >= 0 ||
                (!allow_missing && !mac_is_zero(nodes[i].parent))) {
                continue;
            }
            int c = bfs_from(g, (int)i, queue, NULL);
            if (c > best_count) {
                best = (int)i;
                best_count = c;
            }
        }
    }
    g->root = best;

    if (best >= 0) {
        g->reachable = bfs_from(g, best, queue, g->layer);
        for (size_t i = 0; i < n; i++) {
            if (g->layer[i] > g->max_layer) {
                g->max_layer = g->layer[i];
            }
        }
    }
    free(queue);
    return true;
}

void topo_free(topo_graph_t *g)
{
    free(g->parent);
    free(g->layer);
    free(g->child_count);
    free(g->first_child);
    free(g->next_sibling);
    memset(g, 0, sizeof(*g));
    g->root = -1;
}

/* ── walk ────────────────────────────────────────────────────────────────── */

void topo_walk(const topo_graph_t *g,
               void (*cb)(void *ctx, int idx, int depth), void *ctx)
{
    /* Iterative (sibling/parent links, no recursion, no stack array): a chain
     * can be hundreds of nodes deep and this runs on a small task stack. */
    int cur = g->root, depth = 0;
    while (cur >= 0) {
        cb(ctx, cur, depth);
        if (g->first_child[cur] >= 0) {
            cur = g->first_child[cur];
            depth++;
            continue;
        }
        while (cur != g->root && g->next_sibling[cur] < 0) {
            cur = g->parent[cur];
            depth--;
        }
        if (cur == g->root) {
            break;
        }
        cur = g->next_sibling[cur];
    }
}

/* ── validate ────────────────────────────────────────────────────────────── */

static topo_status_t check_partial(const topo_graph_t *g, const topo_node_t *nodes,
                                   char *reason, size_t reason_len)
{
    size_t n = g->n;
    size_t cap = 0, max_links = 1;
    for (size_t i = 0; i < n; i++) {
        cap += 1 + nodes[i].seen_count;
        if (1 + nodes[i].seen_count > max_links) {
            max_links = 1 + nodes[i].seen_count;
        }
    }
    int *ea      = malloc(cap * sizeof(int));
    int *eb      = malloc(cap * sizeof(int));
    int *parents = malloc(max_links * sizeof(int));
    int *hops    = malloc(n * sizeof(int));
    int *queue   = malloc(n * sizeof(int));
    if (!ea || !eb || !parents || !hops || !queue) {
        free(ea); free(eb); free(parents); free(hops); free(queue);
        snprintf(reason, reason_len, "out of memory checking partial mesh");
        return TOPO_WARN;
    }

    size_t e = 0;
    int multi = 0;
    for (size_t i = 0; i < n; i++) {
        size_t np = 0;
        for (size_t s = 0; s <= nodes[i].seen_count; s++) {
            int p = (s == 0) ? g->parent[i]
                             : resolve(nodes, n, nodes[i].seen_parents + 6 * (s - 1));
            if (p < 0 || p == (int)i) {
                continue;
            }
            bool dup = false;
            for (size_t k = 0; k < np; k++) {
                if (parents[k] == p) {
                    dup = true;
                    break;
                }
            }
            if (dup) {
                continue;
            }
            parents[np++] = p;

            int a = (int)i < p ? (int)i : p;
            int b = (int)i < p ? p : (int)i;
            bool have = false;
            for (size_t k = 0; k < e; k++) {
                if (ea[k] == a && eb[k] == b) {
                    have = true;
                    break;
                }
            }
            if (!have) {
                ea[e] = a;
                eb[e] = b;
                e++;
            }
        }
        if (np >= 2) {
            multi++;
        }
    }

    /* Min-hop layers over the union graph, from the same root. */
    for (size_t i = 0; i < n; i++) {
        hops[i] = 0;
    }
    int head = 0, tail = 0, depth = 0;
    queue[tail++] = g->root;
    hops[g->root] = 1;
    while (head < tail) {
        int u = queue[head++];
        if (hops[u] > depth) {
            depth = hops[u];
        }
        for (size_t k = 0; k < e; k++) {
            int v = (ea[k] == u) ? eb[k] : (eb[k] == u) ? ea[k] : -1;
            if (v >= 0 && hops[v] == 0) {
                hops[v] = hops[u] + 1;
                queue[tail++] = v;
            }
        }
    }
    long vcount = tail;
    long ecount = 0;
    for (size_t k = 0; k < e; k++) {
        if (hops[ea[k]] > 0) {
            ecount++;
        }
    }

    free(ea); free(eb); free(parents); free(hops); free(queue);

    if (vcount >= 3 && ecount == vcount * (vcount - 1) / 2) {
        snprintf(reason, reason_len,
                 "every pair of the %ld nodes is linked - that is a full mesh, not partial",
                 vcount);
        return TOPO_WARN;
    }
    if (multi == 0) {
        snprintf(reason, reason_len,
                 "%ld nodes, each seen under only one parent so far - still a plain tree "
                 "(depth %d)", vcount, g->max_layer);
        return TOPO_WARN;
    }
    snprintf(reason, reason_len,
             "%ld links over %ld nodes, %d node(s) seen under 2+ parents, "
             "tree depth %d, min-hop depth %d",
             ecount, vcount, multi, g->max_layer, depth);
    return TOPO_OK;
}

topo_status_t topo_validate(const topo_graph_t *g, const topo_node_t *nodes,
                            topo_kind_t kind, char *reason, size_t reason_len)
{
    char mac[18];
    topo_status_t st = TOPO_OK;

    if (g->n == 0) {
        snprintf(reason, reason_len, "no nodes");
        return TOPO_WARN;
    }
    if (g->cycle) {
        snprintf(reason, reason_len, "parent links form a cycle - not a valid mesh");
        return TOPO_FAIL;
    }
    if (g->root < 0) {
        snprintf(reason, reason_len, "no root found");
        return TOPO_FAIL;
    }

    switch (kind) {
    case TOPO_KIND_STAR:
        for (size_t i = 0; i < g->n; i++) {
            if (g->layer[i] > 2) {
                mac_str(nodes[i].mac, mac);
                snprintf(reason, reason_len,
                         "%s is at layer %d - a star allows only the center (1) and "
                         "its direct nodes (2)", mac, g->layer[i]);
                return TOPO_FAIL;
            }
        }
        mac_str(nodes[g->root].mac, mac);
        snprintf(reason, reason_len, "center %s + %d direct node(s)",
                 mac, g->reachable - 1);
        break;

    case TOPO_KIND_LINEAR: {
        int leaf = g->root;
        for (size_t i = 0; i < g->n; i++) {
            if (g->layer[i] == 0) {
                continue;
            }
            if (g->child_count[i] > 1) {
                mac_str(nodes[i].mac, mac);
                snprintf(reason, reason_len,
                         "%s has %d children - a linear chain allows 1 (branch)",
                         mac, g->child_count[i]);
                return TOPO_FAIL;
            }
            if (g->layer[i] == g->max_layer) {
                leaf = (int)i;
            }
        }
        char mac2[18];
        mac_str(nodes[g->root].mac, mac);
        mac_str(nodes[leaf].mac, mac2);
        snprintf(reason, reason_len, "chain of %d node(s), %s .. %s",
                 g->reachable, mac, mac2);
        break;
    }

    case TOPO_KIND_TREE:
        if (g->reachable >= 3 && g->max_layer <= 2) {
            snprintf(reason, reason_len,
                     "all %d nodes hang directly off the root - flat like a star (depth 2)",
                     g->reachable);
            st = TOPO_WARN;
        } else {
            snprintf(reason, reason_len, "%d node(s), depth %d",
                     g->reachable, g->max_layer);
        }
        break;

    case TOPO_KIND_PARTIAL:
        st = check_partial(g, nodes, reason, reason_len);
        break;

    default:
        snprintf(reason, reason_len, "unknown topology %d", (int)kind);
        return TOPO_FAIL;
    }

    int detached = (int)g->n - g->reachable;
    if (detached > 0) {
        size_t used = strlen(reason);
        if (used < reason_len) {
            snprintf(reason + used, reason_len - used,
                     "; %d node(s) not attached to the root", detached);
        }
        if (st == TOPO_OK) {
            st = TOPO_WARN;
        }
    }
    return st;
}

const char *topo_status_str(topo_status_t s)
{
    switch (s) {
    case TOPO_OK:   return "OK";
    case TOPO_WARN: return "WARN";
    case TOPO_FAIL: return "FAIL";
    default:        return "?";
    }
}

const char *topo_kind_str(topo_kind_t k)
{
    switch (k) {
    case TOPO_KIND_STAR:    return "STAR";
    case TOPO_KIND_TREE:    return "TREE";
    case TOPO_KIND_LINEAR:  return "LINEAR";
    case TOPO_KIND_PARTIAL: return "PARTIAL";
    default:                return "?";
    }
}
