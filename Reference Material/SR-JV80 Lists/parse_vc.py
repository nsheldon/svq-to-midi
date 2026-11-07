# Parses patch listings laid out as "No. Patch Name Voices Category" columns (SR-JV80-15, -17).
import re, subprocess, json, sys
out = {}
for key, path in [('15', 'SR-JV80-15 EFX_P1.pdf'), ('17', 'SR-JV80-17 cntryp.pdf')]:
    txt = subprocess.run(['pdftotext', '-layout', path, '-'], capture_output=True, text=True).stdout
    names = {}
    for line in txt.split('\n'):
        for m in re.finditer(r'(?:^|\s)(\d{1,3})\s{1,6}(\S.{0,13}?)\s+(\d)\s+([A-Z&]{2,4})\b', line):
            names.setdefault(int(m.group(1)), m.group(2).strip())
    top = max(names)
    print(key, len(names), 'max', top, 'missing', [k for k in range(1, top + 1) if k not in names])
    out[key] = {str(k): v for k, v in sorted(names.items())}
json.dump(out, open('vc_lists.json', 'w'), indent=0)
