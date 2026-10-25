import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

/// RGBA pixels decoded by the platform codec, ready to send to an isolate.
class NativeRgba {
  final TransferableTypedData pixels;
  final int width;
  final int height;

  const NativeRgba(this.pixels, this.width, this.height);

  /// Materializes as a 3-channel image. Call once, inside the receiving isolate.
  img.Image toImage() {
    final rgba = pixels.materialize().asUint8List();
    final rgb = Uint8List(width * height * 3);
    for (int i = 0, j = 0; j < rgb.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    return img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);
  }
}

/// Thrown when an image cannot be decoded (e.g. HEIC on platforms without a codec).
class UnsupportedImageException implements Exception {
  final String message;
  const UnsupportedImageException(this.message);
  @override
  String toString() => message;
}

/// Normalizes captured / imported photos so every later stage sees upright,
/// reasonably sized pixels without relying on EXIF orientation.
class ImageIngest {
  /// Long-side cap for stored raw photos (12 MP phone shots pass through untouched).
  static const int maxLongSide = 4096;

  /// Above this many pixels, pure-Dart decoding risks running out of memory.
  static const int _nativeDecodeThreshold = 24 * 1000 * 1000;

  /// Returns JPEG bytes that are upright and at most [maxLongSide] on the long side.
  /// Runs synchronously; call it inside an isolate.
  static Uint8List normalize(Uint8List bytes) {
    final info = img.JpegDecoder().startDecode(bytes);
    if (info != null) {
      final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
      final fits = max(info.width, info.height) <= maxLongSide;
      if (fits && (orientation == 0 || orientation == 1)) return bytes;
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const UnsupportedImageException('Unsupported image format. Please use JPEG or PNG images.');
    }
    var image = img.bakeOrientation(decoded);
    final longSide = max(image.width, image.height);
    if (longSide > maxLongSide) {
      final s = maxLongSide / longSide;
      image = img.copyResize(
        image,
        width: (image.width * s).round(),
        height: (image.height * s).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 94));
  }

  /// Whether [bytes] is too large to decode safely in Dart and should use [decodeNativeDownscaled].
  static bool needsNativeDecode(Uint8List bytes) {
    final info = img.JpegDecoder().startDecode(bytes);
    return info != null && info.width * info.height > _nativeDecodeThreshold;
  }

  /// Decodes a photo file with the platform codec (much faster than pure Dart).
  /// Root isolate only; the pixels can be moved to a worker isolate without copying.
  static Future<NativeRgba> decodeNativeRgba(String path) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = NativeRgba(
      TransferableTypedData.fromList([data!.buffer.asUint8List()]),
      frame.image.width,
      frame.image.height,
    );
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return result;
  }

  /// Decodes very large photos with the platform codec, downscaling during decode.
  /// Must run on the root isolate (uses dart:ui). Returns an upright RGBA image.
  static Future<img.Image> decodeNativeDownscaled(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longSide = max(descriptor.width, descriptor.height);
    final s = min(1.0, maxLongSide / longSide);
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * s).round(),
      targetHeight: (descriptor.height * s).round(),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final result = img.Image.fromBytes(
      width: frame.image.width,
      height: frame.image.height,
      bytes: data!.buffer,
      numChannels: 4,
    );
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return result;
  }
}
