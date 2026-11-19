import os
"""Generate request URLs from the lists' own network filters plus controls.
Output TSV: url, top-level URL, abp type, label."""
import random, re, sys, glob

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../Resources/Filters/')
OUT = os.path.join(os.environ['ADBLOCK_SCRATCH'], 'out') + '/'
random.seed(20261118)

TYPES = {'script': 'script', 'image': 'image', 'stylesheet': 'stylesheet', 'css': 'stylesheet', 'font': 'font',
         'media': 'media', 'xmlhttprequest': 'xmlhttprequest', 'xhr': 'xmlhttprequest', 'subdocument': 'subdocument',
         'ping': 'ping', 'websocket': 'websocket', 'other': 'other'}

def gen(line):
    ex = line.startswith('@@')
    body = line[2:] if ex else line
    opts = []
    j = body.rfind('$')
    if j >= 0 and re.fullmatch(r'[~\w-]+(=[^,]*)?(,[~\w-]+(=[^,]*)?)*', body[j+1:] or '#'):
        opts = body[j+1:].split(',')
        body = body[:j]
    names = {o.split('=')[0].lstrip('~').lower() for o in opts}
    if names & {'popup', 'redirect', 'redirect-rule', 'csp', 'removeparam', 'badfilter', 'generichide', 'document', 'doc',
                'elemhide', 'specifichide', 'rewrite', 'replace', 'denyallow', 'to', 'method', 'header', 'permissions',
                'all', 'empty', 'mp4', 'cname', 'inline-script', 'object', 'important'} - {'important'}:
        return None
    if not body or body.startswith('/') and body.endswith('/') and len(body) > 2:
        return None
    if '|' in body.strip('|') or not body.isascii():
        return None
    typ = None
    for o in opts:
        if o.lower() in TYPES:
            typ = TYPES[o.lower()]
    third = 'third-party' in opts or '3p' in opts
    first = '~third-party' in opts or '1p' in opts
    dom = [o.split('=', 1)[1] for o in opts if o.startswith('domain=')]
    top = None
    if dom:
        inc = [d for d in dom[0].split('|') if not d.startswith('~') and '.' in d]
        if inc and '/' not in inc[0] and '*' not in inc[0]:
            top = 'https://www.' + inc[0] + '/'
        elif not inc:
            top = 'https://www.example-news.test/'
    b = body
    if b.startswith('||'):
        host_path = b[2:]
        host_path = host_path.replace('^', '/').replace('*', 'x1')
        if host_path.endswith('/') is False and '/' not in host_path:
            host_path += '/'
        if not host_path[0].isalnum():
            return None
        url = 'https://' + ('cdn.' if random.random() < 0.3 and '/' in host_path else '') + host_path
        if '?' not in url and url.count('/') == 3 and url.endswith('/') is False:
            pass
        host = url.split('/')[2]
    elif b.startswith('|http'):
        url = b[1:].replace('^', '/').replace('*', 'x1')
        host = url.split('/')[2] if url.count('/') >= 2 else 'x.test'
    else:
        p = b.lstrip('*').replace('^', '/').replace('*', 'x1').strip('|')
        if not p:
            return None
        if p.startswith('http'):
            url = p
        elif p.startswith('/'):
            url = 'https://static.adserver-cdn.test' + p
        elif p.startswith('.') or p.startswith('-') or p.startswith('_') or p[0].isalnum():
            url = 'https://static.adserver-cdn.test/assets/' + p
        else:
            return None
        host = url.split('/')[2] if url.count('/') >= 2 else ''
    if top is None:
        if first and not third:
            top = 'https://' + host + '/'
        else:
            top = 'https://www.example-news.test/'
    if typ is None:
        m = re.search(r'\.(js|css|png|gif|jpg|jpeg|svg|woff2?|mp4|swf|php|html?)(\?|$|\|)', url)
        typ = {'js': 'script', 'css': 'stylesheet', 'png': 'image', 'gif': 'image', 'jpg': 'image', 'jpeg': 'image',
               'svg': 'image', 'woff': 'font', 'woff2': 'font', 'mp4': 'media'}.get(m.group(1) if m else '', 'script')
    if ' ' in url or len(url) > 300:
        return None
    return (url, top, typ)

