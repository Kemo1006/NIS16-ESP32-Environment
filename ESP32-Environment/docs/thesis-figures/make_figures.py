"""Figures for the run-verification subsection (thesis). Data: datasets/analysis + verifier reports."""
import re, os, glob, csv
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Patch
from matplotlib.lines import Line2D

plt.rcParams.update({"font.family": "Times New Roman", "font.size": 10, "axes.titlesize": 11,
                     "axes.labelsize": 10, "savefig.dpi": 220, "axes.spines.top": False,
                     "axes.spines.right": False})
BASE = "A:/Angelo/Excelsior/THESIS/T/ESP32-Environment/datasets/analysis"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "figs"); os.makedirs(OUT, exist_ok=True)
VER = os.path.join(HERE, "verify")
C = dict(base="#2b6cb0", atk="#c53030", cool="#2f855a", grey="#718096", amber="#d69e2e",
         ok="#38a169", warn="#d69e2e", fail="#c53030", na="#e2e8f0", purple="#6b46c1")


def ft(attack, topo, site, scn, cols=None):
    return pd.read_csv(f"{BASE}/{attack}/{topo}/{site}/{scn}/feature_table.csv", usecols=cols, low_memory=False)


def rel_time(d, atk_label):
    t0 = d.loc[d.window_label == atk_label, "t_anchor_s"].min()
    return d.t_anchor_s - t0


