# 🎬 M5 Demo Script — Raw Data Extraction & Integrity Validation (10%)

> ## ⚠️ Criteria not yet supplied
> **I don't have M5's criteria text.** Everything below is built from the milestone name and
> the tooling in your repo. **Paste M5's criteria and I'll map each bullet precisely.**
>
> Working assumption: *telemetry reliably extracted from device flash over USB, and validated
> for integrity before entering the dataset.*

> ## 🎯 The framing
> **"Nothing enters the dataset unvalidated."** M5 is where you demonstrate research rigour
> rather than results — and it's the milestone that answers *"how do we know your data is
> genuine?"* before anyone asks it.

---

## 📊 SLIDE 1 — The extraction pipeline

```
board ──USB──▶ export_logs.py ──▶ trim_run.py ──▶ validate_integrity.py ──▶ ledger
               schema guard        session split     5 checks + SHA-256
```

> 🗣️ *"Telemetry is written to each board's internal flash during the run — nothing streams to
> the laptop. Afterwards we pull each CSV over USB serial, split out the experiment run, and
> validate it. Only then does it count toward the matrix."*

---

## 📊 SLIDE 2 — What `trim_run.py` does, and why it's safe

> 🗣️ *"The firmware appends to one file across boots, and the rows carry no run ID. So an
> export contains the experiment **plus** a short session from when we plug the board in to
> export it. `trim_run.py` splits on **timestamp regressions** — the clock going backwards is
> an unambiguous reboot — and keeps the longest segment.*
>
> *Two safety properties: it's a **dry run by default**, and `--apply` writes trimmed **copies**
> into a separate folder. **The raw captures are never modified.**"*

Live output:
```
child_node5_star_wormhole_r2_...telem.csv
    8420 data rows, 2 boot session(s)
      session 1: rows 7415  span 763.4s  <-- KEEPING (longest)
      session 2: rows 1005  span 100.9s
    wrote 7415 row(s), dropped 1005 -> trimmed/...
```

💡 Good 15-second answer to *"aren't you throwing data away?"* — you're separating the run
from the export session, and the raw file still holds both.

---

## 📊 SLIDE 3 — The five integrity checks

| # | Check | Catches |
|:-:|---|---|
| 1 | Schema width & row consistency | truncated or garbled rows |
| 2 | Phase coverage vs expected rate | a run that ended early |
| 3 | Timestamp monotonicity | an un-split reboot |
| 4 | Label integrity vs phase→label map | a mislabelled row |
| 5 | **SHA-256 manifest** | any later modification |

```
21 file(s) — 21 PASS, 0 WARN, 0 FAIL
Manifest: .../trimmed/manifest.json
```

> 🗣️ *"Five checks on every file. **Every recorded cell across the whole matrix is
> zero-FAIL.**"*

---

## 📄 SLIDE 4 — The manifest ⭐ *your strongest artifact for "is this genuine?"*

```json
{
  "child_node2_star_wormhole_r1_20260727_014200_telem.csv": {
    "row_count": 7080,
    "sha256": "4df9c60cf014bf1bee9c26f128ce0f8afbbc0c1d6ef771c67f284f373d20dd2c",
    "size_bytes": 518330
  }
}
```

> 🗣️ *"Every capture is hashed at validation time and locked into a manifest — filename, row
> count, size, and a SHA-256 digest. If a single byte changes afterwards, the next validation
> fails. Combined with the version-controlled repository history, that's the integrity trail
> for the whole dataset."*

---

## 📊 SLIDE 5 — Three silent corruptions, each now caught at source ⭐ *your differentiator*

Most projects don't have this slide. It shows you found your own failures.

| Failure that occurred during collection | Now caught by |
|---|---|
| Device streamed the **wrong file** — telemetry saved under an `_arrivals.csv` name | Schema checked **at capture**; file quarantined as `.rejected`, `--delete` suppressed so the board keeps its copy |
| **Stale derived files** left behind after a re-export | Flagged when a raw source disappears |
| **Duplicate capture** double-counting one node | Flagged before any analysis runs |

