import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'image_buffers.dart';

/// Document enhancement filters, all built on illumination normalization so
/// shadows and uneven lighting are removed before any tone mapping.
class DocumentFilterEngine {
  static img.Image applyFilter(img.Image input, ScanFilterType filter) {
    switch (filter) {
      case ScanFilterType.original:
        return input.clone();
      case ScanFilterType.magicColor:
        return applyMagicColor(input);
      case ScanFilterType.sharpBW:
        return applySharpBW(input);
      case ScanFilterType.grayscale:
        return applyGrayscale(input);
      case ScanFilterType.lighten:
        return applyLighten(input);
    }
  }

  /// Whitens paper, turns ink black and keeps (slightly boosts) colored stamps and signatures.
  ///
  /// After removing uneven lighting, the page's own ink and paper levels are
  /// measured and stretched to black and white. Unlike fixed thresholds, this
  /// keeps the soft edges of thin or slightly blurry strokes, which OCR needs.
  static img.Image applyMagicColor(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final Uint8List rgb = ImageBuffers.rgbBytes(input);
    final Uint8List lum = ImageBuffers.luminance(input);
    final Uint8List bg = ImageBuffers.estimateBackground(lum, w, h);

    final Uint8List normLum = Uint8List(lum.length);
    for (int i = 0; i < lum.length; i++) {
      normLum[i] = min(255, lum[i] * 255 ~/ max(bg[i], 40));
    }
    final levels = _inkPaperLevels(normLum);
    final List<double> tone = List.generate(256, (v) {
      final t = ((v - levels.ink) / (levels.paper - levels.ink)).clamp(0.0, 1.0);
      return pow(t, 1.35).toDouble() * 255;
    });

    final Uint8List out = Uint8List(rgb.length);
    for (int i = 0, j = 0; i < lum.length; i++, j += 3) {
      final double scale = 255.0 / max(bg[i], 40);
      double r = min(255.0, rgb[j] * scale);
      double g = min(255.0, rgb[j + 1] * scale);
      double b = min(255.0, rgb[j + 2] * scale);
      final int l = normLum[i];
      final double target = tone[l];
      if (target >= 254) {
        r = g = b = 255;
      } else {
        // Scale towards the target luminance, preserving hue for colored ink.
        final double f = l == 0 ? 0 : target / l;
        r = min(255.0, r * f);
        g = min(255.0, g * f);
        b = min(255.0, b * f);
        final double maxC = max(r, max(g, b));
        final double minC = min(r, min(g, b));
        if (maxC - minC > 28) {
          final double mean = (r + g + b) / 3;
          r = mean + (r - mean) * 1.3;
          g = mean + (g - mean) * 1.3;
          b = mean + (b - mean) * 1.3;
        }
      }
      out[j] = r.round().clamp(0, 255);
      out[j + 1] = g.round().clamp(0, 255);
      out[j + 2] = b.round().clamp(0, 255);
    }

    return ImageBuffers.fromRgb(w, h, out);
  }

  /// Typical ink and paper luminance of an illumination-normalized page.
  static ({int ink, int paper}) _inkPaperLevels(Uint8List normLum) {
    final hist = List<int>.filled(256, 0);
    for (final v in normLum) {
      hist[v]++;
    }
    int cumulative = 0;
    int ink = 0;
    int median = 255;
    final n = normLum.length;
    bool inkFound = false;
    for (int v = 0; v < 256; v++) {
      cumulative += hist[v];
      if (!inkFound && cumulative >= n * 0.01) {
        ink = v;
        inkFound = true;
      }
      if (cumulative >= n * 0.5) {
        median = v;
        break;
      }
    }
    // Nearly blank pages have no real ink: cap the ink level so paper noise stays light.
    final inkLevel = min(ink + 10, 140);
    // Paper is the majority of the page; keep a little headroom so it turns pure white.
    final paperLevel = (median * 0.93).round().clamp(inkLevel + 60, 250);
    return (ink: inkLevel, paper: paperLevel);
  }

  /// Clean black & white via adaptive (Bradley) thresholding on normalized luminance.
  /// Unlike a single global threshold, it keeps faint text in shadows readable.
  static img.Image applySharpBW(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final Uint8List norm = ImageBuffers.normalizeIllumination(ImageBuffers.luminance(input), w, h);
    return ImageBuffers.fromGray(w, h, binarize(norm, w, h));
  }

  /// Returns 0 for ink and 255 for paper.
  static Uint8List binarize(Uint8List gray, int w, int h, {double sensitivity = 0.15}) {
    final int stride = w + 1;
    final Int64List integral = Int64List((w + 1) * (h + 1));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray[y * w + x];
        integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum;
      }
    }

    final int half = max(7, max(w, h) ~/ 48);
    final Uint8List out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final int y0 = max(0, y - half);
      final int y1 = min(h - 1, y + half);
      for (int x = 0; x < w; x++) {
        final int x0 = max(0, x - half);
        final int x1 = min(w - 1, x + half);
        final int count = (y1 - y0 + 1) * (x1 - x0 + 1);
        final int sum = integral[(y1 + 1) * stride + x1 + 1] -
            integral[y0 * stride + x1 + 1] -
            integral[(y1 + 1) * stride + x0] +
            integral[y0 * stride + x0];
        final int v = gray[y * w + x];
        final bool ink = v < 225 && v * count < sum * (1.0 - sensitivity);
        out[y * w + x] = ink ? 0 : 255;
      }
    }
    return out;
  }

  /// Smooth grayscale with shadows removed and contrast stretched.
  static img.Image applyGrayscale(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final Uint8List norm = ImageBuffers.normalizeIllumination(ImageBuffers.luminance(input), w, h);
    final int low = ImageBuffers.percentile(norm, 0.01);
    final int range = max(1, 245 - low);
    for (int i = 0; i < norm.length; i++) {
      norm[i] = ((norm[i] - low) * 255 ~/ range).clamp(0, 255);
    }
    return ImageBuffers.fromGray(w, h, norm);
  }

  /// Brightens the paper while keeping the original colors.
  static img.Image applyLighten(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final Uint8List rgb = ImageBuffers.rgbBytes(input);
    final Uint8List bg = ImageBuffers.estimateBackground(ImageBuffers.luminance(input), w, h);
    final Uint8List out = Uint8List(rgb.length);
    for (int i = 0, j = 0; i < bg.length; i++, j += 3) {
      // Partial normalization keeps some natural paper tone.
      final double scale = 255.0 / max(bg[i] * 0.85 + 255 * 0.15, 40);
      for (int c = 0; c < 3; c++) {
        out[j + c] = _lightenLut[min(255, (rgb[j + c] * scale).round())];
      }
    }
    return ImageBuffers.fromRgb(w, h, out);
  }

  static final List<int> _lightenLut =
      List.generate(256, (i) => (pow(i / 255.0, 0.85) * 255).round().clamp(0, 255));
}
