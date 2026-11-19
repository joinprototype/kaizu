import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'genurls.py')).read())

# ---- adversarial set: lookalike hosts, mid-pattern separators, $document hosts hit by subresources
rows2 = []
lines = []
for p in ('easylist.txt', 'easyprivacy.txt'):
    lines += [l.strip() for l in open(R + p, encoding='utf-8', errors='replace')]
plain = [l for l in lines if re.fullmatch(r'\|\|[a-z0-9.-]+\^', l)]
for l in random.sample(plain, 150):
    host = l[2:-1]
    rows2.append(('https://' + host + 'x.test/a.js', 'https://www.example-news.test/', 'script', 'lookalike-suffix', l))
for l in random.sample(plain, 100):
    host = l[2:-1]
    rows2.append(('https://' + host + '.evil.test/a.js', 'https://www.example-news.test/', 'script', 'lookalike-dotted', l))
mid = []
for l in lines:
    if l.startswith('@@') or '#' in l or not l:
        continue
    b = l.split('$')[0]
    if '^' in b.rstrip('^') and not b.startswith('/'):
        g = gen(l)
        if g:
            mid.append((l, g))
for l, g in random.sample(mid, min(120, len(mid))):
    rows2.append((*g, 'mid-separator', l))
doc = [l for l in lines if l.startswith('||') and l.endswith('^$document')]
for l in random.sample(doc, min(40, len(doc))):
    host = l[2:].split('^')[0]
    rows2.append(('https://' + host + '/lib.js', 'https://www.example-news.test/', 'script', 'document-option-subresource', l))
with open(OUT + 'requests2.tsv', 'w') as f:
    for r in rows2:
        f.write('\t'.join(r) + '\n')
print('adversarial', len(rows2), len(mid), len(plain), len(doc))
