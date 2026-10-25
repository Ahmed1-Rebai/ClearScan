import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/cv/cv_isolate_service.dart';
import '../../core/models/document.dart';
import '../widgets/magnifier_loupe.dart';
import '../widgets/polygon_cropper_painter.dart';

/// Lets the user adjust the page corners on the raw photo.
/// Pops with the new [DocumentCorners] in image pixel coordinates, or null when cancelled.
class CropScreen extends StatefulWidget {
  final String rawImagePath;
  final DocumentCorners? initialCorners;

  const CropScreen({super.key, required this.rawImagePath, this.initialCorners});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _image;
  DocumentCorners? _corners;
  int? _activeCorner;
  Offset? _touch;
  bool _detecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.rawImagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        _corners = widget.initialCorners;
      });
      if (_corners == null) await _autoDetect();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open this photo.');
    }
  }

  Future<void> _autoDetect() async {
    setState(() => _detecting = true);
    try {
      final corners = await CvIsolateService.detectCornersFromFileAsync(widget.rawImagePath);
      if (mounted) setState(() => _corners = corners);
    } catch (_) {
      _fullPage();
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _fullPage() {
    final image = _image;
    if (image == null) return;
    setState(() => _corners = DocumentCorners.fullImage(image.width.toDouble(), image.height.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust crop'),
        actions: [
          TextButton.icon(
            onPressed: _corners == null || _detecting ? null : () => Navigator.pop(context, _corners),
            icon: const Icon(Icons.check),
            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildEditor(primary)),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _image == null ? null : _fullPage,
                        icon: const Icon(Icons.crop_free),
                        label: const FittedBox(child: Text('Full page')),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _image == null || _detecting ? null : _autoDetect,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const FittedBox(child: Text('Auto-detect')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(Color primary) {
    if (_error != null) return Center(child: Text(_error!));
    final image = _image;
    final corners = _corners;
    if (image == null || corners == null) return Center(child: CircularProgressIndicator(color: primary));

    return LayoutBuilder(builder: (context, constraints) {
      // Leave room around the photo so corner handles stay reachable.
      final scale = max(1e-3, min((constraints.maxWidth - 32) / image.width, (constraints.maxHeight - 32) / image.height));
      final displaySize = Size(image.width * scale, image.height * scale);
      final displayCorners = corners.scale(scale, scale);

      void onPanStart(DragStartDetails d) {
        final pts = displayCorners.toList();
        int? closest;
        double best = 44;
        for (int i = 0; i < 4; i++) {
          final dist = (pts[i] - d.localPosition).distance;
          if (dist < best) {
            best = dist;
            closest = i;
          }
        }
        if (closest != null) {
          setState(() {
            _activeCorner = closest;
            _touch = d.localPosition;
          });
        }
      }

      void onPanUpdate(DragUpdateDetails d) {
        final index = _activeCorner;
        if (index == null) return;
        final p = Offset(
          d.localPosition.dx.clamp(0.0, displaySize.width),
          d.localPosition.dy.clamp(0.0, displaySize.height),
        );
        final pts = corners.toList();
        pts[index] = p / scale;
        final candidate = DocumentCorners.fromList(pts);
        setState(() {
          _touch = p;
          // Reject moves that would fold the quad (a warp of it would be garbage).
          if (candidate.isConvex) _corners = candidate;
        });
      }

      void onPanEnd([Object? _]) => setState(() {
            _activeCorner = null;
            _touch = null;
          });

      return Center(
        child: SizedBox.fromSize(
          size: displaySize,
          child: GestureDetector(
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
            onPanCancel: onPanEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                RawImage(image: image, width: displaySize.width, height: displaySize.height, fit: BoxFit.fill),
                CustomPaint(
                  size: displaySize,
                  painter: PolygonCropperPainter(corners: displayCorners, activeCornerIndex: _activeCorner, primaryColor: primary),
                ),
                if (_activeCorner != null && _touch != null)
                  MagnifierLoupe(position: _touch!, image: image, displaySize: displaySize),
                if (_detecting) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
        ),
      );
    });
  }
}
