// Browser QA. All storage and file sharing are isolated from real user data.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const checkMasonry = require('./check_masonry.cjs');
const checkHelp = require('./check_help.cjs');
const { chromium } = require(process.env.HASR_PLAYWRIGHT_PATH || 'playwright');

const url = process.argv[2];
const prefix = process.argv[3] || 'local-v3';
if (!url) throw new Error('Usage: node scripts/check_web.cjs <url> [prefix]');
const output = path.resolve(__dirname, '..', 'output', 'web-checks');
fs.mkdirSync(output, { recursive: true });

const legacy = {
  version: 1,
  customModels: [{
    id: 'browser-legacy-model', name: 'نموذج سابق محفوظ',
    length: 1.25, width: 1.4, height: .55, concretePerFoundation: 1,
    steel14BarsPerFoundation: 2, steel14BarsPerQuintal: 5,
    steel8BarsPerFoundation: .5, steel8BarsPerQuintal: 10,
  }],
  selectedModelId: 'browser-legacy-model',
  inputs: {
    count: 10,
    prices: { concrete: 560, steel14: 520, steel8: 600, carpenter: 70, steelWorker: 30, casting: 60 },
  },
};

const stateKey = 'hasr_project_state_v3';
const v1Key = 'hasr_alqawaed_state_v1';
const baseOptions = { viewport: { width: 1280, height: 900 }, acceptDownloads: true };
const pdfAction = /^(تنزيل|مشاركة) التقرير PDF$/;

async function session(browser, options = baseOptions) {
  const context = await browser.newContext(options);
  const page = await context.newPage();
  page.setDefaultTimeout(15000);
  page.setDefaultNavigationTimeout(90000);

  const snapshot = () => page.locator('body').ariaSnapshot();
  const button = name => page.getByRole('button', { name, exact: true });
  const textbox = name => page.getByRole('textbox', { name });
  async function enable() {
    const trigger = page.locator('flt-semantics-placeholder');
    await trigger.waitFor({ state: 'attached', timeout: 90000 });
    await trigger.evaluate(el => el.click());
    await page.getByRole('heading', { name: 'كميات المشروع', exact: true }).waitFor();
  }
  async function open(reload = false) {
    if (reload) await page.reload({ waitUntil: 'domcontentloaded' });
    else await page.goto(url, { waitUntil: 'domcontentloaded' });
    await enable();
  }
  async function tab(name) {
    await page.getByRole('tab', { name, exact: true }).press('Enter');
  }
  async function scroll(delta) {
    const viewport = page.viewportSize();
    await page.mouse.move(Math.round(viewport.width / 2), Math.round(viewport.height * .52));
    await page.mouse.wheel(0, delta);
    await page.waitForTimeout(180); // Wait for Flutter to update visible semantics.
  }
  async function seek(locator) {
    for (let i = 0; i < 18; i++) {
      if (await locator.count() && await locator.first().isVisible()) return locator.first();
      await scroll(375);
    }
    await locator.first().waitFor();
    return locator.first();
  }
  async function enter(locator, value) {
    await (await seek(locator)).focus();
    await page.waitForTimeout(175); // Let Flutter attach its editable element.
    await page.keyboard.press('Control+A');
    if (value) await page.keyboard.insertText(value);
    else await page.keyboard.press('Backspace');
    await page.waitForTimeout(550); // Allow the debounced local write.
  }
  async function getState(key = stateKey) {
    return page.evaluate(k => JSON.parse(JSON.parse(localStorage.getItem(k))), key);
  }
  async function includes(value) {
    for (let i = 0; i < 36; i++) {
      if ((await snapshot()).includes(value)) return;
      await page.waitForTimeout(150);
    }
    assert.fail('Missing text: ' + value);
  }
  async function addSample(full = false) {
    const before = (await getState()).currentProjectId;
    await button('اختيار مشروع').press('Enter');
    await button(full ? /^إضافة «مثال الأوراق بالسقف»/ : /^إضافة «مثال الأوراق»/).press('Enter');
    await page.waitForFunction(({ key, before }) => {
      const raw = localStorage.getItem(key);
      return raw && JSON.parse(JSON.parse(raw)).currentProjectId !== before;
    }, { key: stateKey, before });
    await page.getByRole('heading', { name: 'كميات المشروع', exact: true }).waitFor();
    return (await getState()).currentProjectId;
  }
  async function download(label) {
    await (await seek(button(pdfAction))).press('Enter');
    const dialog = page.getByRole('alertdialog');
    await dialog.waitFor({ timeout: 30000 });
    const [file] = await Promise.all([
      page.waitForEvent('download'),
      dialog.getByRole('button', { name: 'تنزيل PDF', exact: true }).press('Enter'),
    ]);
    assert.match(file.suggestedFilename(), /^hasr_project_\d{8}_\d{6}\.pdf$/);
    const dest = path.join(output, prefix + '-' + label + '.pdf');
    await file.saveAs(dest);
    assert.equal(await file.failure(), null);
    assert.equal(fs.readFileSync(dest).subarray(0, 5).toString(), '%PDF-');
    await dialog.waitFor({ state: 'detached' });
    return dest;
  }
  async function screenshot(name) {
    await page.waitForTimeout(250); // Capture the settled view after tab transitions.
    await page.screenshot({ path: path.join(output, prefix + '-' + name + '.png') });
  }
  return { context, page, open, tab, snapshot, button, textbox, getState, includes, addSample, download, screenshot, seek, enter, scroll };
}

