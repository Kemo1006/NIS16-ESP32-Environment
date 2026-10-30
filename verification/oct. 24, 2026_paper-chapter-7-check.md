# Verification: Chapter 7 of the paper matches Chapters 4-6

**Date:** oct. 24, 2026
**Verdict:** 🔶 PARTIALLY CONFIRMED (about 60 checks; 56 match, 2 are wrong in Chapter 7, 2 are smaller wording issues)

## The claim

Chapter 7 (Conclusion and Recommendations) of `Plan/Paper-Editing/1-Working-Copy/FINAL THESIS3 OFFICIAL (4) - Recommendations in Chapter 7.docx` says "Every number in this chapter comes from Chapters 4 to 6." The check covers three things:

1. Every number and factual claim in Chapter 7 appears the same way in Chapters 1-6 of the same file.
2. Every section, table and deviation reference points to a section that exists and says that.
3. The structure is sound (7.1-7.6 in order, nothing repeated, no dangling references).

The user also asked, mid-check, whether the paper explains the failed captures anywhere besides the §7.3 paragraph "Failed captures were replaced and reported...".

## What this means (plain language)

Almost all of Chapter 7 is copied correctly from Chapters 4-6. Two sentences say more than the paper's evidence supports. (a) The §7.3 paragraph calls the replaced captures "failed", but Table 6.5 shows that 9 of the 15 had passed the verifier and only 4 failed. (b) Airehrour et al. is described as working "on hardware", while Chapters 4 and 6 only say "a testbed described as 14 motes", and the cropped Table 4.21 lists Contiki/Cooja (a simulator) as the testbed tool. Fix those two sentences. The other issues are an off-by-one window count that already sits in Chapters 4 and 6, and "40 deviations" in Chapters 5 and 6 where the log has 37.

## Evidence

