# Archive Tech — Workstation Dependency & Environment Ledger

Infinite, append-only log of every package, library, toolchain, or system dependency an
agent installs, updates, verifies, or fails to change on this workstation.
**No line limit. Never edit, clear, or reorder past rows — only append to the bottom.**
Read only when the user asks for install history; otherwise this file is write-only.

## Field schema (fill every column)

1. **Date** — strictly `mmm. dd, yyyy` (e.g. Jul. 15, 2026).
2. **Package** — exact tool/library name.
3. **Version** — version targeted or verified.
4. **Type** — environment layer: `Python / Pip`, `Node / npm`, `Rust / Cargo`, `System / Homebrew`, `System / Choco`, `System / Apt`, `Global Binary`, …
5. **Action Type** — exactly one:
   - `New Install` — package was absent before this session.
   - `Update (from X.X.X)` — existed, version changed; include the old version.
   - `Retain (No Change)` — already at the right version, system left untouched.
6. **Status** — outcome:
   - `Downloaded & Installed` — install/update succeeded.
   - `Verified (Existing)` — no action needed, package retained.
   - `Failed` — errored during install.
   - `Attempted (Cancelled)` — aborted by human or timeout.
7. **Purpose** — the feature/script that required this state.

**When to write:** immediately after checking a version or running any package command.

## Installation & environment history

| Date | Package | Version | Type | Action Type | Status | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
<!-- Example rows — delete on first real use:
| Jul. 12, 2026 | matplotlib | 3.10.0 | Python / Pip | New Install | Downloaded & Installed | Local data-viz script rendering. |
| Jul. 15, 2026 | numpy | 1.26.4 | Python / Pip | Update (from 1.24.0) | Downloaded & Installed | Resolve matplotlib compat issue. |
| Jul. 15, 2026 | graphviz | 12.0.0 | System / Homebrew | New Install | Failed | Missing C++ compiler flags during build. |
| Aug. 02, 2026 | git | 2.45.2 | Global Binary | Retain (No Change) | Verified (Existing) | Confirmed version matches repo requirement. |
-->
