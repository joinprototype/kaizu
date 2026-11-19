// Prints autoconsent's eval snippets as JSON, id -> the expression its
// library would send for that id (`(<function source>)()`). The app runs
// only these, so the table must come from the same release as the rules.
// Usage: node scripts/autoconsent/snippets.cjs <unpacked package folder>
const path = require('path');
const { evalSnippets } = require(path.resolve(process.argv[2], 'dist/autoconsent.cjs.js'));
const table = {};
for (const id of Object.keys(evalSnippets).sort()) {
    table[id] = `(${evalSnippets[id].toString()})()`;
}
process.stdout.write(JSON.stringify(table, null, 1) + '\n');
