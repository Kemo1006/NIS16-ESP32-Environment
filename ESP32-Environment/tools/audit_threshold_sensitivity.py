#!/usr/bin/env python3
"""audit_threshold_sensitivity.py - are the verdicts decided by the DATA or by the numbers
chosen? Every threshold is moved by about -50 % / +50 % (sigma 2.5 / 3.5) and every
analysed attack run is judged again; two absurd CONTROL settings must flip verdicts (else
the test is not changing anything). Read-only. (oct. 19 2026, verification #51)

    python tools/audit_threshold_sensitivity.py
"""
import contextlib, glob, io, os, sys
from concurrent.futures import ProcessPoolExecutor

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VARIANTS = [
    ('as is', {}),
    ('sigma 2.5', {'sigma': 2.5}), ('sigma 3.5', {'sigma': 3.5}),
    ('min effect 0.05', {'min_effect': 0.05}), ('min effect 0.20', {'min_effect': 0.20}),
    ('victim cut 0.25', {'ac.VICTIM_CUT_PDR': 0.25}), ('victim cut 0.75', {'ac.VICTIM_CUT_PDR': 0.75}),
    ('bystander drop 0.15', {'ac.BYSTANDER_MAX_DROP': 0.15}), ('bystander drop 0.45', {'ac.BYSTANDER_MAX_DROP': 0.45}),
    ('attacker fwd 0.25', {'ac.ATTACKER_MAX_FORWARD': 0.25}), ('attacker fwd 0.75', {'ac.ATTACKER_MAX_FORWARD': 0.75}),
    ('flip 2 windows', {'ac.FLIP_MIN_WINDOWS': 2}), ('flip 5 windows', {'ac.FLIP_MIN_WINDOWS': 5}),
    ('baseline floor 0.80', {'floor': 0.80}), ('baseline floor 0.95', {'floor': 0.95}),
    ('CONTROL sigma 1000', {'sigma': 1000.0, 'min_effect': 0.99}), ('CONTROL victim cut 0.0', {'ac.VICTIM_CUT_PDR': 0.0}),
]


def judge(job):
    vname, var, ft, attack = job
    os.chdir(BASE)
    sys.path.insert(0, os.path.join(BASE, 'tools')); sys.path.insert(0, os.path.join(BASE, 'analysis'))
    import pandas as pd
    import verify_attack as va
    import attack_checks as ac
    # reset EVERY knob to its default first - a worker process runs many jobs
    global _DEF
    if '_DEF' not in globals():
        _DEF = {k: getattr(ac, k) for k in ('VICTIM_CUT_PDR', 'BYSTANDER_MAX_DROP', 'ATTACKER_MAX_FORWARD', 'FLIP_MIN_WINDOWS')}
        _DEF['ME'] = dict(va.MIN_EFFECT); _DEF['BF'] = dict(va.BASELINE_FLOOR)
    for k in ('VICTIM_CUT_PDR', 'BYSTANDER_MAX_DROP', 'ATTACKER_MAX_FORWARD', 'FLIP_MIN_WINDOWS'):
        setattr(ac, k, _DEF[k])
    va.MIN_EFFECT.clear(); va.MIN_EFFECT.update(_DEF['ME']); va.BASELINE_FLOOR.clear(); va.BASELINE_FLOOR.update(_DEF['BF'])
    sigma = var.get('sigma', 3.0)
    for k, v in var.items():
        if k.startswith('ac.'):
            setattr(ac, k[3:], v)
    if 'min_effect' in var:
        for f in ('PDR', 'ForwardingRatio', 'NeighbourForwardingRatio', 'ConsistencyScore', 'TunnelIntensity', 'DuplicateRate'):
            va.MIN_EFFECT[f] = var['min_effect']
    if 'floor' in var:
        va.BASELINE_FLOOR['PDR'] = va.BASELINE_FLOOR['ForwardingRatio'] = var['floor']
    df = pd.read_csv(ft, low_memory=False)
    with contextlib.redirect_stdout(io.StringIO()):
        ok, concl = va.verify(df, attack, sigma)
    word = 'CONFIRMED' if ok else ('SETUP INVALID' if va._LAST_SETUP_INVALID[0] else ('INCONCLUSIVE' if not concl else 'NOT CONFIRMED'))
    return vname, ft, word


if __name__ == '__main__':
    tabs = [t for t in sorted(glob.glob(os.path.join(BASE, 'datasets', 'analysis', '*', '*', '*', '*', 'feature_table.csv'))) if '\\baseline\\' not in t]
    jobs = [(vn, var, t, 'wormhole' if '\\wormhole\\' in t else 'blackhole') for vn, var in VARIANTS for t in tabs]
    with ProcessPoolExecutor(6) as ex:
        res = list(ex.map(judge, jobs, chunksize=4))
    base = {ft: w for vn, ft, w in res if vn == 'as is'}
    print(f'{len(tabs)} runs x {len(VARIANTS)} settings\n')
    print('as is:', {w: list(base.values()).count(w) for w in sorted(set(base.values()))})
    for vn, _ in VARIANTS[1:]:
        flips = [(ft, base[ft], w) for v, ft, w in res if v == vn and w != base[ft]]
        print(f'{vn:24} {len(flips):2} verdict(s) flip' + ('' if not flips else ':'))
        for ft, a, b in flips[:4 if vn.startswith('CONTROL') else 99]:
            print('      ', ft.split('analysis\\')[1].replace('\\feature_table.csv', ''), f'{a} -> {b}')