# ---------------------------------------------------------------- Fig 1: flowchart
def fig_flow():
    fig, ax = plt.subplots(figsize=(7.4, 9.6)); ax.set_xlim(0, 100); ax.set_ylim(-4, 124); ax.axis("off")

    def box(x, y, w, h, title, body, fc, ec, tsz=9.6, bsz=8.2):
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.4,rounding_size=1.6", fc=fc, ec=ec, lw=1.2))
        ax.text(x + w / 2, y + h - 2.4, title, ha="center", va="top", fontsize=tsz, fontweight="bold")
        if body:
            ax.text(x + w / 2, y + h - 6.6, body, ha="center", va="top", fontsize=bsz, linespacing=1.25)

    def arrow(x1, y1, x2, y2):
        ax.annotate("", (x2, y2), (x1, y1), arrowprops=dict(arrowstyle="-|>", lw=1.1, color="#2d3748"))

    box(18, 109, 64, 12, "Capture of one run", "8 boards log at 10 Hz on internal flash and microSD;\nroot logs every probe arrival (phases 0 to 3)", "#edf2f7", "#4a5568")
    arrow(50, 109, 50, 105)
    box(18, 93, 64, 12, "Import and completeness (execution)", "every board's file present, card copy matches flash,\n≥ 95% of samples in each experiment phase", "#edf2f7", "#4a5568")
    arrow(50, 93, 50, 89)
    box(18, 77, 64, 12, "Windowing and features", "1 s windows (≥ 8 of 10 samples), 16 features,\nphase label from the root's schedule", "#edf2f7", "#4a5568")
    xs = [1, 26, 51, 76]; w = 23
    titles = ["1. Attack signature", "2. Topology", "3. Dataset", "4. Scenario"]
    bodies = ["3-sigma test of the\nprimary features,\nattack vs baseline\n(FR, PDR / TunnelIntensity,\nDuplicateRate);\n|change| ≥ 0.10,\n≥ 6 attack points",
              "layout at the start\nof the attack;\nshape = the topology\nthe run is filed as;\nno cycle, no re-routing\nin the baseline;\nmoves judged by role",
              "windows per board per\nphase ≥ 95%; missing\nboards graded by role;\nimpact check re-runs\nthe test without every\nboard that has a gap",
              "traffic = the filed\nscenario: 1 probe/s\n(stationary), 4 probes/s\n(highload) or 300 extra\nprobes 60 s into the\nattack (burst)"]
    cols = ["#fed7d7", "#c6f6d5", "#bee3f8", "#feebc8"]; ecs = ["#c53030", "#2f855a", "#2b6cb0", "#c05621"]
    for x, t, b, fc, ec in zip(xs, titles, bodies, cols, ecs):
        arrow(50, 77, x + w / 2, 70.6)
        box(x, 46, w, 24, t, b, fc, ec, tsz=9.2, bsz=7.6)
    box(2, 31, 96, 12, "Supporting setup checks (reported with the four checks)",
        "blackhole: attacker relayed then dropped, victims alive but cut off, bystanders still delivering\n"
        "wormhole: exactly one end A and one end B, A shallower than B, UART frames received, root duplicates; START log", "#faf5ff", "#6b46c1", tsz=8.8, bsz=7.4)
    for x in xs:
        arrow(x + w / 2, 46, 50, 43.6)
    arrow(50, 31, 50, 28)
    box(2, 12, 96, 16, "Outcome of the run (fixed rules, set before the results were read)",
        "PASS = signature PASS and setup PASS and dataset PASS or MINOR (gaps shown harmless)\n"
        "FAIL = testable, but the attack did not happen as designed (design check failed or no signature on valid data)\n"
        "INCONCLUSIVE = the data needed to decide is missing (never counted as a pass or a fail)", "#fffff0", "#975a16", tsz=9.2, bsz=7.8)
    arrow(50, 12, 50, 9)
    box(8, -3, 84, 12, "Campaign status",
        "DONE  ·  DONE - recapture advised (minor gap, e.g. scenario not applied)\n"
        "RECAPTURE REQUIRED (major gap, FAIL)  ·  replaced runs are moved to archive/ with the reason", "#f7fafc", "#4a5568", tsz=9.2, bsz=7.8)
    fig.savefig(f"{OUT}/fig_verify_flow.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 2: attack signature
def pooled(t, v, k=5):
    df = pd.DataFrame({"t": t, "v": v}).dropna().sort_values("t")
    df["b"] = (df.t // k)
    g = df.groupby("b").agg(t=("t", "mean"), v=("v", "mean"))
    return g.t.values, g.v.values


def fig_signature():
    fig, axs = plt.subplots(1, 2, figsize=(7.4, 3.0))
    d = ft("blackhole", "linear", "G402", "stationary", ["t_anchor_s", "window_label", "window_phase_mixed", "node_role", "ForwardingRatio"])
    d = d[d.node_role == "blackhole"].copy(); d["t"] = rel_time(d, 1)
    d = d[(d.t > -300) & (d.t < 300)]
    t, v = pooled(d.t, d.ForwardingRatio)
    base = v[t < 0]; mu, sd = base.mean(), base.std()
    ax = axs[0]
    ax.axvspan(0, 180, color=C["atk"], alpha=0.08, lw=0)
    ax.fill_between([-300, 300], mu - 3 * sd, mu + 3 * sd, color=C["base"], alpha=0.18, lw=0, label="baseline mean ± 3σ")
    ax.axhline(mu, color=C["base"], lw=0.8, ls="--")
    ax.plot(t, v, "o", ms=2.6, color="#2d3748", label="5 s point")
    ax.set(xlim=(-300, 300), ylim=(-0.08, 1.18), xlabel="time from the start of the attack (s)",
           ylabel="ForwardingRatio of the attacker", title="(a) Blackhole: linear, G402, stationary")
    ax.text(90, 0.55, "attack phase", ha="center", color=C["atk"], fontsize=9)
    ax.legend(loc="lower left", fontsize=7.5, frameon=False)
    d = ft("wormhole", "tree", "G402", "stationary", ["t_anchor_s", "window_label", "node_role", "TunnelIntensity"])
    d = d[d.node_role == "wormhole_b"].copy(); d["t"] = rel_time(d, 2)
    d = d[(d.t > -300) & (d.t < 300)]
    t, v = pooled(d.t, d.TunnelIntensity)
    base = v[t < 0]; mu, sd = base.mean(), base.std()
    ax = axs[1]
    ax.axvspan(0, 180, color=C["atk"], alpha=0.08, lw=0)
    ax.fill_between([-300, 300], mu - 3 * sd - 0.02, mu + 3 * sd + 0.02, color=C["base"], alpha=0.18, lw=0)
    ax.plot(t, v, "o", ms=2.6, color="#2d3748")
    ax.set(xlim=(-300, 300), ylim=(-0.1, 1.3), xlabel="time from the start of the attack (s)",
           ylabel="TunnelIntensity of end B (msg/s)", title="(b) Wormhole: tree, G402, stationary")
    ax.text(90, 0.6, "attack phase", ha="center", color=C["atk"], fontsize=9)
    fig.tight_layout(); fig.savefig(f"{OUT}/fig_verify_signature.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 3: topology layouts
def parse_layout(path):
    t = open(path, encoding="utf-8").read()
    lay = t.split("LAYOUT AT THE START")[1].split("SCENARIO ....")[0].splitlines()[1:]
    nodes = []
    for line in lay:
        m = re.match(r"^(\s*)([|`+\- ]*)([0-9A-F]{4})\s+(.*)$", line)
        if not m:
            continue
        depth = 0 if "ROOT" in m.group(4) else (len(m.group(1) + m.group(2)) - 7) // 4
        label = m.group(4).split("*")[0].strip()
        note = m.group(4).split("*")[1].strip() if "*" in m.group(4) else ""
        nodes.append([m.group(3), depth, label, note])
    parent = {}; stack = []
    for n in nodes:
        while stack and stack[-1][1] >= n[1]:
            stack.pop()
        parent[n[0]] = stack[-1][0] if stack else None
        stack.append(n)
    return nodes, parent


def draw_tree(ax, nodes, parent, title):
    kids = {}
    for n in nodes:
        kids.setdefault(parent[n[0]], []).append(n[0])
    info = {n[0]: n for n in nodes}
    pos = {}; nxt = [0]

    def place(v):
        ch = kids.get(v, [])
        if not ch:
            pos[v] = nxt[0]; nxt[0] += 1
        else:
            for c in ch:
                place(c)
            pos[v] = np.mean([pos[c] for c in ch])
    root = kids[None][0]; place(root)
    xs = {v: pos[v] for v in pos}; ys = {v: -info[v][1] for v in pos}
    for v in pos:
        if parent[v]:
            ax.plot([xs[v], xs[parent[v]]], [ys[v], ys[parent[v]]], color="#a0aec0", lw=1.1, zorder=1)
    for v in pos:
        lab = info[v][2]
        if "ROOT" in lab: fc, tx = "#2d3748", "R"
        elif "ATTACKER" in lab: fc, tx = C["atk"], "X"
        elif "WORMHOLE A" in lab: fc, tx = C["purple"], "A"
        elif "WORMHOLE B" in lab: fc, tx = C["purple"], "B"
        elif "VICTIM" in lab: fc, tx = "#feb2b2", ""
        elif "bystander" in lab: fc, tx = "#bee3f8", ""
        else: fc, tx = "#e2e8f0", ""
        ax.scatter(xs[v], ys[v], s=150, color=fc, edgecolor="#2d3748", lw=0.7, zorder=2)
        ax.text(xs[v], ys[v], tx, ha="center", va="center", fontsize=7, color="white", fontweight="bold", zorder=3)
        if info[v][3]:
            note = "moved parent" if "moved" in info[v][3] else "went silent"
            ax.text(xs[v], ys[v] - 0.36, note, fontsize=6.3, color="#975a16", ha="center", va="top")
    ax.set_title(title, fontsize=9)
    ax.set_xlim(min(xs.values()) - 0.8, max(xs.values()) + 0.8); ax.set_ylim(min(ys.values()) - 0.6, 0.6)
    ax.axis("off")


def fig_topology():
    runs = [("blackhole_linear_G402_stationary", "(a) Blackhole, linear"), ("blackhole_star_G402_stationary", "(b) Blackhole, star (attacker = hub)"),
            ("blackhole_tree_G402_stationary", "(c) Blackhole, tree"), ("blackhole_partial_mesh_G402_stationary", "(d) Blackhole, partial mesh"),
            ("wormhole_star_G402_highload", "(e) Wormhole, star (end A = hub)"), ("wormhole_tree_G402_stationary", "(f) Wormhole, tree")]
    fig, axs = plt.subplots(2, 3, figsize=(7.6, 5.6))
    for ax, (k, title) in zip(axs.flat, runs):
        nodes, parent = parse_layout(f"{VER}/{k}.txt.clean")
        draw_tree(ax, nodes, parent, title)
    h = [Line2D([], [], marker="o", ls="", ms=8, mfc=c, mec="#2d3748", label=l) for c, l in
         [("#2d3748", "root (R)"), (C["atk"], "blackhole attacker (X)"), (C["purple"], "wormhole end A / B"),
          ("#feb2b2", "victim"), ("#bee3f8", "bystander"), ("#e2e8f0", "other child")]]
    fig.legend(handles=h, loc="lower center", ncol=6, fontsize=7.5, frameon=False, handletextpad=0.3, columnspacing=0.9)
    fig.tight_layout(rect=(0, 0.05, 1, 1)); fig.savefig(f"{OUT}/fig_verify_topology.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 4: dataset coverage
def fig_dataset():
    d = ft("blackhole", "partial_mesh", "G402", "highload", ["node_id", "node_role", "window_label", "window_phase_id", "window_phase_mixed"])
    d = d[(d.node_role != "root") & (~d.window_phase_mixed.fillna(False).astype(bool))]
    exp = {"baseline": 300, "attack": 180, "cooldown": 120}
    def ph(r):
        if r.window_label == 1: return "attack"
        if r.window_label == 0 and r.window_phase_id == 0: return "baseline"
        if r.window_label == 0 and r.window_phase_id == 3: return "cooldown"
        return None
    d["ph"] = d.apply(ph, axis=1); d = d.dropna(subset=["ph"])
    g = d.groupby(["node_id", "ph"]).size().unstack().fillna(0)
    for p in exp: g[p] = (g[p] / exp[p] * 100).clip(upper=100)
    g.index = [i[-4:] for i in g.index]
    g = g.sort_index()
    fig, ax = plt.subplots(figsize=(7.2, 2.9))
    x = np.arange(len(g)); w = 0.26
    for i, (p, c) in enumerate([("baseline", C["base"]), ("attack", C["atk"]), ("cooldown", C["cool"])]):
        bars = ax.bar(x + (i - 1) * w, g[p], w, color=c, label=p)
        for xi, v in zip(x + (i - 1) * w, g[p]):
            if v < 95:
                ax.text(xi, v + 1.2, f"{v:.1f}%", ha="center", fontsize=8, color=c, fontweight="bold")
    ax.axhline(95, color="#2d3748", ls="--", lw=0.9); ax.text(len(g) - 0.45, 96, "95% floor", fontsize=8, ha="right")
    ax.set(xticks=x, xticklabels=g.index, ylim=(60, 106), ylabel="phase covered by windows (%)",
           xlabel="board (last four hex digits of its MAC address)", title="Blackhole, partial mesh, G402, highload")
    ax.legend(ncol=3, fontsize=8, frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.2))
    fig.tight_layout(); fig.savefig(f"{OUT}/fig_verify_dataset.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 5: scenario
def fig_scenario():
    fig, axs = plt.subplots(3, 1, figsize=(7.2, 5.0), sharex=True)
    for ax, scn, title in zip(axs, ["stationary", "highload", "burst"], ["(a) stationary", "(b) highload", "(c) burst"]):
        d = ft("blackhole", "star", "G402", scn, ["node_id", "node_role", "t_anchor_s", "window_label", "probes_count_delta"])
        d["t"] = rel_time(d, 1).round()
        c = d[d.node_role.isin(["child"])]
        s = c.groupby("t").probes_count_delta.mean()
        s = s[(s.index > -300) & (s.index < 300)]
        ax.axvspan(0, 180, color=C["atk"], alpha=0.08, lw=0)
        ax.plot(s.index, s.values, color="#2d3748", lw=0.8)
        if scn == "burst":
            ax.annotate("300 extra probes from one child\n~60 s into the attack", (63, s.loc[55:75].max()), (110, s.max() * 0.75),
                        fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))
        ax.set_ylabel("probes per child\nper second", fontsize=8.5); ax.set_title(title, loc="left", fontsize=9.5)
    axs[-1].set_xlabel("time from the start of the attack (s)")
    fig.tight_layout(); fig.savefig(f"{OUT}/fig_verify_scenario.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 6: outcome matrix
def fig_matrix():
    rows = list(csv.DictReader(open(os.path.join(HERE, "verify_summary.csv"))))
    rows = [r for r in rows if r["onplan"] == "True" and r["attack"] in ("blackhole", "wormhole")]
    order = {"linear": 0, "star": 1, "tree": 2, "partial_mesh": 3}; so = {"G402": 0, "DLSU_Library": 1, "Yuchengco": 2}
    sc = {"stationary": 0, "burst": 1, "highload": 2}
    checks = ["signature", "TOPOLOGY", "dataset", "SCENARIO", "setup", "outcome"]
    names = ["Attack\nsignature", "Topology", "Dataset", "Scenario", "Setup\n(roles)", "Outcome"]
    val = {"PASS": 2, "OK": 2, "MINOR": 1, "WARN": 1, "FAIL": 0, "INCONCLUSIVE": 0}
    fig, axs = plt.subplots(1, 2, figsize=(7.6, 7.6))
    cmap = matplotlib.colors.ListedColormap([C["fail"], C["warn"], C["ok"]])
    for ax, atk in zip(axs, ["blackhole", "wormhole"]):
        rr = sorted([r for r in rows if r["attack"] == atk], key=lambda r: (order[r["topology"]], so[r["site"]], sc[r["scenario"]]))
        M = np.array([[val.get(r[c], np.nan) for c in checks] for r in rr], float)
        ax.imshow(M, cmap=cmap, vmin=0, vmax=2, aspect="auto")
        ax.set_xticks(range(len(checks))); ax.set_xticklabels(names, fontsize=7.5)
        ax.xaxis.tick_top()
        lab = [f"{r['topology'].replace('partial_mesh', 'partial')} · {r['site'].replace('DLSU_Library', 'Library').replace('Yuchengco', 'Yuch.')} · {dict(stationary='stat.',burst='burst',highload='highl.')[r['scenario']]}" for r in rr]
        ax.set_yticks(range(len(rr))); ax.set_yticklabels(lab, fontsize=6.4)
        for i in range(1, 4): ax.axhline(i * 9 - 0.5, color="white", lw=2.5)
        ax.set_xticks(np.arange(-.5, len(checks)), minor=True); ax.set_yticks(np.arange(-.5, len(rr)), minor=True)
        ax.grid(which="minor", color="white", lw=0.6); ax.tick_params(which="minor", length=0)
        ax.set_title(f"{atk.capitalize()} runs (36)", fontsize=10, pad=34)
        for s in ax.spines.values(): s.set_visible(False)
    h = [Patch(color=C["ok"], label="passed"), Patch(color=C["warn"], label="warning or minor gap (result not affected)"), Patch(color=C["fail"], label="failed")]
    fig.legend(handles=h, loc="lower center", ncol=3, fontsize=8, frameon=False)
    fig.tight_layout(rect=(0, 0.03, 1, 1)); fig.savefig(f"{OUT}/fig_verify_matrix.png", bbox_inches="tight"); plt.close(fig)


# ---------------------------------------------------------------- Fig 7: wormhole tunnel
def fig_wormhole():
    rows = list(csv.DictReader(open(os.path.join(HERE, "wormhole_summary.csv"))))
    tops = ["linear", "star", "tree", "partial_mesh"]; nm = ["Linear", "Star", "Tree", "Partial mesh"]
    fig, axs = plt.subplots(1, 2, figsize=(7.4, 2.9))
    rng = np.random.default_rng(3)
    for i, tp in enumerate(tops):
        s = [r for r in rows if r["topology"] == tp]
        sk = np.array([int(r["skip"]) for r in s]); la = np.array([float(r["tunnel_ms"]) for r in s])
        cnt = pd.Series(sk).value_counts()
        for k, n in cnt.items():
            axs[0].scatter(i, k, s=40 + 45 * n, color=C["purple"], alpha=0.75, edgecolor="white")
            axs[0].text(i + 0.18, k, f"{n}", va="center", fontsize=8)
        axs[1].scatter(i + rng.uniform(-0.15, 0.15, len(la)), la, s=18, color=C["purple"], alpha=0.8, edgecolor="none")
        axs[1].plot([i - 0.25, i + 0.25], [np.median(la)] * 2, color="#2d3748", lw=1.4)
    axs[0].set(xticks=range(4), xticklabels=nm, ylabel="hops skipped by the tunnel", ylim=(0.4, 5.6), title="(a) Depth of end B minus depth of end A")
    axs[1].set(xticks=range(4), xticklabels=nm, ylabel="TunnelLatency (ms, log scale)", yscale="log", title="(b) Gap between the two copies at the root")
    fig.tight_layout(); fig.savefig(f"{OUT}/fig_wormhole_tunnel.png", bbox_inches="tight"); plt.close(fig)


if __name__ == "__main__":
    import sys
    todo = sys.argv[1:] or ["flow", "signature", "topology", "dataset", "scenario", "matrix", "wormhole"]
    for k in todo:
        globals()["fig_" + k](); print("ok", k)
