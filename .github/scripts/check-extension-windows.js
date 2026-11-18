// Runs as a real WebExtension background page inside the disposable release app.
async function checkWindows(first) {
    const base = new URL(first.url).origin;
    try {
        const target = await browser.tabs.create({
            windowId: first.windowId, active: false, url: base + "/extension-test/personal"
        });
        const second = await browser.windows.create({url: base + "/extension-test/work"});
        const [work] = await browser.tabs.query({active: true, windowId: second.id});
        await browser.tabs.update(target.id, {active: true});
        const [personal] = await browser.tabs.query({active: true, windowId: first.windowId});
        const [stillWorking] = await browser.tabs.query({active: true, windowId: second.id});
        if (personal?.id !== target.id || stillWorking?.id !== work?.id || !work) {
            throw new Error("Activating a background tab changed the wrong window");
        }
        // Loading /start completes the runner's page and cookie check.
        await browser.tabs.update(target.id, {url: base + "/start"});
    } catch (error) {
        await fetch(base + "/extension-test/failure?message=" + encodeURIComponent(error.message));
    }
}

async function waitForTestTab() {
    for (let attempt = 0; attempt < 200; attempt++) {
        const tabs = await browser.tabs.query({});
        const first = tabs.find(tab => tab.url?.endsWith("/extension-test/first"));
        if (first) {
            await checkWindows(first);
            return;
        }
        await new Promise(resolve => setTimeout(resolve, 200));
    }
}

waitForTestTab();
