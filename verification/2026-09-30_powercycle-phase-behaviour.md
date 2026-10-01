# Verification: does power-cycling a board mid-run make the phases go back?

**Date:** sep. 30, 2026
**Verdict:** 🔶 **PARTIALLY CONFIRMED — it depends entirely on *which* board you unplug.**

- Unplug a **CHILD** → ❌ phases **cannot** go back. You lose data instead (a silent gap).
- Unplug the **ROOT** → ✅ the run genuinely restarts. This is the one case to fear.

## The claim

User: *"how does powercycle work because we are just worried that if we plug it off it might cause the
phases to go back. so just wanna know if the powercycle works diff in firmware or how does it work in
our test."*

Two sub-claims:

1. **Does the firmware behave differently for a `powercycle` run?**
2. **Can unplugging a board mid-run push the phases backward?**

## What this means (plain language)

**Unplugging a child is safe for your phase timeline.** The root alone decides what phase the network
is in, and it walks the phases forward on its own timer — no child can rewind it. A child that you
unplug and replug comes back as "I don't know what phase it is" (255), never as "baseline". It then
waits for the root's next announcement and rejoins at whatever phase is current by then.

**The real cost is a hole in that child's data, not a wrong phase.** The root only announces a phase
**once**, at the moment it starts. There is no repeat during a phase. So a child that reboots in the
middle of the attack window hears nothing until cooldown begins, and — because of a deliberate
"don't log junk" gate — it writes **no rows at all** for that entire stretch. Unplug at the start of
the attack and you lose all 180 seconds of that node's attack data.

⚠️ **Your wizard's own on-screen checklist is misleading about this.** It tells the operator "keep the
board powered afterward — it keeps logging." It does not keep logging right away; it resumes only at
the next phase boundary.

**Unplugging the root is the dangerous one.** The root stamps every announcement with a session ID.
A rebooted root is a *new* session, and every child throws away the phase it was holding and drops to
255 until the new root reaches Phase 0 — while the root itself restarts from stabilisation. That is a
genuine "the phases went back," and it has already happened to you once (the sep. 26 21:11 run).

## Evidence

### Sub-claim 1 — is the firmware different for a powercycle run? ❌ NO

- **`components/mesh_common/include/mesh_config.h:478`** — *"mobility / powercycle are HUMAN scenarios:
  no flag, label-only on the host."* The scenario never reaches the firmware.
- **`run.ps1:427`** — *"mobility / powercycle -> no flag anywhere (human, label-only)"*.
- **`run.ps1:477`** — `-DTRAFFIC_PROFILE` gets a build suffix, *"so a plain 'stationary'/'mobility'/
  'powercycle' [build is] untouched"*. The compiled binary is byte-identical to a stationary run.
- **`menu.ps1:343`** — the scenario is offered as *"powercycle (HUMAN: you unplug/replug one child --
  checklist only)"*.

**So:** there is no powercycle code path. The firmware cannot tell a powercycle run from a normal one.
The only difference is the export folder name, the ledger label, and a human pulling a plug.

### Sub-claim 2a — can a CHILD's reboot move the phases backward? ❌ NO (three independent reasons)

**1. The root owns the timeline and nothing feeds back into it.**
`root_node/main/root_main.c:419-470` is a straight line: announce Phase 0 → `vTaskDelay(baseline)` →
announce attack → `vTaskDelay(attack)` → announce cooldown → `vTaskDelay(cooldown)` → TERMINATE →
`vTaskDelete(NULL)`. The phase sequence is driven purely by the root's own clock. No child message,
join, or reboot is an input to it.

**2. Sequence-number deduplication makes going backward impossible by construction.**
`components/mesh_common/src/phase_listener.c` — every phase message is checked:

```c
if (msg->seq_num <= s_last_seq) {
    /* Duplicate or out-of-order broadcast — ignore. */
    continue;
}
```

An older or repeated announcement is discarded. A child can only ever move *forward*.

**3. The root never re-sends an earlier phase.** Enumerated **every** caller of
`phase_listener_broadcast*` in the whole tree:

| Call site | What it sends | When |
|---|---|---|
| `root_main.c:259` (`broadcast_and_count`) | the real phases 0/1/3/4 | **once each**, at the transition |
| `root_main.c:366` | PREPARE | while waiting for the child roster (**before Phase 0**) |
| `root_main.c:413` | PREPARE | during the stabilisation window (**before Phase 0**) |
| `root_main.c:483` | TERMINATE | re-sent for `TERMINATE_RESEND_S` after the run |

Nothing else broadcasts a phase. `MESH_EVENT_CHILD_CONNECTED` exists (`mesh_setup.c:395`) but does
**not** trigger a re-announcement.

### Sub-claim 2b — what actually happens to the power-cycled child

**Boot state** (`phase_listener.c` statics): `s_phase_id = PHASE_ID_UNSET` (**255**), `s_last_seq = 0`,
`s_session_id = 0`, `s_prepare_heard = false`. It returns as *unknown*, not as *baseline* — so even the
"it restarts at phase 0" worry does not hold.

