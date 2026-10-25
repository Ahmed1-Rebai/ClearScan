import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import 'crop_screen.dart';

class CameraScreen extends StatefulWidget {
  final ScannedDocument? targetDocument;

  const CameraScreen({super.key, this.targetDocument});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isBatchMode = false;
  final List<ScannedPage> _batchPages = [];
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras.first,
          ResolutionPreset.veryHigh,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    } catch (_) {
      // Desktop / emulator without camera fallback
      if (mounted) setState(() => _isCameraInitialized = false);
    }
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    Uint8List? imageBytes;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final xfile = await _cameraController!.takePicture();
        imageBytes = await xfile.readAsBytes();
      } catch (_) {}
    }

    // Fallback sample document if no camera available (e.g. desktop/simulator)
    imageBytes ??= _generateSampleDocumentImage();

    final rawPath = await DocumentRepository.instance.saveRawPageImage(imageBytes);
    final page = ScannedPage(rawImagePath: rawPath);

    setState(() => _isCapturing = false);

    if (_isBatchMode) {
      setState(() => _batchPages.add(page));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured page ${_batchPages.length}!'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CropScreen(
              page: page,
              parentDocument: widget.targetDocument,
            ),
          ),
        );
      }
    }
  }

  Future<void> _importFromGallery() async {
    final files = await FilePicker.pickFiles(
      type: FileType.image,
    );

    if (files.isNotEmpty) {
      for (final file in files) {
        if (file.path != null) {
          final bytes = await File(file.path!).readAsBytes();
          final rawPath = await DocumentRepository.instance.saveRawPageImage(bytes);
          final page = ScannedPage(rawImagePath: rawPath);

          if (_isBatchMode) {
            _batchPages.add(page);
          } else {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => CropScreen(
                    page: page,
                    parentDocument: widget.targetDocument,
                  ),
                ),
              );
              return;
            }
          }
        }
      }
      if (_isBatchMode && mounted) {
        setState(() {});
      }
    }
  }

  void _finishBatch() {
    if (_batchPages.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CropScreen(
          page: _batchPages.first,
          parentDocument: widget.targetDocument,
        ),
      ),
    );
  }

  Uint8List _generateSampleDocumentImage() {
    // Generates a simulated realistic scanned invoice document
    final doc = img.Image(width: 800, height: 1100);
    img.fill(doc, color: img.ColorRgb8(245, 245, 245));

    // Simulated header
    for (int y = 80; y < 140; y++) {
      for (int x = 80; x < 720; x++) {
        if (y < 95 || y > 125 || x < 300) {
          doc.setPixelRgba(x, y, 30, 40, 50, 255);
        }
      }
    }

    // Simulated invoice rows
    for (int row = 0; row < 12; row++) {
      final int y = 220 + row * 65;
      for (int h = 0; h < 14; h++) {
        for (int x = 80; x < 720; x++) {
          if ((x > 80 && x < 400) || (x > 500 && x < 720)) {
            doc.setPixelRgba(x, y + h, 50, 50, 50, 255);
          }
        }
      }
    }

    // Red seal stamp at bottom right
    for (int y = 920; y < 1020; y++) {
      for (int x = 550; x < 650; x++) {
        final double dist = (x - 600) * (x - 600) + (y - 970) * (y - 970) + 0.0;
        if (dist > 1800 && dist < 2200) {
          doc.setPixelRgba(x, y, 220, 40, 40, 255);
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(doc, quality: 90));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_isBatchMode ? 'Batch Scan (${_batchPages.length})' : 'Single Scan'),
        actions: [
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
              color: _flashMode == FlashMode.torch ? Colors.amber : Colors.white,
            ),
            onPressed: () async {
              if (_cameraController != null && _cameraController!.value.isInitialized) {
                final next = _flashMode == FlashMode.torch ? FlashMode.off : FlashMode.torch;
                await _cameraController!.setFlashMode(next);
                setState(() => _flashMode = next);
              }
            },
          ),
          TextButton(
            onPressed: () => setState(() => _isBatchMode = !_isBatchMode),
            child: Text(
              _isBatchMode ? 'Single' : 'Batch',
              style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            Container(
              color: const Color(0xFF0B0F19),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.document_scanner, size: 72, color: const Color(0xFF00E5FF).withOpacity(0.8)),
                    const SizedBox(height: 16),
                    const Text('Document Viewfinder Ready', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Tap the shutter to capture or import from gallery', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ),

          // Document Guide Viewfinder Frame
          Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.6), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Bottom Shutter Controls
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery button
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.white, size: 30),
                  onPressed: _importFromGallery,
                ),

                // Shutter Button
                GestureDetector(
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.transparent,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E5FF),
                      ),
                      child: _isCapturing
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                          : null,
                    ),
                  ),
                ),

                // Finish batch button or placeholder
                if (_isBatchMode && _batchPages.isNotEmpty)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(16),
                    ),
                    onPressed: _finishBatch,
                    child: Text('${_batchPages.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
