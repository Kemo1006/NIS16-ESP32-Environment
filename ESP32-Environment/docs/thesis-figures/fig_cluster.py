import json, pandas as pd, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
plt.rcParams.update({"font.family": "Times New Roman", "font.size": 10, "savefig.dpi": 220, "axes.spines.top": False, "axes.spines.right": False})
R = pd.concat([pd.read_csv("cluster_out/results.csv"), pd.read_csv("cluster_out/results_pdr4.csv")])
comp = json.load(open("cluster_out/composition.json"))
fig = plt.figure(figsize=(7.4, 6.0))
ax1 = fig.add_axes([0.08, 0.58, 0.40, 0.36]); ax2 = fig.add_axes([0.58, 0.58, 0.40, 0.36]); ax3 = fig.add_axes([0.14, 0.17, 0.62, 0.25])
cols = {"K-Means": "#2b6cb0", "Ward": "#2f855a", "GMM": "#d69e2e", "Spectral": "#6b46c1"}
for ax, s, t in [(ax1, "PDR + RSSI (as in 6.4.1)", "(a) PDR, RSSI_mean, RSSI_var, RSSI_Hop_Diff"), (ax2, "REDUCED", "(b) REDUCED by the filters (no PDR)")]:
    d = R[R.set == s]
    for alg, c in cols.items():
        g = d[d.alg == alg].groupby("k").ari.agg(["mean", "std"])
        ax.errorbar(g.index, g["mean"], yerr=g["std"], color=c, marker="o", ms=3, lw=1, capsize=2, label=alg)
    ax.axhline(d[d.alg == "DBSCAN"].ari.mean(), color="#c53030", ls=":", lw=1.2, label="DBSCAN")
    ax.axhline(0.335, color="#2d3748", ls="--", lw=0.8); ax.text(8, 0.347, "best possible 0.335", ha="right", fontsize=7.5)
    ax.set_xticks(range(2, 9)); ax.set_ylim(-0.05, 0.42); ax.set_xlabel("k (number of clusters)"); ax.set_ylabel("ARI against the label")
    ax.set_title(t, fontsize=9)
ax2.legend(fontsize=7.5, frameon=False, loc="center right", ncol=1)
kinds = ["blackhole attack, victim", "blackhole attack, bystander", "wormhole attack", "benign run", "normal phase of an attack run"]
kc = ["#c53030", "#90cdf4", "#6b46c1", "#68d391", "#2b6cb0"]
k2 = comp["2"]
for y, cl in enumerate(["0", "1"]):
    left = 0
    for kk, c in zip(kinds, kc):
        v = k2[cl].get(kk, 0)
        ax3.barh(y, v, left=left, color=c, height=0.55, label=kk if y == 0 else None); left += v
    ax3.text(102, y, f"n = {k2[cl]['n']}\nmean PDR {k2[cl]['meanPDR']:.2f}", va="center", fontsize=8)
ax3.set_yticks([0, 1]); ax3.set_yticklabels(["Cluster 0", "Cluster 1"]); ax3.invert_yaxis()
ax3.set_xlim(0, 100); ax3.set_xlabel("share of the windows of the cluster (%)")
ax3.set_title("(c) Content of each cluster: K-Means, k = 2, feature set (a), seed 42", fontsize=9)
ax3.legend(fontsize=7.5, frameon=False, loc="upper center", bbox_to_anchor=(0.6, -0.35), ncol=3)
fig.savefig("figs/fig_cluster_final.png")