**The logging gate** — `mesh_config.h:680` sets `LOG_ONLY_DURING_RUN 1`, and
`csv_logger.c:1182-1195` implements it:

```c
if (!s_phase_seen
        && (phase_listener_prepare_heard() || phase_id <= PHASE_ID_COOLDOWN)) {
    s_phase_seen = true;   /* logging starts now */
}
```

The board writes nothing until it hears **PREPARE** or a row carrying **phase 0–3**. Since PREPARE only
goes out before Phase 0, a mid-run reboot means the gate stays shut until the **next phase transition**.

**Worked worst case:** unplug the target child just as `PHASE -- ATTACK` prints (which is exactly what
the wizard's checklist instructs — `run.ps1:576`). The child reboots, hears nothing for the full
180 s attack window, writes **zero rows** for it, and only starts logging when cooldown is announced.
The attack-phase data for that node is gone, and PDR/ForwardingRatio for it will be NaN, not 0.

**The data also splits into two files.** `csv_logger.c:204-205`:

```c
snprintf(out, out_len, "%s/%s_%s_r%d_b%d_%s.csv",
         run_dir, role_str, node_id, run_number, sd_status_boot_count(), kind);
```

`b%d` is the boot counter, so the pre-unplug rows are in `…_b1_…csv` and the post-unplug rows in
`…_b2_…csv`. **Both must be imported** or half the run silently goes missing — the same failure mode as
the G402 "phase-255 files are later boots" finding.

### Sub-claim 2c — the ROOT reboot: phases DO go back ✅

`phase_listener.c`, session check:

```c
if (msg->session_id != s_session_id) {
    ...
    s_phase_id = PHASE_ID_UNSET;   /* drop the phase from the old session */
    s_last_seq = 0;
    ESP_LOGW(TAG, "Root RESTARTED (new session %08lx) - dropped phase %u from the old "
                  "session; rows stay phase 255 until the new root's Phase 0.");
}
```

The root's `seq_num` restarts at 1 on every boot, so without this guard the new root's announcements
would all fail the dedupe test and children would carry the dead session's phase forever. With it, every
child resets to 255 and the run effectively begins again — the root's controller task restarts from
stabilisation.

The code comment records this as a real incident: the **2026-09-26 21:11 home run**, where the root
booted old firmware, reached Phase 0 with the children, was reflashed, *"and the children logged 129 s
of 'baseline' before the real root's Phase 0."*

## Conflicts between sources

**1. The operator checklist contradicts the logging gate.** `run.ps1:580` prints:

> *"Do it ONCE, in one motion; keep the board powered afterward -- it keeps logging
> (CSV_EXPORT_ON_INIT, append mode)."*

That is wrong for a mid-phase unplug. `CSV_EXPORT_ON_INIT` controls when the *export task* starts, not
whether rows are written; `LOG_ONLY_DURING_RUN` independently blocks all writes until a phase is heard.
**The code wins** — the board is silent until the next phase boundary. The checklist should say so,
because it is the one instruction the operator reads before pulling the plug.

**2. A prior memory note is imprecise.** A saved note says the mid-run logging gap was *"fixed for
powercycle runs only (root re-announce)."* There is **no mid-run re-announce** in the current tree — the
only repeated announcements are PREPARE (before Phase 0) and TERMINATE (after the run). The fix covers a
board power-cycled *before* Phase 0, not one power-cycled *during* a phase. **The code wins.**

## What remains unverified

- **Not hardware-tested.** This is a reading of the firmware, not an observed run. I did not flash a
  board or pull a plug.
- **No empirical powercycle data exists to check against.** `find` over `datasets/` returns **no**
  `powercycle` or `mobility` folder — the only scenario folders are the stationary/highload/burst cells
  under `baseline/linear/home`, `blackhole/linear/home` and `blackhole/linear/G402`. Likewise **no
  `_b2_` or higher file exists anywhere in `exports/`**, confirming no imported run has ever contained a
  mid-run reboot. So the behaviour above has never actually been exercised in your dataset.
- **How long the rejoin itself takes** (mesh re-association after replug) is not bounded here — if the
  child takes longer to rejoin than the remaining phase, it would miss the next announcement too and
  stay silent into the following phase. Not measured.

## Sources

- `components/mesh_common/include/mesh_config.h:478` — powercycle is a human, label-only scenario.
- `components/mesh_common/include/mesh_config.h:680` — `LOG_ONLY_DURING_RUN`.
- `components/mesh_common/src/phase_listener.c` — boot statics, session-ID guard, seq dedupe.
- `components/mesh_common/src/csv_logger.c:204-205` — per-boot filenames (`_b<N>_`).
- `components/mesh_common/src/csv_logger.c:1182-1195` — `log_gate_open()`, the silence rule.
- `root_node/main/root_main.c:400-486` — the phase sequence and every broadcast call site.
- `run.ps1:565-590` — `Show-ScenarioChecklist`, the operator instructions (and the misleading line).
- `menu.ps1:343,2311` — how the wizard offers and reminds about the scenario.
