# Paper-Editing — Thesis 3 (CTTHES3) paper

**Who this is for:** every member editing the Thesis 3 paper. Open this folder, nothing else.

| Folder | What is inside | Can you edit it? |
|---|---|---|
| `1-Working-Copy/` | `All_in_one_CTHESIS3_no_jitter_8boards.docx` — **the current** Thesis 3 paper (8 boards, run status oct. 20; **green = changed in the oct. 20 verification pass**). `All_in_one_CTHESIS3_no_jitter.docx` = the oct. 19 copy, kept for reference. `_backup/` = the 8-board copy before the green pass. **`…_8boards v2 (code and data recheck, oct. 20, 2026).docx` = the newest version**: the green copy plus the team's work checked against code and data (D-23…D-32, verifier rules, SD recovery, renumbered Ch. 4 headings, Table C.2) | No — continue in v4 |
| `1-Working-Copy/` | **`…_8boards v4 (Chapter 5 merged and checked, oct. 21, 2026).docx` = the newest version**: v3 (no development dates, partial-mesh and 0-row fixes) plus the member's new Chapter 5, every Chapter 5 number re-checked against the data (verification #72); green = changed. `All in one (CTHESIS3).docx` is the member's copy: it is older than v2 and is missing 143 of the fixes, so do not continue in it | No — superseded by THESIS3 Official |
| `1-Working-Copy/` | **`THESIS3 Official (oct. 24, 2026).docx` = the newest version**: the Google Doc tabs exported oct. 24 (Tab 1, latest Chapters 5 and 6, Claude new sections) combined into one paper; every suggestion accepted, every change highlighted yellow (old yellow kept too, so read **`THESIS3 Official - change report (oct. 24, 2026).md`** for the full list, including removed text). The four tab exports sit next to it | No — superseded by COMBINED v2 |
| `1-Working-Copy/` | **`THESIS3 Official (oct. 24, 2026) - COMBINED v2 (formats and pendings fixed).docx` = the newest version**: Angelo's `… - COMBINED.docx` with headings flush left, every chapter on a new page, PENDINGs resolved (Karlof & Wagner = [81]) and 8 reference exhibits inserted in §4.2.7.6. Open: the tree-wormhole content (team decision) and Khan et al.'s 2 exhibits | **Yes — newest** |
| `Thesis Images/` | Sharpest copy of every figure in the tabs (Google Docs blurs them), named by figure number, plus `INDEX.md`. Paste with Insert > Image > Upload from computer | Copy from it; don't edit |
| `2-Thesis2-Reference/` | `NIS 16 - (Not Highlighted) …(1).pdf` — the approved Thesis 2 paper (March 15, 2026) | No — reference only |
| `3-Guides/` | `Thesis-3-To-do-before-the-Oct-24-submission.docx` (task list), `Attack-and-Dataset-Validation-Basis.docx` (how the attacks and dataset are argued valid) | No — read them |
| `4-Verification/` | `THESIS3-PAPER-VERIFICATION-2026-10-19.docx` — what in the working copy is wrong, what to reword, what is verified, what still needs a source check | Tick the boxes as you fix things |
| `4-Verification/` | `THESIS3-Paper-Status oct. 20, 2026.docx` — **read first**: where the paper stands, run status, every green edit with its evidence, 11 open issues for the team, and where each oct. 19 item stands | Work through section 3 (open issues) |
| `4-Verification/` | `Validation-Basis-Check oct. 20, 2026.docx` — check of the Validation Basis guide (oct. 14): 6 wrong claims, 13 outdated, 1 unverified, with fixes. `Attack-and-Dataset-Validation-Basis.docx` here is a duplicate of the 3-Guides copy | Fix the guide in 3-Guides |
| `4-Verification/` | `THESIS3-Paper_Fixes-in-Green_2026-10-19.docx` — the whole paper with the report's fixes already applied: **green = changed text**, all other highlights cleared; Word comments = items only the team can answer | Re-read and double-check the green text; carry accepted fixes into the working copy |

## Rules

1. **Edit only the working copy.** Never edit the PDF or the guides.
2. **Highlights in the working copy:** yellow = new Thesis 3 text or provisional numbers;
   cyan = `[PENDING: …]` placeholders; green = changed in the oct. 20 verification pass
   (re-read it, then clear it). Unhighlighted text is from Thesis 2.
   Highlight new text yellow when you add it, so others can see it.
3. **Before submission** (from the paper's Appendix D): fill every `[PENDING`, delete Appendix D,
   clear all yellow and cyan, select all + F9, rebuild the contents / table / figure lists.
4. **Close Word before syncing or moving the file** — an open .docx cannot be moved or synced.
5. Numbers in the paper must come from the repo (verifier output, analysis tables). If you
   change a number, say where it came from.

## Read the guides with care

- The **To-do** doc was written for a copy of the paper that still has the jitter scenario
  (96 + 12 runs). This working copy has **no jitter (72 + 9 = 81 runs)**. Its formatting and
  team items still apply; its run counts and `[PENDING` count (23) do not.
- The **Validation Basis** doc repeats two numbers that are wrong (G402 child PDR 0.938 → 0.238);
  see item 1 of the verification report.
- **Jitter is OUT (team decision, oct. 20, 2026)** — the paper's 81-run design (72 + 9) is final; captured jitter runs are outside it.
