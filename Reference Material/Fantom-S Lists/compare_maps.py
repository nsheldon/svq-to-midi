"""Compare the Fantom-S map (fs_map.json, from parse_fs_map.py) with the Fantom-X map
(../Fantom-X Map/map678.json): per section, parameters matched by offset; reports offsets/masks
only in one map, and parameters whose mask, name or range differ.
    python3 -I compare_maps.py
"""
import json, re, os
HERE = os.path.dirname(os.path.abspath(__file__))
fs = json.load(open(os.path.join(HERE, 'fs_map.json')))
fx = json.load(open(os.path.join(HERE, '../Fantom-X Map/map678.json')))
def norm(n): return re.sub(r'\s+', ' ', n.replace('—', '-').replace('—', '-')).strip()
def rng(n):
    m = re.search(r'\((-?\d+)\s*-\s*(-?\d+)\)', norm(n)); return (int(m.group(1)), int(m.group(2))) if m else None
def base(n): return re.sub(r'\s*\(-?\d+\s*-\s*-?\d+\).*$', '', norm(n)).strip()
def width(p): return sum(c.count('a') + c.count('b') + c.count('c') + c.count('d') for c in p['masks'])
for s in fs:
    a = {p['off']: p for p in fs[s] if 'off' in p}
    if not a: continue
    if s not in fx: print(f'== {s}: not in Fantom-X map'); continue
    b = {p['off']: p for p in fx[s] if 'off' in p}
    diffs = []
    for off in sorted(set(a) | set(b)):
        p, q = a.get(off), b.get(off)
        if not q: diffs.append(f'  {off:04X} only Fantom-S: {norm(p["name"])} {p["masks"]}'); continue
        if not p: diffs.append(f'  {off:04X} only Fantom-X: {norm(q["name"])} {q["masks"]}'); continue
        d = []
        if p['masks'] != q['masks']: d.append(f'masks {q["masks"]} -> {p["masks"]}')
        if base(p['name']).lower() != base(q['name']).lower(): d.append(f'name {base(q["name"])!r} -> {base(p["name"])!r}')
        if rng(p['name']) != rng(q['name']): d.append(f'range {rng(q["name"])} -> {rng(p["name"])}')
        if d: diffs.append(f'  {off:04X} ' + '; '.join(d))
    tot = lambda m: [hex(p['total']) for p in m[s] if 'total' in p]
    bits = lambda m: sum(width(p) for p in m[s] if 'off' in p)
    print(f'== {s}: FS {len(a)} params {tot(fs)} {bits(fs)} bits / FX {len(b)} params {tot(fx)} {bits(fx)} bits: ' + ('identical' if not diffs else f'{len(diffs)} differences'))
    for d in diffs: print(d)
