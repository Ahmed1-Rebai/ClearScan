import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/cv/edge_detector.dart';
import '../../core/cv/perspective_transformer.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import '../widgets/magnifier_loupe.dart';
import '../widgets/polygon_cropper_painter.dart';
import 'filter_screen.dart';

class CropScreen extends StatefulWidget {
  final ScannedPage page;
  final ScannedDocument? parentDocument;

  const CropScreen({
    super.key,
    required this.page,
    this.parentDocument,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _decodedUiImage;
  img.Image? _decodedImg;
  DocumentCorners? _corners;
  int? _activeCornerIndex;
  Offset? _touchPosition;
  bool _isLoading = true;
  Size _displaySize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.page.rawImagePath);
    if (!await file.exists()) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final Uint8List bytes = await file.readAsBytes();
    final uiCodec = await ui.instantiateImageCodec(bytes);
    final frame = await uiCodec.getNextFrame();
    final decodedImg = img.decodeImage(bytes);

    if (mounted) {
      setState(() {
        _decodedUiImage = frame.image;
        _decodedImg = decodedImg;
        _isLoading = false;
      });
    }
  }

  void _initializeCorners(Size size) {
    if (_corners != null || _decodedImg == null) return;

    // Detect using CV edge detector
    final detected = DocumentEdgeDetector.detectCorners(_decodedImg!);

    // Scale from image coordinates to display size
    final double scaleX = size.width / _decodedImg!.width;
    final double scaleY = size.height / _decodedImg!.height;

    setState(() {
      _displaySize = size;
      _corners = DocumentCorners(
        topLeft: Offset(detected.topLeft.dx * scaleX, detected.topLeft.dy * scaleY),
        topRight: Offset(detected.topRight.dx * scaleX, detected.topRight.dy * scaleY),
        bottomRight: Offset(detected.bottomRight.dx * scaleX, detected.bottomRight.dy * scaleY),
        bottomLeft: Offset(detected.bottomLeft.dx * scaleX, detected.bottomLeft.dy * scaleY),
      );
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (_corners == null) return;
    final List<Offset> pts = _corners!.toList();
    final Offset pos = details.localPosition;

    int? closestIdx;
    double closestDist = 45.0; // Touch hit radius

    for (int i = 0; i < 4; i++) {
      final double d = (pts[i] - pos).distance;
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }

    if (closestIdx != null) {
      setState(() {
        _activeCornerIndex = closestIdx;
        _touchPosition = pos;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeCornerIndex == null || _corners == null) return;

    final Offset pos = details.localPosition;
    final double clampedX = pos.dx.clamp(0.0, _displaySize.width);
    final double clampedY = pos.dy.clamp(0.0, _displaySize.height);
    final Offset clamped = Offset(clampedX, clampedY);

    setState(() {
      _touchPosition = clamped;
      switch (_activeCornerIndex) {
        case 0:
          _corners = _corners!.copyWith(topLeft: clamped);
          break;
        case 1:
          _corners = _corners!.copyWith(topRight: clamped);
          break;
        case 2:
          _corners = _corners!.copyWith(bottomRight: clamped);
          break;
        case 3:
          _corners = _corners!.copyWith(bottomLeft: clamped);
          break;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _activeCornerIndex = null;
      _touchPosition = null;
    });
  }

  void _resetToFullPage() {
    if (_displaySize == Size.zero) return;
    setState(() {
      _corners = DocumentCorners.defaultRect(_displaySize.width, _displaySize.height);
    });
  }

  void _autoDetect() {
    if (_decodedImg == null || _displaySize == Size.zero) return;
    final detected = DocumentEdgeDetector.detectCorners(_decodedImg!);
    final double scaleX = _displaySize.width / _decodedImg!.width;
    final double scaleY = _displaySize.height / _decodedImg!.height;

    setState(() {
      _corners = DocumentCorners(
        topLeft: Offset(detected.topLeft.dx * scaleX, detected.topLeft.dy * scaleY),
        topRight: Offset(detected.topRight.dx * scaleX, detected.topRight.dy * scaleY),
        bottomRight: Offset(detected.bottomRight.dx * scaleX, detected.bottomRight.dy * scaleY),
        bottomLeft: Offset(detected.bottomLeft.dx * scaleX, detected.bottomLeft.dy * scaleY),
      );
    });
  }

  Future<void> _proceedToFilter() async {
    if (_decodedImg == null || _corners == null) return;

    setState(() => _isLoading = true);

    // Map display corners back to original image dimensions
    final double scaleX = _decodedImg!.width / _displaySize.width;
    final double scaleY = _decodedImg!.height / _displaySize.height;

    final imageCorners = DocumentCorners(
      topLeft: Offset(_corners!.topLeft.dx * scaleX, _corners!.topLeft.dy * scaleY),
      topRight: Offset(_corners!.topRight.dx * scaleX, _corners!.topRight.dy * scaleY),
      bottomRight: Offset(_corners!.bottomRight.dx * scaleX, _corners!.bottomRight.dy * scaleY),
      bottomLeft: Offset(_corners!.bottomLeft.dx * scaleX, _corners!.bottomLeft.dy * scaleY),
    );

    // Run perspective rectification
    final warped = PerspectiveTransformer.warpPerspective(_decodedImg!, imageCorners);
    final processedPath = await DocumentRepository.instance.saveProcessedPageImage(warped, widget.page.id);

    final updatedPage = widget.page.copyWith(
      corners: imageCorners,
      processedImagePath: processedPath,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FilterScreen(
            page: updatedPage,
            warpedImage: warped,
            parentDocument: widget.parentDocument,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Adjust Crop'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _proceedToFilter,
            icon: const Icon(Icons.check, color: Colors.tealAccent),
            label: const Text('Next', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _initializeCorners(size);
                      });

                      return GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_decodedUiImage != null)
                              RawImage(
                                image: _decodedUiImage,
                                fit: BoxFit.fill,
                              ),
                            if (_corners != null)
                              CustomPaint(
                                size: size,
                                painter: PolygonCropperPainter(
                                  corners: _corners!,
                                  activeCornerIndex: _activeCornerIndex,
                                ),
                              ),
                            if (_activeCornerIndex != null && _touchPosition != null)
                              MagnifierLoupe(
                                position: _touchPosition!,
                                image: _decodedUiImage,
                                displaySize: size,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.grey[900],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: _resetToFullPage,
                        icon: const Icon(Icons.crop_free, color: Colors.white70),
                        label: const Text('Full Page', style: TextStyle(color: Colors.white70)),
                      ),
                      TextButton.icon(
                        onPressed: _autoDetect,
                        icon: const Icon(Icons.auto_fix_high, color: Colors.tealAccent),
                        label: const Text('Auto-Detect', style: TextStyle(color: Colors.tealAccent)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

