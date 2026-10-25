import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'edge_detector.dart';
import 'filter_engine.dart';
import 'image_buffers.dart';
import 'image_ingest.dart';
import 'page_processor.dart';
import 'perspective_transformer.dart';

/// Background-isolate entry points for heavy image work, keeping the UI thread free.
class CvIsolateService {
  static Future<img.Image?> decodeImageAsync(Uint8List bytes) {
    return Isolate.run(() => img.decodeImage(bytes));
  }

  static Future<DocumentCorners> detectCornersAsync(img.Image image) {
    return Isolate.run(() => DocumentEdgeDetector.detectCorners(image));
  }

  /// Decodes the photo at [path] and detects the page boundary, off the UI thread.
  static Future<DocumentCorners> detectCornersFromFileAsync(String path) async {
    final decoded = await _decodeNative(path);
    return Isolate.run(() {
      final image = decoded?.toImage() ?? img.decodeImage(File(path).readAsBytesSync());
      if (image == null) throw const UnsupportedImageException('Could not read the captured image.');
      return DocumentEdgeDetector.detectCorners(image);
    });
  }

  static Future<img.Image> warpPerspectiveAsync(
    img.Image image,
    DocumentCorners corners, {
    int maxDimension = PerspectiveTransformer.maxOutputDimension,
  }) {
    return Isolate.run(() => PerspectiveTransformer.warpPerspective(image, corners, maxOutputDimension: maxDimension));
  }

  static Future<img.Image> applyFilterAsync(img.Image image, ScanFilterType filter) {
    return Isolate.run(() => DocumentFilterEngine.applyFilter(image, filter));
  }

  static Future<Uint8List> encodeJpgAsync(img.Image image, {int quality = 90}) {
    return Isolate.run(() => Uint8List.fromList(img.encodeJpg(image, quality: quality)));
  }

  /// Applies a filter and encodes to JPEG in one isolate hop.
  static Future<Uint8List> applyFilterAndEncodeAsync(img.Image image, ScanFilterType filter, {int quality = 88}) {
    return Isolate.run(() {
      final filtered = DocumentFilterEngine.applyFilter(image, filter);
      return Uint8List.fromList(img.encodeJpg(filtered, quality: quality));
    });
  }

  /// Rotates clockwise by a multiple of 90°.
  static Future<img.Image> rotateAsync(img.Image image, int angle) {
    return Isolate.run(() => ImageBuffers.rotate(image, angle));
  }

  /// Writes a copy of the image at [sourcePath] rotated clockwise by [degrees] to [outputPath].
  static Future<void> rotateImageFileAsync(String sourcePath, String outputPath, int degrees) {
    return Isolate.run(() {
      final image = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (image == null) throw const UnsupportedImageException('Could not read the page image.');
      File(outputPath).writeAsBytesSync(img.encodeJpg(ImageBuffers.rotate(image, degrees), quality: 92, chroma: img.JpegChroma.yuv420));
    });
  }

  /// Makes captured / imported bytes upright and size-capped (see [ImageIngest]).
  static Future<Uint8List> normalizeCaptureAsync(Uint8List bytes) {
    return Isolate.run(() => ImageIngest.normalize(bytes));
  }

  static Future<ProcessedPageResult> processPageAsync({
    required String rawPath,
    required String outputPath,
    required ScanFilterType filter,
    DocumentCorners? corners,
    int rotation = 0,
    bool autoOrient = false,
  }) async {
    final decoded = await _decodeNative(rawPath);
    return Isolate.run(() => PageProcessor.processSync(
          rawPath: rawPath,
          outputPath: outputPath,
          filter: filter,
          corners: corners,
          rotation: rotation,
          autoOrient: autoOrient,
          decoded: decoded,
        ));
  }

  /// Warped + rotated (unfiltered) page at preview resolution, for live filter previews.
  static Future<img.Image> renderPreviewBaseAsync({
    required String rawPath,
    required DocumentCorners? corners,
    required int rotation,
    int maxDimension = 1400,
  }) async {
    final decoded = await _decodeNative(rawPath);
    return Isolate.run(() {
      final warped = PageProcessor.renderWarped(
        rawPath: rawPath,
        corners: corners,
        maxOutputDimension: maxDimension,
        decoded: decoded,
      );
      return ImageBuffers.rotate(warped.image, rotation);
    });
  }

  /// The platform codec decodes photos several times faster than pure Dart; it is
  /// used on Android/iOS, with the Dart decoder as fallback (and on other platforms).
  static Future<NativeRgba?> _decodeNative(String path) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      return await ImageIngest.decodeNativeRgba(path);
    } catch (e) {
      debugPrint('Native decode failed, using Dart decoder: $e');
      return null;
    }
  }
}
