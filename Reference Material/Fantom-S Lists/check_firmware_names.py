"""Check fantoms_lists.json against the preset data inside the Fantom-S 1.09 system program
(FANS.PRG from fans.bin, LZSS-decompressed as described in docs/SVQ-Format.md, "Format versions and
firmware"; Roland's program, not committed). Preset Patches are stored as 664-byte records whose
name is twelve 7-bit characters packed MSB first (the PATa layout), each group as 128 consecutive
records; preset Rhythm Sets as 10928-byte RHYa-layout records; GM2 names as plain 12-character text.
    python3 -I check_firmware_names.py <decompressed FANS.PRG>
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
L = json.load(open(os.path.join(HERE, 'fantoms_lists.json')))
d = open(sys.argv[1], 'rb').read()
def pack(n):
    b = ''.join(format(ord(c), '07b') for c in n.ljust(12)); return bytes(int(b[i:i + 8], 2) for i in range(0, 80, 8))
def unpack(b):
    s = ''.join(format(x, '08b') for x in b[:11]); return ''.join(chr(int(s[i:i + 7], 2)) for i in range(0, 84, 7)).rstrip()
def best_run(first, stride, names):
    best = (0, None, None); i = -1
    while True:
        i = d.find(pack(first), i + 1)
        if i < 0: return best
        got = [unpack(d[i + stride * k:i + stride * k + 11]) for k in range(len(names))]
        m = sum(a == b for a, b in zip(names, got))
        if m > best[0]: best = (m, i, got)
for g, names in L['presets'].items():
    m, at, got = best_run(names[0], 664, names)
    print(f'{g}: {m}/{len(names)} match at {at:#x}' if at is not None else f'{g}: not found',
          [(k + 1, a, b) for k, (a, b) in enumerate(zip(names, got or [])) if a != b])
m, at, got = best_run(L['presetRhythmSets'][0], 10928, L['presetRhythmSets'])
print(f'PRST rhythm sets: {m}/32 match at {at:#x}', [(k + 1, a, b) for k, (a, b) in enumerate(zip(L['presetRhythmSets'], got)) if a != b])
miss = [n for _, _, n in L['gm2'] if d.find(n.ljust(12).encode()) < 0]
print('GM2 Patch names found as 12-character text:', 256 - len(miss), 'missing', miss)
miss = [n for n in L['gm2RhythmSets'] if d.find(n.ljust(12).encode()) < 0]
print('GM2 Rhythm Set names found:', 9 - len(miss), 'missing', miss)
