# ClearScan (Local AI Scanner) — Project Roadmap & TODO

A fully private, 100% on-device document scanning and intelligence application. Zero third-party cloud APIs, zero tracking, zero external telemetry.

---

## ✅ Done

- [x] **Repository & toolchain**: Flutter 3.41, Android SDK 35 (Java 17), brand assets and launcher icons
- [x] **Capture & import**
  - [x] Full-resolution camera capture (`ResolutionPreset.max`), tap-to-focus, torch, lifecycle handling
  - [x] Multi-page camera mode and multi-image gallery import
  - [x] Ingestion: EXIF orientation baked into pixels, size cap, native decoding for very large photos, clear errors for unsupported formats
- [x] **Computer vision (pure Dart, background isolates)**
  - [x] Page detection: Sobel + non-max suppression + Hough lines, quads scored by edge support and paper/background contrast, full-frame fallback for close-ups
  - [x] Text orientation detection (0/90/180/270°) from character components, white-corridor axis voting and ascender/descender asymmetry
  - [x] Homography warp (DLT) with bilinear resampling on typed buffers, up to 3000 px
  - [x] Filters on illumination-normalized luminance: Magic Color (adaptive ink/paper levels), adaptive B&W (Bradley), Grayscale, Lighten
- [x] **OCR**
  - [x] Google ML Kit Text Recognition v2 (bundled Latin model, offline)
  - [x] OCR-specific preprocessing, orientation verification (gibberish/tilted lines → rotation trials)
  - [x] Reading order via XY-cut (headers, columns), table/receipt rows kept together, de-hyphenation, OCR confusion fixes
  - [x] Per-page OCR text and normalized line boxes stored with each page
- [x] **Grounded document insights**
  - [x] Classification (EN/FR) including course/exercise sheets
  - [x] Label-based field extraction with source-line evidence (totals, VAT, stamp duty, references, dates, IBAN with checksum, tax IDs, contacts)
  - [x] Totals cross-check and warnings; TND three-decimal amounts
  - [x] Q&A that answers from the document or says the information is absent
- [x] **Documents**
  - [x] Scan review: per-page crop / enhance / rotate / delete, drag-to-reorder, add pages (also to existing documents)
  - [x] Repository: atomic index writes, change notifications, safe concurrent updates, orphan image cleanup
  - [x] Searchable PDF export (invisible OCR text layer)
  - [x] Search by title and recognized text; filter by detected document type
  - [x] Long-press multi-select and delete; light/dark/system theme remembered
- [x] **Quality**
  - [x] 215 automated tests, including layout-overflow tests of every screen (320–1280 px, text ×2)
  - [x] Release builds without network permission

## 🔜 Next

- [ ] Optional on-device LLM (e.g. Gemma via MediaPipe / `flutter_gemma`) for summaries and Q&A, with the same grounding check on its output (values must appear in the OCR text)
- [ ] Arabic OCR (not supported by ML Kit; would need e.g. Tesseract `ara` data)
- [ ] Handwriting recognition (ML Kit Digital Ink is for strokes, not photos)
- [ ] Per-page re-ordering directly from the document viewer (currently via "Edit pages")
