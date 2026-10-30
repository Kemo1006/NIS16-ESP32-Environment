# Verification: the defense study guide matches the final paper

**Date:** oct. 30, 2026 (Basti's laptop)
**Verdict:** 🔶 MOSTLY CONFIRMED. About 250 numbers and claims were checked; 2 were wrong, 4 were imprecise, 4 paper weak spots were missing. All are fixed in v2 of the guide.

## The claim

`Paper/Defense/THESIS3 Defense Study Guide oct. 30, 2026 v1.md` says: "Every number in this guide is taken from [the final paper], and the feature formulas were checked against `analysis/features.py`." The check covers:

1. Every number in the guide, against `Plan/Paper-Editing/1-Working-Copy/NIS16-Full_Thesis_Document.docx` (newest paper file, oct. 24, 2026 2:55 PM).
2. Every claim in context (the right table, the right group of boards, the right direction).
3. Every worked example, recomputed.
4. The Part 10 "weak spots" list: are they still in the paper, and is anything missing?

## Method

- The paper's text and all 106 tables were extracted from `word/document.xml` (paragraphs and table cells in document order).
- A script listed every number in the guide that does not appear as a whole number in the paper. Only derived values (worked-example steps) and one input (1,077) were left over.
- Chapters 5, 6 and 7 were then read in full against Parts 4 to 8, and Chapters 1 to 4 were checked claim by claim with targeted searches.
- Worked examples were recomputed in Python: 1/1077, z = -498.5, pooled SD 0.0336, the ARI ceiling (0.5154 from the Table 6.30 counts), purity 0.870, 16,499/38,232 = 43.2%, 420/600 = 0.70, Table 6.2 sums.
- The absolute-value note was checked in `ESP32-Environment/analysis/features.py` (lines 210 and 1230: `(recv - fwd).abs()`, `(... - expected_rssi).abs()`).
- Figures 4.16 and 4.17 in `Paper/Defense/images/` were viewed: both already show the hub design, as Part 10 says.

## Findings

| # | Guide (v1) | Paper | Kind | Fix in v2 |
|---|---|---|---|---|
| 1 | Part 9 and the Part 2 conformance line: the blackhole meets "4 of the 5" criteria of Airehrour et al. | Table 4.4 has 6 criteria, 5 met ("Receives rather than jamming" and "Drops instead of forwarding" are separate rows) | Wrong | 5 of 6, all six listed |
| 2 | Figure 6.10 note: "The strong pairs are formula-linked" | §6.3.1 names four strong pairs; RSSI_var/RSSI_stability (a few extreme windows) and ParentSwitchRate/HopChangeCount (attack windows only) are not formula links | Imprecise | All four pairs explained |
| 3 | Part 3 worked example: 1,077 received, 1 forwarded, "the value the paper reports" | The paper prints only 1.000 -> 0.001 (Table 4.4); 1,077 is in `docs/dataset-verification.md` | Unsourced | Source note added |
| 4 | "about 8 dB" between captures of the same cell (3 places) | §6.3.3 and §6.5.4: 8.1 dB (blackhole) and 7.1 dB (wormhole) | Imprecise | Exact values |
| 5 | "121 of 123 victims fell below 0.5 in the first second" | §6.2.1: all 123 in the first second, 121 in the first window, the other 2 within 1 s; §7.3 says the other 2 "in the following second" | Imprecise | Window wording |
| 6 | Part 10 lacked four weak spots | §6.5.3 cites "(Section 6.6)" twice, but 6.6 moved to §7.6; the Ch. 6 intro still says "(repository snapshot THESIS3, commit 970fb15)"; §6.2.2 "The spread does not grow with the hops skipped" overstates Figs 6.4/6.6; the Fig 6.15 paragraph says whiskers 5th-95th, but its script uses 1.5 IQR (found by the parallel deck check, MEMORY oct. 30 top entry) | Missing | Four rows added |
| 8 | Figs 6.4/6.6 captions: "the gap is not bigger where more hops are skipped", "no upward trend" | Fig 6.4: the two 5-hop linear cells have the largest medians (9.9, 8.3 ms) and the 4-hop cells 5.4-7.4 ms; §6.2.2 only supports "no relation can be claimed" (Spearman 0.25, p = 0.14) | Wrong | Captions reworded |
| 7 | Objective 3 "Mixed"; Table 6.13 PDR all-boards cell without †; pooled ceiling aside unlabelled | §7.4 "differed between the two attacks"; Table 6.13 has 86.9†; 0.337/0.323 are not in the paper | Minor | Fixed |

Everything else matched, including:

- All of Part 0's 25 numbers.
- Tables 4.1, 5.1 and 5.2, and Tables 6.1 to 6.35 as quoted.
- Every Part 10 row (all still present in the paper).
- The D-18/D-33/D-35 benign-run history.
- Formation and phase rules, the tunnel frame layout, the verifier rules, and the robustness numbers.

## The same slips in the defense deck (not edited)

`Paper/Defense/THESIS3-Defense oct. 30, 2026 (final paper).pptx` repeats some of them:

- Slide 8 and its notes: "4 of 5 criteria".
- Notes 11: says the 1,077/1 counts are "as in the paper".
- Slide 18: "121 of 123 victims cut off in the first second" (matches §7.3, acceptable).
- Slide 48 and notes 24 and 48: "only formula-linked pairs are strong".

The newer `... (final paper, plain graph guides).pptx` (1:27 AM) was open in PowerPoint during this check and was not inspected.

## Paper

The weak spots in Part 10 are not fixed in the paper. They are listed as checklist row B-defense30.
