# THESIS3 Official — change report (oct. 24, 2026)

What was changed when the exported Google Doc tabs were combined into `THESIS3 Official (oct. 24, 2026).docx`. Every added or rewritten word is highlighted **yellow** in the document. The old yellow highlights were kept (team choice), so this list is the reliable record; removed text cannot be highlighted and is listed here only.

**Sources:** Tab 1, tab "latest version chapter 5 and 6", tab "Claude – new sections" (exports of oct. 24, 2026, ~7:30 AM).

## Structure

- **Ch 6 (latest tab)** — renumbered: 71 table/figure numbers and references to the new numbering
- **Tab 1** — accepted suggestions: 115 insertions (now yellow), 114 deletions
- **latest Ch 5-6 tab** — accepted suggestions: 9 insertions (now yellow), 9 deletions
- **Tab 1, Section 4.4** — renumbered: Figure 4.55 -> 4.60 (t-SNE), new Figures 4.55-4.59 come first
- **Tab 1, Section 4.2.7** — inserted: Block A: new Section 4.2.7.7 (Figures 4.55-4.59, Table 4.26)
- **Ch 6.1** — replaced paragraph: Block B1 (Table 6.5)
- **Ch 6.2.2** — replaced paragraph: Block B2 (Table 6.8, Figure 6.4)
- **Ch 6.2.4** — replaced paragraph: Block B3
- **Ch 6.2** — inserted: Block B4: new Section 6.2.6 (Tables 6.10, 6.11, Figure 6.6)
- **Ch 6.4** — replaced paragraph: Block C1: new Section 6.4.6 (Table 6.17, Figure 6.16)
- **Ch 6.5** — replaced paragraph: Block C2, first paragraph
- **Ch 6.5.1** — inserted: Block C2, second paragraph (wormhole objectives)
- **Ch 6.5.2** — replaced paragraph: Block C3
- **Ch 6.5.3** — inserted: Block C4
- **Ch 6.5.4** — replaced paragraph: Block C5, first paragraph
- **Ch 6.5.4** — inserted: Block C5, paragraphs 2-3 (limits)
- **Ch 6.6** — inserted: Block C6 (future work)
- **Ch 6.7** — replaced paragraph: Block C7 (conclusion)
- **Tab 1** — replaced: old Chapter 5 (136 elements) by the latest Chapters 5 and 6 with Blocks B1-C7
- **Tab 1** — comments: 65 comments dropped with the old Chapter 5 text they were attached to; 0 kept

## Text removed (not highlightable)

