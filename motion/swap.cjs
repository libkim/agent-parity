// Swap the inline logo <svg> in sceneB2.html for the video app-icon (no baked
// shadow) and apply the shared card --shadow token, producing sceneB2_icon.html.
const fs = require('fs');
let h = fs.readFileSync(__dirname + '/sceneB2.html', 'utf8');
h = h.replace(/<svg class="sym" id="sym"[\s\S]*?<\/svg>/, `<img class="sym" id="sym" src="app-icon-video.png" alt="">`);
h = h.replace(/\.hub \.sym\{[^}]*\}/, '.hub .sym{position:relative;z-index:2;height:120px;width:auto;display:inline-block;border-radius:22%;box-shadow:var(--shadow)}');
fs.writeFileSync(__dirname + '/sceneB2_icon.html', h);
console.log('swap: img', h.includes('app-icon-video.png'), '| card-shadow', h.includes('box-shadow:var(--shadow)}'));
