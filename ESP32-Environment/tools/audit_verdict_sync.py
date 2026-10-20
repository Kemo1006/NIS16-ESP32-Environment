#!/usr/bin/env python3
"""audit_verdict_sync.py - do the VERIFIER (verdict + CONFIDENCE grade) and the REDO LIST
(REDO / CHECK / OK) agree, for every analysed attack run? (oct. 19 2026, verification #51)

  R1  NOT CONFIRMED / SETUP INVALID / INCONCLUSIVE -> the redo list has a verifier REDO
  R2  CONFIRMED + STRONG / GOOD -> OK (green DONE, same note count); MINOR GAPS ->
      one verifier CHECK with the same minor-gap count (yellow DONE - RECAPTURE ADVISED)
  R3  CONFIRMED + MAJOR GAPS -> one 'verifier-data' REDO naming the same data gaps
      (orange RECAPTURE REQUIRED)
  R4  any other REDO on a CONFIRMED run comes from a NON-verifier source (capture completeness,
      structure, the verification log, a thesis-checklist D-row) - and that source is named
  R5  each run's redo severity = the worst of its reasons (computed, never set by hand)

    python tools/audit_verdict_sync.py          exit 0 = all rules hold, 1 = a problem listed
"""
import contextlib, io, os, re, sys, collections
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, 'tools'); sys.path.insert(0, 'analysis')
import pandas as pd
import verify_attack as va
import redo_list as rl

with contextlib.redirect_stderr(io.StringIO()):
    cells = rl.collect()
rank = {rl.OK: 0, rl.CHECK: 1, rl.REDO: 2}
bad, rows = [], []
for c in cells:
    key = (c['attack'], c['topology'], c['location'], c['scenario'])
    if c['attack'] == 'baseline':
        continue
    ft = os.path.join('datasets', 'analysis', *key, 'feature_table.csv')
    if not os.path.isfile(ft):
        continue
    df = pd.read_csv(ft, low_memory=False)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        conf, concl = va.verify(df, c['attack'], 3.0)
    txt = buf.getvalue()
    verdict = re.search(r'VERDICT: (.+?)(\s{2}\(|$)', txt, re.M).group(1).strip()
    grade = (re.search(r'CONFIDENCE: (STRONG|GOOD|MINOR GAPS|UNDETERMINED|MAJOR GAPS|FAILED)', txt) or [None, '?'])[1]
    ngap = len(re.findall(r'(?m)^     ~ MAJOR GAP \(affects the result\): ', txt))
    nmin = len(re.findall(r'(?m)^     ~ MINOR GAP ', txt))
    reasons = c['reasons']                       # (sev, text, evidence, fix)
    ver = [r for r in reasons if r[2] in ('verifier', 'verifier-data')]
    other = [r for r in reasons if r[2] not in ('verifier', 'verifier-data')]
    sev = c['severity']
    name = '/'.join(key)
    # R5
    worst = max([r[0] for r in reasons], key=lambda s: rank[s], default=rl.OK)
    if worst != sev:
        bad.append(f'R5 {name}: severity {sev} but worst reason {worst}')
    if 'CONFIRMED' not in verdict or 'NOT CONFIRMED' in verdict:
        if not any(r[0] == rl.REDO for r in ver):
            bad.append(f'R1 {name}: verdict "{verdict}" but the redo list has no verifier REDO')
    else:
        if grade == 'MINOR GAPS':
            q = [r for r in ver if r[0] == rl.CHECK and r[1].startswith('CONFIRMED - MINOR GAPS')]
            m = re.search(r'\((\d+) minor gap', q[0][1]) if q else None
            if len(q) != 1 or not m or int(m.group(1)) != nmin:
                bad.append(f'R2 {name}: report has {nmin} minor gap(s), redo list says {q[0][1][:70] if q else "nothing"}')
        if grade in ('STRONG', 'GOOD') and any(r[0] != rl.OK for r in ver):
            bad.append(f'R2 {name}: {grade} but the redo list has a verifier CHECK/REDO: {[r[1][:60] for r in ver]}')
        if grade == 'MINOR GAPS' and any(r[0] == rl.REDO for r in ver):
            bad.append(f'R2 {name}: {grade} but the redo list has a verifier CHECK/REDO: {[r[1][:60] for r in ver]}')
        if grade == 'GOOD':
            q = [r for r in ver if r[1].startswith('CONFIRMED - GOOD')]
            m = re.search(r'\((\d+) note', q[0][1]) if q else None
            nnote = len(re.findall(r'(?m)^     ~ note: ', txt))
            if len(q) != 1 or not m or int(m.group(1)) != nnote:
                bad.append(f'R2 {name}: report has {nfoot} note(s), redo list says {q[0][1][:70] if q else "nothing"}')
        if grade == 'MAJOR GAPS':
            q = [r for r in ver if r[0] == rl.REDO and r[2] == 'verifier-data' and r[1].startswith('CONFIRMED - MAJOR GAPS')]
            if len(q) != 1 or q[0][1].split(' | ')[0].count(';') + 1 != ngap:
                bad.append(f'R3 {name}: report has {ngap} data gap(s), redo list says {q[0][1][:70] if q else "nothing"}')
        if sev == rl.REDO and grade != 'MAJOR GAPS' and not any(r[0] == rl.REDO for r in other):
            bad.append(f'R4 {name}: CONFIRMED but REDO without a non-verifier REDO source')
    src = sorted({r[2] if not r[2].startswith('verification') else 'verification log' for r in reasons if r[0] == rl.REDO})
    rows.append((name, verdict.replace(c['attack'].upper() + ' ', ''), grade, sev, ', '.join(src)))

print(f'{len(rows)} attack runs checked\n')
print(f'{"run":44} {"verdict":28} {"grade":10} {"redo list":6}  REDO comes from')
for r in rows:
    print(f'{r[0]:44} {r[1][:28]:28} {r[2]:10} {r[3]:6}  {r[4]}')
print('\nCONSISTENCY:', 'ALL 5 RULES HOLD' if not bad else f'{len(bad)} problem(s)')
for b in bad:
    print('  ', b)
sys.exit(1 if bad else 0)
cnt = collections.Counter((r[1].split(' -')[0].split('  ')[0], r[3]) for r in rows)
print('\nverdict x redo:', dict(cnt))
