# Thesis defense briefing for the Claude Project (iPad) - oct. 31, 2026

Upload this file to the Claude Project's knowledge, together with: `THESIS3 Defense Study Guide oct. 30, 2026 v5.md`, the paper (PDF), and the deck exported from Canva as PDF. Project instructions to paste: "You are my thesis-defense coach. Answer from these files, in short spoken-style answers. Say when something is not in the files. Never claim more than the thesis shows."

## 1. The project in one paragraph
ESP-WIFI-MESH testbed (8 ESP32 boards, ESP-IDF, C firmware) that captures labelled **blackhole** and **wormhole** attack datasets, plus a Python pipeline (pandas/scikit-learn) for exploratory analysis (clustering, PCA/t-SNE, DBSCAN). 4 topologies, 3 campus sites, 3 traffic patterns. Repo: GitHub `NIS16-ESP32-Environment`, branch `THESIS3`.

## 2. Setting and traffic (corrected today)
- Context follows Khan et al. [22] (smart-campus monitoring over an ESP32 mesh; 64-byte packet every 2 min). Ours: about 1 packet/s per board to one collector (the root).
- Sites: G402 (controlled classroom), DLSU Library (busy, heavy Wi-Fi), Yuchengco (**semi-outdoor open area below the building, NOT indoor** - user, oct. 31). Say "3 campus sites, one semi-outdoor". The paper's "3 indoor sites" (Sec. 1.4) is wrong and must be fixed (checklist A45).
- Scenarios: stationary 1/s, highload 4/s, burst (300 probes at +60 s).
- Topologies: 4 (e.g. linear, tree, partial, star-like). Attackers are placed on purpose: attacker never root; wormhole end B deeper than end A; pre-run gates + START (D-22).

## 3. Why the traffic is synthetic (answer for the panel)
"Boards send small test packets about once a second, not real temperature or soil readings. Blackhole/wormhole act on forwarding, not payload, so a known steady stream lets us measure exactly what went missing (forwarding ratio, delivery ratio) and define a baseline. We control the rate (1, 4, burst). Limitation: not real sensor data and heavier than Khan's 1 packet per 2 min; real sensor traffic is future work. Do not claim the results generalise to real deployments."

## 4. The verifier (4 checks, one verdict)
1. **Signature** - 3-sigma rule (from Zhukabayeva [71]). Blackhole primaries: attacker ForwardingRatio + PDR of non-attacker boards (Airehrour [70]). Wormhole primaries: TunnelIntensity + DuplicateRate at the root (D-21, Ramirez [72]). A broken baseline (mean < 0.90 or SD > 0.15 of mean) is excluded, not failed (the 0.90 bound is ours; Khan's healthy rate > 97%).
2. **Topology** - tree shape (Karlof & Wagner [81], Hu [46]); a class change (D-23) fails the run; D-31; D-32 missing boards by role.
3. **Dataset** - at least 95% of windows per phase; impact check; grades STRONG/GOOD/MINOR/MAJOR/UNDETERMINED/FAILED.
4. **Scenario** - stationary <= 1.5/s, highload >= 3/s median, burst >= 240 extra probes in 10 s; not applied = MINOR gap (D-34).
- Verdict: PASS / FAIL / INCONCLUSIVE.
- Testing the verifier: placebo 0 of 106 false alarms; +-50% threshold 0 flips; 1,000 SD perturbations 18 flips.
- A sniffer on 7 runs is an independent witness.
- Blackhole meets 5 of 6 criteria (Table 4.4), wormhole 4 of 5 (Table 4.5).

## 5. Honest weak points (say them before the panel does)
- PDR is both a verifier check and a clustering feature (circular).
- We wrote the checker.
- Attack is emulated at the application layer (D-20); the attacker ACKs at link layer, and the emulation cannot write routes, so a real routing blackhole would re-route ([70]: 16-246 rank changes). Only 1 of 132 tree boards changed parent in labelled phases.
- 8 boards, one run per cell; traffic is synthetic probes; the 0.90 bound is ours.
- Failed/inconclusive runs are real network behaviour (see section 8).

## 6. Deck state (Canva design DAHZjwi19Ko, "THESIS3-Defense oct. 30, 2026 ... v13 (studies and signatures)")
- Slide 7 new (strip + notes now also answer "traffic is synthetic"; team reminder comment posted on the Canva design): "Our testbed and what it follows" (drawn mesh; rows to Khan [22], Airehrour [70] 5 of 6, Zhukabayeva [71]/Hu [46] 4 of 5/Ramirez [72], Karlof & Wagner [81]).
- Slides 13-20 rebuilt around the 4 checks: 13 overview, 14 two signatures, 15 3-sigma rule, 16 topology, 17 dataset, 18 scenario, 19 verdict, 20 testing the verifier.
- "Indoor" wording fixed on slides 4, 7, 10, 56 (saved today). Speaker notes of 4 and 56 still say "indoor".
- Known gaps: footer page numbers on 14-20 are one too low; speaker notes on rebuilt slides still hold old study text; slide 7 has no notes. Download a fresh .pptx/PDF from Canva before presenting.
- Rule: every deck change gets a yellow tag ("NEW SLIDE"/"CHANGED") top-right, and touched slide numbers are listed.

## 7. Facts for explanations
- Victims = boards cut off by the attacker; bystanders = control group that should be unaffected.
- Only 1 of 132 tree boards changed parent in labelled phases; victims' ParentSwitchRate rose 0.00000 to 0.00009/s.
- Reference studies: Khan [22], Airehrour [70], Zhukabayeva [71], Ramirez [72], Hu [46], Karlof & Wagner [81]. Hu [46] and Karlof & Wagner [81] originals were never opened - get them via the DLSU library.

## 8. OPEN reminder (keep until done)
Failed / inconclusive runs = real network behaviour (checklist A41): table of every non-PASS run -> Results + Discussion/Limitations (instability can mimic or mask an attack) -> Methodology sentence -> adviser check.

## 9. Open to-dos
- Fix "3 indoor sites" in the paper (A45) and the two speaker notes.
- Add panel-answer text to speaker notes (slides 7, 16); fix footer numbers on 14-20.
- Count how many runs (if any) failed for a victim/bystander class switch before quoting a number.
- Firmware rule: tree wormhole firmware is FROZEN at D-41 (git tag `thesis3-fw-d41`); never change it without explicit OK; never mention it in the paper.