function logFailures(page, errors) {
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('response', r => { if (r.status() >= 400) errors.push(r.status() + ' ' + r.url()); });
  page.on('requestfailed', r => {
    if (r.failure()?.errorText !== 'net::ERR_ABORTED') errors.push(r.url() + ': ' + r.failure()?.errorText);
  });
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.HASR_CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
  });
  const checks = [];
  const errors = [];
  const s = await session(browser);
  logFailures(s.page, errors);
  try {
    if (process.argv.includes('--help-only')) {
      await checkHelp(browser, session, logFailures, errors);
      assert.deepEqual(errors, []);
      console.log(JSON.stringify({ url, passed: true, checks: ['contextualHelp'] }));
      return;
    }
    if (process.argv.includes('--masonry-only')) {
      const pdf = await checkMasonry(browser, session, logFailures, errors);
      assert.deepEqual(errors, []);
      console.log(JSON.stringify({ url, passed: true, pdf }));
      return;
    }
    await s.context.addInitScript(({ data, key }) => {
      if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify(JSON.stringify(data)));
    }, { data: legacy, key: v1Key });
    await s.open();
    const migrated = await s.getState();
    assert.equal(migrated.version, 3);
    assert.equal(migrated.projects[0].name, 'مشروعي السابق');
    assert.equal(migrated.customModels[0].id, 'browser-legacy-model');
    assert.equal(migrated.projects[0].works.filter(w => w.included).length, 1);
    assert.equal(migrated.projects[0].profitPercentage, 0);
    assert.deepEqual(await s.getState(v1Key), legacy);
    assert.deepEqual(await s.getState('hasr_project_v1_original_backup'), legacy);
    checks.push('legacyMigrationAndOriginalBackup');

    const old = await s.addSample();
    await s.tab('النتائج');
    await s.includes('لم يُحسب المشروع بعد');
    assert.equal(await s.button(pdfAction).count(), 0);
    await s.tab('الكميات');
    await s.screenshot('desktop-quantities');
    await s.button('احسب المشروع').press('Enter');
    await s.includes('86,364.20');
    await s.includes('66,656.20');
    await s.includes('19,708.00');
    const oldPdf = await s.download('previous-example');
    await s.tab('الأسعار والربح');
    await s.enter(s.textbox(/^سعر أسمنت بالنقل/), '٤٠');
    await s.tab('النتائج');
    await s.includes('الحسبة تحتاج تحديثًا');
    assert.equal(await s.button(pdfAction).count(), 0);
    await s.open(true);
    await s.tab('النتائج');
    await s.includes('الحسبة تحتاج تحديثًا');
    await s.button('تحديث الحسبة').press('Enter');
    await s.includes('86,026.20');
    checks.push('previousBaselineAndArabicCementPrice', 'staleCalculationAndPdfGuardSurviveReload');

    const full = await s.addSample(true);
    assert.notEqual(full, old);
    await s.tab('الأسعار والربح');
    await s.enter(s.textbox(/^نسبة الربح على التكلفة/), '١٠');
    await s.tab('الكميات');
    await s.button('احسب المشروع').press('Enter');
    for (const amount of ['162,724.87', '120,723.70', '27,208.00', '147,931.70', '14,793.17']) {
      await s.includes(amount);
    }
    const saved = await s.getState();
    const fullProject = saved.projects.find(project => project.id === full);
    const oldProject = saved.projects.find(project => project.id === old);
    assert.equal(fullProject.profitPercentage, 10);
    assert.equal(fullProject.materialPrices.cement, 42);
    assert.equal(oldProject.profitPercentage, 0);
    assert.equal(oldProject.materialPrices.cement, 40);
    await s.screenshot('desktop-results');
    const fullPdf = await s.download('full-example');
    checks.push('fullRoofAndProfit162724.87', 'pricesAndProfitIndependent', 'desktopPdfDownload');

    await s.page.setViewportSize({ width: 320, height: 640 });
    await s.open(true);
    await s.screenshot('mobile-quantities');
    await s.tab('الأسعار والربح');
    await s.screenshot('mobile-prices');
    await s.tab('النتائج');
    await s.includes('162,724.87');
    await s.screenshot('mobile-results');
    const mobilePdf = await s.download('mobile-full-example');
    await s.tab('الكميات');
    await s.enter(s.textbox(/^إجمالي أطوال كمرات السقف/), '');
    await s.button('احسب المشروع').press('Enter');
    await s.includes('حصر جزئي — توجد بنود غير مكتملة');
    await s.includes('البنود غير المكتملة: السقف');
    const partialPdf = await s.download('partial');
    assert.equal((await s.getState()).projects.length, 3);
    checks.push('mobile320AndPdf', 'missingRoofBeamLengthRemainsPartial');

    // Confirm the v2 storage path in a distinct browser profile. Strip v3-only
    // fields to reproduce persisted v2 input, including an old roof selection.
    const m = await session(browser);
    logFailures(m.page, errors);
    const v2 = structuredClone(saved);
    v2.version = 2;
    const legacyRoof = {
      id: 'legacy-roof', kind: 'roof', name: 'سقف قديم مستقل',
      description: '', inputUnit: 'linear',
      rows: [{
        id: 'roof-v2-line', label: 'خرسانة للسقف القديم', materialId: 'concrete',
        unit: 'volume', sourceUnit: null, coefficient: .1, divisor: 1,
        defaultPrice: 560, reviewBasis: false,
      }],
    };
    v2.customModels.push(legacyRoof);
    v2.projects = v2.projects.filter(project => project.id === old);
    v2.currentProjectId = old;
    const p = v2.projects[0];
    const roof = p.works.find(work => work.kind === 'roof');
    roof.model = legacyRoof;
    roof.quantity = 77;
    roof.priceOverrides = { 'roof-v2-line': 555 };
    delete p.materialPrices.steel6;
    delete p.materialPrices.hollowBlock;
    for (const property of ['inputDrafts', 'profitPercentage', 'calculatedProject', 'calculationStale']) delete p[property];
    for (const work of p.works) {
      delete work.linkedToTieBeam;
      delete work.roofBeamLength;
      delete work.explicitlyExcluded;
      for (const row of work.model?.rows ?? []) delete row.quantitySource;
    }
    await m.context.addInitScript(data => {
      const key = 'hasr_project_state_v2';
      if (!localStorage.getItem(key)) localStorage.setItem(key, JSON.stringify(JSON.stringify(data)));
    }, v2);
    await m.open();
    let updated = await m.getState();
    assert.deepEqual(await m.getState('hasr_project_v2_original_backup'), v2);
    const kept = updated.projects[0].works.find(work => work.kind === 'roof');
    assert.equal(kept.model.id, 'legacy-roof');
    assert.equal(kept.model.rows[0].quantitySource, 'workQuantity');
    assert.equal(kept.quantity, 77);
    assert.equal(kept.explicitlyExcluded, true);
    assert.equal(kept.priceOverrides['roof-v2-line'], 555);
    assert.equal(updated.projects[0].materialPrices.cement, 40);
    await m.open(true);
    assert.deepEqual(await m.getState(), updated);
    await m.context.close();
    checks.push('v2MigrationIdempotentPreservesLegacyRoofAndOverrides');

    const share = await session(browser);
    logFailures(share.page, errors);
    await share.context.addInitScript(() => {
      Object.defineProperty(navigator, 'canShare', {
        value: ({ files }) => files?.length === 1 && files[0].type === 'application/pdf',
      });
      Object.defineProperty(navigator, 'share', {
        value: async ({ files }) => {
          window.hasrSharedFile = {
            name: files[0].name, type: files[0].type,
            startsWithPdf: (await files[0].slice(0, 5).text()) === '%PDF-',
          };
        },
      });
    });
    await share.open();
    await share.addSample(true);
    await share.button('احسب المشروع').press('Enter');
    await (await share.seek(share.button('مشاركة التقرير PDF'))).press('Enter');
    const dialog = share.page.getByRole('alertdialog');
    await dialog.getByRole('button', { name: 'مشاركة PDF', exact: true }).press('Enter');
    await dialog.waitFor({ state: 'detached' });
    const shared = await share.page.evaluate(() => window.hasrSharedFile);
    assert.equal(shared.type, 'application/pdf');
    assert.ok(shared.startsWithPdf);
    await share.context.close();
    checks.push('shareCapableBrowserPdfApiWithStub');

    const mixedPdf = await checkMasonry(browser, session, logFailures, errors);
    checks.push('linkedAndCustomLengthsAcrossReload', 'exclusionsAndExplicitZero', 'mixedMasonryPdf');
    await checkHelp(browser, session, logFailures, errors);
    checks.push('contextualHelpWithKeyboardAndTouch', 'hintsKeepSavedState', 'sharedPriceUnitsAndProfitExample');
    if (process.env.HASR_PREVIOUS_WEB_FIXTURE) checks.push('releasedV31PreservesEqualIndependentLengths');
    assert.deepEqual(errors, []);
    const result = { url, passed: true, checks, oldPdf, fullPdf, mobilePdf, partialPdf, mixedPdf, errors };
    fs.writeFileSync(path.join(output, prefix + '-results.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.log('Failure state:', await s.snapshot().catch(() => '(not available)'));
    await s.screenshot('failure').catch(() => {});
    console.log(JSON.stringify({ checks, errors }, null, 2));
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
