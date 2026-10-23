import json, numpy as np, pandas as pd
from cluster_final import load, run, OUT
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import adjusted_rand_score
D = load()
feats = ["PDR", "RSSI_mean", "RSSI_var", "RSSI_Hop_Diff"]
r, n = run(D, feats, "PDR + RSSI (as in 6.4.1)"); r["pool"] = n
r.to_csv(f"{OUT}/results_pdr4.csv", index=False)
print(r[(r.k == 2) | (r.alg == "DBSCAN")].groupby("alg")[["sil", "dbi", "purity", "ari", "ari_felt", "k"]].mean().round(3))
print("ARI range k2-8:", r.ari.min().round(3), r.ari.max().round(3))
# composition and per-attack agreement, K-Means k=2 and k=3, seed 42
pool = D.dropna(subset=feats)
S = pool.sample(n=6000, random_state=42); X = StandardScaler().fit_transform(S[feats].values)
comp = {}
for k in (2, 3):
    c = KMeans(k, n_init=10, random_state=42).fit_predict(X)
    S2 = S.assign(c=c)
    kind = np.select([(S2.y == 1) & S2.victim, S2.y == 1, S2.y == 2, S2.attack == "baseline"],
                     ["blackhole attack, victim", "blackhole attack, bystander", "wormhole attack", "benign run"], "normal phase of an attack run")
    S2 = S2.assign(kind=kind)
    comp[k] = {int(cl): {"n": int((S2.c == cl).sum()), **{kk: round(100 * v, 1) for kk, v in S2[S2.c == cl].kind.value_counts(normalize=True).items()},
                         "meanPDR": round(float(S2[S2.c == cl].PDR.mean()), 3)} for cl in sorted(set(c))}
    comp[k]["ari_bh_vs_rest"] = round(float(adjusted_rand_score((S2.y == 1).astype(int), c)), 3)
    comp[k]["ari_wh_vs_rest"] = round(float(adjusted_rand_score((S2.y == 2).astype(int), c)), 3)
    comp[k]["ari_3"] = round(float(adjusted_rand_score(S2.y, c)), 3)
json.dump(comp, open(f"{OUT}/composition.json", "w"), indent=1)
print(json.dumps(comp, indent=1))
# ceiling for this pool
print("ceiling", round(adjusted_rand_score(pool.y, pool.felt), 3), "majority", round(pool.y.value_counts(normalize=True).iloc[0], 3), "pool", len(pool))
print(pool.groupby("attack").y.value_counts())
