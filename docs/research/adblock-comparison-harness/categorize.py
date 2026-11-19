import re, sys, collections, json

OUT = sys.argv[1]
MARK = re.compile(r'#(@?)(\?|\$|%|\+)?#')

def category(line):
    if not line.isascii():
        nonascii = True
    else:
        nonascii = False
    m = re.search(r'#@?[?$%]?#', line)
    if m and '$$' not in line:
        i = m.start()
        domains = line[:i]
        body = line[m.end():]
        mk = m.group(0)
        if body.startswith('+js('):
            c = 'cosmetic: scriptlet (+js)'
        elif body.startswith('^'):
            c = 'cosmetic: HTML filter (##^)'
        elif mk in ('#%#',) or mk == '#@%#':
            c = 'cosmetic: JS snippet (#%#)'
        elif mk in ('#$#', '#@$#'):
            c = 'cosmetic: CSS/snippet injection (#$#)'
        elif ':style(' in body or ':remove(' in body:
            c = 'cosmetic: :style()/:remove() action'
        elif mk in ('#?#', '#@?#') or re.search(r':(has-text|xpath|matches-css|matches-attr|matches-path|upward|min-text-length|-abp-|contains|nth-ancestor|watch-attr|others|if|if-not|not\()', body) and re.search(r':(has-text|xpath|matches-css|matches-attr|matches-path|upward|min-text-length|-abp-|contains|nth-ancestor|watch-attr|others)\(', body):
            c = 'cosmetic: procedural / extended CSS'
        elif re.search(r'(^|,)~?[\w.-]*\.\*(,|$)', domains):
            c = 'cosmetic: entity domain (google.*)'
        elif nonascii:
            c = 'cosmetic: non-ASCII'
        elif '~' in domains and re.search(r'(^|,)[^~]', domains):
            c = 'cosmetic: mixed include/exclude domains'
        elif mk == '#@#':
            c = 'cosmetic: exception (#@#) not expressible'
        else:
            c = 'cosmetic: other / unsupported selector'
        return c
    # network
    body = line
    opts = ''
    j = body.rfind('$')
    if j >= 0 and re.fullmatch(r'[~\w-]+(=[^,]*)?(,[~\w-]+(=[^,]*)?)*', body[j+1:] or '#'):
        opts = body[j+1:]
        pat = body[:j]
    else:
        pat = body
    names = [o.split('=')[0].lower().lstrip('~') for o in opts.split(',')] if opts else []
    full = [o.lower() for o in opts.split(',')] if opts else []
    pr = pat[2:] if pat.startswith('@@') else pat
    for n, label in [('popup', 'popup'), ('popunder', 'popup'), ('redirect', '$redirect'), ('redirect-rule', '$redirect'),
                     ('csp', '$csp'), ('removeparam', '$removeparam'), ('queryprune', '$removeparam'),
                     ('badfilter', '$badfilter'), ('generichide', '$generichide'),
                     ('elemhide', '$elemhide/specifichide'), ('specifichide', '$elemhide/specifichide'),
                     ('denyallow', '$denyallow'), ('to', '$to'), ('replace', '$replace'),
                     ('header', '$header'), ('permissions', '$permissions'), ('empty', '$empty/mp4'), ('mp4', '$empty/mp4'),
                     ('inline-script', '$inline-script'), ('inline-font', '$inline-script'),
                     ('cname', '$cname'), ('ctag', '$ctag'), ('app', '$app'), ('rewrite', '$rewrite'),
                     ('all', '$all')]:
        if n in names:
            return 'network option: ' + label
    if 'document' in names or 'doc' in names:
        return 'network option: $document'
    if any(n in names for n in ('xmlhttprequest', 'xhr')) and False:
        pass
    if 'object' in names or 'object-subrequest' in names:
        return 'network option: $object (plugin type)'
    if 'important' in names and False:
        pass
    if re.fullmatch(r'/.*/', pr) or (len(pr) > 2 and pr.startswith('/') and pr.endswith('/')):
        return 'network: regex filter'
    if not line.isascii():
        return 'network: non-ASCII'
    if 'domain' in names or 'from' in names:
        dv = [o for o in opts.split(',') if o.lower().startswith(('domain=', 'from='))][0]
        if '/' in dv:
            return 'network option: $domain=/regex/'
        d = dv.split('=', 1)[1].split('|')
        if any(x.startswith('~') for x in d) and any(not x.startswith('~') for x in d):
            return 'network option: $domain mixing include and ~exclude'
        return 'network option: $domain (other)'
    if pr.startswith('||') is False and (pr == '' or pr == '*'):
        return 'network: match-all pattern'
    return 'network: other (' + ','.join(sorted(set(names))) + ')' if names else 'network: other pattern'

def load(path):
    rows = []
    for l in open(path, encoding='utf-8', errors='replace'):
        p = l.rstrip('\n').split('\t', 3)
        rows.append(p)
    return rows

if __name__ == '__main__':
    pass
