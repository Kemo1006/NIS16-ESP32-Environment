#!/usr/bin/env python3
"""audit_false_positives.py - does the attack test ever 'confirm' an attack on NORMAL traffic?
(oct. 19 2026, verification #53)

A placebo test. For every analysed attack run, only its BASELINE windows are kept; the
second half of the baseline is relabelled as if it were the attack, and the exact same
3-sigma test (verify_attack.verify, same signatures, same minimum effect) is run on it.
Nothing changed between the two halves, so a sound test must NOT confirm. Each run is
tested against the blackhole AND the wormhole signature.

A confirmation here is a FALSE POSITIVE: the test sees an attack where there was none.
Zhukabayeva et al. (2025) use the 3-sigma rule; under a normal distribution a single
3-sigma move happens by chance ~0.27 % of the time (two-sided), so ~0 are expected.

    python tools/audit_false_positives.py        exit 0 = no false positive, 1 = some
"""
import contextlib, glob, io, os, sys
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, 'tools'); sys.path.insert(0, 'analysis')
import pandas as pd
import verify_attack as va
import attack_checks as ac


def placebo(df, attack):
    lab = pd.to_numeric(df["Label"], errors="coerce")
    base = df[lab == va.LABEL_BASELINE].copy()
    if base.empty:
        return None
    tc = "t_anchor_s" if "t_anchor_s" in base.columns else "window_start"
    cut = pd.to_numeric(base[tc], errors="coerce").median()
    base.loc[pd.to_numeric(base[tc], errors="coerce") > cut, "Label"] = va.ATTACK_LABEL[attack]
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        ok, conclusive = va.verify(base, attack, 3.0, checks=False)
    blocked = ''
    if ok and attack == 'blackhole' and 'node_role' in base.columns:
        # the full verdict also needs the ATTACKER check: a blackhole forwards < 50 %
        # (attack_checks.ATTACKER_MAX_FORWARD); congestion that only dents forwarding fails it
        a = base[(base['node_role'] == 'blackhole') & (pd.to_numeric(base['Label'], errors='coerce') == 1)]
        rec = pd.to_numeric(a.get('recv_count_delta'), errors='coerce').sum()
        fwd = pd.to_numeric(a.get('forward_count_delta'), errors='coerce').sum()
        if rec > 0 and fwd / rec > ac.ATTACKER_MAX_FORWARD:
            blocked = f'blocked by the attacker check (it forwarded {fwd / rec:.0%} > {ac.ATTACKER_MAX_FORWARD:.0%})'
    return ok, blocked


fps, stopped, n = [], [], 0
for f in sorted(glob.glob('datasets/analysis/*/*/*/*/feature_table.csv')):
    cell = '/'.join(f.replace(os.sep, '/').split('/')[2:6])
    if cell.startswith('baseline/'):
        continue
    df = pd.read_csv(f, low_memory=False)
    for attack in ('blackhole', 'wormhole'):
        r = placebo(df, attack)
        if r is None:
            continue
        n += 1
        if r[0] and r[1]:
            stopped.append(f'{cell} ({attack} signature): 3-sigma alone passed - {r[1]}')
        elif r[0]:
            fps.append(f'{cell} ({attack} signature)')
print(f'{n} placebo tests (baseline half vs baseline half, both signatures)')
print(f'3-sigma alone passed, the full verdict would not: {len(stopped)}' + ''.join('\n   ' + x for x in stopped))
print(f'FALSE POSITIVES (full verdict): {len(fps)}' + ''.join('\n   ' + x for x in fps))
sys.exit(1 if fps else 0)
