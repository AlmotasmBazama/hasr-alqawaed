const assert = require('node:assert/strict');

module.exports = async function checkHelp(browser, session, logFailures, errors) {
  const s = await session(browser, {
    viewport: { width: 1280, height: 900 },
    hasTouch: true,
    acceptDownloads: true,
  });
  logFailures(s.page, errors);
  const storageKey = 'hasr_project_state_v4';
  const state = () => s.page.evaluate(key => ({
    saved: localStorage.getItem(key),
    writes: window.projectWriteCount,
  }), storageKey);

  async function help(title, expected, { touch = false } = {}) {
    const opener = await s.seek(s.button('مساعدة حول ' + title));
    const before = await state();
    assert.equal(await s.button('فهمت').count(), 0);
    if (touch) await opener.tap();
    else await opener.press('Enter');
    const card = s.page.getByRole('alertdialog');
    await card.waitFor();
    const contents = await card.ariaSnapshot();
    for (const phrase of expected) assert.ok(contents.includes(phrase), contents);
    const dismiss = card.getByRole('button', { name: 'فهمت', exact: true });
    if (touch) {
      await s.screenshot('mobile-help');
      await dismiss.tap();
    }
    else await dismiss.press('Enter');
    await card.waitFor({ state: 'detached' });
    assert.deepEqual(await state(), before, 'Opening help must leave the project and write count intact');
  }

  try {
    await s.context.addInitScript(key => {
      window.projectWriteCount = 0;
      const save = Storage.prototype.setItem;
      Storage.prototype.setItem = function (name, value) {
        if (this === localStorage && name === key) window.projectWriteCount++;
        return save.call(this, name, value);
      };
    }, storageKey);
    await s.open();
    assert.ok(!(await s.snapshot()).includes('أدخل عددًا صحيحًا غير سالب.'));
    await s.addSample(true);
    await s.button('احسب المشروع').press('Enter');
    await s.includes('147,931.70');
    await s.tab('الكميات');
    await help('طول الميدة', ['طول الميدة', 'حسب مخطط المشروع']);
    await help('طول مباني تحت الكتينة', ['أدخل مجموع أطوال المباني تحت الكتينة بالمتر حسب المخطط.']);
    await help('طول مباني فوق الكتينة', ['أدخل مجموع أطوال المباني فوق الكتينة بالمتر حسب المخطط.']);
    const project = await s.getState();
    assert.equal(project.projects.find(p => p.id === project.currentProjectId).calculationStale, false);

    await help('إجمالي أطوال كمرات السقف', ['مستقلة عن طول الميدة']);
    await s.scroll(-3200);
    const input = s.textbox(/^طول مباني فوق الكتينة/);
    await s.enter(input, '١٧٠٫٥');
    await help('طول مباني فوق الكتينة', ['أدخل مجموع أطوال المباني فوق الكتينة بالمتر حسب المخطط.']);
    // Returning from help preserves the user's original Arabic edit buffer.
    await input.focus();
    await s.page.waitForFunction(() => {
      let editor = document.activeElement;
      while (editor?.shadowRoot?.activeElement) editor = editor.shadowRoot.activeElement;
      return editor?.value === '١٧٠٫٥';
    });
    await s.tab('النتائج');
    await s.includes('تغيّرت المدخلات. حدّث الحسبة لإظهار النتائج الجديدة.');
    assert.equal(await s.button(/^(مشاركة|تنزيل) التقرير PDF$/).count(), 0);

    await s.tab('الأسعار والربح');
    await help('الأسعار المشتركة', ['تخص هذه الأسعار المشروع الحالي']);
    await help('سعر حديد قطر 14', ['يحوّل التطبيق كمية الحديد حسب معاملات النموذج المختار']);
    await s.includes('د.ل / قنطار');
    await s.page.setViewportSize({ width: 320, height: 640 });
    await s.open(true);
    await s.tab('الأسعار والربح');
    await help('نسبة الربح على التكلفة', [
      'تُضاف هذه النسبة مرة واحدة',
      'تكلفة 1,000 د.ل وربح 10% تعطي إجمالي عرض 1,100 د.ل.',
    ], { touch: true });
    await s.tab('النتائج');
    await s.button('تحديث الحسبة').press('Enter');
    await s.includes('154,047.20');
    await s.download('help-quotation');
    await s.tab('الكميات');
    await (await s.seek(s.button('غير مطلوب مباني تحت الكتينة'))).press('Enter');
    assert.ok((await s.getState()).projects.find(p => p.id === project.currentProjectId)
      .works.find(w => w.kind === 'belowMasonry').explicitlyExcluded);
  } catch (error) {
    console.error('Help verification screen:', await s.snapshot().catch(() => 'unavailable'));
    await s.screenshot('help-failure').catch(() => {});
    throw error;
  } finally {
    await s.context.close();
  }
};
