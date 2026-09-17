/**
 * @file topology_graph.h
 * @brief Derive the mesh's shape from parent links and check it against the
 *        built topology's structural rules.
 *
 * Nothing here knows a node count, a layer count or a node ID in advance:
 * layers come from a breadth-first walk from whichever node turns out to be
 * the root, and each topology is judged by its STRUCTURE only:
 *
 *   STAR    - every node is a direct child of the center (max layer 2, any N)
 *   LINEAR  - every node has at most one child (a chain, any length)
 *   TREE    - one root, no cycles, any depth
 *   PARTIAL - a tree right now, but nodes have been seen under more than one
 *             parent over time, without every pair being linked (not full mesh)
 *
 * Pure C, no ESP-IDF calls, so the same file builds on the host for tests.
 * tools/topology_graph.py implements the same rules for offline analysis -
 * keep the two in step.
 */

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Values match NIS_TOPO_* in mesh_config.h, so MESH_TOPOLOGY casts directly. */
typedef enum {
    TOPO_KIND_STAR    = 0,
    TOPO_KIND_TREE    = 1,
    TOPO_KIND_LINEAR  = 2,
    TOPO_KIND_PARTIAL = 3
} topo_kind_t;

typedef enum {
    TOPO_OK   = 0,
    TOPO_WARN = 1,
    TOPO_FAIL = 2
} topo_status_t;

typedef struct {
    uint8_t        mac[6];        /**< identity: the node's STA MAC                    */
    uint8_t        parent[6];     /**< current parent as the mesh reports it (its
                                       SoftAP BSSID = STA + 1); all-zero = no parent */
    const uint8_t *seen_parents;  /**< 6 bytes per entry: every parent ever observed
                                       for this node (PARTIAL's union graph); may be
                                       NULL                                          */
    size_t         seen_count;
} topo_node_t;

typedef struct {
    size_t n;
    int    root;           /**< index of the root, -1 if none                        */
    int   *parent;         /**< resolved parent index, -1 = none                     */
    int   *layer;          /**< 1 = root, 0 = not reachable from the root            */
    int   *child_count;
    int   *first_child;    /**< -1 = leaf                                            */
    int   *next_sibling;   /**< -1 = last child                                      */
    int    reachable;      /**< nodes reachable from the root, root included         */
    int    max_layer;
    int    unresolved;     /**< nodes whose reported parent is not in the node set   */
    bool   cycle;          /**< some parent chain never reaches a parentless node    */
} topo_graph_t;

/** Build the graph. Allocates; release with topo_free(). false on OOM. */
bool topo_build(topo_graph_t *g, const topo_node_t *nodes, size_t n);

void topo_free(topo_graph_t *g);

/** Check the structure against @p kind. Writes a one-line reason. */
topo_status_t topo_validate(const topo_graph_t *g, const topo_node_t *nodes,
                            topo_kind_t kind, char *reason, size_t reason_len);

/** Depth-first pre-order walk from the root (depth 0 = root). */
void topo_walk(const topo_graph_t *g,
               void (*cb)(void *ctx, int idx, int depth), void *ctx);

const char *topo_status_str(topo_status_t s);
const char *topo_kind_str(topo_kind_t k);

#ifdef __cplusplus
}
#endif
