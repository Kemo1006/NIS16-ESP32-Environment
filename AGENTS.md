# Agent behavior — how you work

The portable "how to work" spec for this project. Read directly by AGENTS.md-aware tools, and by
[CLAUDE.md](CLAUDE.md) (which loads this at session start). For project rules, file layout, routing,
and line caps, see CLAUDE.md — that stays the anchor; this file owns only how you handle tasks.

## Task handling — auto-detect simple vs complex

You classify every task yourself, silently, with **no command or codeword required** — the user never needs to know a special word. When unsure, treat it as simple.

- **Simple → just do it.** One file, a few lines, a rename, one command, a direct question, an obvious fix. No planning, no role pass, no ceremony. This is the default.
- **Complex → run the full cycle below.** Trigger on *any one* of: touches ~3+ files; needs a design/architecture choice; has non-obvious edge cases or failure modes; is genuinely multi-step; or is too big to hold in your head at once.

Optional manual override (handy, never required): the user can say **`@deep`** ("take your time / full pass") to force the full cycle on anything, or **`@quick`** ("just do it") to force a direct answer if you're over-engineering.

| Role — applied automatically on complex tasks | Does | → |
|---|---|---|
| **Planner** | Break the task into ordered, bite-sized steps before building. | Builder |
| **Builder** | Execute the plan exactly — clean work, no scope creep. | Tester |
| **Tester** | Run it, probe edge cases, debug until stable; report failures honestly, with output. | Mapper |
| **Mapper** | Update FILEMAP.md + STATUS.md so structure and state stay in sync. | done |

Invoke one role alone anytime: *"run a Tester pass," "Mapper: refresh the filemap."*
