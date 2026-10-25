# ClearScan (Local AI Scanner) — Project Roadmap & TODO

A fully private, high-performance, 100% on-device document scanning and intelligence application. Zero third-party cloud APIs, zero tracking, zero external telemetry.

---

## 📋 Architecture & Core Pillars
- [x] **Repository & Toolchain Setup**
  - [x] Initialize Git repository (`main` branch)
  - [x] Configure Flutter 3.41 & Android SDK (Java 17 OpenJDK, API 35)
  - [x] Create project `.gitignore`, `README.md`, and `TODO.md`
  - [x] Configure remote repository: `https://github.com/Ahmed1-Rebai/ClearScan`
  - [x] Add brand logo assets and Android mipmap launcher icons

- [x] **Phase 1: Computer Vision & Document Processing Engine**
  - [x] Implement pure-Dart/native image processing core:
    - [x] Grayscale conversion and Gaussian blur
    - [x] Sobel gradient & Canny edge detection
    - [x] Diagonal projection extreme corner detection (`[Top-Left, Top-Right, Bottom-Right, Bottom-Left]`)
    - [x] Convex hull & Shoelace polygon area sanity checks
  - [x] Homography & Perspective Transformation:
    - [x] 8x8 Linear Direct Linear Transform (DLT) with Gaussian elimination and partial pivoting
    - [x] Bi-linear sub-pixel interpolation perspective warp
    - [x] High-resolution document flattening
  - [x] Image Enhancement Filters:
    - [x] *Original*: Preserved uncompressed raw capture
    - [x] *Magic Color*: Background illumination normalization, shadow suppression, high-pass edge crisping, and color saturation boosting
    - [x] *Sharp B&W*: Otsu global thresholding binarization
    - [x] *Grayscale*: Multi-tone smooth grayscale with contrast adjustment
    - [x] *Lighten*: High-key gamma curve for paper whitening

- [x] **Phase 2: Camera Capture & Interactive Crop UI**
  - [x] Camera interface with document viewfinder guide
  - [x] Flash toggle, single scan, and multi-page batch mode toggle
  - [x] Gallery image import with auto-orientation
  - [x] Simulated fallback document generator for simulator / desktop testing
  - [x] Interactive 4-point Magnetic Corner Adjustment:
    - [x] Drag-to-adjust corner handles with smooth physics
    - [x] Magnifying loupe widget (zoom lens above fingertip to place corners with pixel accuracy)
    - [x] 3x3 internal perspective alignment grid
    - [x] Auto-snapping to detected high-gradient page boundaries

- [x] **Phase 3: On-Device AI Engine (Gemma / LiteRT / MediaPipe)**
  - [x] On-device model pipeline design:
    - [x] Zero cloud calls, 100% offline local model inference runner
    - [x] Gemma 2B / 3B & PaliGemma structured prompt templates with turn delimiters
  - [x] Local Document Intelligence Features:
    - [x] **Automatic Document Classifier**: Identifies document type (Invoice, Receipt, ID Card, Contract, Notes, Business Card, Whiteboard)
    - [x] **Structured Information Extraction**: Extracts vendor, dates, totals, reference numbers into structured key-value pairs
    - [x] **On-Device Summarizer**: Executive summary and key bullet points
    - [x] **Document Q&A / Chat**: Offline interactive conversational assistant for scanned documents

- [x] **Phase 4: Multi-Page Document Management & PDF Synthesis**
  - [x] Local metadata repository for document cataloging:
    - [x] Documents, pages, tags, creation timestamps, raw and processed paths
  - [x] Document Organizer:
    - [x] Multi-page document viewer with interactive zoom & pan
    - [x] Page reordering, rotation (90° clockwise), and re-cropping
    - [x] Tagging and search filtering
  - [x] PDF Generation:
    - [x] Clean multi-page PDF compilation with `package:pdf`
    - [x] Direct export and system share sheet via `package:printing`

- [x] **Phase 5: User Interface, Polish & Verification**
  - [x] ClearScan Deep Midnight & Neon Cyan Material 3 Theme
  - [x] Fully responsive layout for phones, tablets, and desktop
  - [x] Comprehensive test suite (10/10 passing unit & widget tests)
  - [x] Verified Linux desktop compilation (`build/linux/x64/debug/bundle/cam_scan`)
  - [x] Verified Android APK compilation (`build/app/outputs/flutter-apk/app-debug.apk`)
