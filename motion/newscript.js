const FPS=24, DUR=12.8;
const AGENTS=[
  {name:'Claude Code', c:'#d97757'},
  {name:'Codex',       c:'#10a37f'},
  {name:'Cursor',      c:'#8b8b94'},
  {name:'Antigravity', c:'#a855f7'},
];
const MI='<svg class="mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/></svg>';
const MI2='<svg class="mi" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l2.2 5.8L20 11l-5.8 2.2L12 19l-2.2-5.8L4 11l5.8-2.2z"/></svg>';

const wrap=document.getElementById('agents');
AGENTS.forEach((a,i)=>{
  const el=document.createElement('div'); el.className='card'; el.id='card'+i;
  el.innerHTML=`<div class="chead"><span class="dot" style="background:${a.c}"></span><span class="cname">${a.name}</span></div>
  <div class="slotwrap">
    <div class="slot empty" id="empty${i}m">no shared memory</div>
    <div class="slot pill" id="pill${i}m">${MI}<span class="txt">memory</span><span class="tick" id="tick${i}m">✓</span></div>
  </div>
  <div class="slotwrap">
    <div class="slot empty" id="empty${i}s">no shared skills</div>
    <div class="slot pill" id="pill${i}s">${MI2}<span class="txt">skills</span><span class="tick" id="tick${i}s">✓</span></div>
  </div>`;
  wrap.appendChild(el);
});

const E={
  out:t=>1-Math.pow(1-t,3),               // ease-out (enter)
  expo:t=>t>=1?1:1-Math.pow(2,-10*t),     // strong ease-out
  in:t=>t*t,                              // ease-in (exit, accelerate)
  // damped spring (ζ=0.66 → subtle ~6% overshoot, one gentle settle); natural for spatial moves
  spring:t=>{if(t>=1)return 1;const z=0.66,w=7.5,wd=w*Math.sqrt(1-z*z);return 1-Math.exp(-z*w*t)*(Math.cos(wd*t)+(z*w/wd)*Math.sin(wd*t));},
};
function seg(t,a,b,e){e=e||E.out;let u=(t-a)/(b-a);u=u<0?0:u>1?1:u;return e(u);}
const $=id=>document.getElementById(id);
const op=(id,v)=>{const e=$(id);if(e)e.style.opacity=v;};
const tf=(id,v)=>{const e=$(id);if(e)e.style.transform=v;};

function render(t){
  // 1) cards stagger in
  AGENTS.forEach((a,i)=>{const s=seg(t,0.3+i*0.09,1.15+i*0.09);op('card'+i,s);tf('card'+i,`translateY(${(1-s)*16}px)`);});

  // 2) Claude Code gets memory, then skills
  const dropM=seg(t,1.35,2.15,E.expo);
  op('pill0m',dropM); tf('pill0m',`translateY(${(1-dropM)*-12}px) scale(${.95+.05*dropM})`);
  op('empty0m',1-seg(t,1.35,1.75));
  const dropS=seg(t,1.7,2.5,E.expo);
  op('pill0s',dropS); tf('pill0s',`translateY(${(1-dropS)*-12}px) scale(${.95+.05*dropS})`);
  op('empty0s',1-seg(t,1.7,2.1));
  op('tick0m',seg(t,2.2,2.5));
  op('tick0s',seg(t,2.55,2.85));

  // 3) captions cross-fade
  op('cap0',seg(t,1.0,1.5)-seg(t,2.9,3.4));
  op('cap1',seg(t,3.0,3.5)-seg(t,6.6,7.1));
  op('cap2',seg(t,8.1,8.6)-seg(t,10.7,11.2));

  // 4) command box (low) types, ✓ installs, HOLDS ~0.5s to let it land, then slides DOWN out
  const cmdIn=seg(t,3.2,3.6);
  const cmdExit=seg(t,6.1,6.7,E.in);
  op('cmd', cmdIn*(1-cmdExit));
  tf('cmd', `translateX(-50%) translateY(${cmdExit*110}px)`);
  const full='curl -fsSL …/install.sh | sh';
  const n=Math.floor(seg(t,3.4,4.6,x=>x)*full.length);
  $('cmdt').textContent=' '+full.slice(0,n);
  op('cur', (n>=full.length||cmdExit>0)?0:(Math.floor(t*2)%2?0.3:1));
  op('cmddone', seg(t,4.7,5.0)*(1-cmdExit));

  // 5) app icon INSTALLS — after the command lands, rises from below (spring), behind the box
  const rise=seg(t,5.5,6.1,E.spring);
  op('hub', seg(t,5.5,5.85));
  tf('hub', `translateX(-50%) translateY(${(1-rise)*200}px) scale(${.985+.015*Math.min(1,rise)})`);

  // 5b) LOGO EMIT — after the icon settles (~0.4s hold): soft glow + expanding filled discs
  const bloom=seg(t,6.6,7.0)-seg(t,7.2,7.7);
  op('symglow',0.78*bloom);
  const pulse=1+0.03*(seg(t,6.65,6.9)-seg(t,6.9,7.2));
  tf('sym',`scale(${pulse})`);
  for(let i=0;i<2;i++){
    const t0=6.7+i*0.16;
    const app=seg(t,t0,t0+0.15)-seg(t,t0+0.2,t0+0.9);
    op('disc'+i,0.45*app);
    tf('disc'+i,`scale(${0.7+2.0*seg(t,t0,t0+0.9,E.out)})`);
  }

  // 6) propagate to the other three — ORIGINAL per-agent cascade (each agent lights up
  //    memory + skills together), only paced differently: 0.34s stagger (was 0.18) and
  //    preceded by an anticipation beat (~7.6-7.95) so it reads instead of rushing
  for(let i=1;i<4;i++){
    const b=7.95+(i-1)*0.34;
    op('empty'+i+'m',1-seg(t,b-0.2,b+0.15));
    const pM=seg(t,b,b+0.7,E.expo);
    op('pill'+i+'m',pM); tf('pill'+i+'m',`scale(${.9+.1*pM})`);
    op('tick'+i+'m',seg(t,b+0.8,b+1.15));
    op('empty'+i+'s',1-seg(t,b-0.05,b+0.3));
    const pS=seg(t,b+0.15,b+0.85,E.expo);
    op('pill'+i+'s',pS); tf('pill'+i+'s',`scale(${.9+.1*pS})`);
    op('tick'+i+'s',seg(t,b+0.95,b+1.3));
  }

  // 7) hold on the settled system (~0.5s), then fade to payoff
  const out=seg(t,10.5,11.3);
  op('system',1-out);
  const pay=seg(t,10.9,11.7,E.expo);
  op('payoff',pay); tf('payoff',`translateY(${(1-pay)*12}px)`);
}
window.__render=render;
window.__meta={FPS,DUR,frames:Math.round(FPS*DUR)};
if(!window.__capture){let st=null;(function loop(ts){if(st===null)st=ts;render(((ts-st)/1000)%DUR);requestAnimationFrame(loop);})(performance.now());}
