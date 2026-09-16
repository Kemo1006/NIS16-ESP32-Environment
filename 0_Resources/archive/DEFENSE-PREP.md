# NIS16 — Panel Defense Prep (THES2 / Implementation Stage)

Questions a panel is likely to ask, with answers written to be **spoken** — plain and clear, but still exact. Each answer leads with the simple idea, then backs it with the number or section that proves it. Start with the **⚠️** items; those are the ones that trip people up.

**Where the project actually stands (say this honestly if asked):** the full pipeline — capture → clean → features → analysis — works end to end on real data. The experiment matrix is **4 of 24 runs done**: the whole `linear · blackhole` set (3 repeats) and one `linear · wormhole` run. Tree, star, and partial-mesh topologies are next.

---

## A. What the study is and why it matters

**Q1. What's your actual contribution? A dataset isn't a system.**
Right — and we're not claiming to build a detector. Our contribution is a **real, labeled dataset** of how an ESP32 mesh behaves normally and under attack, taken from actual hardware, plus the tooling to reproduce it. Almost every existing security dataset comes from simulations, which miss the messy hardware behavior of a real board. We give researchers something built from the real thing, with the ground truth attached.

**Q2. ⚠️ You have the true labels already. Why cluster instead of just training a classifier?**
Because our goal is to show the dataset *has structure*, not to build a model that memorizes our lab. If we trained a classifier on this small, controlled set, it would just overfit to our specific conditions. Clustering asks a harder, fairer question: do normal and attack windows *naturally* fall into separate groups on their own? We only bring the labels back in at the very end, to score how clean those groups are — never to train.

**Q3. Aren't blackhole and wormhole already well studied? What's new?**
The attacks are old news *in simulation*. What nobody has documented is how they look on **real ESP32 hardware across multiple layers at once** — signal, link, and routing together — where the Wi-Fi stack is closed and limits what you can even do. Working within that real-world limitation, and showing what the attacks look like anyway, is the new part.

---

## B. "Is this really an attack?" — the section they'll push hardest on

**Q4. ⚠️ This isn't a real blackhole. You *told* the victims to send to the attacker. A real attacker lures traffic by lying about routes. Explain.**
You're correct, and we say so openly in the paper. The reason is simple: on the ESP32, routing and forwarding are handled by Espressif's **closed firmware** — we can't inject fake routes because that layer isn't open to us. So instead of faking the paper's *mechanism*, we reproduce its *effect*. The victims send through the attacker, the attacker forwards normally during baseline, and during the attack window it just stops forwarding. What a network monitor would actually see — forwarding drops to zero, delivery collapses, retries spike — is identical to a real blackhole. Since our study is about observable behavior, that's what matters.

**Q5. ⚠️ Then how is your "attack" different from a node that simply failed? How do you know the drop is intentional?**
Because the attacker's own log proves it chose to drop. During the attack window it recorded **720 probes received, 720 dropped, 0 forwarded** — and its "received" counter kept climbing the whole time, so the victims never stopped sending. It received everything and forwarded nothing on purpose. The numbers next to it: delivery went from **0.94 down to 0.08**, forwarding from **~1.0 to ~0.02**, retries from **0.004 to 0.165**. A real failure would also show the mesh re-routing around the dead node — ours shows **zero re-routing**. So it's a deliberate gap at one node, not a breakdown.

**Q6. In your chain the attacker sits deep (layer 4), but even the nodes closer to the root go silent. Doesn't that mean the whole mesh died?**
No — that's the design, and it's worth explaining. Every victim is set to send its probes *to the attacker's address* at the app layer, no matter where it sits in the chain. So all traffic funnels through the attacker even when the mesh wouldn't normally route it that way. When the attacker drops, everyone goes quiet. We flag this as a fair limitation: it's driven by our setup, not something that emerged naturally.

**Q7. ⚠️ Your wormhole is just two of your own boards joined by a wire. Where's the attack?**
A wormhole *is* exactly that — two cooperating nodes secretly linked by an outside channel. Building that link is implementing the attack. One board sits near the victims, the other near the root, and they pass probe data to each other over a side connection (a serial wire or a separate Wi-Fi channel). The tell-tale sign shows up cleanly: tunneled probes get **replayed, so the root logs each one twice**. In our first wormhole run, during the attack window the root saw 901 arrivals but only 720 unique ones — **181 duplicates, all from the tunneled node**, while the other three victims stayed at exactly one copy each. That doubling is the wormhole signature.

**Q8. Why only blackhole and wormhole? Why not grayhole, Sybil, and others?**
Because these two are the cleanest examples of the two fundamentally different routing threats. Blackhole breaks the "what you receive, you forward" rule. Wormhole breaks the "closer nodes have stronger signal" rule — it fakes a shortcut. One attacks forwarding, the other attacks the shape of the network. Those two cover the two categories; the rest are out of scope by design.

---

## C. The features and the dataset

**Q9. ⚠️ You say 16 features, but a third of them are empty in most runs. Do you really have 16?**
It depends what "have" means, and we're careful about it. Five features only apply to a specific situation, so they're blank (NaN) by design everywhere else. Three are *relay* features — only the blackhole attacker relays traffic, so they're empty in normal and wormhole runs. The other two-plus are *tunnel* features — only the wormhole attacker tunnels, so they're empty otherwise. Per run you get 10, 13, or 13 of 16 — but across the **combined dataset you get all 16**, because each one is filled in by at least one run type. Every empty cell is flagged, so nobody mistakes "blank by design" for "missing data."

