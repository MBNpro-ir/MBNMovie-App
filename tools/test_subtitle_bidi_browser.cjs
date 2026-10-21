// Build --target=tools/subtitle_bidi_probe.dart --output=build/subtitle-bidi-probe
// and serve that directory on MBN_SUBTITLE_PROBE_URL before running.
const {webkit,chromium,devices}=require(process.env.MBN_PLAYWRIGHT_PATH);
const assert=require('node:assert/strict');
(async()=>{
  const engine=process.env.MBN_BROWSER_ENGINE||'webkit';
  const browser=engine==='chrome'
    ? await chromium.launch({headless:true,channel:'chrome'})
    : await webkit.launch({headless:true,executablePath:process.env.MBN_WEBKIT_EXECUTABLE});
  try {
    const context=await browser.newContext({...devices['iPhone 11 Pro'],viewport:{width:900,height:900}});
    await context.addInitScript(()=>Object.defineProperty(navigator,'standalone',{get:()=>true}));
    const page=await context.newPage(),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    await page.goto(process.env.MBN_SUBTITLE_PROBE_URL||'http://127.0.0.1:8771/');
    await page.waitForFunction(()=>window.mbnSubtitleState&&JSON.parse(mbnSubtitleState()).pairs,null,{timeout:60000});
    const caseCount=await page.evaluate(()=>window.mbnSubtitleCount);
    assert(caseCount>=15,'expected the shared subtitle fixtures');
    let checked=0;
    for(const font of ['Vazirmatn','NotoSansArabic','NotoNaskhArabic','MarkaziText']) {
      for(const width of [760,260]) for(const rtl of [true,false]) {
        for(let index=0;index<caseCount;index++) {
          await page.evaluate(({index,width,rtl,font})=>mbnSubtitleSet(index,width,rtl,font),{index,width,rtl,font});
          const handle=await page.waitForFunction(({width,font})=>{
            const state=JSON.parse(mbnSubtitleState());
            return state.pairs&&Math.abs(state.width-width)<1&&state.font===font&&state;
          },{width,font},{timeout:5000});
          const state=await handle.jsonValue();
          for(const pair of state.pairs) {
            const {a,b}=pair;
            const correct=Math.abs(a.y-b.y)>1?a.y<b.y:(pair.rtl?a.x>b.x:a.x<b.x);
            assert(correct,`${engine} ${font} width ${width} ${state.id}: ${pair.first} before ${pair.second}: ${JSON.stringify(pair)}`);
          }
          checked++;
        }
      }
    }
    await page.evaluate(()=>mbnSubtitleSet(0,760,true,'Vazirmatn'));
    await page.waitForFunction(()=>JSON.parse(mbnSubtitleState()).id==='reported-persian');
    if(engine==='chrome')await page.screenshot({path:'build/subtitle-bidi-chrome.png'});
    assert.deepEqual(errors,[]);
    console.log(`${engine}: ${checked} production subtitle layouts PASS (four fonts, RTL/LTR surroundings, wide/wrapped lines, punctuation, numbers and presentation forms)`);
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
