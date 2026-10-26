# ClearScan promo — build notes and review

Source of truth: `../SCRIPT.md` and `../BRIEF.md`. 28 s, 1080×1920, 30 fps, cuts on a 120 BPM grid
(scene starts 0, 2.5, 6, 9.5, 12, 16.5, 20, 22.5, 25 s). Rendered to `../out/clearscan_promo.mp4`
with a silent stereo AAC track so music can be laid in later.

## Scenes → assets
| # | File | Assets |
|---|---|---|
| 1 | `compositions/desk.html` | motion graphic only (no footage) |
| 2 | `compositions/capture.html` | `B_camera_multipage.mp4` 6.0–15.0 s and 16.0–21.0 s at 4× (counter 1 → 2 → 3) |
| 3 | `compositions/clean.html` | `02_raw_processing_before` → light wipe → `03_magic_clean_after`, 0.8 s insert of `04_adjust_crop_corners` |
| 4 | `compositions/pages.html` | `05_review_3_pages` (thumbnails lifted as cards, cropped from the still), then `06_ocr_recognizing` |
| 5 | `compositions/insights.html` | `D_review_save_ocr.mp4` 12.6–18.6 s at 4× (Recognizing page 1→3), `07_insights_overview` |
| 6 | `compositions/ask.html` | `F_text_and_ask.mp4` 9.2–12.2 s at 2× (typing), `09_ask_answer_quoted` |
| 7 | `compositions/export.html` | `10_share_pdf_contacts_blurred` |
| 8 | `compositions/privacy.html` | line icons only |
| 9 | `compositions/endcard.html` | `12_logo.png`; `derived/home_library_blur24.jpg` at 20 % opacity |

## Privacy rules
- Real status bar: phone scenes cover the top 110 px (scaled) with a clean 9:41 / full-battery bar;
  full-screen stills in scene 3 are offset so the top 110 px is outside the frame.
- `11_home_library.png` is never used directly: `assets/derived/home_library_blur24.jpg` is that still
  with the status bar cropped and a Gaussian blur (sigma 24 px) baked in by ffmpeg, shown at 20 % opacity.
- Share screen is only the pre-anonymised `10_share_pdf_contacts_blurred.png`.

## Deviations from the script
- Scene 2 caption shortened to "Scan every page at once" (the brief caps captions at 5 words).
- Logo comes from `promo/stills/12_logo.png` (transparent navy mark), placed on a white rounded tile
  so it reads on the navy ground.
- GSAP is vendored in `assets/vendor/` (the render sandbox has no CDN access).

## Check
`npx hyperframes check`: ok. Remaining warnings are deliberate: silent film (brief), status-bar "9:41"
below the 28 px type floor (marked as texture), end-card lines shorter than the closing-line hold
because the script fixes the end card at 3 s with a fade to black.

## Regenerate
`npx hyperframes render --video-bitrate 12M --fps 30 --output ../out/render_raw.mp4`, then
`ffmpeg -i ../out/render_raw.mp4 -f lavfi -i anullsrc=r=48000:cl=stereo -map 0:v -map 1:a -c:v copy -c:a aac -t 28 -movflags +faststart ../out/clearscan_promo.mp4`.
