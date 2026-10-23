"""Final pooled clustering on the 80 on-plan runs (Section 6.4 method: non-attacker windows,
standardised features, 5 algorithms, k = 2..8, seeds 42/7/123, 6,000-window samples).
Labels: 0 normal (baseline + cooldown of every run, benign runs included), 1 blackhole, 2 wormhole.
Labels are used only after clustering."""
import glob, json, os, sys, time, warnings
import numpy as np, pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans, AgglomerativeClustering, DBSCAN, SpectralClustering
from sklearn.mixture import GaussianMixture
from sklearn.metrics import silhouette_score, davies_bouldin_score, adjusted_rand_score
from sklearn.neighbors import NearestNeighbors

warnings.filterwarnings("ignore")
BASE = "A:/Angelo/Excelsior/THESIS/T/ESP32-Environment/datasets/analysis"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cluster_out"); os.makedirs(OUT, exist_ok=True)
FULL = ["PDR", "ParentSwitchRate", "HopChangeCount", "HopStabilityDuration", "RSSI_mean", "RSSI_var", "RSSI_stability", "RSSI_Hop_Diff"]
COLS = FULL + ["node_role", "window_label", "window_phase_mixed", "exposure", "node_id"]


def load():
    parts = []
    for f in glob.glob(BASE + "/*/*/*/*/feature_table.csv"):
        a, t, l, s = os.path.normpath(f).replace(chr(92), "/").split("/")[-5:-1]
        if l == "home" or s == "jitter":
            continue
        d = pd.read_csv(f, usecols=COLS, low_memory=False)
        d = d[(d.node_role == "child") & d.window_label.notna() & (~d.window_phase_mixed.fillna(False).astype(bool))]
        d["attack"], d["topology"], d["site"], d["scenario"] = a, t, l, s
        d["run"] = f"{a}/{t}/{l}/{s}"
        parts.append(d)
    D = pd.concat(parts, ignore_index=True)
    D["y"] = 0
    D.loc[(D.attack == "blackhole") & (D.window_label == 1), "y"] = 1
    D.loc[(D.attack == "wormhole") & (D.window_label == 2), "y"] = 2
    D["victim"] = D.exposure.astype(str) == "downstream"
    # "felt" = windows in which the attack reached the board: victim windows of a blackhole attack
    D["felt"] = ((D.y == 1) & D.victim).astype(int)
    return D


def filters(P):
    keep, dropped = [], {}
    for f in FULL:
        top = P[f].round(6).value_counts(normalize=True).iloc[0]
        if top > 0.90:
            dropped[f] = round(100 * top, 1)
        else:
            keep.append(f)
    C = P[keep].corr().abs()
    removed = []
    for i, a in enumerate(keep):
        for b in keep[i + 1:]:
            if C.loc[a, b] > 0.85 and b not in removed:
                removed.append(b)
    red = [f for f in keep if f not in removed]
    maxr = max((C.loc[a, b] for i, a in enumerate(red) for b in red[i + 1:]), default=0)
    return red, dropped, removed, round(float(maxr), 3)


def purity(y, c):
    s = 0
    for k in np.unique(c):
        s += np.bincount(y[c == k]).max()
    return s / len(y)


def knee_eps(X, ms):
    d = np.sort(NearestNeighbors(n_neighbors=ms).fit(X).kneighbors(X)[0][:, -1])
    x = np.linspace(0, 1, len(d)); yy = (d - d.min()) / (d.max() - d.min() + 1e-12)
    return float(d[np.argmax(x - yy)])


def run(D, feats, tag, seeds=(42, 7, 123), ks=range(2, 9)):
    pool = D.dropna(subset=feats)
    rows = []
    for seed in seeds:
        S = pool.sample(n=min(6000, len(pool)), random_state=seed)
        X = StandardScaler().fit_transform(S[feats].values)
        y = S.y.values; felt = S.felt.values
        ms = len(feats) + 1
        eps = knee_eps(X, ms)
        db = DBSCAN(eps=eps, min_samples=ms).fit_predict(X)
        m = db != -1
        nclu = len(set(db[m]))
        sil = silhouette_score(X[m], db[m]) if nclu > 1 else np.nan
        dbi = davies_bouldin_score(X[m], db[m]) if nclu > 1 else np.nan
        rows.append(dict(set=tag, alg="DBSCAN", k=nclu, seed=seed, sil=sil, dbi=dbi, purity=purity(y, db),
                         ari=adjusted_rand_score(y, db), ari_felt=adjusted_rand_score(felt, db), noise=float((~m).mean()), eps=eps))
        for k in ks:
            labs = {
                "K-Means": KMeans(k, n_init=10, random_state=seed).fit_predict(X),
                "Ward": AgglomerativeClustering(k, linkage="ward").fit_predict(X),
                "GMM": GaussianMixture(k, random_state=seed).fit_predict(X),
                "Spectral": SpectralClustering(k, affinity="nearest_neighbors", n_neighbors=15, random_state=seed, assign_labels="cluster_qr").fit_predict(X),
            }
            for alg, c in labs.items():
                ok = len(set(c)) > 1
                rows.append(dict(set=tag, alg=alg, k=k, seed=seed,
                                 sil=silhouette_score(X, c) if ok else np.nan,
                                 dbi=davies_bouldin_score(X, c) if ok else np.nan,
                                 purity=purity(y, c), ari=adjusted_rand_score(y, c),
                                 ari_felt=adjusted_rand_score(felt, c)))
        print(tag, seed, "done", time.strftime("%X"), flush=True)
    return pd.DataFrame(rows), len(pool)


if __name__ == "__main__":
    D = load()
    info = dict(windows=len(D), by_y=D.y.value_counts().to_dict(),
                by_attack=D.attack.value_counts().to_dict(), runs=D.run.nunique(),
                felt=int(D.felt.sum()), bh_attack_bystander=int(((D.y == 1) & ~D.victim).sum()))
    full_pool = D.dropna(subset=FULL)
    red, dropped, removed, maxr = filters(full_pool)
    info.update(full_pool=len(full_pool), reduced=red, dropped=dropped, corr_removed=removed, max_r_reduced=maxr)
    # best possible ARI: exactly the felt windows in one group, everything else in the other
    yb = full_pool.y.values; info["ceiling_ari"] = float(adjusted_rand_score(yb, full_pool.felt.values))
    info["majority"] = float(full_pool.y.value_counts(normalize=True).iloc[0])
    # phase means for the three kinds of window
    info["means"] = D.groupby(["attack", "y"])[FULL].mean().round(4).reset_index().to_dict("records")
    json.dump(info, open(f"{OUT}/info.json", "w"), indent=1, default=str)
    print(json.dumps({k: v for k, v in info.items() if k != "means"}, indent=1, default=str))
    sets = {"FULL": FULL, "REDUCED": red, "REDUCED without PDR": [f for f in red if f != "PDR"]}
    allr = []
    for tag, feats in sets.items():
        r, n = run(D, feats, tag); r["pool"] = n; allr.append(r)
    R = pd.concat(allr); R.to_csv(f"{OUT}/results.csv", index=False)
    k2 = R[(R.k == 2) | (R.alg == "DBSCAN")].groupby(["set", "alg"])[["sil", "dbi", "purity", "ari", "ari_felt", "k"]].mean().round(3)
    print(k2)
    print(R.groupby(["set"])["ari"].agg(["min", "max"]).round(3))
