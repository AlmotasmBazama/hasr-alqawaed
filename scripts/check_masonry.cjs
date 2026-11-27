const assert = require('node:assert/strict');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');

// Use a fresh browser profile so the full mobile journey starts with an empty job.
module.exports = async function checkMasonry(browser, session, logFailures, errors) {
  const s = await session(browser, {
    viewport: { width: 360, height: 640 }, hasTouch: true, acceptDownloads: true,
  });
  logFailures(s.page, errors);
  const kinds = ['tieBeam', 'belowMasonry', 'aboveMasonry'];
  const fields = [
    s.textbox(/^طول الميدة/),
    s.textbox(/^طول مباني تحت الكتينة/),
    s.textbox(/^طول مباني فوق الكتينة/),
  ];
  const press = async name => (await s.seek(s.button(name))).press('Enter');
  const input = (index, text) => s.enter(fields[index], text);
  const project = async () => {
    const state = await s.getState();
    return state.projects.find(p => p.id === state.currentProjectId);
  };
  async function lengths(expected, saved = false) {
    const job = await project();
    const works = saved ? job.calculatedProject.works : job.works;
    assert.deepEqual(kinds.map(kind => works.find(w => w.kind === kind).quantity), expected);
  }
  async function calculate(total, action = 'احسب المشروع') {
    await press(action);
    await s.includes(total);
  }
  let pdf;
  try {
    await s.open();
    await press('اختيار مشروع');
    await press('إنشاء مشروع جديد');
    const dialog = s.page.getByRole('alertdialog');
    await s.enter(dialog.getByRole('textbox', { name: /اسم المشروع/ }), 'مشروع النخيل');
    const location = dialog.getByRole('textbox', { name: /الموقع/ });
    if (await location.count()) await s.enter(location, 'طرابلس');
    await dialog.getByRole('button', { name: 'حفظ', exact: true }).press('Enter');
    await dialog.waitFor({state:'detached'});
    await lengths([null, null, null]);
    await input(2, '١٢٥٫٧٥');
    await lengths([null, null, 125.75]);
    // Edit a digit in the middle without refocusing or replacing the entire input.
    // Set the same logical selection as highlighting the second digit with
    // touch. Physical arrow-key directions depend on the browser's bidi run.
    await s.page.evaluate(() => {
      let editor = document.activeElement;
      while (editor?.shadowRoot?.activeElement) editor = editor.shadowRoot.activeElement;
      if (editor?.value !== '١٢٥٫٧٥') throw Error('The numeric keyboard lost its active editor');
      editor.setSelectionRange(1, 2);
      document.dispatchEvent(new Event('selectionchange'));
    });
    await s.page.waitForTimeout(120);
    await s.page.keyboard.insertText('٩');
    await s.page.waitForTimeout(550);
    await lengths([null, null, 195.75]);
    assert.deepEqual((await project()).works.filter(w => w.included).map(w => w.kind), ['aboveMasonry']);
    await input(0, '١٣٠');
    await input(1, '٩٥');
    await input(2, '١٦٠');
    await calculate('47,908.50');
    await lengths([130, 95, 160], true);
    await s.tab('الكميات');
    await input(0, '150');
    await s.open(true);
    await lengths([150, 95, 160]);
    await s.tab('النتائج');
    await s.includes('تحديث الحسبة');
    assert.equal(await s.button(/^(تنزيل|مشاركة) التقرير PDF$/).count(), 0);
    await calculate('50,844.50', 'تحديث الحسبة');
    await lengths([150, 95, 160], true);
    await s.screenshot('mobile-independent-results');
    await press(/^كميات المواد/);
    await s.includes('6,950');
    await press(/^كميات المواد/);
    pdf = await s.download('independent');
    const viewer = await s.context.newPage();
    const [pdfFrame] = await Promise.all([
      viewer.waitForEvent('framenavigated', {predicate: frame => frame.url().startsWith('chrome-extension:')}),
      viewer.goto(pathToFileURL(pdf).href, {waitUntil:'domcontentloaded'}),
    ]);
    await pdfFrame.locator('pdf-viewer').waitFor({state:'attached'});
    await viewer.close();

    await s.page.setViewportSize({width:1360, height:1000});
    await s.open(true);
    await s.screenshot('independent-quantities');
    await s.tab('النتائج');
    await s.includes('50,844.50');
    await s.screenshot('independent-results');
    await s.tab('الكميات');
    await input(2, '١٧٠');
    await calculate('52,354.50');
    await lengths([150, 95, 170], true);
    await s.tab('الكميات');
    await input(1, '');
    await calculate('47,690.00');
    await s.includes('حصر جزئي');
    await s.includes('مباني تحت الكتينة');
    await s.tab('الكميات');
    await input(1, '٠');
    await lengths([150, 0, 170]);
    await press('غير مطلوب مباني فوق الكتينة');
    await input(0, '151');
    await s.open(true);
    await lengths([151, 0, 170]);
    assert.ok((await project()).works.find(w => w.kind === 'aboveMasonry').explicitlyExcluded);
    await calculate('22,166.80');
  } catch (error) {
    console.error('Masonry verification screen:', await s.snapshot().catch(() => 'unavailable'));
    await s.screenshot('masonry-failure').catch(() => {});
    throw error;
  } finally {
    await s.context.close();
  }

  // A raw storage export from the previous released app, captured after issuing
  // an estimate with three 130 m lengths and changing only its beam to 150 m.
  if (process.env.HASR_V33_WEB_FIXTURE) {
    const m = await session(browser);
    const raw = fs.readFileSync(process.env.HASR_V33_WEB_FIXTURE, 'utf8');
    try {
      await m.context.addInitScript(value => {
        if (!localStorage.getItem('hasr_project_state_v3')) localStorage.setItem('hasr_project_state_v3', value);
      }, raw);
      await m.open();
      const getJob = async () => {
        const state = await m.getState();
        return state.projects.find(p => p.id === state.currentProjectId);
      };
      const works = (await getJob()).works;
      assert.deepEqual(kinds.map(k => works.find(w => w.kind === k).quantity), [150,130,130]);
      assert.equal(works.filter(w => w.needsLengthReview).length, 2);
      assert.equal(await m.page.evaluate(()=>localStorage.getItem('hasr_project_state_v3')), raw);
      const issued = (await getJob()).calculatedProject;
      assert.deepEqual(kinds.map(k => issued.works.find(w => w.kind === k).quantity), [130,130,130]);
      await m.enter(m.textbox(/^طول مباني تحت الكتينة/), '95');
      await m.open(true);
      const reviewed = (await getJob()).works;
      assert.ok(!reviewed.find(w => w.kind === 'belowMasonry').needsLengthReview);
      assert.ok(reviewed.find(w => w.kind === 'aboveMasonry').needsLengthReview);
      await (await m.seek(m.button('اعتماد الطول'))).press('Enter');
      await m.open(true);
      const accepted = (await getJob()).works;
      assert.ok(accepted.every(w => !w.needsLengthReview));
      assert.deepEqual(kinds.map(k => accepted.find(w => w.kind === k).quantity), [150,95,130]);
    } finally { await m.context.close(); }
  }
  return pdf;
};
