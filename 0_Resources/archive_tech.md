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
| Sep. 26, 2026 | scapy | 2.7.0 | Python / Pip | New Install | Downloaded & Installed | Throwaway venv in the Claude session scratchpad only (not the IDF env, not the repo): independent radiotap decoder to test tools/sniff.py output. |
| Oct. 20, 2026 | docx | 9.13.0 | Node / npm | New Install | Downloaded & Installed | Local install in the Claude session scratchpad only (not global, not the repo): build the paper-status report .docx in Plan/Paper-Editing/4-Verification. |
| Oct. 20, 2026 | pptxgenjs | 4.0.1 | Node / npm | New Install | Downloaded & Installed | Local install in the Claude session scratchpad only (not global, not the repo): build the Thesis 3 defense slide deck .pptx. |
| Oct. 22, 2026 | lxml | 6.1.3 | Python / Pip | New Install | Downloaded & Installed | User site-packages (pip --user, system Python 3.12; not the IDF env): needed by the docx skill's office/validate.py to schema-check the edited thesis copies (Downloads/Thesis 3 - To check*.docx). |