rows = []
def sample(path, n_block, n_exc, label):
    lines = [l.strip() for l in open(path, encoding='utf-8', errors='replace')]
    cand_b, cand_e = [], []
    for l in lines:
        if not l or l[0] in '![' or re.search(r'#@?[?$%+]?#', l) or '$$' in l:
            continue
        g = gen(l)
        if g is None:
            continue
        (cand_e if l.startswith('@@') else cand_b).append((l, g))
    for l, g in random.sample(cand_b, min(n_block, len(cand_b))):
        rows.append((*g, label + ':block', l))
    for l, g in random.sample(cand_e, min(n_exc, len(cand_e))):
        rows.append((*g, label + ':exception', l))

sample(R + 'easylist.txt', 160, 60, 'easylist')
sample(R + 'easyprivacy.txt', 160, 40, 'easyprivacy')
sample(R + 'cookies.txt', 60, 10, 'cookies')

controls = [
    ('https://www.wikipedia.org/', 'https://www.wikipedia.org/', 'document'),
    ('https://en.wikipedia.org/static/images/logo.png', 'https://en.wikipedia.org/wiki/Main', 'image'),
    ('https://github.com/joinprototype/kaizu', 'https://github.com/joinprototype/kaizu', 'document'),
    ('https://github.githubassets.com/assets/app.js', 'https://github.com/', 'script'),
    ('https://www.example.com/', 'https://www.example.com/', 'document'),
    ('https://developer.apple.com/documentation/webkit', 'https://developer.apple.com/documentation/webkit', 'document'),
    ('https://fonts.gstatic.com/s/inter/v12/x.woff2', 'https://www.example.com/', 'font'),
    ('https://cdn.jsdelivr.net/npm/react@18/index.js', 'https://www.example.com/', 'script'),
    ('https://www.youtube.com/watch?v=abc', 'https://www.youtube.com/watch?v=abc', 'document'),
    ('https://www.youtube.com/embed/abc', 'https://www.example.com/', 'subdocument'),
    ('https://news.ycombinator.com/', 'https://news.ycombinator.com/', 'document'),
    ('https://www.nytimes.com/', 'https://www.nytimes.com/', 'document'),
    ('https://ads.example.com/', 'https://ads.example.com/', 'document'),
    ('https://doubleclick.net/', 'https://doubleclick.net/', 'document'),
    ('https://www.google-analytics.com/analytics.js', 'https://www.google-analytics.com/analytics.js', 'document'),
    ('https://stackoverflow.com/questions/1', 'https://stackoverflow.com/questions/1', 'document'),
    ('https://api.github.com/user', 'https://github.com/', 'xmlhttprequest'),
    ('https://www.reddit.com/r/swift/', 'https://www.reddit.com/r/swift/', 'document'),
]
for c in controls:
    rows.append((*c, 'control', ''))
# $document/subdocument-style filters from lists as top-level navigations
for path in ('easylist.txt',):
    cands = [l.strip() for l in open(R + path, encoding='utf-8', errors='replace') if l.strip().endswith('$document') and l.startswith('||')]
    for l in random.sample(cands, min(20, len(cands))):
        host = l[2:].split('^')[0].split('$')[0]
        if '/' in host or '*' in host: continue
        u = 'https://' + host + '/'
        rows.append((u, u, 'document', 'toplevel:' + 'document-option', l))

with open(OUT + 'requests.tsv', 'w') as f:
    for r in rows:
        f.write('\t'.join(r[:3]) + '\t' + '\t'.join(r[3:]) + '\n')
print(len(rows))
