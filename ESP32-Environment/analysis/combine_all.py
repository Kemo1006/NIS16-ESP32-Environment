"""
combine_all.py — concatenate every feature_table.csv under analysis/
into one combined dataset for the full-coverage M8 EDA pass.

Folder shape is <attack>/<topology>/feature_table.csv for runs recorded
before the SD-card location work, and <attack>/<topology>/<location>/
feature_table.csv (home | G402 | DLSU_Library | Goks) for every run since —
run.ps1 has required --location for any -Export/-Analyze since sep. 12,
2026 (see MEMORY.md). Walking recursively and reading the location off
however many path segments are actually there (instead of a fixed-depth
glob) means a run tagged with a site is never silently dropped from the
combined dataset the way a `*/*/feature_table.csv` glob would drop it.

Run this from inside the analysis/ folder:
    python combine_all.py
"""
import pandas as pd
import glob
import os

files = glob.glob(os.path.join("**", "feature_table.csv"), recursive=True)

if not files:
    print("No feature_table.csv files found. Are you running this from analysis\\ ?")
    raise SystemExit(1)

dfs = []
for f in sorted(files):
    d = pd.read_csv(f)

    # preprocess.py now writes attack/topology/location/scenario into every row,
    # so the table describes itself. Prefer those; fall back to the folder path
    # for feature tables generated before that change. The path fallback is also
    # why `scenario` matters here: it used to be dropped entirely, so a
    # `mobility` run and a `none` run in the same cell pooled into one group with
    # no way to separate them afterwards.
    dir_parts = f.split(os.sep)[:-1]  # drop the filename itself

    def _resolve(column, part_index, default):
        if column in d.columns and d[column].notna().any():
            return d[column].fillna(default)
        # Pre-location captures have no third segment; label them "unrecorded"
        # to match the convention run_matrix.py used to backfill run_ledger.csv.
        return dir_parts[part_index] if len(dir_parts) > part_index else default

    attack_type = _resolve("attack", 0, "unrecorded")
    topology = _resolve("topology", 1, "unrecorded")
    location = _resolve("location", 2, "unrecorded")
    # No scenario folder means the `none` scenario — absence IS the value.
    scenario = _resolve("scenario", 3, "none")

    d["attack_type"] = attack_type
    d["topology"] = topology
    d["location"] = location
    d["scenario"] = scenario
    # Avoid shipping both `attack` and `attack_type` for the same fact.
    d = d.drop(columns=["attack"], errors="ignore")

    dfs.append(d)
    print(f"  loaded {f}: {len(d)} rows")

combined = pd.concat(dfs, ignore_index=True)
combined.to_csv("combined_all.csv", index=False)

print()
print(f"Combined dataset: {len(combined)} rows -> combined_all.csv")
print()
print("Rows per (attack_type, topology, location, scenario):")
print(combined.groupby(["attack_type", "topology", "location", "scenario"]).size().to_string())
print()
print("Label distribution (0=baseline, 1=blackhole, 2=wormhole):")
print(combined["Label"].value_counts().sort_index().to_string())
