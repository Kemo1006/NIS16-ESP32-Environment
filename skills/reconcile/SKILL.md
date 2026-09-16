---
name: reconcile
description: >
  Compare an AI draft with the final used version, explain meaningful edits, and propose the smallest reusable instruction update. Use for "reconcile," "what did I change," or draft-final reviews.
---

# Reconcile

Turn the difference between an AI draft and the version actually used into a practical learning. The goal is not to preserve every edit as a new rule. It is to identify the smallest instruction change that would prevent the same meaningful miss next time.

This skill is standalone. It needs only the original draft and the final version. A writing guide, project instruction file, or preference list is optional and should be used only when the user provides it or makes it accessible.

## Context Loading

No workspace, command center, reference folder, connector, or companion skill is required.

Required inputs:

1. **Original draft**: the AI-generated version before the user's edits.
2. **Final version**: the version the user actually sent, published, submitted, or approved.

Optional input:

3. **Current instruction source**: a writing guide, project instruction file, preference list, custom instruction, or relevant excerpt. Load it only when the user wants a carry-forward instruction change and has provided or shared access to it.

If the draft or final is missing, ask for that input and pause. Do not infer missing text from memory. If no instruction source is available, complete the comparison and provide a portable instruction the user can paste into the system they already use.

## Workflow

### Phase 1: Compare the Draft and Final

1. Read the draft and final in full before analyzing individual edits.
2. List every change briefly as `draft -> final`, including deletions, additions, structural moves, tone shifts, word-choice changes, and formatting changes.
3. Classify each change:
   - **Material**: changes meaning, emphasis, structure, voice, audience fit, specificity, or a repeatable writing pattern.
   - **Trivial**: fixes a typo, punctuation, spacing, or a one-off detail that reveals no reusable preference.
4. Continue with material changes only. Keep the complete census available if the user asks for it.

### Phase 2: Diagnose the Reusable Learning

For each material change, explain what the edit demonstrates without guessing what the user was thinking. Combine multiple edits when they support the same principle.

If an instruction source is available, search it for rules related to the edit and assign one disposition:

- **Delete**: an existing instruction is obsolete, counterproductive, or fully superseded.
- **Merge**: two instructions overlap and should become one.
- **Move**: the instruction is correct but too far from the workflow step where it must influence the draft.
- **Rewrite**: the instruction exists but is too broad, vague, narrow, or weak to prevent the miss.
- **Stage**: the edit suggests a useful preference, but one example is not enough to make it a standing rule.
- **Add**: a durable pattern has no current owner and cannot be handled by deleting, merging, moving, or rewriting an existing instruction.
- **No change**: the current instruction is already visible and specific enough, and the miss is a true one-off.
- **Dismiss**: the edit is trivial, message-specific, accidental, or makes the result worse.

If no instruction source is available, use **portable instruction**, **stage**, or **dismiss**. Do not claim that an existing instruction is missing when no instruction set was inspected.

### Phase 3: Apply the Minimal Sufficient Precision Gate

Before recommending an instruction change, test it against all five questions:

1. **Evidence**: Which exact draft-to-final change proves this instruction is needed?
2. **Recurrence**: Is the underlying situation likely to happen again?
3. **Prevention**: Would the wording have prevented the observed miss before the draft was written?
4. **Scope**: Is the instruction narrow enough to avoid damaging unrelated work?
5. **Placement**: Where should the instruction live so it appears at the moment it must influence the work?

Prefer, in order: delete, merge, move, rewrite, stage, then add. An addition is allowed only when no existing instruction can be adjusted and the evidence supports a durable rule. Write one instruction per principle, even when several edits support it.

For a portable instruction, recommend the smallest suitable home the user already has, such as Claude profile preferences, project instructions, a team writing guide, or a reusable prompt. Do not require the user to create a new operating system or folder structure.

### Phase 4: Propose Before Changing Anything

1. Present the material deltas and recommended dispositions.
2. For each proposed delete, merge, move, or rewrite, quote the current wording and provide the full replacement or destination.
3. For each proposed addition or portable instruction, provide the exact paste-ready wording and its recommended placement.
4. Explain staged and dismissed items in one line each.
5. Ask for approval before editing any accessible instruction source. If the source is unavailable or read-only, stop at the paste-ready recommendation.

### Phase 5: Verify an Approved Edit

If the user approves and the instruction source is editable:

1. Make only the approved change.
2. Re-read the edited section to confirm that it is clear, non-duplicative, and in the intended location.
3. Check that the original failure case would now be prevented.
4. Report the exact instruction changed. Do not claim the update was made if the source was not actually edited.

## Output Format

Use this structure:

### Bottom Line

One sentence with the number of material changes and the recommended instruction outcome.

### Material Deltas

- `Draft wording -> Final wording` — change type and the reusable signal.

Omit trivial changes unless the user asks for the full census.

### Recommended Learning

Use one continuous numbered list, ordered as delete, merge, move, rewrite, stage, add or portable instruction, then no change.

**1. [Action-first recommendation]**

- **Context:** Cite the decisive draft-to-final evidence and, when available, the related current instruction.
- **Proposed action:** Name the disposition, recommended location, and exact ready-to-use wording. For an addition, state why no smaller change would work.

### Dismissed

- `[Change]` — one-line reason.

Omit this section when nothing was dismissed.

### Approval

If an editable source and proposed changes exist, summarize the changes and ask whether to apply them. Otherwise, state that the paste-ready instruction is the completed deliverable.

## Constraints

- **Stay standalone.** Never assume or require a particular workspace, file path, reference folder, account, connector, command center, or companion skill.
- **Use only available evidence.** Do not invent a missing draft, final, instruction source, rule, or file location.
- **Prune before adding.** A shorter, sharper instruction surface is usually more reliable than a growing list of narrow rules.
- **Do not overlearn from one edit.** Stage weak or single-instance signals instead of turning each preference into permanent policy.
- **Attribute conclusions to the edit.** Describe what the text change demonstrates, not the user's hidden intent or emotional state.
- **Protect the source.** Never edit an instruction file without the user's approval, and never broaden the edit beyond the demonstrated pattern.
- **Keep private material private.** Quote only the minimum text needed to explain the comparison, especially when the draft or final contains personal, confidential, or customer information.

## Edge Cases

- **Draft or final is missing:** Ask the user to provide the missing version. Do not reconstruct it.
- **A screenshot is unreadable or incomplete:** Ask for pasted text or a clearer image before comparing uncertain wording.
- **The two versions match:** Say, "No changes. The draft was used as-is," and stop.
- **Only trivial changes exist:** Say, "No material changes. Nothing needs to be carried forward," and stop.
- **No instruction source exists:** Complete the analysis and provide one portable instruction with a recommended home. Do not make creating a new system a prerequisite.
- **The source cannot be edited:** Provide the exact replacement text and placement instructions, clearly labeled as not yet applied.
- **Several edits express one preference:** Combine them into one learning with multiple examples.
- **A final edit conflicts with an explicit current rule:** Flag the conflict neutrally and ask which behavior should govern future drafts. Do not silently rewrite the rule.
- **The final appears worse than the draft:** Dismiss that change as non-reusable unless the user confirms it reflects a deliberate preference.

_From Jeff Su's Cowork Academy: https://coworkacademy.ai/_
