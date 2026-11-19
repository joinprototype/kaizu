// Writes what autoconsent's own filterCompactRules picks for the sites in its
// test suite, so Kaizu's Swift port can be checked against it
// (Tests/BrowserCoreTests/Fixtures/autoconsent-filter-parity.json).
// Usage: node scripts/autoconsent/parity.cjs <unpacked package folder>
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2]);
const { filterCompactRules } = require(path.join(root, 'dist/autoconsent.cjs.js'));
const rules = JSON.parse(fs.readFileSync(path.join(root, 'rules/compact-rules.json'), 'utf8'));

const urls = new Set(['https://example.com/', 'https://www.cookiebot.com/en/help/', 'https://www.cookieyes.com/documentation/']);
for (const file of fs.readdirSync(path.join(root, 'tests')).sort()) {
    if (!file.endsWith('.spec.ts')) continue;
    const text = fs.readFileSync(path.join(root, 'tests', file), 'utf8');
    for (const match of text.matchAll(/'(https?:\/\/[^'\s]+)'/g)) urls.add(match[1]);
}
// Every third site keeps the fixture small while still touching most rules.
const sample = [...urls].filter((_, index) => index % 3 === 0);
const generic = rules.index.genericRuleRange[1] - rules.index.genericRuleRange[0];
const cases = [];
for (const url of sample) {
    for (const mainFrame of [true, false]) {
        const filtered = filterCompactRules(rules, { url, mainFrame });
        const names = filtered.r.map((rule) => rule[1]);
        cases.push({
            url,
            mainFrame,
            // A main frame always starts with every generic rule.
            rules: mainFrame ? names.slice(generic) : names,
            strings: filtered.s.length,
            used: filtered.s.filter((s) => s !== '').length,
        });
    }
}
process.stdout.write(JSON.stringify({ version: rules.v, generic, cases }) + '\n');
