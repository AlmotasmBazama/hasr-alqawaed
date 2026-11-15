// Release browser QA in isolated storage; no personal browser profile is used.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.HASR_PLAYWRIGHT_PATH || 'playwright');
const url = process.argv[2];
const prefix = process.argv[3] || 'local-v2';
if (!url) throw new Error('Usage: node scripts/check_web.cjs <url> [prefix]');
const output = path.resolve(__dirname, '..', 'output', 'web-checks');
fs.mkdirSync(output, {recursive:true});
const legacy = {
  version:1,
  customModels:[{id:'browser-legacy-model',name:'نموذج سابق محفوظ',length:1.25,width:1.4,height:.55,concretePerFoundation:1,steel14BarsPerFoundation:2,steel14BarsPerQuintal:5,steel8BarsPerFoundation:.5,steel8BarsPerQuintal:10}],
  selectedModelId:'browser-legacy-model',
  inputs:{count:10,prices:{concrete:560,steel14:520,steel8:600,carpenter:70,steelWorker:30,casting:60}},
};
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.HASR_CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 const context=await browser.newContext({viewport:{width:1280,height:900},acceptDownloads:true});
 await context.addInitScript(data=>{if(!localStorage.getItem('hasr_qa_seeded')){localStorage.setItem('hasr_alqawaed_state_v1',JSON.stringify(JSON.stringify(data)));localStorage.setItem('hasr_qa_seeded','true');}},legacy);
 const page=await context.newPage(); page.setDefaultTimeout(60000); page.setDefaultNavigationTimeout(120000);
 const errors=[],consoleErrors=[],failedRequests=[],badResponses=[];
 page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text());});
 page.on('requestfailed',r=>failedRequests.push({url:r.url(),error:r.failure()?.errorText}));
 page.on('response',r=>{if(r.status()>=400)badResponses.push({url:r.url(),status:r.status()});});
 const snapshot=()=>page.locator('body').ariaSnapshot();
 async function enable(){const trigger=page.locator('flt-semantics-placeholder');await trigger.waitFor({state:'attached',timeout:90000});await trigger.evaluate(e=>e.click());await page.getByRole('heading',{name:'حصر المشروع',exact:true}).waitFor();await page.waitForTimeout(300);}
 async function tab(name){await page.getByRole('tab',{name,exact:true}).press('Enter');await page.waitForTimeout(250);}
 async function enter(locator,value){await locator.focus();await page.waitForTimeout(150);await page.keyboard.press('Control+A');await page.keyboard.insertText(value);await page.waitForTimeout(600);}
 async function state(){return page.evaluate(()=>JSON.parse(JSON.parse(localStorage.getItem('hasr_project_state_v2'))));}
 async function download(label){await page.getByRole('button',{name:'تنزيل PDF',exact:true}).press('Enter');await page.getByRole('alertdialog').waitFor({timeout:25000});const [file]=await Promise.all([page.waitForEvent('download'),page.getByRole('alertdialog').getByRole('button',{name:'تنزيل PDF',exact:true}).press('Enter')]);assert.equal(await file.failure(),null);const dest=path.join(output,`${prefix}-${label}.pdf`);await file.saveAs(dest);assert.equal(fs.readFileSync(dest).subarray(0,5).toString(),'%PDF-');await page.getByRole('alertdialog').waitFor({state:'detached'});return dest;}
 async function top(){await page.mouse.move(180,250);await page.mouse.wheel(0,-12000);await page.waitForTimeout(350);}
 try{
  await page.goto(url,{waitUntil:'domcontentloaded'});await enable();
  let saved=await state();assert.equal(saved.projects.length,1);assert.equal(saved.projects[0].name,'مشروعي السابق');assert.equal(saved.customModels[0].id,'browser-legacy-model');assert.equal(saved.projects[0].works.filter(w=>w.included).length,1);assert.ok((await snapshot()).includes('9,580.00'));
  const original=await page.evaluate(()=>JSON.parse(localStorage.getItem('hasr_alqawaed_state_v1')));assert.deepEqual(JSON.parse(original),legacy);assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('hasr_project_v1_original_backup'))),original);
  await page.getByRole('button',{name:'اختيار مشروع',exact:true}).press('Enter');await page.getByRole('button',{name:/^إضافة «مثال الأوراق»/}).press('Enter');await page.waitForTimeout(400);
  saved=await state();const exampleId=saved.currentProjectId;assert.equal(saved.projects.length,2);assert.ok((await snapshot()).includes('86,364.20'));
  await tab('النتائج');assert.ok((await snapshot()).includes('66,656.20'));assert.ok((await snapshot()).includes('19,708.00'));assert.ok((await snapshot()).includes('السقف غير مشمول في الإجمالي'));
  await page.screenshot({path:path.join(output,`${prefix}-desktop-results.png`)});
  const examplePdf=await download('example');
  await tab('الأسعار');await enter(page.getByRole('textbox',{name:/^سعر أسمنت بالنقل/}),'٤٠');await tab('النتائج');assert.ok((await snapshot()).includes('86,026.20'));
  await page.reload({waitUntil:'domcontentloaded'});await enable();await tab('النتائج');assert.ok((await snapshot()).includes('86,026.20'));saved=await state();assert.equal(saved.projects.find(p=>p.id!==exampleId).materialPrices.cement,42);
  await tab('المشروع');await enter(page.getByRole('textbox',{name:/^كمية القواعد/}),'');await tab('النتائج');assert.ok((await snapshot()).includes('68,226.20'));assert.ok((await snapshot()).includes('القواعد: يحتاج بيانات'));
  saved=await state();assert.equal(saved.projects.find(p=>p.id===exampleId).works.find(w=>w.kind==='foundations').quantity,20);const partialPdf=await download('partial');
  await tab('المشروع');await enter(page.getByRole('textbox',{name:/^كمية القواعد/}),'٢٠');await tab('الأسعار');await enter(page.getByRole('textbox',{name:/^سعر أسمنت بالنقل/}),'42');
  await page.setViewportSize({width:360,height:740});await tab('المشروع');await top();await page.screenshot({path:path.join(output,`${prefix}-mobile-project.png`)});
  await tab('الأسعار');await top();await page.screenshot({path:path.join(output,`${prefix}-mobile-prices.png`)});
  await tab('النتائج');await top();await page.screenshot({path:path.join(output,`${prefix}-mobile-results.png`)});const mobilePdf=await download('mobile');
  await tab('المشروع');await page.getByRole('button',{name:/^الميدة نموذج/}).press('Enter');await page.getByRole('button',{name:'تعديل الثوابت',exact:true}).press('Enter');
  await enter(page.getByRole('textbox',{name:'اسم النموذج',exact:true}),'نموذج ميدة الويب');await enter(page.getByRole('textbox',{name:'الكمية لكل متر طولي',exact:true}).first(),'٠٫١');await page.getByRole('button',{name:'حفظ النموذج',exact:true}).press('Enter');await page.getByRole('heading',{name:'الميدة',exact:true}).waitFor();await page.waitForTimeout(350);
  saved=await state();const beam=saved.projects.find(p=>p.id===exampleId).works.find(w=>w.kind==='tieBeam');assert.equal(beam.model.name,'نموذج ميدة الويب');assert.equal(beam.model.rows[0].coefficient,.1);assert.equal(saved.customModels.filter(m=>m.id===beam.model.id).length,1);
  await page.reload({waitUntil:'domcontentloaded'});await enable();await tab('النتائج');assert.ok((await snapshot()).includes('87,820.20'));saved=await state();assert.equal(saved.projects.length,2);assert.equal(saved.projects[0].works[0].model.id,'browser-legacy-model');
  assert.deepEqual(errors,[]);assert.deepEqual(consoleErrors,[]);assert.deepEqual(failedRequests,[]);assert.deepEqual(badResponses,[]);
  const result={url,passed:true,examplePdf,partialPdf,mobilePdf,checks:['v1MigrationWithBackup','example86364.20','materials66656.20','services19708','cement40Gives86026.20','projectIsolation','reloadPersistence','blankQuantityPartial68226.20','savedValidDraftRetained','desktopMobilePdfDownloads','mobile360Layout','customBeamModel87820.20','roofPending'],errors,consoleErrors,failedRequests,badResponses};fs.writeFileSync(path.join(output,`${prefix}-results.json`),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }catch(error){console.log('Failure state:',await snapshot());await page.screenshot({path:path.join(output,`${prefix}-failure.png`)});fs.writeFileSync(path.join(output,`${prefix}-failure.html`),await page.content());console.log(JSON.stringify({errors,consoleErrors,failedRequests,badResponses},null,2));throw error;}finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
