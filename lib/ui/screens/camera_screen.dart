import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/storage/document_repository.dart';
import '../gallery_import.dart';
import '../widgets/page_image.dart';
import 'scan_review_screen.dart';

/// Captures one or more pages.
///
/// - Default: opens [ScanReviewScreen] for a new document (or for [targetDocumentId]).
/// - [returnCaptures]: pops with the captured raw image paths instead (used by an open review).
class CameraScreen extends StatefulWidget {
  final String? targetDocumentId;
  final bool returnCaptures;

  const CameraScreen({super.key, this.targetDocumentId, this.returnCaptures = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  String? _cameraError;
  bool _batchMode = true;
  bool _shutterBusy = false;
  bool _finishing = false;
  FlashMode _flash = FlashMode.off;
  Offset? _focusPoint;

  /// Captures in shutter order; imports finish asynchronously and fill their slot.
  final List<String?> _slots = [];
  final List<Future<void>> _pending = [];

  List<String> get _captured => _slots.whereType<String>().toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller != null) {
        _controller = null;
        controller.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found on this device.');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      // Full sensor resolution: small print needs every pixel for good OCR.
      final controller = CameraController(back, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      try {
        await controller.setFlashMode(_flash);
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _cameraError = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
              ? 'Camera permission was denied. Allow camera access in Settings, or import photos instead.'
              : 'The camera is not available. You can import photos instead.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _cameraError = 'The camera is not available. You can import photos instead.';
        });
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _shutterBusy || _finishing) return;
    setState(() => _shutterBusy = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      unawaited(File(shot.path).delete().then((_) {}, onError: (_) {}));
      _store(bytes);
      if (mounted) setState(() => _shutterBusy = false);
      if (!_batchMode) await _finish();
    } catch (_) {
      if (mounted) {
        setState(() => _shutterBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not take the picture. Please try again.')));
      }
    }
  }

  void _store(Uint8List bytes) {
    final slot = _slots.length;
    _slots.add(null);
    _pending.add(
      DocumentRepository.instance
          .importImageBytes(bytes)
          .then(
            (path) {
              _slots[slot] = path;
              if (mounted) setState(() {});
            },
            onError: (Object _) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A photo could not be saved.')));
              }
            },
          ),
    );
  }

  Future<void> _importFromGallery() async {
    final paths = await importImagesFromGallery(context);
    if (!mounted || paths.isEmpty) return;
    setState(() => _slots.addAll(paths));
    if (!_batchMode) await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await Future.wait(_pending);
    if (!mounted) return;
    final captured = _captured;
    if (captured.isEmpty) {
      setState(() => _finishing = false);
      return;
    }
    if (widget.returnCaptures) {
      Navigator.pop(context, captured);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(documentId: widget.targetDocumentId, newRawPaths: captured),
        ),
      );
    }
  }

  Future<void> _confirmClose() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard captured pages?'),
        content: Text('${_slots.length} page${_slots.length == 1 ? '' : 's'} will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep scanning')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard != true) return;
    await Future.wait(_pending);
    await DocumentRepository.instance.deleteFiles(_captured);
    _slots.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flash == FlashMode.torch ? FlashMode.off : FlashMode.torch;
    try {
      await controller.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _focusAt(TapDownDetails details, BoxConstraints box) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (details.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
    );
    setState(() => _focusPoint = details.localPosition);
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00E5FF);
    final count = _slots.length;

    return PopScope(
      canPop: _slots.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Every child is positioned and the box is expanded, so the stack fills the
        // screen (a non-positioned top bar would shrink it to the bar's height).
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(child: _buildPreview(accent)),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close',
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            _flash == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
                            color: _flash == FlashMode.torch ? Colors.amber : Colors.white,
                          ),
                          tooltip: 'Torch',
                          onPressed: _controller == null ? null : _toggleFlash,
                        ),
                        Flexible(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _batchMode = !_batchMode),
                              icon: Icon(_batchMode ? Icons.burst_mode_outlined : Icons.crop_portrait, color: accent),
                              label: Text(
                                _batchMode ? 'Multi-page' : 'Single page',
                                style: const TextStyle(color: accent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 30),
                          tooltip: 'Import from gallery',
                          onPressed: _finishing ? null : _importFromGallery,
                        ),
                        _ShutterButton(busy: _shutterBusy, onTap: _controller == null || _finishing ? null : _capture),
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: count == 0
                              ? null
                              : _DoneButton(
                                  count: count,
                                  lastPath: _captured.isEmpty ? null : _captured.last,
                                  busy: _finishing,
                                  onTap: _finish,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(Color accent) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return Center(
        child: CameraPreview(
          controller,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _focusAt(d, box),
              child: Stack(
                children: [
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 28,
                      top: _focusPoint!.dy - 28,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_initializing) return Center(child: CircularProgressIndicator(color: accent));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 64, color: accent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(
              _cameraError ?? 'The camera is not available.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _importFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Import photos'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _ShutterButton({required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: onTap == null ? Colors.white38 : Colors.white, width: 4),
        ),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: onTap == null ? Colors.white24 : const Color(0xFF00E5FF)),
          child: busy ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black)) : null,
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  final int count;
  final String? lastPath;
  final bool busy;
  final VoidCallback onTap;

  const _DoneButton({required this.count, required this.lastPath, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Review $count page${count == 1 ? '' : 's'}',
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: lastPath == null || busy
                    ? const Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      )
                    : PageImage(path: lastPath!, fit: BoxFit.cover, cacheWidth: 160),
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF00E5FF), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '$count',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