**Q10. ⚠️ Your latency feature needs round-trip time, but you have no reply packet and your two boards' clocks aren't synced. How is it valid?**
This looked broken at first and we fixed it without touching firmware. The root's latency number mixes two unsynced clocks, so the raw value is meaningless on its own — we saw values like minus 194 seconds. But the key realization is that the **error is a fixed constant** for each node, so when you subtract two of that node's readings, the error cancels out. Using that, latency-per-hop comes out to a steady **2.4–2.8 milliseconds per hop across all layers** — exactly the "steady ratio means normal forwarding" the paper predicts. Tunnel latency we get the same way, from the gap between a probe's two arrivals. No re-capture needed — it was recoverable from data we already had.

**Q11. Why 5-second windows, and why throw away windows with too few samples?**
Five seconds is a balance — long enough to be statistically stable, short enough to catch behavior changes, giving about 12 windows a minute. We use non-overlapping windows so each one is an independent observation, with no bleed-over that could fool the clustering. And if a window is missing more than one of its five expected samples, we drop it, so no summary is based on almost-empty data. We report exactly how many we dropped — under 1% — as an honesty metric.

**Q12. How do you know your labels are trustworthy and not influenced by the data?**
The labels never come from the measurements. The root announces which phase is active, every node stamps that phase onto each row as it logs, and that's the label. It comes purely from the experiment's control signal, not from any feature crossing a threshold. That's what makes it real ground truth for scoring the clusters.

---

## D. The analysis and clustering

**Q13. ⚠️ With only 4 of 24 runs and mostly one topology, how can you claim the classes separate?**
Honestly, we can't fully claim that yet, and I won't overstate it. What we *can* show is that the attack signatures are strong, repeatable, and clearly different from normal — the delivery, forwarding, and duplication numbers are night-and-day. Proving full between-class separation needs normal, blackhole, and wormhole together in one table, and assembling that is our immediate next step. So far we've shown the dataset *captures* the difference cleanly; the separation study builds on top of that.

**Q14. You use five clustering algorithms. Isn't that just throwing everything at the wall?**
Each one answers a different question, and we compare them on purpose. DBSCAN finds dense groups and can label weird in-between windows as noise. K-Means is the simple baseline. GMM allows soft, overlapping groups. Hierarchical and spectral handle oddly-shaped clusters. Then we grade them two ways: with scores that need no labels (how tight and separated the clusters are), and with scores that use our ground truth (how pure the clusters turn out). Running several guards against any single method's built-in assumptions deciding the answer for us.

**Q15. Couldn't one strong feature be doing all the work?**
We check for exactly that. Before clustering we drop features that barely vary, drop one of any two that move together too closely, and run PCA to see which features actually carry the information. Then we cluster on both the full set and the trimmed set and compare. So a result can't secretly rest on one dominant or duplicated feature.

---

## E. Limits, deviations, and the real engineering

**Q16. ⚠️ Your proposal says sample at 1 Hz, but you captured at 10 Hz. Why change it?**
We capture faster and then analyze at the proposal's 1 Hz — the code down-samples to that grid. Faster capture is purely a safety margin: if the stream loses some rows, a 10 Hz capture missing 30% still gives a complete 1-second dataset. The analysis grid is unchanged, so results stay comparable to what we proposed.

**Q17. Only 5–10 nodes, indoors, two attacks. Does any of this generalize?**
We state those limits plainly. Our claim isn't statistical generalization — it's method and structure: a repeatable way to instrument a real ESP32 mesh and a labeled dataset others can extend to bigger networks or more attacks. It also lines up with UN Sustainable Development Goal 9 on resilient low-cost infrastructure.

**Q18. What was genuinely hard here? Convince us this was real work.**
Real hardware broke in ways the proposal never imagined, and each fix is documented. One example: a **silent data-loss bug** where a corrupted end-of-file marker glued two logs together, and our trimmer kept the wrong half — producing a file with the right name and size but zero useful rows. We fixed it by splitting on the data's structure instead of its size. Another: boards left powered too long **overfilled their flash storage** until they couldn't be read, so we wrote a recovery tool that pulls the raw memory directly and rebuilt over 6,000 rows from a board that couldn't send a single one. A third: a checker that called a *perfect* wormhole run "broken" because it assumed attacks mean fewer packets, when a wormhole means *more* (duplicates). We keep receipts on all of it.

**Q19. Could you run it right now if we asked?**
Yes. From the ESP-IDF PowerShell, one command flashes a board, runs the roughly 8–11 minute phased experiment, exports every node's data, and runs the whole analysis. Before each run we check the board's storage isn't too full, we carry boards back **unplugged** so they don't keep logging, and we never run `set-target`, which silently breaks the logging.

> **One housekeeping note to fix before defense:** the boards now run **ESP-IDF v5.5.4**, but the README still says v5.3.5. Update the doc (or note the upgrade) so the version you *say* matches the version you *ran*.

---

## F. Quick one-liners to have ready
- **Why ESP32 and not laptops?** It's the actual low-cost device these networks use — its limits are exactly what's worth studying.
- **Why a probe every second?** Steady, known traffic, so delivery and forwarding are measurable without flooding the mesh.
- **What does "cross-layer" mean here?** One row combines signal (RSSI), link (retries), and routing (forwarding, delivery, topology) — an attack shows in all three at once, which single-layer datasets miss.
- **Is the raw data trustworthy?** Every raw capture is tracked with a checksum; nothing is rebuilt from lossy copies.
- **Can someone reproduce it?** Yes — fixed phase timeline, broadcast phase IDs, and baselines computed from each run's own stable window.
