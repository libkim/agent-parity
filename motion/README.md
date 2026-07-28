# motion — README hero demo source

Source for `assets/demo-{dark,light}.{mp4,gif}` (the animated hero in the
README). Kept in-repo so the video is reproducible and never has to be
reconstructed from a chat transcript again.

## Rebuild

```sh
./build.sh          # -> ../assets/demo-{dark,light}.{mp4,gif}
```

## Pipeline

1. `render_icon.mjs` — renders the app icon from `../assets/frame-2.svg` into
   `app-icon.png` (README still, baked 4-layer shadow) and `app-icon-video.png`
   (tight, no shadow — the video adds the shared card shadow via CSS).
2. `generate2.cjs` — reads `scene2.html` + `logo.svg` + `newscript.js`, rebases
   the palette (zinc→stone warm, amber accent), and writes `sceneB2.html`.
3. `swap.cjs` — swaps the inline logo for `app-icon-video.png` + the card
   `--shadow` token → `sceneB2_icon.html`.
4. `captureB2_icon.mjs` (derived from `captureB2.mjs`) — headless Chromium
   captures 276 frames/theme by calling `window.__render(t)`, a pure function
   of time defined in `newscript.js`.
5. ffmpeg → mp4 (crf 16) + gif (palette, fps 20, 900px).

## Where the animation lives

All timing/easing is in **`newscript.js`** — `render(t)` and the `E` easing set
(`out`, `expo`, `in`, `spring` ζ=0.66). Edit there, then `./build.sh`.

Requires `node`, `ffmpeg`, and a Chromium at the path hardcoded in
`render_icon.mjs` / `captureB2.mjs` (`$CHROME`). Generated files
(`sceneB2*.html`, `app-icon*.png`, `frI_*/`, `node_modules/`,
`captureB2_icon.mjs`) are gitignored — only source is tracked.
