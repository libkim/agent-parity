import puppeteer from 'puppeteer-core';
const EXE=process.env.CHROME||'chromium';
const dir=process.cwd(); const fs=await import('fs');
const b=await puppeteer.launch({executablePath:EXE,headless:true,
  args:['--no-sandbox','--force-color-profile=srgb','--hide-scrollbars','--disable-gpu','--font-render-hinting=none']});
for(const theme of ['dark','light']){
  const p=await b.newPage();
  await p.setViewport({width:1000,height:560,deviceScaleFactor:1.5});
  await p.evaluateOnNewDocument(()=>{window.__capture=true;});
  await p.goto('file://'+dir+'/sceneB2.html',{waitUntil:'load'});
  await p.evaluate(th=>{document.body.className=th;},theme);
  await p.evaluate(async()=>{await document.fonts.ready;});
  await new Promise(r=>setTimeout(r,300));
  const meta=await p.evaluate(()=>window.__meta);
  fs.mkdirSync(`${dir}/frB_${theme}`,{recursive:true});
  const stage=await p.$('#stage');
  for(let f=0;f<meta.frames;f++){
    await p.evaluate(t=>window.__render(t),f/meta.FPS);
    await stage.screenshot({path:`${dir}/frB_${theme}/f${String(f).padStart(4,'0')}.png`});
  }
  await p.close(); console.log(theme,'frames',meta.frames);
}
await b.close();