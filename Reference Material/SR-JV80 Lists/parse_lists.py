# Parses lists/*.html (Roland's SR-JV80 data lists) into archive_lists.json.
import re, glob, os, json, html
out = {}
for f in sorted(glob.glob('lists/*.html')):
    t = open(f, encoding='latin-1').read()
    entries = []
    for r in re.findall(r'<TR[^>]*>(.*?)</TR>', t, re.S | re.I):
        cells = [html.unescape(re.sub(r'<[^>]*>', '', c)).strip() for c in re.findall(r'<TD[^>]*>(.*?)</TD>', r, re.S | re.I)]
        if cells and re.fullmatch(r'\d{3}', cells[0]):
            entries.append((int(cells[0]), cells[1]))
    m = re.match(r'SRJV(\d\d)(P|R)(A|B)?_e', os.path.basename(f))
    out.setdefault(int(m.group(1)), {}).setdefault(m.group(2), {})[m.group(3) or 'A'] = entries
json.dump(out, open('archive_lists.json', 'w'))
