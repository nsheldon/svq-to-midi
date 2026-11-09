"""Compare fantoms_lists.json (Fantom-S Sound List) with the app's Fantom-X tables in
SVQKit/Sources/SVQKit/FantomPatchNames.swift (read-only). Prints, per group, the entries that
differ; "spacing only" when they match with all spaces removed.
    python3 -I compare_lists.py
"""
import json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
fs = json.load(open(os.path.join(HERE, 'fantoms_lists.json')))
src = open(os.path.join(HERE, '../../SVQKit/Sources/SVQKit/FantomPatchNames.swift')).read()
def strings(block): return re.findall(r'"((?:[^"\\]|\\.)*)"', block)
def unesc(s): return s.replace('\\"', '"').replace('\\\\', '\\')
pres_src = src[src.index('static let presets'):src.index('static let gm2:')]
fx_groups = {}
for m in re.finditer(r'// (PR-[A-I])[^\n]*\n(.*?)\n        \],', pres_src, re.S):
    fx_groups[m.group(1)] = [unesc(s) for s in strings(m.group(2))]
fx_gm2 = [(int(a), int(b), unesc(c)) for a, b, c in re.findall(r'\((\d+), (\d+), "((?:[^"\\]|\\.)*)"\)', src[src.index('static let gm2:'):src.index('presetRhythmSets')])]
fx_prst = [unesc(s) for s in strings(src[src.index('static let presetRhythmSets'):src.index('static let gm2RhythmSets')])]
fx_gmkits = [(int(a), unesc(b)) for a, b in re.findall(r'\((\d+), "((?:[^"\\]|\\.)*)"\)', src[src.index('static let gm2RhythmSets'):])]
assert all(len(v) == 128 for v in fx_groups.values()) and len(fx_gm2) == 256, {k: len(v) for k, v in fx_groups.items()}
squash = lambda s: s.replace(' ', '') if isinstance(s, str) else (tuple(map(squash, s)) if isinstance(s, tuple) else s)
fx_all = {n: (g, i + 1) for g, v in fx_groups.items() for i, n in enumerate(v)}
fx_all_sq = {squash(n): (g, i + 1, n) for g, v in fx_groups.items() for i, n in enumerate(v)}
def cmp(label, a, b):
    d = []
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y: d.append((i + 1, x, y, 'spacing only' if squash(x) == squash(y) else ''))
    print(f'== {label}: {len(a)} FS vs {len(b)} FX: ' + ('identical' if not d and len(a) == len(b) else f'{len(d)} differ'))
    return d
for g in ['PR-A', 'PR-B', 'PR-C', 'PR-D', 'PR-E']:
    for n, x, y, note in cmp(g, fs['presets'][g], fx_groups[g]):
        where = fx_all.get(x) or (fx_all_sq.get(squash(x)) and fx_all_sq[squash(x)][:2])
        print(f'   {n:3d} FS {x!r:16} FX {y!r:16} {note}' + (f'  (FS name is FX {where[0]} {where[1]})' if where and not note else ''))
print('== PR-F (S88 only):', fs['presets']['PR-F'])
for n in fs['presets']['PR-F']:
    w = fx_all.get(n) or (fx_all_sq.get(squash(n)) and fx_all_sq[squash(n)])
    print('   ', n, '-> in Fantom-X list at', w)
print('   Fantom-X PR-F 1-10:', fx_groups['PR-F'][:10])
d = cmp('GM2 (lsb, program, name)', [tuple(e) for e in fs['gm2']], fx_gm2)
for n, x, y, note in d: print(f'   {n:3d} FS {x} FX {y} {"spacing only" if squash(x[2]) == squash(y[2]) and x[:2] == y[:2] else ""}')
for n, x, y, note in cmp('PRST rhythm sets', fs['presetRhythmSets'], fx_prst): print(f'   {n} FS {x!r} FX {y!r} {note}')
if len(fx_prst) > len(fs['presetRhythmSets']): print('   FX only:', fx_prst[len(fs['presetRhythmSets']):])
for n, x, y, note in cmp('GM2 rhythm sets', fs['gm2RhythmSets'], [b for a, b in fx_gmkits]): print(f'   {n} FS {x!r} FX {y!r} {note}')
