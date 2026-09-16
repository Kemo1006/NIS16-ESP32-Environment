# CLAUDE.local.md — personal overrides (NOT shared)

Your private layer on top of [CLAUDE.md](CLAUDE.md) + [AGENTS.md](AGENTS.md). Git-ignored —
add `CLAUDE.local.md` to `.gitignore` so it never ships to anyone using this template.
**On conflict, this file wins** for you locally; the shared files stay untouched for others.
Rules/prefs only — keep it under ~50 lines. Delete any section you don't need.

## My working style (overrides AGENTS.md defaults for me)

- Verbosity: <e.g. terse — skip preamble, lead with the answer>
- Default task bias: <e.g. lean `@quick` unless I say `@deep`  |  or leave AGENTS.md auto-detect as-is>
- Ask vs act: <e.g. just proceed on reversible changes, don't ask>
- Tone: <e.g. blunt, no hedging>

## My local environment (machine-specific facts)

- OS / shell: <e.g. Windows 10 · PowerShell>
- Project root on this machine: <absolute path>
- Run (local): <command that works on my box>
- Test (local): <command>
- Tool versions that differ here: <e.g. node 20, python 3.12>

## Private references (pointers only — never paste secrets here)

- Secrets/creds file: <path outside the repo, e.g. C:\Users\me\.secrets\project.env>
- Personal scratch/notes: <path>

## Personal rule overrides

<!-- Explicit exceptions to the shared rules, for me only. Examples: -->
- <e.g. Skip the "confirm before deploy" rule — I've pre-authorized deploys to staging.>
- <e.g. When I say "ship it," commit + push without asking.>

## Do not

- Copy anything from this file into CLAUDE.md, AGENTS.md, or any shared/committed file.
- Commit this file. It is personal and local by design.
