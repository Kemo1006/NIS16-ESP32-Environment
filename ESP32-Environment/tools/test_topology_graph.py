"""
Tests for tools/topology_graph.py.   Run:  python -m unittest tools.test_topology_graph
(or from tools/:  python -m unittest test_topology_graph)

Mirrors tools/topology_graph_host_test.c, so the live root check and the
offline checker are held to the same rules.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import topology_graph as tg  # noqa: E402


def check(topology, links, history=None):
    g = tg.build_graph(links)
    return g, tg.validate(topology, g, history)


class LinearTests(unittest.TestCase):
    def test_any_length_no_layer_cap(self):
        for n in (3, 5, 7, 8, 10, 15, 20, 50, 1000):
            links, _ = tg.generate("linear", n)
            g, (st, reason) = check("linear", links)
            self.assertEqual(st, tg.OK, f"n={n}: {reason}")
            self.assertEqual(g.max_layer, n)
            self.assertEqual([g.layer[i] for i in range(n)], list(range(1, n + 1)))
            self.assertEqual((g.root, g.leaf()), (0, n - 1))

    def test_branch_fails(self):
        for n in (3, 7, 20):
            links, _ = tg.generate("linear", n)
            links[n] = n // 2
            _, (st, _) = check("linear", links)
            self.assertEqual(st, tg.FAIL, f"n={n}")


class StarTests(unittest.TestCase):
    def test_two_levels_for_any_size(self):
        for n in (3, 7, 10, 20, 50, 100):
            links, _ = tg.generate("star", n)
            g, (st, reason) = check("star", links)
            self.assertEqual(st, tg.OK, f"n={n}: {reason}")
            self.assertEqual(g.max_layer, 2)
            self.assertEqual(len(g.children[g.root]), n - 1)

    def test_layer_three_fails(self):
        for n in (3, 10, 50):
            links, _ = tg.generate("star", n)
            links[n - 1] = 1
            _, (st, _) = check("star", links)
            self.assertEqual(st, tg.FAIL, f"n={n}")

    def test_center_found_not_assumed(self):
        links = {"a": "hub", "b": "hub", "hub": None, "c": "hub"}
        g, (st, _) = check("star", links)
        self.assertEqual((g.root, st), ("hub", tg.OK))


class TreeTests(unittest.TestCase):
    def test_layers_follow_depth(self):
        for depth in (2, 3, 5, 10, 15, 25, 40):
            links, _ = tg.generate("tree", depth * 3, depth=depth, seed=depth)
            g, (st, reason) = check("tree", links)
            self.assertEqual(g.max_layer, depth, f"depth={depth}")
            expected = tg.WARN if depth <= 2 else tg.OK
            self.assertEqual(st, expected, f"depth={depth}: {reason}")

    def test_cycle_fails(self):
        _, (st, _) = check("tree", {0: None, 1: 2, 2: 1})
        self.assertEqual(st, tg.FAIL)

    def test_missing_parent_is_not_the_root(self):
        # real case: a chain whose middle board never exported - the fragment
        # below the gap is bigger than the root's side but is not the root
        links = {"root": None, "a": "board-not-exported", "b": "a", "c": "b"}
        g, (st, _) = check("linear", links)
        self.assertEqual(g.root, "root")
        self.assertEqual(sorted(g.detached), ["a", "b", "c"])
        self.assertEqual(st, tg.WARN)

    def test_detached_node_warns(self):
        links, _ = tg.generate("tree", 6, depth=3, seed=1)
        links[99] = "not-in-mesh"
        g, (st, _) = check("tree", links)
        self.assertEqual(st, tg.WARN)
        self.assertEqual(g.unresolved, [99])


class DynamicRootTests(unittest.TestCase):
    def test_layers_follow_the_root_not_ids(self):
        links = {i: i + 1 for i in range(5)}
        links[5] = None
        g, (st, _) = check("linear", links)
        self.assertEqual((g.root, st), (5, tg.OK))
        self.assertEqual((g.layer[5], g.layer[0]), (1, 6))

    def test_recalculates_when_structure_changes(self):
        links, _ = tg.generate("linear", 8)
        self.assertEqual(tg.build_graph(links).max_layer, 8)
        del links[7]                       # node removed
        self.assertEqual(tg.build_graph(links).max_layer, 7)
        links[3] = 0                       # connection moved
        g = tg.build_graph(links)
        self.assertEqual(g.layer[6], 5)


class PartialTests(unittest.TestCase):
    def test_alternate_parents_pass(self):
        for n in (4, 6, 9, 16, 30, 100):
            links, history = tg.generate("partial", n, seed=n)
            self.assertTrue(history)
            g, (st, reason) = check("partial", links, history)
            self.assertEqual(st, tg.OK, f"n={n}: {reason}")

    def test_without_history_is_just_a_tree(self):
        links, history = tg.generate("partial", 12, seed=3)
        _, (st, _) = check("partial", links, [])
        self.assertEqual(st, tg.WARN)
        _, (st, _) = check("partial", links, history)   # links added back
        self.assertEqual(st, tg.OK)

    def test_full_mesh_warns(self):
        n = 5
        links, _ = tg.generate("linear", n)
        history = [(a, b) for a in range(n) for b in range(n) if a != b]
        _, (st, reason) = check("partial", links, history)
        self.assertEqual(st, tg.WARN)
        self.assertIn("full mesh", reason)

    def test_min_hop_layers_use_union(self):
        links = {0: None, 1: 0, 2: 1, 3: 2}
        g = tg.build_graph(links)
        hops, _ = tg.union_layers(g, [(3, 0)])
        self.assertEqual((g.layer[3], hops[3]), (4, 2))


if __name__ == "__main__":
    unittest.main()
