import json, re, glob, os
arch = json.load(open('archive_lists.json'))
scans = json.load(open('scans.json'))
session = json.load(open('session09.json'))

# Board titles from Roland's list pages where available
titles = {}
for f in glob.glob('lists/*_e.html'):
    t = open(f, encoding='latin-1').read()
    m = re.search(r'SR-JV80-(\d\d)\s+([^<\n]+?)\s+Original', t)
    if m: titles[int(m.group(1))] = m.group(2).strip()
titles.update({1: 'Pop', 3: 'Piano', 6: 'Dance', 7: 'Super Sound Set', 9: 'Session',
               15: 'Special FX Collection', 17: 'Country Collection',
               97: 'Experience III', 98: 'Experience II', 99: 'Experience'})

def seq(kind, board):
    banks = arch.get(str(board), {}).get(kind, {})
    return [name for bank in ('A', 'B') for _, name in banks.get(bank, [])]

boards = {}
for b in range(1, 20):
    if str(b) in arch:
        boards[b] = (seq('P', b), seq('R', b), 'Roland SR-JV80 reproduction data lists (SRX-06 to SRX-09 CD-ROM)')
boards[9] = (session['patches'], session['rhythm'], 'Roland JV-1010 Owner’s Manual (Session is built in)')
pop = [scans['POP_P'][str(k)] for k in range(1, 146)]
piano = {int(k): v for k, v in scans['PIANO_P'].items() if int(k) <= 111}
piano[64] = 'BellRhodes 2'
fixes = {8: 'ClasclPiano1', 9: 'ClasclPiano2', 10: 'ClasclPiano3', 21: 'SA Piano 1',
         88: 'Funkee Whirl', 89: 'Morning Mist', 105: 'Velo Clav 1T'}
piano.update(fixes)
boards[1] = (pop, [], 'Roland Pop Expansion Board Patch Listing (1996), proofread against the page image')
boards[3] = ([piano[k] for k in range(1, 112)], [], 'Roland Piano Expansion Board Patch Listing (1996), proofread; typesetting errors fixed')

# 06 Dance: hand transcription of the owner's manual scan (dance06.txt)
dance = {}
for line in open('dance06.txt'):
    m = re.match(r'(\d+) (.+)$', line.rstrip('\n'))
    if m: dance[int(m.group(1))] = m.group(2)
boards[6] = ([dance[k] for k in range(1, 256)], [], 'SR-JV80-06 Owner\u2019s Manual p. 5 (scan), transcribed by hand')

# 07 Super Sound Set: Roland patch listing (scan text), proofread against the page image
sss = {int(k): v for k, v in json.load(open('sss07_raw.json')).items()}
sss.update({46: "'60 CompKlav", 138: 'Bs/Master1', 152: 'Super Fiddle', 248: 'Drum Set 1'})
boards[7] = ([sss[k] for k in range(1, 256)], [], 'Roland Super Sound Set Patch Listing, proofread; typesetting errors fixed')

# 15 Special FX and 17 Country: Roland patch listings (text PDFs)
vc = json.load(open('vc_lists.json'))
fx = {int(k): v for k, v in vc['15'].items()}
# The sheet prints rows 10 and 11 as "1 Fathoms" / "10 Turbine"; by position they are 10 and 11.
fx.update({10: 'Fathoms', 11: 'Turbine', 74: 'Quantum Jump', 203: 'Amb.DrumMenu', 211: 'FuzDrm&HitMn'})
boards[15] = ([fx[k] for k in range(1, 257)], [], 'Roland SR-JV80-15 Patch Listing; two misprinted row numbers fixed by position')
boards[17] = ([vc['17'][str(k)] for k in range(1, 257)], [], 'Roland SR-JV80-17 Country Patch Listing')

# 98 Experience II and 99 Experience: synthmania.com transcriptions
import exp_lists
boards[97] = (exp_lists.patches97, [], 'synthmania.com transcription of the Experience III demo board (two fixes, see exp_lists.py)')
boards[98] = (exp_lists.patches98, [], 'synthmania.com transcription of the Experience II demo board')
boards[99] = (exp_lists.patches99, [], 'synthmania.com transcription of the Experience demo board')

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

parts = []
for b in sorted(boards):
    patches, rhythm, source = boards[b]
    assert all(patches), b
    body = ',\n'.join('            ' + ', '.join(q(n) for n in patches[i:i + 6]) for i in range(0, len(patches), 6))
    rbody = ', '.join(q(n) for n in rhythm)
    parts.append('''        %d: Board(
            title: %s,
            // %s
            patches: [
%s,
            ],
            rhythmSets: [%s]),''' % (b, q(titles[b]), source, body, rbody))
    print('SR-JV80-%02d %-28s patches %3d rhythm sets %d' % (b, titles[b], len(patches), len(rhythm)))

src = '''// Patch and Rhythm Set names of the Roland SR-JV80 Wave Expansion boards, used to name the
// expansion-board patches of XP songs. Sources are noted per board. Boards not listed here have
// no published list available to this project yet.

public enum SRJV80Boards {
    struct Board: Sendable {
        let title: String
        /// Patch names, 1-based patch number - 1 (bank B continues at 129).
        let patches: [String]
        /// Rhythm Set names in order (bank A, then bank B).
        let rhythmSets: [String]
    }

    /// Every SR-JV80 board by number, with its title (names known or not).
    public static let titles: [Int: String] = [
%s
    ]

    static let boards: [Int: Board] = [
%s
    ]
}
''' % ('\n'.join('        %d: %s,' % (b, q(titles[b])) for b in sorted(titles)), '\n'.join(parts))
open('../../SVQKit/Sources/SVQKit/SRJV80Boards.swift', 'w').write(src)
