import re, json
L = open('jv1010.txt').read().split('\n')
i = L.index('XP-A (Session)')
names = {}
for line in L[i:i+80]:
    for m in re.finditer(r'(\d{3}) {2,4}(.{12}) *(\d)(?= |$)', line):
        names[int(m.group(1))] = m.group(2).strip()
print(len(names), [k for k in range(1, 256) if k not in names][:10], names[52], names[67], names[22], names[146], names[234])
rhythm = ['SessionSet 1', 'SessionSet 2', 'SessionSet 3', 'SessionSet 4', 'SessionSet 5', 'SessionSet 6', 'SessionSet 7', 'Demo Drum']
json.dump({'patches': [names[k] for k in range(1, 256)], 'rhythm': rhythm}, open('session09.json', 'w'))
