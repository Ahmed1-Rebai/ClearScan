# CamScanner Local AI (Gemma Edition) — Project Roadmap & TODO

A fully private, high-performance, 100% on-device document scanning and intelligence application. Zero third-party cloud APIs, zero tracking, zero external telemetry.

---

## 📋 Architecture & Core Pillars
- [x] **Repository & Toolchain Setup**
  - [x] Initialize Git repository (`main` branch)
  - [x] Configure Flutter 3.41 & Android SDK (Java 17 OpenJDK, API 35)
  - [x] Create project `.gitignore`, `README.md`, and `TODO.md`
  - [x] Verify environment readiness across Android, Linux, and Web

- [ ] **Phase 1: Computer Vision & Document Processing Engine**
  - [ ] Implement pure-Dart/native image processing core:
    - [ ] Grayscale conversion and Gaussian blur
    - [ ] Canny edge detection & morphological operations
    - [ ] Contour extraction and convex hull analysis
    - [ ] Quadrilateral approximation & corner ordering (`[Top-Left, Top-Right, Bottom-Right, Bottom-Left]`)
  - [ ] Homography & Perspective Transformation:
    - [ ] Bi-linear interpolation perspective warp matrix calculation
    - [ ] High-resolution document flattening
  - [ ] CamScanner-Grade Image Enhancement Filters:
    - [ ] *Original*: Preserved uncompressed raw capture
    - [ ] *Magic Color*: Local adaptive contrast enhancement, shadow suppression, ink darkening
    - [ ] *Sharp B&W*: High-contrast text binarization (Otsu / adaptive mean-C)
    - [ ] *Grayscale*: Clean multi-shade grayscale
    - [ ] *Lighten*: Soft background whitening for documents with colored backgrounds

- [ ] **Phase 2: Camera Capture & Interactive Crop UI**
  - [ ] Camera interface with real-time viewfinder overlay
  - [ ] Auto-capture trigger on stable document detection
  - [ ] Manual capture with flash, grid, and multi-page batch mode toggle
  - [ ] Interactive 4-point Magnetic Corner Adjustment:
    - [ ] Drag-to-adjust corner handles with smooth physics
    - [ ] Magnifying loupe widget (zoom lens above fingertip to place corners with pixel accuracy)
    - [ ] Real-time perspective grid feedback
    - [ ] Auto-snapping to detected high-gradient page boundaries

- [ ] **Phase 3: On-Device AI Engine (Gemma / LiteRT / MediaPipe)**
  - [ ] On-device model pipeline design:
    - [ ] Local model runtime runner (Google MediaPipe GenAI / LiteRT for Android/Linux)
    - [ ] Quantized Gemma 2B / 3B & PaliGemma on-device execution configuration
  - [ ] Local Document Intelligence Features:
    - [ ] **Automatic Document Classifier**: Identifies document type (Invoice, Receipt, ID Card, Contract, Notes, Whiteboard)
    - [ ] **Structured Information Extraction**: Extracts vendor, dates, totals, itemized tables into structured JSON
    - [ ] **On-Device Summarizer**: Quick bullet summaries of lengthy contracts or articles
    - [ ] **Document Q&A / Chat**: Ask questions directly about the scanned document completely offline
    - [ ] **Offline OCR Engine**: Fast character recognition and bounding box mapping

- [ ] **Phase 4: Multi-Page Document Management & PDF Synthesis**
  - [ ] Local SQLite / Isar metadata database for document cataloging:
    - [ ] Documents, pages, tags, creation timestamps, extracted text
  - [ ] Document Organizer:
    - [ ] Multi-page document viewer
    - [ ] Page reordering, rotation, deletion, and addition
    - [ ] Tagging and local full-text search (FTS)
  - [ ] PDF Generation:
    - [ ] Clean multi-page PDF compilation with customizable compression (Low, Medium, High)
    - [ ] Searchable PDF support (invisible OCR text layer beneath image for text selection/copying)
    - [ ] Direct export to local storage or system share sheet

- [ ] **Phase 5: User Interface, Polish & Verification**
  - [ ] Material 3 Theme with Dark & Light mode
  - [ ] Responsive layouts for phones, tablets, and desktop
  - [ ] Unit & Integration test suite for image processing and edge detection algorithms
  - [ ] Benchmark latency and memory usage of on-device vision & AI pipelines
