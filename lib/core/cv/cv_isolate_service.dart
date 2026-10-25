import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'edge_detector.dart';
import 'filter_engine.dart';
import 'perspective_transformer.dart';

/// High-performance worker service offloading heavy computer vision calculations
/// to background isolates.
/// Keeps the Flutter UI thread at a smooth 60/120fps with ZERO Application Not Responding (ANR) freezes.
class CvIsolateService {
  /// Asynchronously decodes an image in a background isolate.
  static Future<img.Image?> decodeImageAsync(Uint8List bytes) async {
    return Isolate.run(() => img.decodeImage(bytes));
  }

  /// Asynchronously runs Sobel edge and corner detection in a background isolate.
  static Future<DocumentCorners> detectCornersAsync(img.Image image) async {
    return Isolate.run(() => DocumentEdgeDetector.detectCorners(image));
  }

  /// Asynchronously computes the homography warp and bilinear resampling in a background isolate.
  static Future<img.Image> warpPerspectiveAsync(
    img.Image image,
    DocumentCorners corners, {
    int maxDimension = 1800,
  }) async {
    return Isolate.run(() => PerspectiveTransformer.warpPerspective(
          image,
          corners,
          maxOutputDimension: maxDimension,
        ));
  }

  /// Asynchronously applies document filters (Magic Color, B&W, etc.) in a background isolate.
  static Future<img.Image> applyFilterAsync(img.Image image, ScanFilterType filter) async {
    return Isolate.run(() => DocumentFilterEngine.applyFilter(image, filter));
  }

  /// Asynchronously encodes an image to JPEG bytes in a background isolate.
  static Future<Uint8List> encodeJpgAsync(img.Image image, {int quality = 90}) async {
    return Isolate.run(() => Uint8List.fromList(img.encodeJpg(image, quality: quality)));
  }

  /// Applies filter and encodes to JPEG in a single background isolate execution,
  /// minimizing isolate message serialization overhead.
  static Future<Uint8List> applyFilterAndEncodeAsync(
    img.Image image,
    ScanFilterType filter, {
    int quality = 88,
  }) async {
    return Isolate.run(() {
      final filtered = DocumentFilterEngine.applyFilter(image, filter);
      return Uint8List.fromList(img.encodeJpg(filtered, quality: quality));
    });
  }

  /// Asynchronously rotates an image by [angle] (90, 180, 270) in a background isolate.
  static Future<img.Image> rotateAsync(img.Image image, int angle) async {
    return Isolate.run(() => img.copyRotate(image, angle: angle));
  }
}
