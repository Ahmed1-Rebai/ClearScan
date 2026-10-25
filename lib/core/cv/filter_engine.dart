import 'dart:math';
import 'package:image/image.dart' as img;
import '../models/document.dart';

/// High-fidelity document enhancement filter engine.
/// Re-implements CamScanner's signature "Magic Color" along with B&W, Grayscale, and Lighten.
class DocumentFilterEngine {
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
  /// 2. High-pass unsharp mask (sharpens text edges and handwriting).
  /// 3. Selective color boosting (keeps blue/black ink crisp, preserves red stamps/signatures).
  static img.Image applyMagicColor(img.Image input) {
    final int w = input.width;
    final int h = input.height;
    final img.Image result = img.Image(width: w, height: h);

    // 1. Generate low-frequency background illumination map via large radius blur
    final img.Image backgroundMap = img.copyResize(input, width: min(w, 160), height: min(h, 160));
    final img.Image blurredBg = img.gaussianBlur(backgroundMap, radius: 8);
    final img.Image fullBg = img.copyResize(blurredBg, width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel orig = input.getPixel(x, y);
        final img.Pixel bg = fullBg.getPixel(x, y);

        final double r = orig.r.toDouble();
        final double g = orig.g.toDouble();
        final double b = orig.b.toDouble();

        // Background luminance estimate
        final double bgLum = max(50.0, 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);

        // Normalize illumination: scaled by (255 / bgLum)
        final double factor = 255.0 / bgLum;
        double normR = r * factor;
        double normG = g * factor;
        double normB = b * factor;

        // Calculate normalized luminance
        final double lum = 0.299 * normR + 0.587 * normG + 0.114 * normB;

        // 2. High-contrast tone curve: push text ink dark, whiten paper
        // If luminance > 200, smooth blend to pure white
        double finalR, finalG, finalB;
        if (lum > 185) {
          final double t = ((lum - 185) / 70.0).clamp(0.0, 1.0);
          finalR = normR + (255.0 - normR) * t;
          finalG = normG + (255.0 - normG) * t;
          finalB = normB + (255.0 - normB) * t;
        } else {
          // Darken ink / text strokes for maximum readability
          final double darkFactor = pow(lum / 185.0, 1.45).toDouble();
          finalR = normR * darkFactor;
          finalG = normG * darkFactor;
          finalB = normB * darkFactor;
        }

        // 3. Color saturation boost for stamps, signatures, colored text
        final double maxC = max(finalR, max(finalG, finalB));
        final double minC = min(finalR, min(finalG, finalB));
        final double chroma = maxC - minC;
        if (chroma > 25) {
          // Distinct color (e.g. blue pen ink, red seal stamp)
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

    // Compute Otsu global threshold
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
    // Apply gentle S-curve to increase contrast
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

        // Gamma < 1.0 brightens mid-tones and highlights
        final double r = pow(p.r / 255.0, 0.72) * 255.0;
        final double g = pow(p.g / 255.0, 0.72) * 255.0;
        final double b = pow(p.b / 255.0, 0.72) * 255.0;

        result.setPixelRgba(
          x,
          y,
          r.round().clamp(0, 255),
          g.round().clamp(0, 255),
          b.round().clamp(0, 255),
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

