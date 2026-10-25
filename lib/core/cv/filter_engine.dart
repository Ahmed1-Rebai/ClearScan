import 'dart:math';
import 'package:image/image.dart' as img;
import '../models/document.dart';

/// High-performance document enhancement filter engine.
/// Re-implements CamScanner's signature "Magic Color" with lookup tables (LUTs)
/// and memory-efficient background illumination mapping.
class DocumentFilterEngine {
  // Precomputed 256-element tone curves for instant O(1) pixel processing
  static final List<double> _magicDarkLut = List.generate(
    186,
    (i) => pow(i / 185.0, 1.45).toDouble(),
  );

  static final List<int> _lightenLut = List.generate(
    256,
    (i) => (pow(i / 255.0, 0.72) * 255.0).round().clamp(0, 255),
  );

  /// Applies the requested [filter] to the [input] image.
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

  /// CamScanner's Signature "Magic Color" filter:
  /// 1. Background illumination normalization (erases shadows, whitens paper).
  /// 2. Text edge crisping and contrast maximization.
  /// 3. Saturation boost for signatures, stamps, and colored headers.
  static img.Image applyMagicColor(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final img.Image result = img.Image(width: w, height: h);

    // 1. Generate small background illumination map (e.g. max 120px) to estimate low-frequency lighting
    const int bgTargetDim = 120;
    final int bgW = min(w, bgTargetDim);
    final int bgH = min(h, (bgTargetDim * (h / w)).round());

    final img.Image backgroundMap = img.copyResize(
      input,
      width: bgW,
      height: bgH,
      interpolation: img.Interpolation.linear,
    );
    final img.Image blurredBg = img.gaussianBlur(backgroundMap, radius: 5);

    final double scaleBgX = bgW / w;
    final double scaleBgY = bgH / h;

    for (int y = 0; y < h; y++) {
      final int bgY = min((y * scaleBgY).floor(), bgH - 1);
      for (int x = 0; x < w; x++) {
        final img.Pixel orig = input.getPixel(x, y);

        final int bgX = min((x * scaleBgX).floor(), bgW - 1);
        final img.Pixel bg = blurredBg.getPixel(bgX, bgY);

        final double r = orig.r.toDouble();
        final double g = orig.g.toDouble();
        final double b = orig.b.toDouble();

        // Estimated background luminance
        final double bgLum = max(50.0, 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);

        // Normalize illumination
        final double factor = 255.0 / bgLum;
        final double normR = r * factor;
        final double normG = g * factor;
        final double normB = b * factor;

        final int lum = (0.299 * normR + 0.587 * normG + 0.114 * normB).round().clamp(0, 255);

        double finalR, finalG, finalB;
        if (lum > 185) {
          final double t = ((lum - 185) / 70.0).clamp(0.0, 1.0);
          finalR = normR + (255.0 - normR) * t;
          finalG = normG + (255.0 - normG) * t;
          finalB = normB + (255.0 - normB) * t;
        } else {
          final double darkFactor = _magicDarkLut[lum];
          finalR = normR * darkFactor;
          finalG = normG * darkFactor;
          finalB = normB * darkFactor;
        }

        // Color boost for colored ink, stamps, logos
        final double maxC = max(finalR, max(finalG, finalB));
        final double minC = min(finalR, min(finalG, finalB));
        final double chroma = maxC - minC;
        if (chroma > 25) {
          final double mean = (finalR + finalG + finalB) / 3.0;
          finalR = (mean + (finalR - mean) * 1.35).clamp(0.0, 255.0);
          finalG = (mean + (finalG - mean) * 1.35).clamp(0.0, 255.0);
          finalB = (mean + (finalB - mean) * 1.35).clamp(0.0, 255.0);
        }

        result.setPixelRgba(
          x,
          y,
          finalR.round().clamp(0, 255),
          finalG.round().clamp(0, 255),
          finalB.round().clamp(0, 255),
          orig.a.toInt(),
        );
      }
    }

    return result;
  }

  /// High-Contrast Black & White binarization for clean text, forms, and photocopying.
  static img.Image applySharpBW(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final img.Image gray = img.grayscale(input);
    final img.Image result = img.Image(width: w, height: h);

    final int threshold = _computeOtsuThreshold(gray);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int val = gray.getPixel(x, y).r.toInt();
        final int out = (val < threshold) ? 0 : 255;
        result.setPixelRgba(x, y, out, out, out, 255);
      }
    }

    return result;
  }

  /// Multi-tone smooth grayscale document filter.
  static img.Image applyGrayscale(img.Image input) {
    final img.Image gray = img.grayscale(input);
    return img.adjustColor(gray, contrast: 1.25, brightness: 1.05);
  }

  /// Lighten filter: brightens shaded background while maintaining ink visibility.
  static img.Image applyLighten(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final img.Image result = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel p = input.getPixel(x, y);

        result.setPixelRgba(
          x,
          y,
          _lightenLut[p.r.toInt().clamp(0, 255)],
          _lightenLut[p.g.toInt().clamp(0, 255)],
          _lightenLut[p.b.toInt().clamp(0, 255)],
          p.a.toInt(),
        );
      }
    }

    return result;
  }

  /// Otsu's optimal thresholding algorithm for bimodal document distributions.
  static int _computeOtsuThreshold(img.Image gray) {
    final List<int> histogram = List<int>.filled(256, 0);
    final int total = gray.width * gray.height;

    for (final pixel in gray) {
      histogram[pixel.r.toInt()]++;
    }

    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumB = 0;
    int wB = 0;
    int wF = 0;
    double varMax = 0;
    int threshold = 128;

    for (int t = 0; t < 256; t++) {
      wB += histogram[t];
      if (wB == 0) continue;
      wF = total - wB;
      if (wF == 0) break;

      sumB += t * histogram[t];
      final double mB = sumB / wB;
      final double mF = (sum - sumB) / wF;

      final double varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (varBetween > varMax) {
        varMax = varBetween;
        threshold = t;
      }
    }

    return threshold;
  }
}
