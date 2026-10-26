# Task: render the ClearScan promo video with HyperFrames

You are working on branch `promo-video`. Everything you need is in `promo/`:
- `SCRIPT.md`: the scene-by-scene script, timings, palette, captions, transitions and the master prompt. Follow it.
- `clips/`: real screen recordings of the app (1080×2400, 30 fps).
- `stills/`: real screenshots (1080×2400) and `12_logo.png`.

## Steps

1. Install the HyperFrames skills, then use the `/hyperframes` router skill:
   ```
   npx skills add heygen-com/hyperframes --all --full-depth
   ```
   If the installer prompts or fails non-interactively, use `npx hyperframes skills update`.
2. Build the composition in `promo/video/` following `SCRIPT.md` (9 scenes, 28 s, 1080×1920, 30 fps).
3. Render to `promo/out/clearscan_promo.mp4` (H.264, yuv420p).
4. Export three preview frames (`promo/out/preview_03s.png`, `preview_14s.png`, `preview_26s.png`) and check them yourself.
5. Commit `promo/video/` and `promo/out/` to `promo-video` and push. Do not touch `lib/`, `android/`, `ios/` or `main`.

## Rules

- **App UI comes only from the files in `clips/` and `stills/`.** Show them inside a smartphone frame (rounded corners, thin dark bezel, slight 5–8° tilt, cyan glow behind). Never redraw or invent app screens.
- **Hide the real status bar**: the top 110 px of every clip and still show a personal status bar. Crop it or cover it with a clean status bar (9:41, full battery).
- `stills/11_home_library.png` contains a mislabelled card ("ID / Passport"): use it only blurred (≥ 12 px) and at ≤ 20% opacity, as in scene 9.
- `stills/10_share_pdf_contacts_blurred.png` is already anonymized; do not replace it with any other share-screen footage.
- Speed up clips 2–4× and trim loading waits so each scene fits its time slot.
- Scene 1 (desk with papers): there is no live-action footage. Build it as a motion graphic instead: printed pages (white, faint text lines) dropping into a messy stack on a navy background, slow push-in.
- Captions: Inter (Google Fonts), white #F8FAFC, accent #00E5FF, max 5 words, top third of the frame, at least 1.2 s on screen.
- Audio: no copyrighted music. Render with silent audio, keep cuts on a 120 BPM grid (0.5 s) so music can be added later.

## Done when

- `promo/out/clearscan_promo.mp4` is 28 s (±0.2 s), 1080×1920, plays start to end.
- Every app scene uses the matching asset from the table in `SCRIPT.md`.
- No status bar, contact photo or contact name is visible anywhere.
