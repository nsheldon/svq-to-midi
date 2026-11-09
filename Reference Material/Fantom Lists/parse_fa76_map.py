"""Parse the Parameter Address Map of the Fantom (FA-76) MIDI Implementation into fa76_map.json.
Each page holds two columns of tables; the page is cut at its column split and read left column
first. Prints each section with its parameter count, SysEx bytes and the manual's Total Size
(7-bit address arithmetic: 0x111 = 145). Run: python3 parse_fa76_map.py
"""
import re, json, collections, sys
txt = open(sys.argv[1] if len(sys.argv) > 1 else 'dl/FANTOM_MI.txt').read()
start = txt.find('5. Parameter Address Map'); end = txt.find('6. Supplementary', start)
pages = txt[start:end if end > 0 else len(txt)].split('\f')
row = re.compile(r'^\|\s*(#?)\s*([0-9A-F]{2} [0-9A-F]{2})\s*\|\s*([0a-z]{4} [0a-z]{4})\s*\|\s*(.*?)\s*\|?\s*$')
cont = re.compile(r'^\|\s*\|\s*([0a-z]{4} [0a-z]{4})\s*\|\s*(.*?)\s*\|?\s*$')
total = re.compile(r'\|\s*([0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2})\s*\|\s*Total Size')
def split_at(page):
    lines = page.split('\n')
    hist = collections.Counter()
    for l in lines:
        for i in range(60, min(len(l), 140)):
            if l[i] in '|+❍' and l[i-1] == ' ' and l[i-2] == ' ':
                hist[i] += 1; break
    return hist.most_common(1)[0][0] if hist else None
stream = []
for page in pages:
    lines = page.split('\n'); x = split_at(page)
    left = [l[:x] if x else l for l in lines]; right = [l[x:] if x else '' for l in lines]
    stream += [l.strip() for l in left] + [l.strip() for l in right]
sections = {}; order = []; cur = None
for line in stream:
    m = re.match(r'❍\s*(.+?)\s*$', line)
    if m and '|' not in line:
        cur = m.group(1); sections.setdefault(cur, []); order.append(cur) if cur not in order else None; continue
    if cur is None: continue
    m = row.match(line)
    if m:
        sections[cur].append({'off': int(m.group(2).replace(' ', ''), 16), 'multi': bool(m.group(1)), 'masks': [m.group(3)], 'name': m.group(4)}); continue
    m = cont.match(line)
    if m and sections[cur] and 'masks' in sections[cur][-1]:
        sections[cur][-1]['masks'].append(m.group(1))
        if m.group(2) and not re.search(r'\(\s*-?\d', sections[cur][-1]['name']):
            sections[cur][-1]['name'] += ' ' + m.group(2)
        continue
    m = total.search(line)
    if m: sections[cur].append({'total': int(m.group(1).replace(' ', ''), 16)})
def width(p): return sum(c.count('a') + c.count('b') + c.count('c') + c.count('d') for c in p['masks'])
for s in order:
    ps = [p for p in sections[s] if 'off' in p]; t = [p['total'] for p in sections[s] if 'total' in p]
    sysex = sum(len(p['masks']) for p in ps)
    ok = 'OK' if t and (t[0] >> 8) * 128 + (t[0] & 0xFF) == sysex else ''
    print(f'{s:36s} params {len(ps):3d} sysex {sysex:4d} total {[hex(v) for v in t]} bits {sum(width(p) for p in ps)} {ok}')
json.dump({s: sections[s] for s in order}, open(sys.argv[2] if len(sys.argv) > 2 else 'fa76_map.json', 'w'), indent=1)
