# Creating a New Workstation

**Read this when:** the user asks to create/add a new workstation (a domain subfolder).
Not needed otherwise — this is a build-time recipe, not session context.

A workstation is a self-contained domain folder (e.g. `Email/`, `Finances/`, `School/`)
that the root routes into when a task matches it. It **inherits all root rules** — only
add what is *different* for this domain. Never re-state global rules; that's duplication
that drifts.

## Scaffold — create `<Workstation Name>/` with three items

### 1. `CLAUDE.md` (≤ 60 lines) — sections in this order

- **Identity** — one paragraph: what you are in this workstation, what routes here, what doesn't.
- **Resources** — table `Resource | Read when…`, start empty. These are *local* files in this
  workstation's own `Resources/` folder, loaded only while this workstation is active.
- **Workflow** — numbered steps for the primary task. Start simple; refine over time.
- **Domain rules** — rules that layer on top of root, specific to this domain only.
  *(If this workstation produces written content, open with: "Follow the voice guide —
  see 0_Resources/INDEX.md." Otherwise omit — not every domain writes prose.)*

### 2. `MEMORY.md` (≤ 100 lines) — facts only, populated over time (not written by hand)

- Header: `<Workstation Name> Memory`
- **Contacts** — people relevant to this domain.
- **Key Decisions** — the reasoning behind choices made here.
- **Facts & preferences** — domain-specific realities and how the user likes things done.

### 3. `Resources/` — empty folder for this domain's reference files

Local reference files live here and are listed in this workstation's own CLAUDE.md Resources
table. **Keep domain files local — do not push them into root `0_Resources/`.** Root
`0_Resources/` is reserved for genuinely cross-workstation material (like `archive_tech.md`).
This keeps each domain isolated and stops any one index from becoming a bottleneck.

## Register it (one step)

Add a row to the **Workstations** table in the *root* CLAUDE.md so future sessions route here
automatically: `| <Workstation Name> | Route here when the task is about… |`.

## Ready-to-paste skeleton

```
<Workstation Name>/
├── CLAUDE.md    # Identity · Resources · Workflow · Domain rules   (≤ 60 lines)
├── MEMORY.md    # Contacts · Key Decisions · Facts & preferences   (≤ 100 lines)
└── Resources/   # local reference files (empty at first)
```

## What changed from the original spec, and why

- **Inherit, don't duplicate:** workstation CLAUDE.md states only domain *differences* — root rules already apply. Smaller files, no drift.
- **"Editorial Rules" → "Domain rules":** generalized so this works for code, finance, or study domains, not just writing. The voice-guide line is now optional, used only when the domain outputs prose.
- **Local resources stay local:** each workstation owns its `Resources/`; root `0_Resources/` is only for cross-cutting files. Prevents one giant index and keeps domain context from leaking between workstations.
- **Caps aligned to this template** (60 / 100 lines) and a copy-paste skeleton added so scaffolding is deterministic instead of improvised each time.
