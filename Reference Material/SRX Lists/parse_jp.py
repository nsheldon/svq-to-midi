"""Read Roland Japan's SRX text lists and cross-check the owner's-manual lists.

Input: dl/SRXINSTLIST/srx-NN.txt from Roland Japan's SRXINSTLIST.zip
(https://static.roland.com/jp/media/zip/SRXINSTLIST.zip, 2010; Shift-JIS, CR line endings; not
committed). Each file lists the patches (and rhythm sets) per group of host instruments; the first
group is the Fantom/XV one (for SRX-12, the Fantom-X/Fantom-S/Juno-G one).

- Compares SRX-01 to SRX-12 with srx_lists.json (from the owner's manuals) and reports differences.
- Writes jp_lists.json (SRX-01 to SRX-12), which gen_srx.py uses for exact spacing: pdftotext
  collapses the double spaces that pad some 12-character names ("Kick 1  Menu").
- Writes special_lists.json with SRX-99, which has no owner's manual online.
"""
import json, re, sys


def read(board):
    raw = open(f'dl/SRXINSTLIST/srx-{board:02d}.txt', 'rb').read().decode('cp932')
    lines = raw.replace('\r\n', '\n').replace('\r', '\n').split('\n')
    lists = {'patch': {}, 'rhythm': {}}
    lsbs = {'patch': [], 'rhythm': []}
    section, group = None, 0
    for line in lines:
        if re.match(r'Patch\b', line):
            section, group = 'patch', 0
        elif re.match(r'Rhythm', line):
            section, group = 'rhythm', 0
        elif line.startswith('For ') and section:
            group += 1
        elif section and group <= 1:
            m = re.match(r'Bank Sel LSB[^:]*:\s*(\d+)', line)
            if m:
                lsbs[section].append(int(m.group(1)))
                continue
            fields = [f for f in line.split('\t') if f.strip()]
            if len(fields) >= 3 and fields[0].strip().isdigit() and fields[1].strip().isdigit():
                number, name = int(fields[1]), fields[2].rstrip()
                if number in lists[section]:
                    sys.exit(f'SRX-{board:02d}: {section} {number} twice')
                lists[section][number] = name
    out = {}
    for section in ('patch', 'rhythm'):
        found = lists[section]
        if found and sorted(found) != list(range(1, len(found) + 1)):
            sys.exit(f'SRX-{board:02d}: {section} numbers not 1-{len(found)}')
        out[section] = [found[n] for n in range(1, len(found) + 1)]
        out[section + 'LSBs'] = list(dict.fromkeys(lsbs[section]))
    return out


manual = json.load(open('srx_lists.json'))
json.dump({board: {'patches': (l := read(board))['patch'], 'rhythmSets': l['rhythm']} for board in range(1, 13)},
          open('jp_lists.json', 'w'), indent=1, ensure_ascii=False)
differences = 0
for board in range(1, 13):
    jp, m = read(board), manual[str(board)]
    for kind, key in (('patch', 'patches'), ('rhythm', 'rhythmSets')):
        a, b = m[key], jp[kind]
        if len(a) != len(b):
            print(f'SRX-{board:02d} {key}: manual {len(a)}, Roland Japan list {len(b)}')
            differences += 1
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y.replace('’', "'"):
                print(f'SRX-{board:02d} {key} {i + 1}: manual {x!r}, Roland Japan list {y!r}')
                differences += 1
    if jp['patchLSBs'] != m['patchLSBs'] or (m['rhythmLSB'] is not None and jp['rhythmLSBs'][:1] != [m['rhythmLSB']]):
        print(f'SRX-{board:02d} LSBs: manual {m["patchLSBs"]}/{m["rhythmLSB"]}, Roland Japan list {jp["patchLSBs"]}/{jp["rhythmLSBs"]}')
        differences += 1
print('differences:', differences)

srx99 = read(99)
assert srx99['patchLSBs'] == [105] and len(srx99['patch']) == 64 and not srx99['rhythm']
json.dump({99: {'patches': srx99['patch'], 'rhythmSets': [], 'patchLSBs': [105], 'rhythmLSB': None,
                'source': 'Roland Japan SRX list (SRXINSTLIST.zip, srx-99.txt), list for the Fantom series'}},
          open('special_lists.json', 'w'), indent=1, ensure_ascii=False)
print('SRX-99:', len(srx99['patch']), 'patches, LSB 105')