Paragraph numbers (#N) count the paragraphs of `word/document.xml` in the (4) file from 0. Section names are given so each can be found in Word.

### Claims that match (✅)

| Chapter 7 says | Found in | Match |
|---|---|---|
| 80 runs = 36 BH + 36 WH + 8 benign; 72 attack runs, one per cell | §4.2.2.5 #2060, §6.1 #3939 | ✅ |
| Schedule: formation, 300 s baseline, 180 s attack, 120 s cooldown | §4.2.3.4 #2343, §6.1 #3939 | ✅ |
| 10 samples per second, flash + microSD | §4.1 #1309 | ✅ |
| ~1 probe/s, 4/s in highload | §6.2.2 #4613 | ✅ |
| Sites: Room G402 (GCCS), DLSU Library, Yuchengco Building | §1 #519, §6.1 #3939 | ✅ |
| Window kept if ≥ 8 of 10 samples; 16 features (§4.2.4) | §4.2.3.7 #2407, Table 4.17 | ✅ |
| 37 deviation entries in Appendix C | Table 5.2 title "D-1 to D-37"; IDs in Table 5.2 and Appendix C = D-1…D-37 (counted) | ✅ (but see conflicts) |
| 456,195 windows; 369,678 analysed = 266,491 normal + 103,187 attack | §6.1 #4020, Table 6.2 | ✅ |
| 123 victims, 92 bystanders; 180 untouched wormhole boards | §6.1 #4152 | ✅ |
| 72 attack runs PASS: 67 complete + 5 minor gaps; 8 benign confirmed | §4.2.7.1 #3143; BH 4 strong/27 good/5 minor #4533, WH 21 strong/15 good #4613 | ✅ |
| Setup check: attacker placed as designed, victims alive but cut off | §4.2.7.1 #3139, §4.2.7.7 #3185 | ✅ |
| Attacker FR 1.000–1.004 baseline, 0.0–0.7% attack; z ≥ 22.9, median 111 | §6.2.1 #4496 | ✅ |
| Victim PDR 0.998 → 0.000; all 123 exactly 0; bystanders 1.000 (0.996) | §6.2.1 #4534 | ✅ |
| 121 boards in first second, 2 within the next | §6.2.1 #4534 | ✅ |
| Neighbour check passed in all 32 testable runs | §6.2.1 #4532 (4 runs have no attack values, other 32 pass) | ✅ |
| Root-side check from victims' sequence numbers | §4.2.7.1 #3142 | ✅ |
| Exit end received 99–101% in all 36 runs | §6.2.2 #4614 | ✅ |
| 12,448 of 12,465 probes twice (99.86%); no other board | §6.2.2 #4697 | ✅ |
| 6,468 of 6,469 attack windows with a duplicate (99.98%), none in baseline/cooldown | §6.2.2 #4614 | ✅ |
| Entry end deeper, hops constant, 1–5 hops skipped | §6.2.2 #4614 | ✅ |
| 457,568 formed, 1,372 discarded (0.30%), no run > 1%, mean ≥ 9.97 | §4.2.3.7 #2412, §6.1 #4072 | ✅ (see conflicts) |
| 637 telemetry files, none empty; row count vs the card's runs.csv | §4.2.3.7 #2408, #2411 | ✅ |
| No run excluded by the integrity checks | §4.2.3.7 #2410 (7 timestamp failures, "No run was excluded") | ✅ |
| One board without data, bystander, minor (D-32) | §6.2.1 #4533 | ✅ |
| Benign: 21 checks none passed; PDR 0.9994–1.0000 both phases; 24/24 cooldown within 0.5 sd | §6.2.6 #5041, §6.3.3 #5679 | ✅ |
| ±50% → no verdict change in 53 runs / 14 settings; 1,000 sd → 18 changes; placebo 106 tests | §4.2.7.1 #3143 | ✅ |
| 15 earlier captures of 11 cells archived, newest analysed (Table 6.5) | §6.1 #4205 | ✅ |
| Leakage guard; only PDR decides the label for victims | §6.2.3 | ✅ |
| Baseline PDR 0.998 / 0.996 / 0.9999 (WH); Khan above 97% | §4.2.7.4 #3150, §2 #683 | ✅ |
| Airehrour 60–75% loss | §4.2.7.6 #3158, Table 6.34 #6363 | ✅ (but see ❌ 2) |
| Ramírez Gómez: duplicates as a wormhole signature | §4.2.7.2 #3146 | ✅ |
| Zhukabayeva 3-sigma rule | §6.5.2 #6413 | ✅ |
| Within 0.03 per site/topology; resample 0.41–0.63; 35 of 36 runs within 0.05 | §6.4.4 #5911, #5951 | ✅ |
| d = −29.71; others < 0.1 sd | §6.3.1 #5126 | ✅ |
| ARI 0.514 vs 0.515; 0.996 victims; −0.016 to 0.002 without PDR | §6.4.2 #5853, #5864 | ✅ |
| Wormhole ARI −0.012 to 0.009 | §6.5.1 #6322 (non-attacker −0.012…0.003, ends −0.012…0.009) | ✅ |
| Pooled 0.333 vs 0.334; 21,733 victim windows in one cluster, none of 22,481 benign | §6.4.7 #6126, #6260 | ✅ |
| Sniffer retry rate in some runs (7 of 36 BH) | §4.2.7.4 #3150 | ✅ |
| "Two simple baselines that Chapter 6 identifies" (PDR, duplicates) | §6.5.3 #6419 | ✅ |
| References: §1.3.2, §4.2.2.5, §4.2.3.4, §4.2.3.7, §4.2.4, §4.2.7.1, §4.2.7.7, §6.2.1–6.2.6, §6.3, §6.4.4, §6.4.6, §6.4.7, §6.5.1–6.5.4, Tables 3.4, 3.5, 4.17, 6.1, 6.2, 6.5, 6.7 | all exist with matching content | ✅ |

### ❌ 1 — §7.3 "Failed captures were replaced" (paragraph #6536)

Table 6.5 (#4206–#4254) lists the verdict recorded for each of the 15 replaced captures:

- **9 "confirmed"**: they passed the verifier and were still replaced;
- **4 "not confirmed, setup invalid"**: BH tree/G402/stationary 1, BH tree/G402/highload 2, WH tree/G402/stationary 1;
- **2 "no verdict recorded"**: WH star/G402/highload 1, benign partial mesh/G402/highload 1.

So most of the replaced captures did not fail. The paper never gives the reasons for each replacement. #4205 says they "are kept in the verification log of the repository and are not repeated here". "The dataset therefore contains only runs that passed" is true (all 80 confirmed, #2410), but it follows from the verification, not from the replacements.

### ❌ 2 — §7.3 Airehrour "measured under a blackhole on hardware" (paragraph #6538)

Chapters 4 and 6 hedge this: "a testbed that the paper lists as 14 motes" (#3155) and "a testbed described as 14 AS-XM1000 (Telos-B) motes running InstantContiki 3.0" (#6412). The cropped Table 4.21 (an image) lists the testbed tool as Contiki/Cooja 3.0, and Cooja is a simulator. Chapter 7 drops the hedge.

### 🔶 3 — §7.3 "delivery came back within 3 s" (paragraph #6531)

§6.2.1 #4534 says this held "in the 122 boards that kept reporting", because one board went silent. Chapter 7 states it without that limit.

### 🔶 4 — Window counts do not add up by 1 (paragraph #6533 vs #6524)

457,568 formed − 1,372 discarded = 456,196, but the paper's total is 456,195 (Table 6.2, #4020). The mismatch is already between §4.2.3.7 and §6.1, and Chapter 7 repeats both numbers. One of the source numbers needs checking against the analysis output.

## Conflicts between sources (if any)

- **Deviation count:** Table 5.2 title, #3334, Appendix C (#6786) and Chapter 7 all say D-1 to D-37, and the IDs actually present are D-1…D-37. But §5.1 #3377 ("Table 5.2 lists all 40 identifiers") and the Chapter 6 intro #3935 ("Table 5.2 explains all 40") say 40. The 40 is stale (D-38 and D-39 were removed on oct. 24 and D-41 is never in the paper), so 37 wins. Chapter 7 is right, and #3377 and #3935 should change to 37.
- **Window total:** see 🔶 4. Neither chapter can be preferred without the analysis output.

## What remains unverified

- The numbers were checked against Chapters 1-6 of the same file, not re-computed from the repository data. A number that is wrong in Chapter 6 would also be wrong in Chapter 7 and still pass this check. The window off-by-one (🔶 4) is the one internal sign of such a problem.
- Table 4.21 is an image. "Cooja" comes from the user's screenshot of it, not from text in the docx.
- The user's quoted version of the §7.3 paragraph says "not excluded", but the (4) file says "not hidden". If the user edited their own copy, this check covers the (4) file only.

## Sources

- `Plan/Paper-Editing/1-Working-Copy/FINAL THESIS3 OFFICIAL (4) - Recommendations in Chapter 7.docx`: the checked file (Chapter 7 = paragraphs #6514–#6554).
- §6.1 Table 6.5 "Earlier Captures Replaced by a Newer Capture": verdicts of the 15 replaced captures.
- §4.2.2.5 #2060, §4.2.3.7 #2409–#2410, §4.2.7.7 #3200/#3221, §6.1 #4205/#4261: the other places that explain replaced and out-of-plan captures.
- `ESP32-Environment/docs/dataset-verification.md`: the verification log that #4205 points to for the replacement reasons.
