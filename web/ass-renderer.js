/* Local libass renderer. No worker, canvas or frame loop exists in plain mode. */
(() => {
  const base = new URL('.', document.currentScript.src);
  let loading, current, generation = 0;
  function load() {
    if (window.SubtitlesOctopus) return Promise.resolve();
    return loading ||= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('ass/subtitles-octopus.js', base);
      script.onload = resolve;
      script.onerror = () => { loading = null; script.remove(); reject(Error('ASS renderer unavailable')); };
      document.head.append(script);
    });
  }
  function clear() {
    generation++;
    if (!current) return;
    const state = current; current = null;
    state.cancel?.();
    state.observer?.disconnect();
    for (const event of state.events) state.video.removeEventListener(event, state.sync);
    window.removeEventListener('resize', state.layout);
    window.removeEventListener('scroll', state.layout, true);
    try { state.renderer?.dispose(); } finally { state.canvas.remove(); }
  }
  window.mbnAss = {
    clear,
    async show(video, content, fonts = []) {
      clear(); const id = generation;
      await load();
      if (id !== generation) return;
      const canvas = document.createElement('canvas');
      canvas.className = 'mbn-ass-canvas';
      Object.assign(canvas.style, {position:'fixed', pointerEvents:'none', zIndex:'5'});
      document.body.append(canvas);
      const state = current = {canvas, video, events:['timeupdate','playing','pause','seeking','seeked','ratechange','loadedmetadata']};
      state.layout = () => {
        if (current !== state || !state.renderer) return;
        const rect = video.getBoundingClientRect();
        if (!rect.width || !rect.height || !video.videoWidth) {canvas.style.display='none';return;}
        canvas.style.display='block';
        const cover = getComputedStyle(video).objectFit === 'cover';
        const scale = (cover ? Math.max : Math.min)(rect.width/video.videoWidth, rect.height/video.videoHeight);
        const w=video.videoWidth*scale, h=video.videoHeight*scale;
        const left=rect.left+(rect.width-w)/2, top=rect.top+(rect.height-h)/2;
        Object.assign(canvas.style,{left:left+'px',top:top+'px',width:w+'px',height:h+'px',
          clipPath:`inset(${Math.max(0,rect.top-top)}px ${Math.max(0,left+w-rect.right)}px ${Math.max(0,top+h-rect.bottom)}px ${Math.max(0,rect.left-left)}px)`});
        const ratio=Math.min(devicePixelRatio||1,2), capped=Math.min(1,1080/(h*ratio));
        const width=Math.max(1,Math.round(w*ratio*capped)), height=Math.max(1,Math.round(h*ratio*capped));
        if (canvas.width!==width || canvas.height!==height) state.renderer.resize(width,height);
      };
      state.sync = () => {
        if (current!==state || !state.renderer) return;
        state.renderer.setRate(video.playbackRate);
        state.renderer.setIsPaused(video.paused || video.ended,video.currentTime);
        state.renderer.setCurrentTime(video.currentTime);
        state.layout();
      };
      try {
        await new Promise((resolve,reject) => {
          const timer=setTimeout(()=>reject(Error('ASS worker timeout')),20000);
          state.cancel=()=>{clearTimeout(timer);resolve();};
          state.renderer=new SubtitlesOctopus({canvas,subContent:content,
            workerUrl:new URL('ass/subtitles-octopus-worker.js',base).href,
            fonts:[new URL('assets/assets/fonts/Vazirmatn-Regular.ttf',base).href,...fonts],
            fallbackFont:new URL('assets/assets/fonts/Vazirmatn-Regular.ttf',base).href,
            targetFps:24,libassMemoryLimit:24,libassGlyphLimit:8,
            onReady:()=>{clearTimeout(timer);resolve();},
            onError:e=>{clearTimeout(timer);reject(e);}});
        });
        if (current!==state) return;
        for (const event of state.events) video.addEventListener(event,state.sync);
        window.addEventListener('resize',state.layout);
        window.addEventListener('scroll',state.layout,true);
        state.observer=new ResizeObserver(state.layout); state.observer.observe(video);
        state.sync();
      } catch(e) {if (current===state) clear();throw e;}
    }
  };
})();
