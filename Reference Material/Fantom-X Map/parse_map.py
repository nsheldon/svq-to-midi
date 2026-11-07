import re,json
txt=open('dl/fx678_imp.txt').read()
start=txt.find('5. Parameter Address Map')
end=txt.find('6. Supplementary', start)
if end<0: end=len(txt)
pages=txt[start:end].split('\f')
row=re.compile(r'^\|\s*(#?)\s*([0-9A-F]{2})\s+([0-9A-F]{2})\s*\|\s*([0a-z]{4} [0a-z]{4})\s*\|\s*(.*?)\s*\|\s*$')
cont=re.compile(r'^\|\s*\|\s*([0a-z]{4} [0a-z]{4})\s*\|\s*(.*?)\s*\|\s*$')
hdr=re.compile(r'❍\s*(.+?)\s*$')
total=re.compile(r'\|\s*([0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2})\s*\|\s*Total Size')
sections={}; order=[]; cur=None
def colsplit(line):
    # find the start of the right-hand table: a '|' or '+' or '❍' at col>=85
    for i in range(85,min(len(line),110)):
        if line[i] in '|+❍': return line[:i].rstrip(), line[i:].rstrip()
    return line.rstrip(), ''
for pg in pages:
    L=[];R=[]
    for line in pg.split('\n'):
        a,b=colsplit(line); L.append(a.strip()); R.append(b.strip())
    for line in L+R:
        m=hdr.search(line)
        if m and '|' not in line:
            cur=m.group(1); 
            if cur not in sections: sections[cur]=[]; order.append(cur)
            continue
        if cur is None: continue
        m=row.match(line)
        if m:
            mask=m.group(4); name=m.group(5)
            sections[cur].append({'off':int(m.group(2)+m.group(3),16),'multi':bool(m.group(1)),'masks':[mask],'name':name})
            continue
        m=cont.match(line)
        if m and sections[cur]:
            sections[cur][-1]['masks'].append(m.group(1))
            if m.group(2) and not sections[cur][-1]['name']: sections[cur][-1]['name']=m.group(2)
            continue
        m=total.search(line)
        if m: sections[cur].append({'total':int(m.group(1).replace(' ',''),16)})
for s in order:
    p=[x for x in sections[s] if 'off' in x]
    t=[x['total'] for x in sections[s] if 'total' in x]
    bits=sum(sum(c.count('a')+c.count('b')+c.count('c')+c.count('d') for c in x['masks']) for x in p)
    print('%-34s params %3d  total %s  bits %d'%(s,len(p),[hex(v) for v in t],bits))
json.dump({s:sections[s] for s in order},open('map678.json','w'),indent=1)
