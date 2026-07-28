import puppeteer from 'puppeteer-core'; import fs from 'fs';
const EXE=process.env.CHROME||'chromium';
const A=process.env.ASSETS_DIR||'../assets';
const svg=fs.readFileSync(`${A}/frame-2.svg`,'utf8')
  .replace('<svg ','<svg style="width:100%;height:auto;display:block" ')
  .replace(/fill="black"/g,'fill="#1c1917"');
const S=1024, BODY=812, R=Math.round(BODY*0.2237), LOGO=BODY;
const html=`<body style="margin:0;width:${S}px;height:${S}px;display:flex;align-items:center;justify-content:center">
  <div style="width:${BODY}px;height:${BODY}px;background:#faf8f2;border-radius:${R}px;border:6px solid rgba(45,38,26,.12);
       box-shadow:0 1px 2px rgba(28,26,22,.05), 0 4px 10px rgba(28,26,22,.05), 0 12px 24px rgba(28,26,22,.06), 0 28px 56px rgba(28,26,22,.06);
       display:flex;align-items:center;justify-content:center">
    <div style="width:${LOGO}px">${svg}</div>
  </div></body>`;
const b=await puppeteer.launch({executablePath:EXE,headless:true,args:['--no-sandbox','--disable-gpu']});
const p=await b.newPage(); await p.setViewport({width:S,height:S,deviceScaleFactor:1});
await p.setContent(html,{waitUntil:'load'}); await new Promise(r=>setTimeout(r,200));
await p.screenshot({path:`${process.cwd()}/app-icon.png`, omitBackground:true});
console.log('rendered app-icon.png',S);
const S2=BODY+12;
const htmlV=`<body style="margin:0;width:${S2}px;height:${S2}px">
  <div style="width:${BODY}px;height:${BODY}px;background:#faf8f2;border-radius:${R}px;border:6px solid rgba(45,38,26,.12);
       display:flex;align-items:center;justify-content:center">
    <div style="width:${LOGO}px">${svg}</div>
  </div></body>`;
const p2=await b.newPage(); await p2.setViewport({width:S2,height:S2,deviceScaleFactor:1});
await p2.setContent(htmlV,{waitUntil:'load'}); await new Promise(r=>setTimeout(r,200));
await p2.screenshot({path:`${process.cwd()}/app-icon-video.png`, omitBackground:true});
console.log('rendered app-icon-video.png',S2);
await b.close();