| Where | Why | Removed text (start) |
|---|---|---|
| Ch 6.1 | superseded: Section 6.2.6 reports both recaptures (new-sections tab, point 3) | [PENDING: tree at G402 with burst and with highload are the earlier captures. Both were captured again, and their re-analysed tables. With them, tree … |
| Table 5.2 | jitter is not part of the paper (team decision) | D-33 / Jitter scenario / The jitter scenario is left out of the plan, which leaves three scenarios. / Table 5.6 |
| Table 5.2 | checklist A39: not for the paper | D-38 / Tree association time / In the tree, a parent keeps a silent child for 30 s instead of 10 s. / Table 5.6 |
| Table 5.2 | checklist A42: not for the paper | D-39 / Wormhole end scan / In the tree, the wormhole ends scan the mesh channel only. / Table 5.5 |
| Ch 5.1 | D-41 must never appear in the paper (checklist A44, user oct. 23) | [PENDING, internal note to delete before submission: Appendix C also holds D-41 (23 October 2026), which the log marks as not for the paper. For tree … |
| Table 5.5 | checklist A42: not for the paper | D-39 Wormhole end scan / New / In tree builds, the wormhole ends scan the mesh channel only when they look for a parent. / A scan of all channels made … |
| Ch 5.4, D-39 | checklist A42: not for the paper | Entry D-39 concerns the way in which the wormhole ends scan for a parent in the tree. The scan that both ends use to find a parent by hand listened pa … |
| Ch 5.4, D-39 | checklist A42: not for the paper | In the tree builds, the scan now listens on the mesh channel only (channel 11), which takes about 0.36 s a scan. The mesh never leaves that channel, b … |
| Table 5.6 | jitter is not part of the paper (team decision) | D-33 Jitter scenario / Modified / The jitter scenario is left out of the plan, which leaves three scenarios. / A scope decision of the team, to be che … |
| Table 5.6 | checklist A39: not for the paper | D-38 Tree association time / New / In tree runs, a parent keeps a silent child for 30 s instead of 10 s. / ESP-IDF advises about 30 s for an encrypted … |
| Table 5.6 legend | jitter is not part of the paper (team decision) | ●       Jitter = a fourth traffic scenario of the working plan, which is not one of the three scenarios of Section 4.2.2.5. |
| Ch 5.5, D-33 | jitter is not part of the paper (team decision) | Entry D-33 concerns the jitter scenario. The plan of the campaign had four scenarios for every combination of site, topology and attack: stationary, h … |
| Ch 5.5, D-37 | tree-wormhole firmware story and dates (checklists A39/A42/A44) | On the evening of 22 October, a team member asked that the result of the partial mesh, whose wormhole runs all looked like a tree, be applied to the t … |
| Ch 5.5, D-38 | checklist A39: not for the paper | Entry D-38 concerns the time for which a tree parent keeps a silent child. Every topology set the association expiry of a parent to 10 s. In the expor … |
| Ch 5.5, D-38 | checklist A39: not for the paper | The tree builds therefore keep a silent child associated for 30 s, whereas the star, linear and partial builds keep 10 s. A busy parent, such as a roo … |
| Ch 5.5, D-40 | named D-36/D-38/D-39 protections and a dated run (checklists A39/A42) | The default fan-out of the tree is therefore set back to the stock limit of 10. The other protections stay in place: the leaf ends of D-36, the fallba … |

## Text edited (new wording is yellow)

| Where | Why | Was → Now |
|---|---|---|
| Title page | Change log #1: the suggestion was missing from the Google Doc | Thesis Proposal Presented → Thesis Presented |
| Ch 4 intro | no development dates in the paper | the data-capture campaign was completed on 24 October 2026. → the data-capture campaign was completed. |
| Section 4.2.2.5, run status | no development dates in the paper | All 80 runs of the final plan were captured by 24 October 2026: → All 80 runs of the final plan were captured: |
| Section 4.2.2.5, run status | stale 44-run text left after change #78 (37 runs to capture, 81-run PENDING) contradicted the first sentence | Five further captures are held out of the processed set: one blackhole capture on the tree topology at G402 (h … → The leakage audit (Section 4.2.7.3) was computed on an earlier set of 34 runs and is to be rerun on the 80 run … |
| Section 4.2.2.5, design | jitter is not part of the paper (team decision) | The five jitter captures and the captures made at home are kept on disk outside the plan (D-19, D-33). → The captures made at home are kept on disk outside the plan (D-19). |
| Section 4.2.2.5, timeline | wrong since the D-35 amendment: tree and partial mesh have one benign run each, at G402 | In addition, every topology has three matched runs with no attack, one at each site, each under a different sc … → In addition, 8 matched runs with no attack were captured (D-35): one at each site for the linear and the star … |
| Section 4.2.3, run inventory | jitter is not part of the paper (team decision) | and the jitter captures and the captures made at home are kept on disk outside the plan. → and the captures made at home are kept on disk outside the plan. |
| Section 4.2.7.2 | no development dates in the paper | on the final captures (24 October 2026), all 72 → on the final captures, all 72 |
| Appendix C note | D-33, D-38, D-39 are not in the paper; no development dates | Table C.1 lists D-1 to D-32, and D-33 to D-40 are summarised in Table 5.2 of Chapter 5 until the table is upda … → Table C.1 lists D-1 to D-32, and the later entries are summarised in Table 5.2 of Chapter 5 until the table is … |
| Appendix C, D-1 | no development dates in the paper | on a baseline run of 25 July only 6 of 583 → on an early baseline run only 6 of 583 |
| Appendix C, D-4 | no development dates in the paper | On the 25 July baseline run all 6 changes → On an early baseline run all 6 changes |
| Appendix D | jitter is not part of the paper (team decision) | The study has no jitter scenario (team decision), so the design has three scenarios, → The design has three scenarios, |
| Appendix D, Table D.1 | no development dates in the paper | Done on 24 October 2026: the plan file → Done: the plan file |
| Ch 5.1 | D-33, D-38, D-39 are not in the paper | The 40 entries fall into five groups (Table 5.1) → The entries fall into five groups (Table 5.1) |
| Table 5.1 | D-39 not for the paper (checklist A42) | D-30, D-36, D-39 → D-30, D-36 |
| Table 5.1 | D-39 not for the paper (checklist A42) | The wormhole ends join the mesh as leaf nodes, and in the tree they scan the mesh channel only. → In the tree and the partial mesh, the wormhole ends join the mesh as leaf nodes. |
| Table 5.1 | D-33 (jitter) and D-38 (checklist A39) not in the paper | D-29, D-33, D-35, D-37, D-38, D-40 → D-29, D-35, D-37, D-40 |
| Ch 5.1 | D-33, D-38, D-39 are not in the paper | Table 5.2 lists all 40 identifiers in numerical order → Table 5.2 lists the identifiers in numerical order |
| Tables 5.2 and 5.6, D-37 | tree-wormhole firmware detail removed (checklists A39/A42/A44) | Tree boards were limited to two children, and wormhole end B was given a fallback parent. → Tree boards were limited to two children (withdrawn by D-40). |
| Tables 5.2 and 5.6, D-37 | tree-wormhole firmware detail removed (checklists A39/A42/A44) | Tree boards were limited to two children, and wormhole end B was given a fallback parent. → Tree boards were limited to two children (withdrawn by D-40). |
| Ch 5.1 | no development dates in the paper | The 40 entries of Appendix C were not planned at the start of the study. They were made between July and Octob … → The entries of Appendix C were not planned at the start of the study. They were made during the study, each ti … |
| Ch 5.1 | no development dates in the paper | The earliest entries arose from the first captures of July (D-1, D-2, D-3 and D-4), several from the work of S … → The earliest entries arose from the first captures (D-1, D-2, D-3 and D-4), several from the later development … |
| Ch 5.1 | no development dates in the paper | (D-21 to D-40, 16 to 23 October 2026) → (D-21 to D-40) |
| Ch 5.1 | D-38, D-39 not for the paper; D-37/D-40 are about the tree fan-out | gave a valid run (D-36 to D-40) → gave a valid run (D-36) |
| Ch 5.1 | jitter is not part of the paper (team decision) | for example the choice of sites (D-19), of benign runs (D-18 and D-35) and of scenarios (D-33). → for example the choice of sites (D-19) and of benign runs (D-18 and D-35). |
| Ch 5.1 | recount after removing D-33 (Modified), D-38 and D-39 (New) | Of the 40 entries, 15 are labelled Modified and 25 New in the tables of this chapter. → Of the 37 entries in the tables of this chapter, 14 are labelled Modified and 23 New. |
| Ch 5.1 | note rewritten without D-33, D-38, D-39 and dates | [PENDING: D-33 to D-40 are written as the log records them. D-36 to D-40 were compile-checked and not yet test … → [PENDING: D-34 to D-37 and D-40 are written as the log records them. D-36, D-37 and D-40 were compile-checked … |
| Ch 5.2, D-14 | no development dates in the paper | so every capture made before 23 September 2026 used the ESP32 default → so the early captures used the ESP32 default |
| Ch 5.2, D-14 | no development dates in the paper | In a capture of 23 September it heard → In one capture it heard |
| Ch 5.2, D-14 | no development dates in the paper | was verified on hardware on 24 September 2026 in a test of 3 minutes → was verified on hardware in a test of 3 minutes |
| Ch 5.3, D-2 | no development dates in the paper | ; it was corrected on 26 September 2026. → ; this was corrected. |
| Ch 5.3, D-2 | no development dates in the paper | On a baseline run of 25 July, the median → On an early baseline run, the median |
| Ch 5.3, D-3 | no development dates in the paper | On a linear wormhole run of 20 July there were → On an early linear wormhole run there were |
| Ch 5.3, D-8 | no development dates in the paper | On a linear blackhole capture of 16 September 2026, three → On one linear blackhole capture, three |
| Ch 5.3, D-11 | no development dates in the paper | independently (21 September 2026), so → independently, so |
| Ch 5.3, D-15 | no development dates in the paper | This was checked on 27 September 2026: the only → This was checked: the only |
| Ch 5.3, D-15 | no development dates in the paper | and since 30 September 2026 the verifier no longer uses it as a check → and the verifier does not use it as a check |
| Ch 5.4 | D-39 not for the paper (checklist A42) | and how the ends join the mesh (D-36, D-39). → and how the ends join the mesh (D-36). |
| Ch 5.4, D-16 | no development dates in the paper | The first hardware run (1 October 2026) formed → The first hardware run formed |
| Ch 5.4, D-17 | no development dates in the paper | Until 7 October 2026, the end of each board was fixed when the board was flashed. A linear wormhole setup of t … → At first, the end of each board was fixed when the board was flashed. A linear wormhole setup made in this way … |
| Ch 5.4, D-17 | no development dates in the paper | A tree capture of 2 October had both ends → An early tree capture had both ends |
| Ch 5.4, D-17 | no development dates in the paper | worked on hardware on 7 October 2026 on a linear run → worked on hardware on a linear run |
| Ch 5.4, D-30 | no development dates in the paper | On 19 October 2026, a partial-mesh setup repeatedly → One partial-mesh setup repeatedly |
| Ch 5.4, D-30 | no development dates; with D-36 the ends are leaves, so 'can still hang' no longer holds | and in the builds of 19 October B can still hang directly under A, in which case A relays the normal copy of B … → and before the leaf rule of D-36, B could also hang directly under A, in which case A relayed the normal copy … |
| Ch 5.4, D-28 | no jitter wording in the paper (here it meant delay variation) | may lie within the jitter → may lie within the normal variation of the delay |
| Ch 5.4, D-36 | no development dates in the paper | Until 22 October 2026, the two tunnel ends joined → Without a rule, the two tunnel ends joined |
| Ch 5.4, D-36 | no development dates in the paper | with stationary traffic on 22 October, end A → with stationary traffic, end A |
| Ch 5.4, D-36 | no development dates in the paper | Captures made before the evening of 22 October may have had children under A or B. → Captures made before this rule may have had children under A or B. |
| Ch 5.5 | jitter not in the paper; no development dates | The plan for the benign runs changed several times (D-18, D-33 and D-35) and ended on 24 October 2026 with 8 b … → The plan for the benign runs changed several times (D-18 and D-35) and ended with 8 benign runs |
| Ch 5.5 | D-33 (jitter) and D-38 (checklist A39) not in the paper | (D-5, D-18, D-35), the scenarios (D-33), the sites (D-19) and the definition of the topologies (D-6, D-26, D-2 … → (D-5, D-18, D-35), the sites (D-19) and the definition of the topologies (D-6, D-26, D-29, D-37, D-40). |
| Table 5.6, D-40 | tree-wormhole firmware story removed (checklists A39/A42/A44) | A limit of two could not form the layout of the one tree wormhole run that worked end to end. → A limit of two could not form the layout of the tree run that had formed best, with five boards directly under … |
| Table 5.6 legend | only used for the jitter skip | ; skip = a setting that leaves a scenario out of the plan → (deleted) |
| Table 5.6 legend | only used by D-38 (not for the paper) | ; association expiry = the time for which a parent keeps a child that has gone silent before it drops the chil … → (deleted) |
| Table 5.6 legend | only used by D-38 (not for the paper) | ; staleness timer = the time after which the root counts a heartbeat as too old → (deleted) |
| Ch 5.5, D-18 | no development dates in the paper | Until 7 October 2026, a benign run was added only → At first, a benign run was added only |
| Ch 5.5, D-18 | four scenarios per site counted jitter | The four topologies of a site were given four different scenarios, each of them → The topologies of a site were given different scenarios, each of them |
| Ch 5.5, D-18 | 108 / 96 counted the jitter scenario | With the three sites of D-19, this came to 12 benign runs and 108 runs in all (96 attack runs and 12 benign ru … → With the three sites of D-19, this came to 12 benign runs. |
| Ch 5.5, D-35 | jitter not in the paper; no development dates | With the jitter scenario taken out of the plan (D-33), three of the 12 benign slots of D-18 had been jitter an … → The team then asked for the benign runs to be arranged differently: |
| Ch 5.5, D-35 | 'restored' only made sense after the jitter cut | This restored the number of benign runs to 12 and brought the plan to 84 runs → This gave 12 benign runs and a plan of 84 runs |
| Ch 5.5, D-35 | no development dates in the paper | On 24 October 2026, the four benign runs that had never been captured were removed → The four benign runs that had never been captured were removed |
| Ch 5.5, D-35 note | no development dates in the paper | (24 October 2026: four uncaptured benign runs removed → (four uncaptured benign runs removed |
| Ch 5.5, D-35 note | no development dates in the paper | was captured as stationary on 22 October 2026, and the plan file → was captured as stationary, and the plan file |
| Ch 5.5, D-19 | no development dates in the paper | The panel-change plan of September 2026 listed four sites → An earlier plan listed four sites |
| Ch 5.5, D-19 | no development dates in the paper | On 7 October 2026, the team dropped home → The team then dropped home |
| Ch 5.5, D-26 | no development dates in the paper | so on 19 October 2026 the change was narrowed → so the change was narrowed |
| Ch 5.5, D-37 | rewritten without the tree-wormhole firmware story and dates (checklists A39/A42/A44) | Entry D-37 concerns the number of children that a tree board accepts. Until 22 October 2026, the tree used the … → Entry D-37 concerns the number of children that a tree board accepts. The tree used the stock limit of 10 chil … |
| Ch 5.5, D-40 | rewritten without the tree-wormhole firmware story and dates (checklists A39/A42/A44) | Entry D-40 withdraws the limit of D-37 for the tree. With the two wormhole ends side by side and both leaves ( … → Entry D-40 withdraws the limit of D-37 for the tree. A limit of two children cannot form a tree in which the r … |
| Ch 5.6, D-4 | no development dates in the paper | On the baseline run of 25 July, all 6 changes → On an early baseline run, all 6 changes |
| Ch 5.6, D-22 | no development dates in the paper | On 16 October 2026, linear runs started with both tunnel ends set as B → Some linear runs started with both tunnel ends set as B |
| Ch 5.6, D-24 | no development dates in the paper | D-24 (18 October) moved the checks → D-24 moved the checks |
| Ch 5.6, D-23 | no development dates in the paper | Before 18 October 2026, any change of parent → At first, any change of parent |
| Ch 5.6, D-23 | no development dates in the paper | A tree blackhole run at G402 of 18 October was an invalid setup → One tree blackhole run at G402 was an invalid setup |
| Ch 5.6, D-31 | no development dates in the paper | A review of 20 October 2026 held that → A later review held that |
| Ch 5.6, D-34 | no development dates in the paper | On 21 October 2026, a scenario that was not applied became a minor gap, which grades → A scenario that was not applied is now a minor gap, which grades |
| Ch 6 note | no development dates in the paper | the 36 blackhole runs of the design that were analysed on 20 October 2026 (repository snapshot THESIS3, commit … → the 36 blackhole runs of the design as they were first analysed (repository snapshot THESIS3, commit 709e455). … |
| Ch 6 intro | D-33, D-38, D-39 are not in the paper | and Table 5.2 explains all 40 in plain words. → and Table 5.2 explains each of them in plain words. |
| Ch 6.1 | no development dates in the paper | All 80 runs were captured by 24 October 2026. The pooled tables of this section report the 36 blackhole runs a … → All 80 runs were captured. The pooled tables of this section report the 36 blackhole runs as they were first a … |
| Ch 6.1, Block B1 | no development dates in the paper | Collection ended on 24 October 2026, and every run of the final plan was captured (Table 6.5). → Every run of the final plan was captured (Table 6.5). |
| Ch 6.1, Block B1 | no development dates in the paper | still come from the 36 blackhole runs analysed on 20 October 2026, whereas → still come from the first analysis of the 36 blackhole runs, whereas |
| Ch 6.2.6, Block B4 | no development dates in the paper | They were applied again to the final captures on 24 October 2026, and Table 6.10 → They were applied again to the final captures, and Table 6.10 |
| Ch 6.4.6, Block C1 | no development dates in the paper | of the 36 blackhole runs of the 20 October snapshot. After collection ended, → of the 36 blackhole runs of the first analysis. After collection ended, |
| Ch 6.4.6, Block C1 | 0.727 is the majority rate of the 6,000-window samples, not of the pool (0.723) | and purity stayed at the majority rate of 0.727. → and purity stayed at the majority rate of its samples (0.727). |
| Table 6.17 legend | purity 0.721 < 0.723 looked impossible; it is a sample effect | the majority rate of this pool is 0.723, and → the majority rate of this pool is 0.723 (each set is clustered on 6,000-window samples, whose majority rate va … |

## Still for the team

- Rebuild the contents, list of tables and list of figures (they still list the old Chapter 5).
- The pooled tables of Sections 6.1–6.4.5 are still the 36-run blackhole snapshot (marked provisional).
- The 65 Tab 1 comments were all on the old Chapter 5 and were not carried over; they remain in the Google Doc.
- Tab 1 (Arial) and the Chapter 5–6 tab (Times New Roman) use different body fonts, as in the Google Doc.
- D-26, D-37 and D-40 describe the tree rules without the tree-wormhole exception (D-41 stays out of the paper by team decision).
