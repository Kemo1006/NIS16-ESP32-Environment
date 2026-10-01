---
name: verify
description: >
  Verify a specific claim, fact, or assertion with concrete, citable evidence before accepting it as
  true — build the case the way a lawyer would, never testify from memory or a guess. Gathers evidence
  from the actual local repo/code (read the real file, run the real command, check git history), the
  project's own memory/status docs where they exist, and official external documentation (the vendor's
  own docs/spec, not a remembered summary of them) — then states an explicit verdict backed by citations,
  written so both a specialist and someone outside that field can follow it. Use whenever the user asks
  to "verify," "double-check," "confirm," "fact-check," "is this actually true/correct," "are you sure,"
  or is visibly unsure whether something they read, were told, or half-remember still holds up. Do not
  use this for routine questions that don't hinge on a specific checkable claim.
---

# Verify

A user brings a claim they're not fully sure about — something they read in a doc, something Claude said
earlier, something a teammate mentioned, a "does this library still work this way" question. The job is
to settle it the way a lawyer settles a case: not by sounding confident, but by producing evidence that
would hold up if someone else went and checked it.

**The standard:** every sentence in the verdict must trace back to something you actually looked at —
a file you read, a command you ran and saw the output of, a doc page you fetched and quoted. "I recall
that..." / "generally..." / "this usually works like..." is not evidence, it's testimony from memory,
and memory (yours or the user's) is exactly what's in question. If you catch yourself about to write a
sentence you can't point to a source for, that's the sentence to go verify next, not soften and keep.

## Step 1 — Pin down the claim

Restate precisely what is being checked, as a claim that can be true, false, or unresolved — not a topic.
"Does the jitter scenario cause the highload collapse" is a claim. "Tell me about jitter" is not. If the
user's request is a topic rather than a checkable claim, ask them to sharpen it before starting — a
lawyer doesn't build a case around a vague accusation, and neither should this. If there are multiple
sub-claims bundled together (common when the user pastes a paragraph), split them out and verify each one
separately so a mixed verdict is possible ("the first half checks out, the second doesn't").

## Step 2 — Gather evidence, don't reason from priors

Pull evidence from whichever of these actually apply to the claim — most claims need more than one:

- **Local repo/code.** The ground truth for "does the code actually do X." Grep for the real symbol,
  read the real file at the real line, run the real script or test and read its real output. Don't
  paraphrase from a prior read earlier in the conversation if the file could have changed since — re-read
  it. Check `git log`/`git blame` when the claim is about *when* or *why* something changed.
- **The project's own memory/status docs**, if the project keeps them (`MEMORY.md`, `STATUS.md`,
  `ARCHIVE.md`, `FILEMAP.md`, or an equivalent durable project-state file). These record decisions the
  team already made — a claim that contradicts one is worth flagging explicitly, and a claim that matches
  one gets stronger evidence for it. Not every project has these; don't go looking for a convention that
  isn't there, and never create these files as a side effect of running this skill.
- **Official external documentation**, for claims about a product, library, API, protocol, or spec.
  Trained knowledge of how a library "usually" behaves is a hypothesis, not a citation — it goes stale
  (deprecations, version bumps, renamed parameters) and it was never the vendor's own word to begin with.
  Search for and fetch the vendor's own docs, changelog, or spec and quote the exact passage that settles
  it, with the URL. If the docs are ambiguous or silent, that's itself a finding — say so rather than
  filling the gap with what seems plausible.

Treat conflicting sources as a finding, not a problem to paper over: if the code says one thing and the
docs say another, or a memory file records a decision the current code no longer matches, report the
conflict and which source should win here and why (usually: running code beats a doc, a dated decision
beats an undated assumption, the vendor's current docs beat a memory of an older version).

This skill is read-only investigation — it doesn't edit code, doesn't fix the contradiction it finds, and
doesn't touch files outside gathering evidence. If the verification surfaces something that clearly needs
fixing, say so in the report and let the user decide whether to act on it.

## Step 3 — Reach a verdict

Every claim gets exactly one of:

| Verdict | Means |
|---|---|
| ✅ **CONFIRMED** | Direct evidence found and it supports the claim as stated. |
| ❌ **CONTRADICTED** | Direct evidence found and it disagrees with the claim. |
| 🔶 **PARTIALLY CONFIRMED** | True under some conditions, false or unverified under others — state which. |
| ⚠️ **UNABLE TO VERIFY** | Looked, found nothing conclusive either way. This is an honest, useful answer — never round it up to CONFIRMED because a guess seems likely, and never round it down to CONTRADICTED because you couldn't find support. Say what you checked and why it came up short, so the user knows the search was real, not skipped. |

## Step 4 — Write for two readers at once

The whole point of the lawyer framing is that a lawyer explains the case to the *client*, not just to
other lawyers — precision for the record, plain language for the person who has to act on it. Every
technical citation (a file path, a config flag, an HTTP status code, a library term) needs a plain-English
gloss sitting right next to it: what it *is*, and what it *means for the user's actual question* — mechanism,
then implication, in the same breath, not a separate "in plain terms" aside bolted on afterward. Don't
cut the technical term to make it accessible (the specialist reading over the user's shoulder still needs
it exact) — explain it in addition to using it. If you're unsure whether a term needs glossing, gloss it;
a specialist skims past an explanation they didn't need in half a second, but a term left unexplained can
stop a non-specialist cold.

## Step 5 — Produce the two outputs

**The file.** Save a dated report to `verification/<date>_<short-slug>.md` in the project root (create the
folder if it doesn't exist yet). Use `assets/report-template.md` as the structure. This is the durable
record — thorough, one section per claim, every piece of evidence cited.

**The chat reply.** A short summary, not a repeat of the file: the verdict(s) in one line each, the single
most important piece of evidence behind each, and a list of links (official docs, or `file:line` for local
evidence) the user can click through themselves if they want to see the primary source rather than take
your word for it. Point to the saved file for the full evidence trail. Close with what — if anything —
remains genuinely open.

## Worked example (short form, for calibration)

**Claim:** "The OpenAI SDK's `chat.completions.create()` still takes a `functions` parameter for tool use."

**Evidence:** Fetched the OpenAI API reference for `chat.completions.create` (platform.openai.com/docs/api-reference/chat/create,
checked [date]) — `functions`/`function_call` are listed as **deprecated in favor of `tools`/`tool_choice`**,
which is the array-of-tools shape introduced for parallel function calling. `functions` still works for
backward compatibility but the docs explicitly steer new code away from it.

**Verdict:** 🔶 PARTIALLY CONFIRMED — the parameter still exists and won't error, but it's the *old* way:
the vendor's own docs mark it deprecated and point new code at `tools` instead. (Plain terms: it'll still
run today, but the OpenAI team has told developers not to use it going forward, and a deprecated parameter
is the kind of thing that gets removed in a future SDK version without warning — worth switching now
rather than building on it.)

## Notes

- If the user's claim turns out to be about *this session's own prior turn* ("did you actually check that
  earlier or did you just say it"), the honest answer is frequently "I didn't check it" — say that plainly
  and then go check it now, rather than retroactively inventing evidence for a claim you made unverified.
- Scope discipline still applies: verify against the project you're in, don't wander into a sibling
  project's files even if they'd be informative, unless the user's claim is explicitly cross-project.
