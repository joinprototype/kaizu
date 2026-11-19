import os
"""Fetch a few popular homepages and extract static subresource URLs (script/img/iframe/link)."""
import re, subprocess, urllib.parse, sys

OUT = os.path.join(os.environ['ADBLOCK_SCRATCH'], 'out') + '/'
sites = ['https://www.cnn.com/', 'https://www.nytimes.com/', 'https://www.bbc.com/', 'https://www.theverge.com/',
         'https://www.forbes.com/', 'https://www.cnet.com/', 'https://www.espn.com/', 'https://www.imdb.com/',
         'https://www.weather.com/', 'https://www.dailymail.co.uk/', 'https://www.wired.com/', 'https://www.foxnews.com/']
rows = []
for s in sites:
    try:
        html = subprocess.run(['curl', '-sL', '--max-time', '20', '-A',
                               'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
                               s], capture_output=True, timeout=30).stdout.decode('utf-8', 'replace')
    except Exception as e:
        print('fail', s, e, file=sys.stderr); continue
    seen = set()
    n = 0
    for m in re.finditer(r'<(script|img|iframe|link)\b[^>]*?\b(?:src|href)=["\']([^"\']+)["\'][^>]*>', html, re.I):
        tag, u = m.group(1).lower(), m.group(2)
        if tag == 'link' and 'stylesheet' not in m.group(0).lower(): continue
        u = urllib.parse.urljoin(s, u.replace('&amp;', '&'))
        if not u.startswith('http') or not u.isascii() or u in seen or ' ' in u: continue
        seen.add(u)
        typ = {'script': 'script', 'img': 'image', 'iframe': 'subdocument', 'link': 'stylesheet'}[tag]
        rows.append((u, s, typ, 'site:' + urllib.parse.urlparse(s).hostname, ''))
        n += 1
    print(s, len(html), n, file=sys.stderr)
with open(OUT + 'requests-sites.tsv', 'w') as f:
    for r in rows:
        f.write('\t'.join(r) + '\n')
print(len(rows))
