"""Parse the Fantom-S/S88 Sound List (FANTOM-S_PA.pdf) into fantoms_lists.json: Performances
(USER, PRESET), preset Patches PR-A..PR-E (+ PR-F, Fantom-S88 only, 8 Patches), GM2 Patches with
Bank Select LSB and 0-based program, preset (PRST) and GM2 Rhythm Sets.

    pdftotext -layout ../FANTOM-S_PA.pdf dl/FANTOM-S_PA.txt   (Roland's text; dl/ isn't committed)
    python3 -I parse_fs_lists.py dl/FANTOM-S_PA.txt fantoms_lists.json

Patch names are at most 12 characters; pdftotext may collapse a double space inside a name.
"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
lines = open(sys.argv[1] if len(sys.argv) > 1 else 'dl/FANTOM-S_PA.txt').read().split('\n')
out_path = sys.argv[2] if len(sys.argv) > 2 else 'fantoms_lists.json'

# Performance List: "No. Name" four columns (USER 1-32, 33-64, PRESET 1-32, 33-64).
perf = {'USER': {}, 'PRESET': {}}
i0 = next(i for i, l in enumerate(lines) if l.startswith('USER Group') and 'PRESET Group' in l)
for l in lines[i0 + 2:i0 + 40]:
    found = re.findall(r'(\d{3})\s+(.+?)(?=\s{2,}\d{3}\s|\s*$)', l)
    if len(found) != 4: continue
    for k, (n, name) in enumerate(found):
        perf['USER' if k < 2 else 'PRESET'][int(n)] = name.strip()
for g in perf: assert sorted(perf[g]) == list(range(1, 65)), g

# Patch List (USER .. PR-F): entries "NNN Name Voice Category", up to four per line.
entry = re.compile(r"(\d{3}) (.{1,13}?)\s+(\d{1,2})\s+([A-Z][A-Z.&/\- ]*?[A-Z.])(?=\s{2,}\d{3} |\s*$)")
groups = {}; page = None
for l in lines:
    heads = re.findall(r'(USER|PR-[A-F]) \((?:User|Preset [A-F]) Group', l)
    if heads: page = heads; continue
    if 'GM (GM2 Group)' in l or 'Rhythm Set List' in l: page = None
    if not page: continue
    found = entry.findall(l)
    if not found: continue
    # Each group prints two columns (1-64, 65-128); PR-F has one short column.
    for col, (n, name, voice, cat) in enumerate(found):
        g = page[col // 2] if len(page) > 1 else page[0]
        assert g not in groups or int(n) not in groups[g], (g, n, l)
        groups.setdefault(g, {})[int(n)] = name.rstrip()
long_names = [(g, n, v) for g in groups for n, v in groups[g].items() if len(v) > 12]
print('names longer than 12 characters (pdftotext added a space?):', long_names)
# Spellings confirmed in the Fantom-S 1.09 program's preset Patch records (check_firmware_names.py):
# pdftotext (or the printed list) adds a space in one name and loses a double space in another.
FIRMWARE_SPELLING = {('PR-E', 54): 'FS AlphaRave', ('PR-E', 99): 'OutOf  sortz'}
for (g, n), name in FIRMWARE_SPELLING.items():
    assert groups[g][n].replace(' ', '') == name.replace(' ', ''), (g, n, groups[g][n])
    groups[g][n] = name
presets = {}
for g in ['PR-A', 'PR-B', 'PR-C', 'PR-D', 'PR-E']:
    assert sorted(groups[g]) == list(range(1, 129)), (g, sorted(set(range(1, 129)) - set(groups[g])))
    presets[g] = [groups[g][i] for i in range(1, 129)]
assert sorted(groups['PR-F']) == list(range(1, 9)), groups['PR-F']
assert all(len(v) <= 12 for g in presets for v in presets[g])
presets['PR-F'] = [groups['PR-F'][i] for i in range(1, 9)]
assert sorted(groups['USER']) == list(range(1, 257)) or sorted(groups['USER']) == list(range(1, 129)), len(groups['USER'])

# GM2 Patches: one page, four blocks "No. Name Voice LSB PC"; PC (1-based) printed only on LSB-0 rows.
# Names can end in a digit, so each block's trailing numbers are taken off the right: three when
# the row has a PC, else two. Which rows have a PC is decided by the GM2 standard's order (taken
# from the app's Fantom-X table); the printed LSB and PC are then checked against it.
s = next(i for i, l in enumerate(lines) if l.strip() == 'GM (GM2 Group)')
cols = [m.start() for m in re.finditer(r'No\.', lines[s + 1])]
assert len(cols) == 4
std = [(int(l), int(p)) for l, p in re.findall(r'\((\d+), (\d+), "', open(os.path.join(HERE, '../../SVQKit/Sources/SVQKit/FantomPatchNames.swift')).read())]
assert len(std) == 256
gm2 = {}; printed_mismatch = []
for l in lines[s + 2:s + 70]:
    for k, c in enumerate(cols):
        block = l[max(0, c - 2):(cols[k + 1] - 2 if k + 1 < 4 else len(l))]
        m = re.match(r'\s*(\d{3})\s+(.*?)\s*$', block)
        if not m: continue
        n, rest = int(m.group(1)), m.group(2)
        lsb, pc = std[n - 1]
        has_pc = lsb == 0
        t = re.match(r'(.*?)\s+(\d+)\s+(\d+)' + (r'\s+(\d+)' if has_pc else '') + r'$', rest)
        assert t, (n, rest)
        if int(t.group(3)) != lsb or (has_pc and int(t.group(4)) != pc + 1):
            printed_mismatch.append((n, t.group(1).strip(), 'printed LSB/PC', int(t.group(3)), t.group(4) if has_pc else None, 'GM2 standard', lsb, pc + 1))
        gm2[n] = [lsb, pc, t.group(1).strip()]
assert sorted(gm2) == list(range(1, 257)), len(gm2)
gm2_list = [gm2[n] for n in range(1, 257)]
print('GM2 rows whose printed LSB/PC differ from the GM2 standard:', printed_mismatch)

# Rhythm Set List: kit names head each page's columns ("Note No.  Kit  Kit ...").
kits = {'PRST': [], 'USER': [], 'GM2': []}; group = None
for l in lines:
    if 'PRST (Preset Group)' in l: group = 'PRST'; user_col = l.find('USER (User Group)')
    elif 'GM (GM2 Group)' in l: group = 'GM2'
    m = re.match(r'(\s*Note No\.\s+)(.*)$', l)
    if m and group:
        for km in re.finditer(r'\S+(?: \S+)*', m.group(2)):
            name = km.group(0); x = len(m.group(1)) + km.start()
            kits['USER' if group == 'PRST' and user_col > 0 and x >= user_col - 2 else group].append(name)
assert len(kits['PRST']) == 32 and len(kits['GM2']) == 9, (len(kits['PRST']), kits['GM2'])
json.dump({'performances': {g: [perf[g][i] for i in range(1, 65)] for g in perf},
           'presets': presets, 'gm2': gm2_list,
           'presetRhythmSets': kits['PRST'], 'userRhythmSets30to32': kits['USER'], 'gm2RhythmSets': kits['GM2']},
          open(out_path, 'w'), indent=1)
print({g: len(v) for g, v in presets.items()}, 'GM2', len(gm2_list), 'PRST', len(kits['PRST']), 'USER kits', kits['USER'], 'GM2 kits', kits['GM2'])
