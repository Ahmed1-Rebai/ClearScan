import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Typed-buffer helpers. Per-pixel accessors of package:image are far too slow
/// for 8–12 MP document photos, so the CV pipeline works on raw byte arrays.
class ImageBuffers {
  /// Returns a 3-channel uint8 image (a no-op for typical decoded JPEGs).
  static img.Image ensureRgb8(img.Image image) {
    if (!image.hasPalette && image.format == img.Format.uint8 && image.numChannels == 3) return image;
    return image.convert(format: img.Format.uint8, numChannels: 3);
  }

  /// Tightly packed RGB bytes (a view, not a copy, for 3-channel uint8 images).
  static Uint8List rgbBytes(img.Image image) => ensureRgb8(image).getBytes();

  static img.Image fromRgb(int width, int height, Uint8List rgb) =>
      img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);

  /// Gray pixels stored as RGB: package:image's JPEG encoder reads 1-channel
  /// images as red (missing green/blue channels count as 0).
  static img.Image fromGray(int width, int height, Uint8List gray) {
    final rgb = Uint8List(gray.length * 3);
    for (int i = 0, j = 0; i < gray.length; i++, j += 3) {
      final v = gray[i];
      rgb[j] = v;
      rgb[j + 1] = v;
      rgb[j + 2] = v;
    }
    return fromRgb(width, height, rgb);
  }

  /// Rec.601 luma of an image as one byte per pixel.
  static Uint8List luminance(img.Image image) {
    if (!image.hasPalette && image.format == img.Format.uint8 && image.numChannels == 1) {
      return Uint8List.fromList(image.getBytes());
    }
    final rgb = rgbBytes(image);
    final n = image.width * image.height;
    final out = Uint8List(n);
    for (int i = 0, j = 0; i < n; i++, j += 3) {
      out[i] = (77 * rgb[j] + 150 * rgb[j + 1] + 29 * rgb[j + 2]) >> 8;
    }
    return out;
  }

  /// Rotates clockwise by a multiple of 90 degrees.
  static img.Image rotate(img.Image image, int degrees) {
    final turns = ((degrees ~/ 90) % 4 + 4) % 4;
    if (turns == 0) return image;
    final channels = image.numChannels == 1 && image.format == img.Format.uint8 && !image.hasPalette ? 1 : 3;
    final src = channels == 1 ? image.getBytes() : rgbBytes(image);
    final w = image.width;
    final h = image.height;
    final outW = turns == 2 ? w : h;
    final outH = turns == 2 ? h : w;
    final dst = Uint8List(src.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int nx, ny;
        switch (turns) {
          case 1:
            nx = h - 1 - y;
            ny = x;
            break;
          case 2:
            nx = w - 1 - x;
            ny = h - 1 - y;
            break;
          default:
            nx = y;
            ny = w - 1 - x;
        }
        final si = (y * w + x) * channels;
        final di = (ny * outW + nx) * channels;
        for (int c = 0; c < channels; c++) {
          dst[di + c] = src[si + c];
        }
      }
    }
    return channels == 1 ? fromGray(outW, outH, dst) : fromRgb(outW, outH, dst);
  }

  /// Resizes a gray buffer: area averaging when shrinking ≥2x (keeps thin strokes), else bilinear.
  static Uint8List resizeGray(Uint8List gray, int w, int h, int nw, int nh) {
    if (nw * 2 <= w && nh * 2 <= h) return _areaDownscale(gray, w, h, nw, nh);
    final out = Uint8List(nw * nh);
    final sx = w / nw;
    final sy = h / nh;
    for (int y = 0; y < nh; y++) {
      final fy = ((y + 0.5) * sy - 0.5).clamp(0.0, h - 1.0);
      final y0 = fy.floor();
      final y1 = math.min(y0 + 1, h - 1);
      final ty = fy - y0;
      for (int x = 0; x < nw; x++) {
        final fx = ((x + 0.5) * sx - 0.5).clamp(0.0, w - 1.0);
        final x0 = fx.floor();
        final x1 = math.min(x0 + 1, w - 1);
        final tx = fx - x0;
        final top = gray[y0 * w + x0] * (1 - tx) + gray[y0 * w + x1] * tx;
        final bottom = gray[y1 * w + x0] * (1 - tx) + gray[y1 * w + x1] * tx;
        out[y * nw + x] = (top * (1 - ty) + bottom * ty + 0.5).toInt();
      }
    }
    return out;
  }

  static Uint8List _areaDownscale(Uint8List gray, int w, int h, int nw, int nh) {
    final out = Uint8List(nw * nh);
    for (int y = 0; y < nh; y++) {
      final y0 = y * h ~/ nh;
      final y1 = math.max(y0 + 1, (y + 1) * h ~/ nh);
      for (int x = 0; x < nw; x++) {
        final x0 = x * w ~/ nw;
        final x1 = math.max(x0 + 1, (x + 1) * w ~/ nw);
        int sum = 0;
        for (int yy = y0; yy < y1; yy++) {
          final row = yy * w;
          for (int xx = x0; xx < x1; xx++) {
            sum += gray[row + xx];
          }
        }
        out[y * nw + x] = sum ~/ ((y1 - y0) * (x1 - x0));
      }
    }
    return out;
  }

  /// Estimates the paper illumination at every pixel, ignoring ink.
  ///
  /// Takes the brightest value per block (text is dark, paper is bright),
  /// dilates to remove bold strokes, smooths, then bilinearly upsamples.
  static Uint8List estimateBackground(Uint8List gray, int w, int h) {
    final block = math.max(8, (math.max(w, h) / 90).round());
    final bw = (w + block - 1) ~/ block;
    final bh = (h + block - 1) ~/ block;
    var map = Float64List(bw * bh);
    for (int by = 0; by < bh; by++) {
      final yEnd = math.min(h, (by + 1) * block);
      for (int bx = 0; bx < bw; bx++) {
        final xEnd = math.min(w, (bx + 1) * block);
        int maxV = 0;
        for (int y = by * block; y < yEnd; y++) {
          final row = y * w;
          for (int x = bx * block; x < xEnd; x++) {
            final v = gray[row + x];
            if (v > maxV) maxV = v;
          }
        }
        map[by * bw + bx] = maxV.toDouble();
      }
    }
    map = _maxFilter3(map, bw, bh);
    map = _boxBlur3(_boxBlur3(map, bw, bh), bw, bh);

    final out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final fy = ((y + 0.5) / block - 0.5).clamp(0.0, bh - 1.0);
      final y0 = fy.floor();
      final y1 = math.min(y0 + 1, bh - 1);
      final ty = fy - y0;
      for (int x = 0; x < w; x++) {
        final fx = ((x + 0.5) / block - 0.5).clamp(0.0, bw - 1.0);
        final x0 = fx.floor();
        final x1 = math.min(x0 + 1, bw - 1);
        final tx = fx - x0;
        final top = map[y0 * bw + x0] * (1 - tx) + map[y0 * bw + x1] * tx;
        final bottom = map[y1 * bw + x0] * (1 - tx) + map[y1 * bw + x1] * tx;
        out[y * w + x] = (top * (1 - ty) + bottom * ty).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Divides out uneven lighting so paper becomes ~255 and ink keeps its contrast.
  static Uint8List normalizeIllumination(Uint8List gray, int w, int h) {
    final bg = estimateBackground(gray, w, h);
    final out = Uint8List(gray.length);
    for (int i = 0; i < gray.length; i++) {
      final b = math.max(bg[i], 40);
      out[i] = math.min(255, gray[i] * 255 ~/ b);
    }
    return out;
  }

  /// Value at the given percentile (0..1) of a gray buffer.
  static int percentile(Uint8List gray, double p) {
    final hist = List<int>.filled(256, 0);
    for (final v in gray) {
      hist[v]++;
    }
    final target = (gray.length * p).round();
    int acc = 0;
    for (int i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }

  static Float64List _maxFilter3(Float64List src, int w, int h) {
    final out = Float64List(src.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double m = 0;
        for (int dy = -1; dy <= 1; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (int dx = -1; dx <= 1; dx++) {
            final xx = (x + dx).clamp(0, w - 1);
            final v = src[yy * w + xx];
            if (v > m) m = v;
          }
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }

  static Float64List _boxBlur3(Float64List src, int w, int h) {
    final out = Float64List(src.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sum = 0;
        for (int dy = -1; dy <= 1; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (int dx = -1; dx <= 1; dx++) {
            sum += src[yy * w + (x + dx).clamp(0, w - 1)];
          }
        }
        out[y * w + x] = sum / 9;
      }
    }
    return out;
  }
}
