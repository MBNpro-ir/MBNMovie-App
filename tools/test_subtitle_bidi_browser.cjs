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
    assert(caseCount>=20,'expected the shared subtitle fixtures');
    let checked=0;
    for(const font of ['Vazirmatn','NotoSansArabic','NotoNaskhArabic','MarkaziText']) {
      for(const width of [760,260]) for(const rtl of [true,false]) {
        for(let index=0;index<caseCount;index++) {
          await page.evaluate(({index,width,rtl,font})=>mbnSubtitleSet(index,width,rtl,font),{index,width,rtl,font});
          const handle=await page.waitForFunction(({index,width,font})=>{
            const state=JSON.parse(mbnSubtitleState());
            return state.pairs&&state.id===mbnSubtitleId(index)&&Math.abs(state.width-width)<1&&state.font===font&&state;
          },{index,width,font},{timeout:5000});
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
    for(let index=0;index<caseCount;index++) {
      const id=await page.evaluate(index=>mbnSubtitleId(index),index);
      if(!['house-dialogue','house-multiple-acronyms','house-number'].includes(id)) continue;
      // Capture a fresh canvas: the rapid layout matrix can leave the browser
      // compositor behind the paragraph state even after the layout settles.
      const shot=await context.newPage();
      shot.on('pageerror',error=>errors.push(error.message));
      await shot.goto(process.env.MBN_SUBTITLE_PROBE_URL||'http://127.0.0.1:8771/');
      await shot.waitForFunction(()=>window.mbnSubtitleState&&JSON.parse(mbnSubtitleState()).pairs,null,{timeout:60000});
      await shot.evaluate(index=>mbnSubtitleSet(index,760,true,'Vazirmatn'),index);
      await shot.waitForFunction(id=>JSON.parse(mbnSubtitleState()).id===id,id,{timeout:5000});
      await shot.waitForTimeout(1500);
      await shot.screenshot({path:`build/subtitle-${id}-${engine}.png`,clip:{x:0,y:340,width:900,height:220}});
      await shot.close();
    }
    assert.deepEqual(errors,[]);
    console.log(`${engine}: ${checked} production subtitle layouts PASS (four fonts, RTL/LTR surroundings, wide/wrapped lines, punctuation, numbers and presentation forms)`);
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
