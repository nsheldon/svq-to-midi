"""Decode the STPa (Setup) record of Fantom-S songs with the Fantom-S Setup layout (fs_map.json):
address order, MSB first, mask widths, no section padding, narrow 64-centred values stored
re-centred (stored = value - 64 + 2^(bits-1)). Prints every value, flags values outside the map's
range, and shows the bits left after the layout.
    python3 -I decode_stpa.py <song.SVQ> ...
"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
MAP = json.load(open(os.path.join(HERE, 'fs_map.json')))
def blocks(d):
    i = d.find(b'SVD1'); base = i - 2
    hl = int.from_bytes(d[base:base + 2], 'big'); p = i + 14; out = {}
    while p + 16 <= base + 2 + hl:
        tag = d[p:p + 4].decode('latin1'); off = int.from_bytes(d[p + 8:p + 12], 'big'); ln = int.from_bytes(d[p + 12:p + 16], 'big')
        if tag.strip('\0'): out[tag] = d[base + off:base + off + ln]
        p += 16
    return out
def header(b): return [int.from_bytes(b[o:o + 4], 'big') for o in (0, 4, 8, 12)]
def width(p): return sum(c.count('a') + c.count('b') + c.count('c') + c.count('d') for c in p['masks'])
def rng(p):
    m = re.search(r'\((-?\d+)\s*-\s*(-?\d+)\)', p['name']); return (int(m.group(1)), int(m.group(2))) if m else None
def centered(p):
    w, r = width(p), rng(p); return bool(r and w < 7 and r[1] >= (1 << w) and r[0] <= 64 <= r[1])
def name(p): return re.sub(r'\s*\(-?\d+\s*-\s*-?\d+\).*$', '', p['name']).strip()
params = [p for p in MAP['Setup'] if 'off' in p]
# Rows the PDF text breaks across lines lose their range; fill them from the printed page.
fix = {0x21: (0, 1), 0x22: (0, 1)}
if __name__ == '__main__':
    total_bad = 0
    for path in sys.argv[1:]:
        b = blocks(open(path, 'rb').read())
        st = b['STPa']; n, size, h, _ = header(st); rec = st[h:h + size]
        bits = ''.join(format(x, '08b') for x in rec); pos = 0; vals = []
        for p in params:
            w = width(p); raw = int(bits[pos:pos + w], 2); pos += w
            v = raw - (1 << (w - 1)) + 64 if centered(p) else raw
            r = rng(p) or fix.get(p['off']); ok = r is None or r[0] <= v <= r[1]
            total_bad += not ok
            vals.append(f'{p["off"]:02X} {name(p)}={v}' + ('' if ok else f' OUT OF RANGE {r}'))
        print(f'== {os.path.basename(path)}: blocks {list(b)}; STPa header {header(st)}; layout {pos} bits of {8 * size}')
        print('   ' + '; '.join(vals))
        print(f'   remaining {8 * size - pos} bits: {bits[pos:]}')
        if 'MSEa' in b: print(f'   MSEa header {header(b["MSEa"])} data {b["MSEa"][16:].hex(" ")}')
    print('values out of range:', total_bad)
