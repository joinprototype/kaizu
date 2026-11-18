const {chromium} = require('playwright-core');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
    const root = path.join(process.env.RUNNER_TEMP, 'vault-test');
    const origin = 'https://localhost:18765';
    const email = 'kaizu-qa@example.invalid';
    const password = crypto.randomBytes(30).toString('base64url');
    fs.writeFileSync(path.join(root, 'dummy-pass'), password, {mode: 0o600});
    const browser = await chromium.launch({channel: 'chrome', headless: true});
    try {
        const page = await browser.newPage();
        await page.route('**/*', route => {
            const url = new URL(route.request().url());
            return url.origin === origin || !['http:', 'https:'].includes(url.protocol) ? route.continue() : route.abort();
        });
        await page.goto(origin);
        const button = (name) => page.getByRole('button', {name, exact: true});
        await page.getByText('Create account', {exact:true}).first().click();
        await page.locator('#register-start_form_input_email').fill(email);
        await page.locator('#register-start_form_input_name').fill('Kaizu QA');
        await button('Continue').click();
        await page.locator('#input-password-form_new-password').fill(password);
        await page.locator('#input-password-form_new-password-confirm').fill(password);
        await page.locator('#input-password-form_check-for-breaches').uncheck();
        await button('Create account').click();
        await page.getByText('Add it later', {exact:true}).click();
        await page.getByText('Skip to web app', {exact:true}).click();
        await button('Skip').or(button('Add item')).first().waitFor();
        if (await button('Skip').isVisible()) await button('Skip').click();
        await button('Add item').click();
        await page.getByLabel(/Item name/).fill('Kaizu autofill fixture');
        await page.getByLabel('Username', {exact:true}).fill('synthetic-kaizu-user');
        await page.getByLabel('Password', {exact:true}).fill('Kaizu-QA-Field-Only-42!');
        await page.getByLabel(/Website \(URI\)/).fill('https://127.0.0.1:18764/login');
        await button('Save').click();
        await page.getByText('Kaizu autofill fixture', {exact:true}).first().waitFor();
        console.log('Created local vault and saved one synthetic login.');
    } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode=1; });
