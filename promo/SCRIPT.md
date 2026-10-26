# ClearScan — 28s Promo Video (built from real app footage)

Format: 1080×1920 (9:16, Reels / Shorts / TikTok), 30 fps, 28 s.
Music: minimal electronic, 120 BPM (1 beat = 0.5 s). Cut on the beat.

Assets folder: `ClearScan_video_assets/`
- `clips/`: real screen recordings, 1080×2400, 30 fps
- `stills/`: real screenshots, 1080×2400 (contacts blurred in the share screen)

## Brand palette
| Role | Hex |
|---|---|
| Background (deep navy) | #0B0F19 |
| Card / surface | #131B2E |
| Accent (neon cyan) | #00E5FF |
| Secondary (soft blue) | #60A5FA |
| Highlight (violet) | #C084FC |
| Text | #F8FAFC |
| Privacy green | #10B981 |

Font: Inter Bold (titles) / Inter Medium (captions), tracking -2%.
Motion: ease-out cubic-bezier(0.16, 1, 0.3, 1), 250–400 ms, cyan glow on key elements.

## Assets → scenes

| File | What it shows | Use in scene |
|---|---|---|
| `clips/B_camera_multipage.mp4` (22 s) | Camera in Multi-page mode, 3 course pages captured, counter goes 1 → 3 | 2 |
| `stills/01_camera_multipage.png` | Camera viewfinder on "Algorithme génétique" page | 2 (backup) |
| `clips/C_crop_and_enhance.mp4` (19 s) | "Cropping and enhancing…" → clean white pages | 3 |
| `stills/02_raw_processing_before.png` | Raw grey photo while processing | 3 (BEFORE) |
| `stills/03_magic_clean_after.png` | Clean, straight, white page | 3 (AFTER) |
| `clips/E_adjust_crop.mp4` / `stills/04_adjust_crop_corners.png` | Adjust crop with cyan corner handles | 3 (insert) |
| `stills/05_review_3_pages.png` | Review scan, thumbnails 1-2-3, "Save (3)" | 4 |
| `clips/D_review_save_ocr.mp4` | Save → "Recognizing text… page 1 of 3" progress bar | 4 → 5 |
| `stills/06_ocr_recognizing.png` | OCR progress bar | 5 |
| `stills/07_insights_overview.png` | Insights: Course / Exercise Sheet · French · 3 pages, sections & highlights | 5 |
| `stills/08_recognized_text.png` | Recognized text, "Copy all" | 5 (insert) |
| `stills/09_ask_answer_quoted.png` | Ask: "c'est quoi algorithme génétique" → answer quoting the document | 6 |
| `clips/F_text_and_ask.mp4` | Text tab scroll + Ask tab with keyboard | 6 (typing motion) |
| `stills/10_share_pdf_contacts_blurred.png` | Share the PDF (contacts blurred) | 7 |
| `stills/11_home_library.png` / `clips/A_home_library.mp4` | Home library, search bar, category chips | 8 |

## Scenario

| # | Time | Visual | Caption | Transition out | SFX |
|---|---|---|---|---|---|
| 1 | 0.0–2.5 | Pile of printed course pages on a desk, slow push-in (stock or real shot) | **"Notes piling up?"** | Hard cut on beat | whoosh |
| 2 | 2.5–6.0 | Phone mockup tilted 6°, playing `B_camera_multipage.mp4` sped up 4×: shutter taps, page counter 1 → 2 → 3 | **"Scan every page in one go"** | Zoom push-through into the screen | shutter ×3 |
| 3 | 6.0–9.5 | Full-screen before/after: `02_raw…before` → vertical cyan light wipe → `03_magic_clean_after`. Quick 0.8 s insert of `04_adjust_crop_corners` with corner handles glowing | **"Straightened. Cleaned. Sharp."** (one word per beat) | Light wipe exits | swipe |
| 4 | 9.5–12.0 | `05_review_3_pages`: the 3 thumbnails lift and float out as cards on navy, then stack | **"3 pages → 1 document"** | Cards collapse into the phone | ticks |
| 5 | 12.0–16.5 | `06_ocr_recognizing` (progress bar fills) → `07_insights_overview`: chips "Course / Exercise Sheet", "French", "3 pages" pop in one by one with a cyan glow; slow pan down to "Sections & highlights" | **"Reads it. Understands it."** | Slide up | blip per chip |
| 6 | 16.5–20.0 | `F_text_and_ask.mp4` typing → `09_ask_answer_quoted`: zoom on the answer bubble "From the document: …" | **"Ask. It quotes the answer."** | Blur dissolve | typing, chime |
| 7 | 20.0–22.5 | `10_share_pdf_contacts_blurred`: the PDF file card glows, the phone slides left | **"Export a searchable PDF"** | Whip pan | whoosh |
| 8 | 22.5–25.0 | Navy screen, airplane-mode icon, shield with green check, cloud crossed out | **"100% on-device. Zero cloud."** small: **"Nothing leaves your phone."** | Shield expands to fill the frame | bass hit |
| 9 | 25.0–28.0 | End card: ClearScan logo (`assets/images/clearscan_logo.png`) with cyan glow pulse; behind it `11_home_library` blurred at 20% opacity | **ClearScan** / **"Scan. Read. Private."** / cyan pill **"Download now"** | Fade to black | shimmer |

