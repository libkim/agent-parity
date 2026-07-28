const fs=require('fs'); const d=__dirname;
let h=fs.readFileSync(d+'/scene2.html','utf8');
const pathEl=fs.readFileSync(d+'/logo.svg','utf8').match(/<path[\s\S]*?\/>/)[0].replace(/fill="[^"]*"/,'fill="currentColor"');
const script=fs.readFileSync(d+'/newscript.js','utf8');

// tone: re-base neutrals zinc(cool) -> stone(warm) to match the warm app icon + stone brand (one temperature per layer)
[['#09090b','#0c0a09'],['#0d0d11','#100e0c'],['#141418','#1a1714'],['#fafafa','#faf9f7'],
 ['#a1a1aa','#a8a29e'],['#27272a','#292524'],['#3f3f46','#44403c'],
 ['#fbfbfd','#faf9f6'],['#f3f3f6','#f1eee9'],['#71717a','#78716c'],['#e4e4e7','#e7e5e4'],['#d4d4d8','#d6d3d1'],
 ['#818cf8','#d9a441'],['#6366f1','#a9781e']            // accent indigo -> warm amber
].forEach(([a,b])=>{h=h.split(a).join(b);});
h=h.split('--card:#ffffff').join('--card:#fffdf9');   // light card -> warm white
h=h.split('rgba(16,24,40').join('rgba(40,34,26');      // light shadow -> warm
h=h.split('rgba(129,140,248,.14)').join('rgba(217,164,65,.15)'); // accent-soft dark -> amber
h=h.split('rgba(99,102,241,.10)').join('rgba(169,120,30,.12)');  // accent-soft light -> amber

// --sym vars (dark brighter+neutral, light brand tone)
h=h.replace('--ok:#4ade80; --grid:rgba(255,255,255,.032);','--ok:#4ade80; --grid:rgba(255,255,255,.032); --sym:#e6e6e6; --pill:#24201b;');
h=h.replace('--ok:#16a34a; --grid:rgba(9,9,11,.04);','--ok:#16a34a; --grid:rgba(9,9,11,.04); --sym:#2B2B2B; --pill:#f2efe7;');
// accent used only on small elements (icons/highlights, ~10%); pill fill -> neutral surface
h=h.split('.pill{background:var(--accent-soft)').join('.pill{background:var(--pill)');
// empty slot left-align
h=h.replace('.slot.empty{border:1px dashed var(--border-strong);color:var(--muted);justify-content:center}',
            '.slot.empty{border:1px dashed var(--border-strong);color:var(--muted);justify-content:flex-start}');
// hub CSS: no box + symbol + soft glow + expanding FILLED discs (surface)
h=h.replace(/\.hub\{position:absolute[\s\S]*?\.hub \.sub\{[^}]*\}/,
  ".hub{position:absolute;left:50%;bottom:128px;z-index:5;transform:translateX(-50%);opacity:0;text-align:center;will-change:transform,opacity;color:var(--sym)}\n"+
  "  .hub .sym{position:relative;z-index:2;height:92px;display:inline-block}\n"+
  "  .hub .sym-glow{position:absolute;left:50%;top:50%;width:420px;height:420px;transform:translate(-50%,-50%);border-radius:50%;background:radial-gradient(circle,var(--accent-soft),transparent 58%);opacity:0;z-index:0;pointer-events:none}\n"+
  "  .hub .emit{position:absolute;left:50%;top:50%;width:0;height:0;z-index:1;pointer-events:none}\n"+
  "  .hub .disc{position:absolute;left:0;top:0;width:175px;height:175px;margin:-87px 0 0 -87px;background:var(--accent-soft);border-radius:50%;opacity:0}");
// cmd move down for taller cards
h=h.replace('.cmd{position:absolute;left:50%;top:256px;','.cmd{position:absolute;left:50%;bottom:64px;z-index:20;');
// hub HTML -> glow + emit discs + symbol
h=h.replace(/<div class="hub" id="hub">[\s\S]*?<\/div>\s*<\/div>/,
  '<div class="hub" id="hub"><div class="sym-glow" id="symglow"></div><div class="emit"><span class="disc" id="disc0"></span><span class="disc" id="disc1"></span></div><svg class="sym" id="sym" viewBox="370 10 1870 1960" fill="currentColor" xmlns="http://www.w3.org/2000/svg">'+pathEl+'</svg></div>');
// caption: not memory-only anymore
h=h.replace('<div class="cap" id="cap0">A memory you add in <b>one agent</b>…</div>',
            '<div class="cap" id="cap0">What you set up in <b>one agent</b>…</div>');
// replace script
h=h.replace(/<script>[\s\S]*<\/script>/, '<script>\n'+script+'\n</script>');

fs.writeFileSync(d+'/sceneB2.html',h);
console.log(JSON.stringify({
  symDark:h.includes('--sym:#e6e6e6;'), leftAlign:h.includes('justify-content:flex-start}'),
  discCss:h.includes('.hub .disc{'), discs:(h.match(/class="disc"/g)||[]).length,
  noSerif:!h.includes('PT+Serif')&&!h.includes("'PT Serif'"), cap0:h.includes('What you set up in'),
  pillMemory:h.includes('>memory</span>'), pillSkills:h.includes('>skills</span>'), emptySkills:h.includes('no shared skills')
}));