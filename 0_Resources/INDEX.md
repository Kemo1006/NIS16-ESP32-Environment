# 0_Resources — Trigger Index (global / shared)

0_Resources holds **cross-workstation** resources only — files used across domains, not owned by any single one. **Never auto-loaded, never read whole.** Consult this index when a task plausibly needs a shared resource, then load **only** the one file whose trigger matches. No match → proceed without loading anything here.

**Domain-specific resources are NOT here.** They live in each workstation's own `Resources/`folder and are listed in that workstation's CLAUDE.md. For domain routing, see the **Workstations** table in root [CLAUDE.md](../CLAUDE.md).

## How to use

1. Task may need a *shared* reference → scan the "Read when…" triggers below.
2. A trigger matches → open **only that one file**. Nothing else.
3. No match → load nothing here.
4. New *shared* resource → add a one-line row below. New *domain* resource → add it to that
   workstation instead, not here.

## Global / shared resources

| Resource | Read when… |
|---|---|
| archive_tech.md          | Installing, updating, verifying, or failing to install any package/dependency |
| creating-workstations.md | Creating or adding a new workstation |

## Not a shared resource — `archive/`

`archive/` holds **retired thesis-specific docs** parked here after the Thesis 2 defense (defense scripts, panel Q&A prep, terms glossary). They are NOT cross-workstation resources and are deliberately absent from the table above — nothing routes to them automatically. Open one only if the user names it.

<!-- Add rows only for resources used across MULTIPLE workstations (e.g. voice-principles.md).
     Anything owned by one domain belongs in that workstation's Resources/, not here.
     Keep each row to one line; big reference bodies go in their own file, not this index. -->