Voiceover (optional):
> "Notes piling up? Scan every page in one go. ClearScan straightens and cleans them, reads the text, and answers your questions, quoting the document. Export a searchable PDF. And everything stays on your phone. ClearScan: scan, read, private."

## Master prompt (copy-paste into CapCut AI / Runway / Kling / Veo / After Effects brief)

```
Create a 28-second vertical (9:16, 1080x1920) promo video for "ClearScan", a private, on-device AI document scanner app. Use the attached real screen recordings and screenshots for every app scene; place them inside a modern black smartphone mockup, tilted 5-8 degrees, floating on a deep navy background with a soft cyan glow behind the phone. Do not redraw or invent app UI.

STYLE: premium tech, dark mode. Background #0B0F19, cards #131B2E, neon cyan accent #00E5FF with glow, blue #60A5FA, violet #C084FC, white text #F8FAFC, green #10B981 for privacy. Inter Bold captions, max 5 words, top third of the frame, word-by-word reveal. Smooth ease-out motion, no bouncy effects. Cuts on a 120 BPM minimal electronic beat.

SCENES:
1 (0-2.5s): Cinematic close-up of a pile of printed French course pages on a wooden desk, warm light, slow push-in. Caption "Notes piling up?"
2 (2.5-6s): Phone mockup plays B_camera_multipage.mp4 at 4x speed: camera in Multi-page mode capturing three pages, counter going 1 to 3. Caption "Scan every page in one go". Zoom push-through into the screen.
3 (6-9.5s): Full-screen before/after: 02_raw_processing_before.png, a vertical cyan light wipe from left to right reveals 03_magic_clean_after.png. Short insert of 04_adjust_crop_corners.png with the four cyan corner handles pulsing. Caption, one word per beat: "Straightened. Cleaned. Sharp."
4 (9.5-12s): 05_review_3_pages.png: the three page thumbnails lift out of the screen as floating 3D cards with soft shadows, then stack into one. Caption "3 pages, 1 document".
5 (12-16.5s): 06_ocr_recognizing.png with the progress bar filling, then 07_insights_overview.png: the chips "Course / Exercise Sheet", "French", "3 pages" pop with a cyan glow one by one, slow pan down to the sections list. Caption "Reads it. Understands it."
6 (16.5-20s): F_text_and_ask.mp4 showing a question being typed, then 09_ask_answer_quoted.png with a smooth zoom on the answer bubble that starts with "From the document". Caption "Ask. It quotes the answer."
7 (20-22.5s): 10_share_pdf_contacts_blurred.png, the PDF file card glows cyan, phone slides out left. Caption "Export a searchable PDF".
8 (22.5-25s): Navy frame, minimal line icons animate in: airplane mode, then a shield with a green check, then a cloud that gets crossed out. Caption "100% on-device. Zero cloud." and smaller "Nothing leaves your phone."
9 (25-28s): The shield expands to fill the frame. ClearScan logo fades in at center with a cyan glow pulse and a light shimmer; 11_home_library.png blurred at 20% opacity in the background. Tagline types in: "Scan. Read. Private." then a rounded cyan button "Download now". Fade to black.

TRANSITIONS: hard cut (1→2), zoom push-through (2→3), light wipe (3→4), card collapse (4→5), slide up (5→6), blur dissolve (6→7), whip pan (7→8), shape expand (8→9).
AUDIO: minimal electronic beat; shutter clicks, swipe, digital blips, typing, bass hit on the privacy line, shimmer on the logo.
```

## Before editing
- **Status bar**: the recordings show the real status bar (Messenger icon, 8:16). Mask the top 110 px with the mockup's own status bar, or crop it.
- **Home library**: the older document card is labelled "ID / Passport" (a misclassification). Only show it blurred (as in scene 9), or crop to the new "Course / Exercise Sheet" card.
- Speed up screen footage 2–4× and trim loading waits.
- Export H.264, 1080×1920, 30 fps, about 12 Mbps.
