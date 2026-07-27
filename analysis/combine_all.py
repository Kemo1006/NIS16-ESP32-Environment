"""
combine_all.py — concatenate every feature_table.csv under analysis/
into one combined dataset for the full-coverage M8 EDA pass.

Run this from inside the analysis/ folder:
    python combine_all.py
"""
import pandas as pd
import glob
import os

files = glob.glob(os.path.join("*", "*", "feature_table.csv"))

if not files:
    print("No feature_table.csv files found. Are you running this from analysis\\ ?")
    raise SystemExit(1)

dfs = []
for f in sorted(files):
    parts = f.split(os.sep)
    attack_type, topology = parts[0], parts[1]
    d = pd.read_csv(f)
    d["attack_type"] = attack_type
    d["topology"] = topology
    dfs.append(d)
    print(f"  loaded {f}: {len(d)} rows")

combined = pd.concat(dfs, ignore_index=True)
combined.to_csv("combined_all.csv", index=False)

print()
print(f"Combined dataset: {len(combined)} rows -> combined_all.csv")
print()
print("Rows per (attack_type, topology):")
print(combined.groupby(["attack_type", "topology"]).size().to_string())
print()
print("Label distribution (0=baseline, 1=blackhole, 2=wormhole):")
print(combined["Label"].value_counts().sort_index().to_string())
