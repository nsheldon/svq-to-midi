"""Extract the Fantom-series Patch and Rhythm Set lists from Roland's SRX owner's manuals.

Input: dl/SRX-NN_OM.txt, made with `pdftotext -layout` from Roland's owner's manuals
(https://static.roland.com/assets/media/pdf/SRX-NN_OM.pdf; the PDFs are not committed).
Output: srx_lists.json  {board: {"patches": [...], "rhythmSets": [...], "patchLSBs": [...], "rhythmLSB": n}}

Many manuals print separate lists for the "Fantom series/XV series" and for the RD series/MC-909;
the line ranges below select the list the Fantom-X uses (for SRX-12, the list printed specifically
"For Fantom-X series/Fantom-S series/JUNO-G").
"""
import json, re, sys

# board: (patch line range, rhythm line range or None, max column for patch, max column for rhythm,
#         expected patch count, expected rhythm count)
SPECS = {
    1:  ((690, 716), (416, 454), None, None, 41, 79),
    2:  ((402, 457), None, None, None, 50, 0),
    3:  ((422, 525), (527, 552), None, 48, 128, None),
    4:  ((413, 555), None, None, None, 128, 0),
    5:  ((427, 574), (575, 598), None, None, 312, 34),
    6:  ((425, 631), (823, 837), None, None, 449, 5),
    7:  ((430, 643), (857, 875), None, None, 475, 11),
    8:  ((452, 656), (845, 862), None, None, 448, 21),
    9:  ((428, 628), (809, 827), None, None, 414, 12),
    10: ((469, 530), None, None, None, 100, 0),
    11: ((464, 535), None, 68, None, 42, 0),
    12: ((454, 493), None, None, None, None, 0),
    98: ((236, 276), None, None, None, 78, 0),
}

# Patch entry: number, name (up to 12 characters, may contain single or double spaces),
# an optional tempo such as (90), voices, category (upper case, e.g. AC.PIANO, BEAT&GROOVE, OTHER SYNTH).
CATEGORIES = ['AC.BRASS', 'AC.GUITAR', 'AC.PIANO', 'ACCORDION', 'BASS', 'BEAT&GROOVE', 'BELL', 'BRIGHT PAD',
              'COMBINATION', 'DIST.GUITAR', 'DRUMS', 'EL.GUITAR', 'EL.PIANO', 'ETHNIC', 'FLUTE', 'FRETTED',
              'HARD LEAD', 'HARMONICA', 'HIT&STAB', 'KEYBOARDS', 'MALLET', 'ORCHESTRA', 'ORGAN', 'OTHER SYNTH',
              'PERCUSSION', 'PLUCKED', 'PULSATING', 'SAX', 'SOFT LEAD', 'SOFT PAD', 'SOUND FX', 'STRINGS',
              'SYNTH BASS', 'SYNTH BRASS', 'SYNTH FX', 'TECHNO SYNTH', 'VOX', 'WIND']
PATCH = re.compile(r'(?<!\S)(\d{1,3})\s+(\S.{0,11}?)\s+(?:\(\d+\)\s+)?(\d{1,2})(?: \(\d\))?\s+('
                   + '|'.join(re.escape(c) for c in CATEGORIES) + r')(?=\s|$)')
# Rhythm entry: number, then a name of words separated by single spaces.
RHYTHM = re.compile(r'(?<!\S)(\d{1,3}) +(\S+(?: \S+)*)')


def lines(board, span, maxcol):
    text = open(f'dl/SRX-{board:02d}_OM.txt', encoding='utf-8').read().split('\n')
    for line in text[span[0] - 1:span[1]]:
        yield line[:maxcol] if maxcol else line


def extract(board, span, maxcol, pattern):
    found = {}
    for line in lines(board, span, maxcol):
        if 'BANK SELECT' in line or 'ページ' in line:
            continue
        for m in pattern.finditer(line):
            number, name = int(m.group(1)), m.group(2).strip()
            if pattern is RHYTHM and (name.startswith('<') or name.startswith('No')):
                continue
            if number in found and found[number] != name:
                sys.exit(f'SRX-{board:02d}: number {number} twice: {found[number]!r} / {name!r}')
            found[number] = name
    return found


def ordered(board, found, expected, kind):
    count = max(found) if found else 0
    missing = [n for n in range(1, count + 1) if n not in found]
    if missing:
        sys.exit(f'SRX-{board:02d} {kind}: missing numbers {missing}')
    if expected is not None and count != expected:
        sys.exit(f'SRX-{board:02d} {kind}: {count} entries, expected {expected}')
    names = [found[n].replace('’', "'") for n in range(1, count + 1)]
    long = [n for n in names if len(n) > 12]
    if long:
        sys.exit(f'SRX-{board:02d} {kind}: names longer than 12 characters: {long}')
    return names


def bank_lsbs(board):
    """Patch bank LSBs (one per 128 patches) and the rhythm LSB, from the manual's headings."""
    text = open(f'dl/SRX-{board:02d}_OM.txt', encoding='utf-8').read()
    patch = [int(x) for x in dict.fromkeys(re.findall(r'LSB\s*[:;]\s*(\d+)', re.search(r'MSB\s*:\s*93[^\n]*', text).group(0)))]
    rhythm = re.search(r'MSB\s*:\s*92\s*[;,]\s*LSB\s*:\s*(\d+)', text)
    return patch, int(rhythm.group(1)) if rhythm else None


out = {}
for board, (pspan, rspan, pcol, rcol, pcount, rcount) in SPECS.items():
    patches = ordered(board, extract(board, pspan, pcol, PATCH), pcount, 'patches')
    rhythms = ordered(board, extract(board, rspan, rcol, RHYTHM), rcount, 'rhythm sets') if rspan else []
    plsbs, rlsb = bank_lsbs(board)
    if len(plsbs) != (len(patches) + 127) // 128:
        sys.exit(f'SRX-{board:02d}: {len(plsbs)} patch LSBs for {len(patches)} patches')
    out[board] = {'patches': patches, 'rhythmSets': rhythms, 'patchLSBs': plsbs, 'rhythmLSB': rlsb}
    print(f'SRX-{board:02d}: {len(patches)} patches (LSB {plsbs}), {len(rhythms)} rhythm sets (LSB {rlsb})')

json.dump(out, open('srx_lists.json', 'w'), indent=1, ensure_ascii=False)
