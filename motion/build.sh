#!/usr/bin/env bash
# Rebuild the README hero demo (assets/demo-{dark,light}.{mp4,gif}) from source.
# One command, deterministic: render(t) is a pure function of time.
#
#   ./build.sh            # renders both themes -> ../assets
#   A=/tmp/out ./build.sh # override output dir
#
# Requires: node, ffmpeg, and a Chromium at $CHROME (see render_icon.mjs /
# captureB2.mjs). puppeteer-core is installed here on first run.
set -euo pipefail
cd "$(dirname "$0")"
A="${A:-$(cd .. && pwd)/assets}"
# Locate a Chromium (override with CHROME=/path). No machine-specific path is stored.
export CHROME="${CHROME:-$(ls -d "$HOME"/.cache/puppeteer/chrome/*/chrome-linux64/chrome 2>/dev/null | sort -V | tail -1)}"
[ -n "$CHROME" ] || { echo "set CHROME=/path/to/chromium (e.g. npx puppeteer browsers install chrome)"; exit 1; }

[ -d node_modules/puppeteer-core ] || { echo "installing puppeteer-core…"; npm install puppeteer-core@23 >/dev/null 2>&1; }

echo "1/4 app icon"      ; node render_icon.mjs
echo "2/4 scene"         ; node generate2.cjs
echo "     swap"         ; node swap.cjs
# captureB2_icon.mjs is derived from captureB2.mjs (scene + frame-dir names).
sed 's/sceneB2\.html/sceneB2_icon.html/; s/frB_/frI_/g' captureB2.mjs > captureB2_icon.mjs
echo "3/4 capture (276x2 frames, ~90s)…"
rm -rf frI_dark frI_light
node captureB2_icon.mjs
echo "4/4 encode -> $A"
for th in dark light; do
  ffmpeg -y -framerate 24 -i "frI_${th}/f%04d.png" -c:v libx264 -pix_fmt yuv420p -crf 16 -movflags +faststart "$A/demo-${th}.mp4" >/dev/null 2>&1
  ffmpeg -y -framerate 24 -i "frI_${th}/f%04d.png" -vf "fps=20,scale=900:-1:flags=lanczos,palettegen=stats_mode=diff" "/tmp/pal_${th}.png" >/dev/null 2>&1
  ffmpeg -y -framerate 24 -i "frI_${th}/f%04d.png" -i "/tmp/pal_${th}.png" -lavfi "fps=20,scale=900:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" "$A/demo-${th}.gif" >/dev/null 2>&1
  rm -f "/tmp/pal_${th}.png"
  echo "   demo-${th}.mp4 + demo-${th}.gif"
done
echo "done."
