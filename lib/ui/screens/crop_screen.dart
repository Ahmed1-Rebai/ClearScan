import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/cv/cv_isolate_service.dart';
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
    // Run GPU codec and background isolate decoder concurrently
    final uiCodecFuture = ui.instantiateImageCodec(bytes);
    final decodeImgFuture = CvIsolateService.decodeImageAsync(bytes);

    final results = await Future.wait([uiCodecFuture, decodeImgFuture]);
    final codec = results[0] as ui.Codec;
    final frame = await codec.getNextFrame();
    final decodedImg = results[1] as img.Image?;

    if (mounted) {
      setState(() {
        _decodedUiImage = frame.image;
        _decodedImg = decodedImg;
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeCorners(Size containerSize) async {
    if (_corners != null || _decodedImg == null) return;

    // Calculate aspect-ratio preserved dimensions
    final double imgAspect = _decodedImg!.width / _decodedImg!.height;
    final double containerAspect = containerSize.width / containerSize.height;

    double renderW, renderH;
    if (imgAspect > containerAspect) {
      renderW = containerSize.width;
      renderH = containerSize.width / imgAspect;
    } else {
      renderH = containerSize.height;
      renderW = containerSize.height * imgAspect;
    }

    final displaySize = Size(renderW, renderH);

    // Detect using CV edge detector in background isolate
    final detected = await CvIsolateService.detectCornersAsync(_decodedImg!);

    final double scaleX = renderW / _decodedImg!.width;
    final double scaleY = renderH / _decodedImg!.height;

    if (mounted) {
      setState(() {
        _displaySize = displaySize;
        _corners = DocumentCorners(
          topLeft: Offset(detected.topLeft.dx * scaleX, detected.topLeft.dy * scaleY),
          topRight: Offset(detected.topRight.dx * scaleX, detected.topRight.dy * scaleY),
          bottomRight: Offset(detected.bottomRight.dx * scaleX, detected.bottomRight.dy * scaleY),
          bottomLeft: Offset(detected.bottomLeft.dx * scaleX, detected.bottomLeft.dy * scaleY),
        );
      });
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_corners == null) return;
    final List<Offset> pts = _corners!.toList();
    final Offset pos = details.localPosition;

    int? closestIdx;
    double closestDist = 48.0; // Touch hit radius

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

  Future<void> _autoDetect() async {
    if (_decodedImg == null || _displaySize == Size.zero) return;
    setState(() => _isLoading = true);

    final detected = await CvIsolateService.detectCornersAsync(_decodedImg!);
    final double scaleX = _displaySize.width / _decodedImg!.width;
    final double scaleY = _displaySize.height / _decodedImg!.height;

    if (mounted) {
      setState(() {
        _isLoading = false;
        _corners = DocumentCorners(
          topLeft: Offset(detected.topLeft.dx * scaleX, detected.topLeft.dy * scaleY),
          topRight: Offset(detected.topRight.dx * scaleX, detected.topRight.dy * scaleY),
          bottomRight: Offset(detected.bottomRight.dx * scaleX, detected.bottomRight.dy * scaleY),
          bottomLeft: Offset(detected.bottomLeft.dx * scaleX, detected.bottomLeft.dy * scaleY),
        );
      });
    }
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

    // Run perspective rectification in background isolate to avoid ANR
    final warped = await CvIsolateService.warpPerspectiveAsync(_decodedImg!, imageCorners);
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
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Adjust Crop'),
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _proceedToFilter,
            icon: Icon(Icons.check, color: primaryColor),
            label: Text(
              'Next',
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  const Text('Processing image in background isolate...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _initializeCorners(containerSize);
                      });

                      if (_displaySize == Size.zero) {
                        return Center(child: CircularProgressIndicator(color: primaryColor));
                      }

                      return Center(
                        child: SizedBox(
                          width: _displaySize.width,
                          height: _displaySize.height,
                          child: GestureDetector(
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (_decodedUiImage != null)
                                  RawImage(
                                    image: _decodedUiImage,
                                    width: _displaySize.width,
                                    height: _displaySize.height,
                                    fit: BoxFit.fill,
                                  ),
                                if (_corners != null)
                                  CustomPaint(
                                    size: _displaySize,
                                    painter: PolygonCropperPainter(
                                      corners: _corners!,
                                      activeCornerIndex: _activeCornerIndex,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                if (_activeCornerIndex != null && _touchPosition != null)
                                  MagnifierLoupe(
                                    position: _touchPosition!,
                                    image: _decodedUiImage,
                                    displaySize: _displaySize,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: _resetToFullPage,
                          icon: Icon(Icons.crop_free, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                          label: Text(
                            'Full Page',
                            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _autoDetect,
                          icon: Icon(Icons.auto_fix_high, color: primaryColor),
                          label: Text('Auto-Detect', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
