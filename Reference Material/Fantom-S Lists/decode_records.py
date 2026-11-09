"""Decode the PRFa, PATa and RHYa records of Fantom-S songs with the Fantom-S map (fs_map.json)
and the packing the app uses for the Fantom-X (docs/SVQ-Format.md: MSB first, mask widths,
sections byte-aligned, multi-nibble values combined, narrow 64-centred values re-centred; PRFa
section order Common, MFX1-3, Chorus, Reverb, MIDI x16, Part x16 (2 lead bits, Decay Time Offset
last), Zone x16, Controller; PATa +1 byte before Tone 1). Counts values outside the map's ranges.
    python3 -I decode_records.py <song.SVQ> ...
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_stpa import blocks, header, width, rng, centered, name
HERE = os.path.dirname(os.path.abspath(__file__))
MAP = json.load(open(os.path.join(HERE, 'fs_map.json')))
def params(s): return [p for p in MAP[s] if 'off' in p]
class Reader:
    def __init__(s, rec): s.b = ''.join(format(x, '08b') for x in rec); s.p = 0
    def align(s): s.p = (s.p + 7) // 8 * 8
    def read(s, ps, label, out):
        for p in ps:
            w = width(p)
            if w == 0: continue   # '(reserve)' rows with an all-zero mask take no bits
            raw = int(s.b[s.p:s.p + w], 2); s.p += w
            v = raw - (1 << (w - 1)) + 64 if centered(p) else raw
            r = rng(p)
            out.append((label, p, v, r is None or r[0] <= v <= r[1]))
def prf(rec):
    out = []; rd = Reader(rec)
    rd.read(params('Performance Common'), 'Common', out); rd.p = 48 * 8
    for i in range(3): rd.p = (48 + 78 * i) * 8; rd.read(params('Performance Common MFX'), f'MFX{i+1}', out)
    rd.p = 282 * 8; rd.read(params('Performance Common Chorus'), 'Chorus', out)
    rd.p = 324 * 8; rd.read(params('Performance Common Reverb'), 'Reverb', out)
    for i in range(16): rd.p = (366 + 2 * i) * 8; rd.read(params('Performance MIDI'), f'MIDI{i+1}', out)
    part = params('Performance Part'); part = [p for p in part if p['off'] != 0x21] + [p for p in part if p['off'] == 0x21]
    for i in range(16): rd.p = 3184 + 288 * i + 2; rd.read(part, f'Part{i+1}', out)
    for i in range(16): rd.p = (974 + 11 * i) * 8; rd.read(params('Performance Zone'), f'Zone{i+1}', out)
    rd.p = 1150 * 8; rd.read(params('Performance Controller'), 'Controller', out)
    return out, rd
def pat(rec):
    out = []; rd = Reader(rec)
    for s in ['Patch Common', 'Patch Common MFX', 'Patch Common Chorus', 'Patch Common Reverb', 'Patch TMT (Tone Mix Table)']:
        rd.align(); rd.read(params(s), s, out)
    rd.align(); rd.p += 8
    for t in range(4): rd.align(); rd.read(params('Patch Tone'), f'Tone{t+1}', out)
    return out, rd
def rhy(rec):
    out = []; rd = Reader(rec)
    for s in ['Rhythm Common', 'Rhythm Common MFX', 'Rhythm Common Chorus', 'Rhythm Common Reverb']:
        rd.align(); rd.read(params(s), s, out)
    for k in range(88): rd.align(); rd.read(params('Rhythm Tone'), f'Key{21+k}', out)
    return out, rd
def text(vals, n=12): return ''.join(chr(v) for _, _, v, _ in vals[:n])
if __name__ == '__main__':
    tot = bad = 0
    for path in sys.argv[1:]:
        b = blocks(open(path, 'rb').read())
        print('==', os.path.basename(path))
        for tag, fn in [('PRFa', prf), ('PATa', pat), ('RHYa', rhy)]:
            blk = b[tag]; n, size, h, _ = header(blk)
            for i in range(n):
                rec = blk[h + i * size:h + (i + 1) * size]
                if not any(rec): continue
                vals, rd = fn(rec)
                nb = [(l, name(p), v, rng(p)) for l, p, v, ok in vals if not ok]
                tot += len(vals); bad += len(nb)
                print(f'  {tag}[{i+1}] {text(vals)!r} params {len(vals)} end bit {rd.p} of {8*size}; out of range {len(nb)}', nb[:6] if nb else '')
    print('decoded values', tot, 'out of range', bad)
