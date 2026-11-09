"""Parse the original Fantom (FA-76)'s preset Patch and Rhythm Set names from its MIDI
Implementation (FANTOM_MI.pdf, "Patch List" and "Rhythm Set List", pages 3-11) into
fantom_lists.json.

    pdftotext -layout ../FANTOM_MI.pdf dl/FANTOM_MI.txt   (Roland's text; dl/ isn't committed)
    python3 parse_fantom.py
"""
import json, re

lines = open('dl/FANTOM_MI.txt').read().split('\n')
text_end = next(i for i, l in enumerate(lines) if 'Waveform List' in l and i > 100)
lines = lines[:text_end]

# Patch List: each page prints two groups side by side, each as two columns of 64.
entry = re.compile(r'(\d{3})\s{2,}(.+?)\s+(\d+)\s+(POLY|MONO)')
groups = {}
page_groups = None
for line in lines:
    heads = re.findall(r'(USER|PR-[A-E]) \((?:User|Preset [A-E]) Group\)', line)
    if heads:
        page_groups = heads
        continue
    if 'GM (GM2 Group)' in line or 'Rhythm Set List' in line:
        page_groups = None
    if not page_groups:
        continue
    found = list(entry.finditer(line))
    if len(found) != 2 * len(page_groups):
        continue
    for k, m in enumerate(found):
        group = page_groups[k // 2]
        number, name = int(m.group(1)), m.group(2).rstrip()
        groups.setdefault(group, {})[number] = name

presets = []
for g in ['PR-A', 'PR-B', 'PR-C', 'PR-D', 'PR-E']:
    names = groups[g]
    assert sorted(names) == list(range(1, 129)), (g, len(names))
    assert all(len(n) <= 12 for n in names.values()), g
    presets.append([names[i] for i in range(1, 129)])

# Rhythm Set List: kit names head each page's columns ("Note No.  R&B Kit 1  R&B Kit 2 ...").
kits = {'PRST': [], 'GM2': []}
group = None
for line in lines:
    if 'PRST (Preset Group)' in line and 'Rhythm' not in line:
        group = 'PRST'
    elif 'GM (GM2 Group)' in line:
        group = 'GM2'
    m = re.match(r'\s*Note No\.\s+(.*)$', line)
    if m and group:
        kits[group] += [k.strip() for k in re.split(r'\s{2,}', m.group(1).strip()) if k.strip()]
assert len(kits['PRST']) == 16, kits['PRST']
assert len(kits['GM2']) == 9, kits['GM2']

# GM2 patches: one page, four blocks of 64 ("No. Name Voice LSB PC"), PC printed only for LSB 0.
# Each line is cut into blocks at the header's "No." columns, and each block's trailing numbers
# (voice, LSB, and PC when LSB is 0) are taken off the right; what is left is the name. The LSB and
# PC order is the GM2 standard's, taken from the app's Fantom-X table and checked block by block.
start = next(i for i, l in enumerate(lines) if l.strip() == 'GM (GM2 Group)')
header = lines[start + 1]
cols = [m.start() for m in re.finditer(r'No\.', header)]
assert len(cols) == 4, header
order = [(int(l), int(p)) for l, p in re.findall(r'\((\d+), (\d+), "', open('../../SVQKit/Sources/SVQKit/FantomPatchNames.swift').read())]
assert len(order) == 256
gm2 = {}
end = next(i for i in range(start, len(lines)) if 'Voice: number of voice' in lines[i])
for line in lines[start + 2:end]:
    for k, c in enumerate(cols):
        block = line[max(0, c - 2):(cols[k + 1] - 2 if k + 1 < 4 else len(line))]
        m = re.match(r'\s*(\d{3})\s+(.*?)\s*$', block)
        if not m:
            continue
        number, rest = int(m.group(1)), m.group(2)
        lsb, pc = order[number - 1]
        nums = 3 if lsb == 0 else 2
        tail = re.match(r'(.*?)\s+(\d+)\s+(\d+)' + (r'\s+(\d+)' if nums == 3 else '') + r'$', rest)
        assert tail, (number, rest)
        assert int(tail.group(3)) == lsb and (nums == 2 or int(tail.group(4)) == pc + 1), (number, rest, lsb, pc)
        gm2[number] = tail.group(1).strip()
assert sorted(gm2) == list(range(1, 257)), [n for n in range(1, 257) if n not in gm2]
gm2_list = [[l, p, gm2[i + 1]] for i, (l, p) in enumerate(order)]

json.dump({'presets': presets, 'presetRhythmSets': kits['PRST'], 'gm2RhythmSets': kits['GM2'], 'gm2': gm2_list},
          open('fantom_lists.json', 'w'), indent=1)
print('presets', [len(p) for p in presets], 'PRST', len(kits['PRST']), 'GM2 kits', len(kits['GM2']), 'GM2', len(gm2_list))
