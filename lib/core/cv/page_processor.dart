import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'edge_detector.dart';
import 'filter_engine.dart';
import 'image_buffers.dart';
import 'image_ingest.dart';
import 'orientation_detector.dart';
import 'perspective_transformer.dart';

class ProcessedPageResult {
  final DocumentCorners corners;
  final int rotation;
  final int width;
  final int height;

  const ProcessedPageResult(this.corners, this.rotation, this.width, this.height);
}

/// The deterministic raw → processed page pipeline:
/// decode → corners (detected when unknown) → warp → (auto-orient) → rotate → filter → JPEG.
///
/// Everything is recomputed from the raw photo, so repeated edits never degrade quality.
class PageProcessor {
  /// [decoded] is the raw photo already decoded by the platform codec, when available.
  static ProcessedPageResult processSync({
    required String rawPath,
    required String outputPath,
    required ScanFilterType filter,
    DocumentCorners? corners,
    int rotation = 0,
    bool autoOrient = false,
    NativeRgba? decoded,
  }) {
    final warped = renderWarped(rawPath: rawPath, corners: corners, decoded: decoded);
    int finalRotation = rotation;
    if (autoOrient) {
      final estimate = TextOrientationDetector.detect(warped.image);
      if (estimate.isReliable) finalRotation = estimate.rotation;
    }
    final upright = ImageBuffers.rotate(warped.image, finalRotation);
    final filtered = DocumentFilterEngine.applyFilter(upright, filter);
    File(outputPath).writeAsBytesSync(img.encodeJpg(filtered, quality: 90, chroma: img.JpegChroma.yuv420));
    return ProcessedPageResult(warped.corners, finalRotation, filtered.width, filtered.height);
  }

  /// Decodes the raw photo and warps it; detects the page boundary when [corners] is null.
  static ({img.Image image, DocumentCorners corners}) renderWarped({
    required String rawPath,
    DocumentCorners? corners,
    int maxOutputDimension = PerspectiveTransformer.maxOutputDimension,
    NativeRgba? decoded,
  }) {
    final raw = decoded?.toImage() ?? img.decodeImage(File(rawPath).readAsBytesSync());
    if (raw == null) throw const UnsupportedImageException('Could not read the captured image.');
    final quad = corners ?? DocumentEdgeDetector.detectCorners(raw);
    final warped = PerspectiveTransformer.warpPerspective(raw, quad, maxOutputDimension: maxOutputDimension);
    return (image: warped, corners: quad);
  }
}
