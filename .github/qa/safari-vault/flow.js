const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function button(label) {
    return [...document.querySelectorAll('button,a,[role=menuitem]')].find(el => el.getClientRects().length && el.innerText?.trim() === label);
}
async function waitFor(fn, name, tries = 100) {
    for (let i = 0; i < tries; i++) {
        const value = fn();
        if (value) return value;
        await delay(200);
    }
    // This browser has only synthetic test data. Exclude inputs from the diagnostic.
    throw new Error(name + ': ' + document.body.innerText.replaceAll('synthetic-kaizu-user','test user').slice(0,550));
}
function setValue(el, value) {
    el.value = value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('blur', {bubbles:true}));
}
await waitFor(() => button('Log in'), 'welcome');
let lastClick = 0;
await waitFor(() => {
    if (button('bitwarden.com')) return true;
    if (Date.now() - lastClick > 1500) {
        button('Log in')?.click();
        lastClick = Date.now();
    }
    return false;
}, 'region menu');
button('bitwarden.com').click();
(await waitFor(() => button('self-hosted'), 'self-hosted option')).click();
const base = await waitFor(() => document.querySelector('#self_hosted_env_settings_form_input_base_url'), 'server URL');
setValue(base, 'https://localhost:18765');
button('Save').click();
await waitFor(() => !base.isConnected && button('self-hosted'), 'saved self-hosted environment');
setValue(document.querySelector('input[type=email]'), 'kaizu-qa@example.invalid');
button('Continue').click();
const input = await waitFor(() => {
    const field = [...document.querySelectorAll('input[type=password]')].find(e => e.getClientRects().length);
    if (!field) button('Log in with master password')?.click();
    return field;
}, 'master password field');
setValue(input, password);
const submit = ['Log in with master password','Log in','Unlock','Continue'].map(button).find(Boolean);
if (!submit) throw new Error('Missing login action');
submit.click();
await waitFor(() => document.body.innerText.includes('Kaizu autofill fixture'), 'vault login and matching item', 170);
const fill = [...document.querySelectorAll('button')].find(el => el.getClientRects().length && /^autofill/i.test((el.getAttribute('aria-label') || el.getAttribute('title') || el.innerText || '').trim()));
if (!fill) throw new Error('Signed in and found the matching item. Fill control not found: ' + document.body.innerText.slice(0,470));
fill.click();
return 'Requested fill from the matching Bitwarden suggestion';
