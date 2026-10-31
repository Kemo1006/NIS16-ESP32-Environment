# Verification: the defense deck's broken visuals are fixed in v8

**Date:** oct. 31, 2026
**Verdict:** ✅ CONFIRMED for v8. 🔶 PARTIALLY CONFIRMED for v7: the tilt fix worked, but three overlaps remained.

## The claim

1. Defense deck v7 (`Paper/Defense/... v7 (visuals fixed).pptx`) has no tilted lines on these three slides:
   - "How to read box plots and Cohen's d" (slide 34)
   - "The 3-sigma test, in one picture" (slide 15)
   - "PCA and t-SNE: how to read the pictures" (slide 29)
2. Nothing else in the deck changed compared with v6.

## What this means (plain language)

v7 fixed the slanted lines that the Canva download had added. But a real PowerPoint render showed three spots where text and shapes still collided. v8 fixes those three spots and changes nothing else. Present from **v8**.

## Evidence

- **Render method.** Every slide of v6, v7 and v8 was exported to PNG through the laptop's own PowerPoint, using copies of the files.
  - This is the renderer the deck is presented with, so it shows real font widths, unlike an XML estimate.
- **Tilt fix (v6 → v7).** A pixel diff over all 75 slides found changes on slides 15, 29 and 34 only.
  - In the before/after crops, the median line, whisker caps, connectors, pin, arrow and the 3-sigma mean line are now straight. In v6 they slanted by 2–3°.
- **v7 still had collisions**, seen in the PowerPoint render:
  - **Slide 34:** "most features: |d| < 0.1" ran into "blackhole victim PDR…". The two read as "0.1blackhole".
  - **Slide 15:** the baseline/attack divider line cut through "3 S|D".
  - **Slide 29:** the middle t-SNE cluster's dots covered "far apart: the distance means nothing".
  - The slide 15 and slide 29 problems were already in v6 (Canva layout). The slide 34 problem was made worse by the v7 label alignment.
- **v8 fixes.**
  - **Slide 34:** the red label is right-aligned so it ends where the arrow ends, with a line break after "29.71,".
  - **Slide 15:** the divider now starts at the top of the shaded band, below the label. Its bottom end is unchanged.
  - **Slide 29:** the 20 dots of the middle cluster moved 35 px up.
  - See the before/after image `oct. 31, 2026_defense-deck-v8-before-after.png` (left = v6, right = v8).
- **Nothing else changed (v7 → v8).**
  - Comparing the two files part by part: 373 parts each, and only `slide15.xml`, `slide29.xml` and `slide33.xml` differ. In this file, `slide33.xml` is shown at position 34.
  - A same-session pixel diff over all 75 slides changed only slide 15 (x 516, y 239–294), slide 29 (the cluster) and slide 34 (the label area).
- **File checks.** The skill's validator (`validate.py`, baselined against v6) passed for v7 and for v8.

## Conflicts between sources

- **Text-fit estimate vs. real render.** My earlier XML-based check said v7 was fine, but the real render showed collisions. The real PowerPoint render wins: the font Canva named ("Calibri (MS) Bold") does not exist, so PowerPoint substitutes a wider font.
- **Render noise.** v8 renders made in a separate PowerPoint session differed on almost every slide because of anti-aliasing. Renders made in the same session differ only in the three edited regions. The same-session comparison is the valid one.

## What remains unverified

- Only these three slides were inspected visually. The other 72 slides were checked only for "unchanged since v6", not for layout problems of their own.
- Footer page numbers are static text from Canva, and 64 of 75 do not match the slide position. Slide 34 still shows "23". Not fixed.
- Rendering on another laptop or in Canva may differ if its fonts differ.

## Sources

- `Paper/Defense/THESIS3-Defense oct. 30, 2026 (final paper, plain graph guides) v8 (overlaps fixed).pptx`: the deck to present.
- `verification/oct. 31, 2026_defense-deck-v8-before-after.png`: left = v6, right = v8, for the three fixed areas.

## Correction (oct. 31, 2026, later the same night)

The "Render method" bullet above overstates the renders.

- **What I found:** the Canva download embeds its own fonts ("Calibri (MS)", "Calibri (MS) Bold", "Calibri (MS) Italics", "Arial Bold") in `ppt/fonts/`. PowerPoint's slide export (`Slides.Item(i).Export`, with or without a window) did **not** use them and fell back to a wider font.
- **Your screen:** your PowerPoint window shows the narrower embedded Calibri. Your screenshots fit text on lines that wrap in my renders.
- **Effect on the v8 findings:**
  - The 3-sigma divider and the t-SNE dot overlap come from shape positions, not fonts, so those fixes stand.
  - The Cohen's d label collision appeared only with the fallback font. In your Calibri view the labels did not touch (your screenshot shows a gap). The v8 change there is harmless: the label ends at the arrow, on two lines.
- **What the renders still prove:** whether text fits on a machine that can't load the embedded fonts. They do not prove what you see on screen.