> 🗣️ *"Each of these corrupted a dataset at least once during collection.*
>
> *The third is the one worth dwelling on: it produced **no error at all**. One node was counted
> twice — 264 windows against about 155 for every other node — and every total still looked
> plausible. That's the failure mode that matters most for a dataset, because **nothing
> announces it**.*
>
> *Each now fails at the moment it happens rather than twenty minutes later in the analysis, and
> each is documented with the incident that produced it."*

💡 If you only have 30 seconds for M5, **show this slide.** It's the most distinctive thing in
the project.

---

## 🗣️ The 75-second M5 script

> *"M5 is extraction and integrity.*
>
> *\[slide 1] Telemetry lives on each board's flash during the run and is pulled over USB
> afterwards, one board at a time.*
>
> *\[slide 2] `trim_run.py` separates the experiment from the export session by splitting on
> timestamp regressions — and it writes copies, so raw captures are never modified.*
>
> *\[slide 3] Five checks on every file: schema, phase coverage, timestamp monotonicity, label
> integrity, and a SHA-256 manifest. Every recorded cell is zero-FAIL.*
>
> *\[slide 4] The manifest is what makes the dataset auditable — if a byte changes, the next
> validation fails.*
>
> *\[slide 5] And these three guards each came from a real corruption during collection. The
> duplicate-capture one produced no error at all — a node counted twice, with totals that still
> looked plausible. That's why we added checks that fire at the moment the fault happens."*

---

## 🛡️ M5 questions

**"How do we know the data is genuine?"** ⭐
> *"Three things. SHA-256 per file in a manifest written at validation time. A ledger recording
> when each cell was validated. And the attack signatures are cross-verified between independent
> boards — the attacker's own counters and the root's arrivals log agree exactly, and those are
> separate devices writing separate files."*

**"Why do you trim the files? Isn't that discarding data?"**
> *"It separates the experiment run from the export session — the firmware appends across boots,
> so plugging a board in to export it adds rows. The raw capture is never modified; trimmed
> copies go to a separate folder. And it's a dry run by default, so you see what would be
> dropped before anything is written."*

**"What happens if an export fails halfway?"**
> *"The partial capture is still saved — a partial CSV is more useful than discarding thousands
> of rows that transferred cleanly — but it's reported as FAILED and the cell won't record. And
> the board keeps its copy, because the delete step is skipped on any failure."*

**"You said a device sent the wrong file. How often?"**
> *"Once, in about eighty exports. The root's arrivals command streamed the telemetry file
> instead. We haven't established the root cause — most likely a lost end-of-file marker making
> the second capture re-read the first file, but that's unproven. What we did was make it
> impossible to miss: the schema is checked at capture, and the board's copy is preserved so it
> can simply be re-pulled."*

**"Could someone tamper with the CSVs after validation?"**
> *"They'd fail the next validation — the manifest hash wouldn't match. And the repository
> history is public and timestamped, so a file appearing without a corresponding export session
> would be visible."*

**"Why validate at all if the firmware writes the files?"**
> *"Because the failures we actually hit weren't firmware bugs — they were transport and
> file-handling faults. A board that couldn't read its own flash, an export that streamed the
> wrong file, a duplicate that double-counted a node. None of those are visible in the data
> itself; they're only visible in checks."*

---

## ✅ M5 checklist

- [ ] Validator screenshot showing `0 PASS / 0 WARN / 0 FAIL` line
- [ ] `manifest.json` open, first entry visible
- [ ] `trim_run.py` output showing the session split
- [ ] **Three-guards table** on a slide *(the differentiator — don't cut this)*
- [ ] Know: **five checks** · **0 FAIL everywhere** · **1 wrong-file export in ~80**
- [ ] Can explain **why trimming is safe** (raw untouched, dry run default) in one sentence
- [ ] Ready to say *"we haven't established the root cause"* about the wrong-file export —
      don't invent one
