import os
import collections, sys
OUT = os.path.join(os.environ['ADBLOCK_SCRATCH'], 'out') + '/'
kzf = sys.argv[1] if len(sys.argv) > 1 else 'dec-kz.txt'
req = [l.rstrip('\n').split('\t') for l in open(OUT + sys.argv[2])]
eng = [l.split('\t')[0].strip() for l in open(OUT + sys.argv[3])]
kz = [l.rstrip('\n').split('\t') for l in open(OUT + kzf)]
br = [l.rstrip('\n').split('\t') for l in open(OUT + sys.argv[4])]
def grp(label):
    if label.startswith('site:'): return 'real sites (static HTML)'
    if label.startswith('toplevel'): return 'top-level $document navigations'
    return label.split(':')[0] + ' patterns' if ':' in label else label
stats = collections.defaultdict(lambda: collections.Counter())
diffs = []
for r, e, k, b in zip(req, eng, kz, br):
    g = grp(r[3])
    stats[g]['n'] += 1
    stats[g]['engine_block'] += e == 'block'
    stats[g]['kz_block'] += k[0] == 'block'
    stats[g]['brave_block'] += b[0] == 'block'
    for name, d in (('kz', k), ('brave', b)):
        if e == 'block' and d[0] == 'allow': stats[g][name + '_miss'] += 1
        if e == 'allow' and d[0] == 'block': stats[g][name + '_over'] += 1
        if e == 'block' and d[0] == 'block': stats[g][name + '_agree_block'] += 1
    if k[0] != b[0]:
        diffs.append((r, e, k, b))
print('| Group | Requests | Engine blocks | Kaizu blocks | Brave blocks | Kaizu missed | Brave missed | Kaizu extra | Brave extra |')
tot = collections.Counter()
for g, s in sorted(stats.items()):
    print(f"| {g} | {s['n']} | {s['engine_block']} | {s['kz_block']} | {s['brave_block']} | {s['kz_miss']} | {s['brave_miss']} | {s['kz_over']} | {s['brave_over']} |")
    tot.update(s)
s = tot
print(f"| **All** | {s['n']} | {s['engine_block']} | {s['kz_block']} | {s['brave_block']} | {s['kz_miss']} | {s['brave_miss']} | {s['kz_over']} | {s['brave_over']} |")
print('decision differences kaizu vs brave:', len(diffs))
import json
with open(OUT + 'diffs-' + sys.argv[2] + '', 'w') as f:
    for r, e, k, b in diffs:
        f.write(f"engine={e} kz={k[0]} brave={b[0]} | {r[2]} {r[0]} top={r[1]} | filter={r[4] if len(r)>4 else ''} | kzrule={k[1] if len(k)>1 else ''} | brrule={b[1] if len(b)>1 else ''}\n")
