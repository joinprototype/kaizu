import os
"""Prototype: merge each untyped filter's subresource rule and child-frame rule into one typeless rule,
plus one trailing top-frame document exception. Measures rule count / JSON size only."""
import json, sys
OUT = os.path.join(os.environ['ADBLOCK_SCRATCH'], 'out') + '/'
SUB = ["fetch", "font", "image", "media", "other", "script", "style-sheet", "svg-document", "websocket"]
for name in sys.argv[1:]:
    rules = json.load(open(OUT + f'kz2-{name}.json'))
    out = []
    dropped = 0
    for r in rules:
        t = r['trigger']
        a = r['action']['type']
        if a == 'block' and t.get('resource-type') == ['document'] and t.get('load-context') == ['child-frame']:
            # drop frame rules whose sibling subresource rule becomes typeless
            key = (t['url-filter'], json.dumps({k: v for k, v in t.items() if k not in ('resource-type', 'load-context')}, sort_keys=True))
            out.append(('frame', key, r))
            continue
        out.append(('rule', None, r))
    sub_keys = set()
    for kind, key, r in out:
        t = r['trigger']
        if kind == 'rule' and r['action']['type'] == 'block' and t.get('resource-type') == SUB:
            sub_keys.add((t['url-filter'], json.dumps({k: v for k, v in t.items() if k != 'resource-type'}, sort_keys=True)))
    merged = []
    for kind, key, r in out:
        t = r['trigger']
        if kind == 'frame' and key in sub_keys:
            dropped += 1
            continue
        if kind == 'rule' and r['action']['type'] == 'block' and t.get('resource-type') == SUB:
            t = dict(t); del t['resource-type']
            r = {'action': r['action'], 'trigger': t}
        merged.append(r)
    # trailing exception goes after all blocks but we append at the very end
    merged.append({'trigger': {'url-filter': '.*', 'resource-type': ['document'], 'load-context': ['top-frame']}, 'action': {'type': 'ignore-previous-rules'}})
    s = json.dumps(merged, separators=(',', ':'))
    open(OUT + f'proto-{name}.json', 'w').write(s)
    print(name, 'rules', len(rules), '->', len(merged), 'json MB', round(len(json.dumps(rules, separators=(',', ':'))) / 1e6, 1), '->', round(len(s) / 1e6, 1))
