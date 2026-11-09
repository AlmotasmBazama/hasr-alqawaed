// Release-browser QA. Run with HASR_PLAYWRIGHT_PATH set if Playwright is not local.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.HASR_PLAYWRIGHT_PATH || 'playwright');

const url = process.argv[2];
const prefix = process.argv[3] || 'local';
if (!url) throw new Error('Usage: node scripts/check_web.cjs <url> [output-prefix]');
const output = path.resolve(__dirname, '..', 'output', 'web-checks');
fs.mkdirSync(output, { recursive: true });

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.HASR_CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  const page = await context.newPage();
  const errors = [], consoleErrors = [], failedRequests = [], badResponses = [], loadedAssets = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  page.on('requestfailed', request => failedRequests.push({ url: request.url(), error: request.failure()?.errorText }));
  page.on('response', response => {
    if (response.status() >= 400) badResponses.push({ url: response.url(), status: response.status() });
    if (/Cairo|canvaskit|AssetManifest|FontManifest/.test(response.url())) loadedAssets.push({ url: response.url(), status: response.status() });
  });
  async function enter(locator, value) {
    await locator.focus();
    // Flutter attaches its live editing element on the following frame.
    await page.waitForTimeout(150);
    await page.keyboard.press('Control+A');
    await page.keyboard.insertText(value);
    await page.waitForTimeout(150);
  }
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 120000 });
    await page.screenshot({ path: path.join(output, `${prefix}-initial.png`) });
    fs.writeFileSync(path.join(output, `${prefix}-initial.html`), await page.content());
    const snapshot = await page.locator('body').ariaSnapshot();
    fs.writeFileSync(path.join(output, `${prefix}-initial.aria.txt`), snapshot);
    console.log(snapshot);
    // Flutter exposes this initial accessibility opt-in before its semantics tree.
    const enableAccessibility = page.getByRole('button', { name: 'Enable accessibility', exact: true });
    if (await enableAccessibility.count()) await enableAccessibility.evaluate(element => element.click());
    await page.waitForTimeout(350);
    fs.writeFileSync(path.join(output, `${prefix}-accessible.html`), await page.content());
    console.log(await page.locator('body').ariaSnapshot());
    await page.getByRole('button', { name: /^(مشاركة|تنزيل) PDF$/ }).click();
    await page.getByRole('alertdialog').waitFor({ timeout: 20000 });
    console.log('After PDF click:', await page.locator('body').ariaSnapshot());
    fs.writeFileSync(path.join(output, `${prefix}-pdf-dialog.html`), await page.content());
    await page.screenshot({ path: path.join(output, `${prefix}-pdf-dialog.png`) });
    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('alertdialog').getByRole('button', { name: 'تنزيل PDF', exact: true }).press('Enter'),
    ]);
    assert.equal(await download.failure(), null);
    await download.saveAs(path.join(output, `${prefix}-default.pdf`));
    assert.equal(fs.readFileSync(path.join(output, `${prefix}-default.pdf`)).subarray(0, 5).toString(), '%PDF-');
    console.log('Downloaded PDF:', download.suggestedFilename());
    await page.getByRole('alertdialog').waitFor({ state: 'detached' });
    await enter(page.getByRole('textbox', { name: 'عدد القواعد', exact: true }), '١٠');
    await enter(page.getByRole('textbox', { name: 'سعر الوحدة', exact: true }).nth(0), '٦٠٠');
    await page.waitForTimeout(550);
    assert.ok((await page.locator('body').ariaSnapshot()).includes('9,200'));
    await page.reload({ waitUntil: 'networkidle' });
    if (await enableAccessibility.count()) await enableAccessibility.evaluate(element => element.click());
    await page.getByRole('textbox', { name: 'عدد القواعد', exact: true }).waitFor();
    assert.ok((await page.locator('body').ariaSnapshot()).includes('9,200'));
    console.log('Restored storage:', await page.evaluate(() => Object.fromEntries(Object.entries(localStorage))));
    await enter(page.getByRole('textbox', { name: 'سعر الوحدة', exact: true }).nth(0), '560');
    await page.getByRole('button', { name: 'نموذج', exact: true }).click();
    await page.getByRole('textbox', { name: 'اسم النموذج', exact: true }).waitFor();
    console.log('Model editor:', await page.locator('body').ariaSnapshot());
    fs.writeFileSync(path.join(output, `${prefix}-editor.html`), await page.content());
    await enter(page.getByRole('textbox', { name: 'اسم النموذج', exact: true }), 'نموذج اختبار الويب');
    await enter(page.getByRole('textbox', { name: 'الخرسانة (م³)', exact: true }), '١');
    await enter(page.getByRole('textbox', { name: 'أسياخ لكل قاعدة', exact: true }).nth(0), '٢');
    await enter(page.getByRole('textbox', { name: 'أسياخ لكل قنطار', exact: true }).nth(0), '٥');
    await enter(page.getByRole('textbox', { name: 'أسياخ لكل قاعدة', exact: true }).nth(1), '٠٫٥');
    await enter(page.getByRole('textbox', { name: 'أسياخ لكل قنطار', exact: true }).nth(1), '١٠');
    await page.getByRole('button', { name: 'حفظ واستخدام النموذج', exact: true }).press('Enter');
    await page.getByRole('heading', { name: 'حصر القواعد', exact: true }).waitFor();
    await page.waitForTimeout(300);
    assert.ok((await page.locator('body').ariaSnapshot()).includes('9,580'));
    const storedModelIds = await page.evaluate(() => [...new Set((localStorage.getItem('hasr_alqawaed_state_v1') || '').match(/custom_\d+_\d+/g))]);
    assert.equal(storedModelIds.length, 1);
    await page.getByRole('button', { name: /^اختيار النموذج/ }).press('Enter');
    console.log('Model picker:', await page.locator('body').ariaSnapshot());
    fs.writeFileSync(path.join(output, `${prefix}-picker.html`), await page.content());
    await page.getByRole('button', { name: 'تعديل نموذج اختبار الويب', exact: true }).press('Enter');
    await page.getByRole('heading', { name: 'تعديل النموذج', exact: true }).waitFor();
    await enter(page.getByRole('textbox', { name: 'اسم النموذج', exact: true }), 'نموذج الويب المعدل');
    await enter(page.getByRole('textbox', { name: 'الخرسانة (م³)', exact: true }), '1.2');
    await page.getByRole('button', { name: 'حفظ التعديلات', exact: true }).press('Enter');
    await page.getByRole('heading', { name: 'حصر القواعد', exact: true }).waitFor();
    await page.waitForTimeout(350);
    assert.ok((await page.locator('body').ariaSnapshot()).includes('10,700'));
    assert.deepEqual(await page.evaluate(() => [...new Set((localStorage.getItem('hasr_alqawaed_state_v1') || '').match(/custom_\d+_\d+/g))]), storedModelIds);
    await page.reload({ waitUntil: 'networkidle' });
    if (await enableAccessibility.count()) await enableAccessibility.evaluate(element => element.click());
    await page.getByRole('button', { name: /^اختيار النموذج نموذج الويب المعدل/ }).waitFor();
    assert.ok((await page.locator('body').ariaSnapshot()).includes('10,700'));
    await page.screenshot({ path: path.join(output, `${prefix}-restored-custom.png`) });
    await page.getByRole('button', { name: /^اختيار النموذج/ }).press('Enter');
    await page.getByRole('button', { name: /^نموذج 1 / }).press('Enter');
    await page.waitForTimeout(300);
    assert.ok((await page.locator('body').ariaSnapshot()).includes('8,900'));
    await enter(page.getByRole('textbox', { name: 'عدد القواعد', exact: true }), '20');
    assert.ok((await page.locator('body').ariaSnapshot()).includes('17,800'));
    await page.setViewportSize({ width: 360, height: 740 });
    await page.mouse.move(180, 350);
    await page.mouse.wheel(0, -2000);
    await page.waitForTimeout(350);
    await page.screenshot({ path: path.join(output, `${prefix}-mobile-top.png`) });
    await page.mouse.wheel(0, 1600);
    await page.waitForTimeout(350);
    assert.ok((await page.locator('body').ariaSnapshot()).includes('17,800'));
    await page.screenshot({ path: path.join(output, `${prefix}-mobile-total.png`) });
    await page.getByRole('button', { name: /^(مشاركة|تنزيل) PDF$/ }).press('Enter');
    await page.getByRole('alertdialog').waitFor({ timeout: 20000 });
    await page.waitForTimeout(350);
    await page.screenshot({ path: path.join(output, `${prefix}-mobile-pdf-dialog.png`) });
    const [mobileDownload] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('alertdialog').getByRole('button', { name: 'تنزيل PDF', exact: true }).press('Enter'),
    ]);
    assert.equal(await mobileDownload.failure(), null);
    await mobileDownload.saveAs(path.join(output, `${prefix}-mobile.pdf`));
    assert.deepEqual(errors, []);
    assert.deepEqual(consoleErrors, []);
    assert.deepEqual(failedRequests, []);
    assert.deepEqual(badResponses, []);
    const result = {
      url, title: await page.title(), passed: true,
      desktopViewport: [1280, 900], mobileViewport: [360, 740],
      checks: ['default17800', 'ArabicCountAndPrice9200', 'inputReloadPersistence', 'customModel9580', 'editSameModel10700', 'customModelReloadPersistence', 'modelSwitchRetainsInputs', 'mobileLayout17800', 'desktopAndMobilePdfDownloads'],
      errors, consoleErrors, failedRequests, badResponses, loadedAssets,
    };
    fs.writeFileSync(path.join(output, `${prefix}-results.json`), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.log('Failure state:', await page.locator('body').ariaSnapshot());
    await page.screenshot({ path: path.join(output, `${prefix}-failure.png`) });
    fs.writeFileSync(path.join(output, `${prefix}-failure.html`), await page.content());
    console.log(JSON.stringify({ errors, consoleErrors, failedRequests, badResponses }, null, 2));
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
