import re, json, subprocess, sys
out = {}
for name in ['POP_P', 'PIANO_P']:
    txt = subprocess.run(['pdftotext', '-layout', name + '.pdf', '-'], capture_output=True, text=True).stdout
    entries = {}
    for line in txt.split('\n'):
        for m in re.finditer(r'(\d{3})\s+(\S.*?)(?=\s{2,}\d{3}\s|\s*$)', line):
            entries.setdefault(int(m.group(1)), m.group(2).strip())
    nums = sorted(entries)
    print(name, len(entries), 'range', nums[0], nums[-1], 'missing', [k for k in range(1, nums[-1] + 1) if k not in entries])
    out[name] = {str(k): v for k, v in sorted(entries.items())}
    print('  tail lines:', [l.strip() for l in txt.split('\n') if l.strip()][-4:])
json.dump(out, open('scans.json', 'w'), indent=0)
