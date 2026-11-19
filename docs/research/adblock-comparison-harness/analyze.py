import os
import sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from categorize import category, load

OUT = os.path.join(os.environ['ADBLOCK_SCRATCH'], 'out') + '/'
prefix = sys.argv[1] if len(sys.argv) > 1 else 'kz'
lists = ['easylist', 'easyprivacy', 'cookies', 'kaizu']
tot = collections.Counter()
bskip = collections.defaultdict(collections.Counter)  # cat -> list -> n
kskip = collections.defaultdict(collections.Counter)
only_b = collections.defaultdict(list)  # brave ok, kaizu skip
only_k = collections.defaultdict(list)  # kaizu ok, brave skip
for l in lists:
    b = load(OUT + f'brave-{l}-lines.tsv')
    k = load(OUT + f'{prefix}-{l}-lines.tsv')
    bi = {}
    # join by line text (counts may differ by edge cases)
    kd = collections.defaultdict(list)
    for r in k:
        kd[r[3]].append(r)
    for r in b:
        line = r[3]
        tot[l] += 1
        kr = kd.get(line)
        kr = kr.pop(0) if kr else None
        b_ok = r[1] == 'ok'
        k_ok = kr is not None and kr[1] != 'skip'
        c = category(line)
        if not b_ok:
            bskip[c][l] += 1
        if kr is not None and kr[1] == 'skip':
            kskip[c][l] += 1
        if b_ok and not k_ok:
            only_b[c].append(line)
        if k_ok and not b_ok:
            only_k[c].append(line)

def table(d, title):
    print('###', title)
    cats = sorted(d, key=lambda c: -sum(d[c].values()))
    print('| Category | ' + ' | '.join(lists) + ' | Total |')
    for c in cats:
        print(f'| {c} | ' + ' | '.join(str(d[c][l]) for l in lists) + f' | {sum(d[c].values())} |')
    print('| **All** | ' + ' | '.join(str(sum(d[c][l] for c in d)) for l in lists) + f' | {sum(sum(v.values()) for v in d.values())} |')

print('lines per list', dict(tot))
table(bskip, 'Brave skipped')
table(kskip, 'Kaizu skipped')
print('### Brave converts, Kaizu skips')
for c in sorted(only_b, key=lambda c: -len(only_b[c])):
    print(len(only_b[c]), c, '|', only_b[c][:3])
print('### Kaizu converts, Brave skips')
for c in sorted(only_k, key=lambda c: -len(only_k[c])):
    print(len(only_k[c]), c, '|', only_k[c][:3])
