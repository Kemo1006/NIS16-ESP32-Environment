"""Per-run, per-phase MAC retry rate (802.11 Retry bit) from the *_retry.csv files
that tools/pcap_retry.py writes next to each sniffer capture.

Reads  datasets/PCAP/**/*_retry.csv   (never edits them)
Writes docs/data-and-results/macretry_<attack>_by_run.csv   one row per run
       docs/data-and-results/macretry_summary.txt           plain-text roll-up (both attacks)

Rates are retried frames / frames heard, pooled over the whole phase:
  all links     every transmitter -> receiver pair the sniffer heard (unicast data frames
                between mesh boards)
  attack link   blackhole: the attacker's own transmissions (ta_role BLACKHOLE)
                wormhole : tunnel end A's transmissions (ta_role WORMHOLE_A), the end that
                           re-injects the tunnelled probes
Which runs count: a capture whose _retry.json has phase segments (a refused capture's json
does not, and an old _retry.csv can be left next to it), and only the LATEST usable capture
per run cell (topology, location, scenario), like the dataset. Archived jitter runs live
outside datasets/PCAP and are not read.
Phases are placed on the laptop clock by tools/pcap_retry.py: blackhole by the attacker's
uplink rate drop, wormhole by end A's uplink rate rise, both over first transmissions only.
"""
import csv
import glob
import json
import os
import statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
PCAP = os.path.join(ROOT, "datasets", "PCAP")
OUT = os.path.join(ROOT, "docs", "data-and-results")
PHASES = ("baseline", "attack", "cooldown")
ROLE = {"blackhole": "BLACKHOLE", "wormhole": "WORMHOLE_A"}


def rate(f, r):
    return (100.0 * r / f) if f else float("nan")


def usable(csv_path, attack):
    jp = csv_path.replace("_retry.csv", "_retry.json")
    if not os.path.exists(jp):
        return None
    d = json.load(open(jp, encoding="utf-8"))
    if "segments" not in d or d.get("identity", {}).get("attack") != attack:
        return None
    i = d["identity"]
    return (i["topology"], i["location"], i["scenario"], d["capture_epoch"][0])


def one(path, attack):
    tot = {p: [0, 0] for p in PHASES}
    lnk = {p: [0, 0] for p in PHASES}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            seg = row["segment"]
            if seg not in tot:
                continue
            fr, rt = int(row["frames"]), int(row["retries"])
            tot[seg][0] += fr
            tot[seg][1] += rt
            if row["ta_role"] == ROLE[attack]:
                lnk[seg][0] += fr
                lnk[seg][1] += rt
    rel = os.path.relpath(path, PCAP).replace("\\", "/").split("/")
    out = {"attack": attack, "topology": rel[1], "location": rel[2], "scenario": rel[3],
           "capture": os.path.basename(path).replace("_retry.csv", "")}
    for p in PHASES:
        out[f"{p}_frames"] = tot[p][0]
        out[f"{p}_pct"] = round(rate(*tot[p]), 2)
        out[f"{p}_link_frames"] = lnk[p][0]
        out[f"{p}_link_pct"] = round(rate(*lnk[p]), 2)
    return out


def rows_for(attack):
    best, skipped = {}, 0
    for pth in sorted(glob.glob(os.path.join(PCAP, attack, "**", "*_retry.csv"), recursive=True)):
        k = usable(pth, attack)
        if k is None:
            skipped += 1
            continue
        cell, t0 = k[:3], k[3]
        if cell not in best or t0 > best[cell][0]:
            best[cell] = (t0, pth)
    return [one(p, attack) for _, p in best.values()], skipped


def summarise(attack, rows, skipped):
    ok = [r for r in rows if r["baseline_frames"] and r["attack_frames"]]
    L = [f"== {attack.upper()}: {len(rows)} runs with per-phase data (latest capture per cell; "
         f"{skipped} refused/stale files skipped); {len(ok)} have frames in both baseline and attack"]
    d = [r["attack_pct"] - r["baseline_pct"] for r in ok]
    L.append(f"All links: baseline mean {st.mean(r['baseline_pct'] for r in ok):.1f}%, "
             f"attack mean {st.mean(r['attack_pct'] for r in ok):.1f}%, "
             f"cooldown mean {st.mean(r['cooldown_pct'] for r in ok if r['cooldown_frames']):.1f}%")
    L.append(f"Attack minus baseline (all links) per run: mean {st.mean(d):+.2f} pts, median {st.median(d):+.2f}, "
             f"up in {sum(x > 0 for x in d)} of {len(d)}, range {min(d):+.1f} to {max(d):+.1f}")
    a = [r for r in ok if r["attack_link_frames"] and r["baseline_link_frames"]]
    da = [r["attack_link_pct"] - r["baseline_link_pct"] for r in a]
    if da:
        L.append(f"{ROLE[attack]} link: baseline mean {st.mean(r['baseline_link_pct'] for r in a):.1f}%, "
                 f"attack mean {st.mean(r['attack_link_pct'] for r in a):.1f}%; attack minus baseline mean "
                 f"{st.mean(da):+.2f}, median {st.median(da):+.2f}, up in {sum(x > 0 for x in da)} of {len(da)}; "
                 f"median frames baseline {st.median(r['baseline_link_frames'] for r in a):.0f} "
                 f"attack {st.median(r['attack_link_frames'] for r in a):.0f}")
    for key in ("topology", "location", "scenario"):
        for v in sorted({r[key] for r in ok}):
            sub = [r for r in ok if r[key] == v]
            L.append(f"  {key:9s} {v:14s} n={len(sub):2d}  baseline {st.mean(r['baseline_pct'] for r in sub):5.1f}%  "
                     f"attack {st.mean(r['attack_pct'] for r in sub):5.1f}%")
    return L, ok


def main():
    os.makedirs(OUT, exist_ok=True)
    lines = []
    for attack in ("blackhole", "wormhole"):
        rows, skipped = rows_for(attack)
        if not rows:
            lines.append(f"== {attack.upper()}: no usable captures")
            continue
        with open(os.path.join(OUT, f"macretry_{attack}_by_run.csv"), "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        L, _ = summarise(attack, rows, skipped)
        lines += L + [""]
    with open(os.path.join(OUT, "macretry_summary.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
