const assert = require('node:assert/strict');
const fs = require('node:fs');

// Run through the same controls contractors use, in an empty browser profile.
module.exports = async function checkMasonry(browser, session, logFailures, errors) {
  const s = await session(browser);
  logFailures(s.page, errors);
  const below = 'مباني تحت الكتينة';
  const above = 'مباني فوق الكتينة';
  const beam = s.textbox(/^طول الميدة/);
  const summary = (item, length, linked) =>
    s.includes(item + ': ' + length + ' م — ' + (linked ? 'نفس طول الميدة' : 'طول مخصص'));
  const press = async name => (await s.seek(s.button(name))).press('Enter');
  async function calculate(total) {
    await press('احسب المشروع');
    await s.includes(total);
  }
  let mixedPdf;
  try {
    await s.open();
    await press('اختيار مشروع');
    await press('إنشاء مشروع جديد');
    const dialog = s.page.getByRole('alertdialog');
    await s.enter(dialog.getByRole('textbox', { name: /اسم المشروع/ }), 'تجربة ربط أطوال المباني');
    await dialog.getByRole('button', { name: 'حفظ', exact: true }).press('Enter');
    await s.enter(beam, '١٣٠');
    await summary(below, 130, true);
    await summary(above, 130, true);
    await calculate('45,097.00');
    await s.tab('الكميات');
    await s.enter(beam, '150');
    await summary(below, 150, true);
    await summary(above, 150, true);
    await press('تعديل الطول ' + above);
    await s.enter(s.textbox(/^طول مخصص مباني فوق الكتينة/), '170');
    await s.enter(beam, '160');
    await summary(below, 160, true);
    await summary(above, 170, false);
    await s.open(true);
    await summary(below, 160, true);
    await summary(above, 170, false);
    await s.tab('النتائج');
    await s.includes('الحسبة تحتاج تحديثًا');
    assert.equal(await s.button(/^(تنزيل|مشاركة) التقرير PDF$/).count(), 0);
    await press('تحديث الحسبة');
    await s.includes('57,014.00'); // 160 × 146.8 + 160 × 49.1 + 170 × 151
    await press(/^كميات المواد المطلوبة/);
    await s.includes('7,975 بلوكة');
    await press(/^كميات المواد المطلوبة/);
    mixedPdf = await s.download('masonry-160-170');
    await s.tab('الكميات');
    await s.enter(beam, '');
    await summary(above, 170, false);
    await calculate('25,670.00');
    await s.tab('الكميات');
    await s.enter(beam, '٠');
    await summary(below, 0, true);
    await summary(above, 170, false);
    await s.enter(beam, '160');
    await press('استخدام طول الميدة ' + above);
    await summary(above, 160, true);
    await press('غير مطلوب ' + below);
    await s.enter(beam, '180');
    await summary(above, 180, true);
    await s.open(true);
    await calculate('53,604.00'); // 180 × (146.8 + 151)
    await s.tab('الكميات');
    await press('إضافة للحصر ' + below);
    await summary(below, 180, true);
    await calculate('62,442.00');
  } finally {
    await s.context.close();
  }

  // Optional raw snapshot captured directly from the released 3.1 app.
  if (process.env.HASR_PREVIOUS_WEB_FIXTURE) {
    const m = await session(browser);
    logFailures(m.page, errors);
    try {
      const raw = fs.readFileSync(process.env.HASR_PREVIOUS_WEB_FIXTURE, 'utf8');
      await m.context.addInitScript(value => {
        if (!localStorage.getItem('hasr_project_state_v3')) {
          localStorage.setItem('hasr_project_state_v3', value);
        }
      }, raw);
      await m.open();
      await m.includes(below + ': 130 م — طول مخصص');
      await m.includes(above + ': 130 م — طول مخصص');
      await m.tab('النتائج');
      await m.includes('86,364.20');
      await m.tab('الكميات');
      await m.enter(m.textbox(/^طول الميدة/), '160');
      await m.includes(below + ': 130 م — طول مخصص');
      await m.includes(above + ': 130 م — طول مخصص');
      await m.button('احسب المشروع').press('Enter');
      await m.includes('90,768.20');
    } finally {
      await m.context.close();
    }
  }
  return mixedPdf;
};
