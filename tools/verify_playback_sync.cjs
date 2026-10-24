// Run against a web release built with tools/playback_sync_probe.dart.
const {chromium,webkit,devices}=require(process.env.MBN_PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(process.env.MBN_QA_WEB_ROOT||'build/web');
const mime={'.html':'text/html','.js':'application/javascript','.json':'application/json',
  '.wasm':'application/wasm','.css':'text/css','.ttf':'font/ttf','.otf':'font/otf',
  '.png':'image/png','.svg':'image/svg+xml'};
(async()=>{
 for(const engine of ['chromium','webkit']){
  const browser=engine==='chromium'
    ?await chromium.launch({headless:true,...(process.env.MBN_QA_CHROME_CHANNEL?{channel:process.env.MBN_QA_CHROME_CHANNEL}:{})})
    :await webkit.launch({headless:true});
  try{
   const context=await browser.newContext({ignoreHTTPSErrors:true,...(engine==='webkit'?devices['iPhone 13']:{viewport:{width:1366,height:768},userAgent:'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'})});
   if(engine==='chromium')await context.addInitScript(()=>Object.defineProperty(navigator,'userAgentData',{get:()=>({platform:'Windows',brands:[{brand:'Google Chrome',version:'140'}]})}));
   if(engine==='webkit')await context.addInitScript(()=>Object.defineProperty(navigator,'standalone',{get:()=>true}));
   const page=await context.newPage(),errors=[],apiRequests=[],partyRequests=[],partyTimes=[];
   const recordApi=request=>{
    const pathname=new URL(request).pathname;
    // Party uses its own client; offline retries keep the solo cadence even
    // if a slower browser takes longer to initialize the player.
    (pathname.startsWith('/api/party/')?partyRequests:apiRequests).push(pathname);
    if(pathname.startsWith('/api/party/'))partyTimes.push(Date.now());
   };
   page.on('pageerror',e=>{errors.push(e.message);console.log(engine,'PAGEERROR',e.message);});
   page.on('console',m=>{if(m.type()==='error')console.log(engine,'CONSOLE',m.text());});
   page.on('crash',()=>console.log(engine,'CRASH'));
   console.log(engine,'launch');
   await page.route('https://localhost:8768/**',async route=>{
    const url=new URL(route.request().url());
    if(url.pathname==='/mbn-compatibility.mp4')return route.continue();
    if(url.pathname.startsWith('/api/')){recordApi(url.href);return route.abort('connectionrefused');}
    const pathname=url.pathname;
    const rel=decodeURIComponent(pathname==='/'?'/index.html':pathname);
    const filename=path.resolve(root,'.'+rel);
    assert(filename.startsWith(root+path.sep));
    if(!fs.existsSync(filename))return route.fulfill({status:404,body:''});
    await route.fulfill({path:filename,contentType:mime[path.extname(filename)]||'application/octet-stream'});
   });
   await page.route(/https:\/\/[^/]*mbnpro\.ir\/api\//,route=>{recordApi(route.request().url());return route.abort('connectionrefused');});
   await page.goto('https://localhost:8768/',{waitUntil:'domcontentloaded'});
   console.log(engine,'loaded');
   await page.waitForFunction(()=>typeof window.mbnQaStats==='function',null,{timeout:60000});
   await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
   await page.waitForFunction(()=>document.querySelector('video'),null,{timeout:30000});
   await page.waitForFunction(()=>document.querySelector('video').currentSrc,null,{timeout:30000});
   const playback=await page.evaluate(async()=>{const v=document.querySelector('video');v.muted=true;
    try{await v.play();return {ok:true};}catch(e){return {ok:false,error:String(e),
      h264:v.canPlayType('video/mp4; codecs="avc1.640032, mp4a.40.2"'),
      mediaError:v.error?.code,src:v.currentSrc,readyState:v.readyState};}});
   assert(playback.ok,JSON.stringify(playback));
   await page.waitForFunction(()=>{const v=document.querySelector('video');return v.currentTime>1&&v.videoHeight===1440;},null,{timeout:30000});
   assert.equal(JSON.parse(await page.evaluate(()=>mbnQaStats())).offline,true);
   await page.evaluate(()=>{
    window.qaGaps=[];window.qaSampling=true;let last=performance.now();
    function tick(now){window.qaGaps.push(now-last);last=now;if(window.qaSampling)requestAnimationFrame(tick);}
    requestAnimationFrame(tick);window.mbnQaFlood();
   });
   // Real episode controls must remain responsive while sync is blocked.
   const button=page.getByRole('button',{name:/انتخاب قسمت/}).first();
   if(!await button.isVisible())await page.mouse.click(180,180);
   const start=Date.now();
   if(engine==='webkit'){
    await button.waitFor();const box=await button.boundingBox();
    await page.touchscreen.tap(box.x+box.width/2,box.y+box.height/2);
   }else await button.click();
   await page.getByRole('button',{name:/قسمت 1 در حال پخش/}).first().waitFor();
   const episodeSheetMs=Date.now()-start;
   const before=await page.evaluate(()=>document.querySelector('video').currentTime);
   await page.waitForTimeout(6000);
   const result=await page.evaluate(()=>{
    window.qaSampling=false;const v=document.querySelector('video'),q=v.getVideoPlaybackQuality?.();
    const gaps=window.qaGaps.slice().sort((a,b)=>a-b);
    return {position:v.currentTime,width:v.videoWidth,height:v.videoHeight,
      totalFrames:q?.totalVideoFrames,droppedFrames:q?.droppedVideoFrames,
      rafP99Ms:gaps[Math.floor(gaps.length*.99)],maxRafGapMs:Math.max(...gaps),
      sync:JSON.parse(mbnQaStats())};
   });
   console.log(JSON.stringify({engine,episodeSheetMs,apiRequests,partyRequests,...result}));
   assert(result.position>before+4,'video advances while sheet is open');
   assert(result.droppedFrames===undefined||result.droppedFrames<=Math.max(3,result.totalFrames*.03),'no sustained video frame loss');
   assert.equal(result.sync.remoteApplied,false);
   assert.equal(result.sync.requests,1,'bulk requests stay deferred during playback');
   assert.equal(apiRequests.length,0,'offline MP4 playback never needs the bridge');
   for(let i=1;i<partyTimes.length;i++)assert(partyTimes[i]-partyTimes[i-1]>=44000,
    'offline Party retries never exceed the solo playback cadence');
   assert(partyRequests.every(p=>p==='/api/party/bootstrap'),'solo playback never sends Party commands');
   assert.equal(errors.length,0,errors.join('\n'));
   assert(episodeSheetMs<2000,'episode sheet stays responsive');
   await context.close();
  }finally{await browser.close();}
 }
})().catch(e=>{console.error(e);process.exitCode=1;});
