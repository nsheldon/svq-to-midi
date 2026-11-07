import re, subprocess, json
txt = subprocess.run(['pdftotext', '-layout', 'SR-JV80-07 SOUND_P.pdf', '-'], capture_output=True, text=True).stdout
names = {}
for line in txt.split('\n'):
    for m in re.finditer(r'(\d{3})\s+(\S.*?)(?=\s{2,}\d{3}\s|\s*$)', line):
        n = int(m.group(1))
        if n < 400: names.setdefault(n, m.group(2).strip())
print(len(names), max(names), [k for k in range(1, max(names) + 1) if k not in names])
json.dump({str(k): v for k, v in sorted(names.items())}, open('sss07_raw.json', 'w'), indent=0)
