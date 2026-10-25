import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'filter_engine.dart';
import 'image_buffers.dart';

class OrientationEstimate {
  /// Clockwise rotation (0, 90, 180 or 270) that makes the text upright.
  final int rotation;

  /// How sure we are that text lines run along the detected axis (0..1).
  final double axisConfidence;

  /// How sure we are about up vs. down along that axis (0..1).
  final double directionConfidence;

  const OrientationEstimate(this.rotation, this.axisConfidence, this.directionConfidence);

  /// Whether [rotation] is reliable enough to apply automatically.
  bool get isReliable {
    if (rotation == 90 || rotation == 270) return axisConfidence >= 0.4;
    if (rotation == 180) return axisConfidence >= 0.3 && directionConfidence >= 0.5;
    return true;
  }

  @override
  String toString() =>
      'OrientationEstimate(rotation: $rotation, axis: ${axisConfidence.toStringAsFixed(2)}, '
      'direction: ${directionConfidence.toStringAsFixed(2)})';
}

/// Detects page text orientation from ink layout, without OCR.
///
/// 1. Keeps only character-sized connected components (drops rules, frames, pictures).
/// 2. Axis: per tile, text lines make the row ink profile alternate sharply while
///    the column profile stays smooth; tiles vote.
/// 3. Direction: Latin text has more ink above the x-height (ascenders, capitals,
///    accents) than below the baseline (descenders).
class TextOrientationDetector {
  static const int _analysisLongSide = 1800;

  static OrientationEstimate detect(img.Image image) {
    final int srcW = image.width;
    final int srcH = image.height;
    final double scale = min(1.0, _analysisLongSide / max(srcW, srcH));
    final int w = max(1, (srcW * scale).round());
    final int h = max(1, (srcH * scale).round());

    var gray = ImageBuffers.luminance(image);
    if (w != srcW || h != srcH) gray = ImageBuffers.resizeGray(gray, srcW, srcH, w, h);
    final binary = DocumentFilterEngine.binarize(ImageBuffers.normalizeIllumination(gray, w, h), w, h);

    final ink = Uint8List(w * h);
    int inkCount = 0;
    for (int i = 0; i < ink.length; i++) {
      if (binary[i] == 0) {
        ink[i] = 1;
        inkCount++;
      }
    }
    if (inkCount < w * h * 0.002) return const OrientationEstimate(0, 0, 0);

    final chars = _characterMask(ink, w, h);
    if (chars == null) return const OrientationEstimate(0, 0, 0);

    final axis = _voteAxis(chars.mask, w, h, chars.size);
    final bool horizontal = axis >= 0;
    final double axisConfidence = axis.abs();

    final Uint8List lineMask = horizontal ? chars.mask : _rotateMaskClockwise(chars.mask, w, h);
    final int lw = horizontal ? w : h;
    final int lh = horizontal ? h : w;
    final double upDown = _ascenderDescenderRatio(lineMask, lw, lh, chars.size);
    final bool flipped = upDown < 1.0;
    final double asymmetry = flipped ? 1.0 / max(upDown, 1e-9) : upDown;
    final double directionConfidence = ((asymmetry - 1.0) / 0.5).clamp(0.0, 1.0);

    final int rotation = horizontal ? (flipped ? 180 : 0) : (flipped ? 270 : 90);
    return OrientationEstimate(rotation, axisConfidence, directionConfidence);
  }

  /// Mask containing only character-sized components, plus the median character size.
  static ({Uint8List mask, int size})? _characterMask(Uint8List ink, int w, int h) {
    final labels = Int32List(w * h);
    final parent = <int>[0];

    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      a = find(a);
      b = find(b);
      if (a == b) return;
      if (a < b) {
        parent[b] = a;
      } else {
        parent[a] = b;
      }
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = y * w + x;
        if (ink[i] == 0) continue;
        int label = 0;
        void consider(int n) {
          final ln = labels[n];
          if (ln == 0) return;
          if (label == 0) {
            label = ln;
          } else if (ln != label) {
            union(label, ln);
          }
        }

        if (x > 0) consider(i - 1);
        if (y > 0) {
          if (x > 0) consider(i - w - 1);
          consider(i - w);
          if (x < w - 1) consider(i - w + 1);
        }
        if (label == 0) {
          label = parent.length;
          parent.add(label);
        }
        labels[i] = label;
      }
    }

    final int n = parent.length;
    final minX = Int32List(n)..fillRange(0, n, w);
    final minY = Int32List(n)..fillRange(0, n, h);
    final maxX = Int32List(n)..fillRange(0, n, -1);
    final maxY = Int32List(n)..fillRange(0, n, -1);
    final count = Int32List(n);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = y * w + x;
        if (labels[i] == 0) continue;
        final r = find(labels[i]);
        labels[i] = r;
        count[r]++;
        if (x < minX[r]) minX[r] = x;
        if (x > maxX[r]) maxX[r] = x;
        if (y < minY[r]) minY[r] = y;
        if (y > maxY[r]) maxY[r] = y;
      }
    }

    final int limit = min(w, h) ~/ 10;
    final sizes = <int>[];
    for (int r = 1; r < n; r++) {
      if (count[r] < 4) continue;
      final s = max(maxX[r] - minX[r], maxY[r] - minY[r]) + 1;
      if (s >= 3 && s <= limit) sizes.add(s);
    }
    if (sizes.length < 20) return null;
    sizes.sort();
    final int median = sizes[sizes.length ~/ 2];

    final keep = Uint8List(n);
    for (int r = 1; r < n; r++) {
      if (count[r] < 3) continue;
      final bw = maxX[r] - minX[r] + 1;
      final bh = maxY[r] - minY[r] + 1;
      final s = max(bw, bh);
      final elongation = s / max(1, min(bw, bh));
      if (s >= median * 0.35 && s <= median * 3 && elongation <= 10) keep[r] = 1;
    }

    final mask = Uint8List(w * h);
    for (int i = 0; i < mask.length; i++) {
      final l = labels[i];
      if (l != 0 && keep[l] == 1) mask[i] = 1;
    }
    return (mask: mask, size: median);
  }

  /// Positive when text lines run horizontally, negative when vertically; magnitude is confidence.
  ///
  /// Between text lines there are white corridors spanning the whole text width,
  /// whereas white runs across lines are cut short by the next line. So the
  /// length-weighted mean white run is much longer along the line direction.
  static double _voteAxis(Uint8List mask, int w, int h, int charSize) {
    final int tile = max(96, charSize * 16);
    double horizontalVotes = 0;
    double verticalVotes = 0;
    for (int ty = 0; ty < h; ty += tile) {
      for (int tx = 0; tx < w; tx += tile) {
        final int tw = min(tile, w - tx);
        final int th = min(tile, h - ty);
        if (tw < tile ~/ 2 || th < tile ~/ 2) continue;

        int inkCount = 0;
        double hSum = 0, hSq = 0;
        for (int y = 0; y < th; y++) {
          final row = (ty + y) * w + tx;
          int run = 0;
          for (int x = 0; x <= tw; x++) {
            if (x < tw && mask[row + x] == 0) {
              run++;
            } else {
              if (x < tw) inkCount++;
              if (run > 0) {
                hSum += run;
                hSq += run * run;
                run = 0;
              }
            }
          }
        }
        if (inkCount < tw * th * 0.03) continue;

        double vSum = 0, vSq = 0;
        for (int x = 0; x < tw; x++) {
          int run = 0;
          for (int y = 0; y <= th; y++) {
            if (y < th && mask[(ty + y) * w + tx + x] == 0) {
              run++;
            } else if (run > 0) {
              vSum += run;
              vSq += run * run;
              run = 0;
            }
          }
        }
        if (hSum == 0 || vSum == 0) continue;
        final double vote = log((hSq / hSum) / (vSq / vSum));
        final double weight = min(1.0, vote.abs());
        if (vote > 0) {
          horizontalVotes += weight;
        } else {
          verticalVotes += weight;
        }
      }
    }
    final double total = horizontalVotes + verticalVotes;
    if (total == 0) return 0;
    return (horizontalVotes - verticalVotes) / total;
  }

  /// Ratio of ink above the x-height to ink below the baseline, over all text lines
  /// (mask must have horizontal lines). > 1 means upright Latin text, < 1 upside down.
  ///
  /// Measured per tile so multi-column layouts, skew and clutter don't merge line bands.
  static double _ascenderDescenderRatio(Uint8List mask, int w, int h, int charSize) {
    final int tile = max(96, charSize * 16);
    double upper = 0;
    double lower = 0;
    for (int ty = 0; ty < h; ty += tile) {
      for (int tx = 0; tx < w; tx += tile) {
        final int tw = min(tile, w - tx);
        final int th = min(tile, h - ty);
        if (tw < tile ~/ 2 || th < tile ~/ 2) continue;
        final profile = List<int>.filled(th, 0);
        int inkCount = 0;
        for (int y = 0; y < th; y++) {
          final row = (ty + y) * w + tx;
          int count = 0;
          for (int x = 0; x < tw; x++) {
            count += mask[row + x];
          }
          profile[y] = count;
          inkCount += count;
        }
        if (inkCount < tw * th * 0.03) continue;
        final r = _bandAsymmetry(profile);
        upper += r.upper;
        lower += r.lower;
      }
    }
    return (upper + 1) / (lower + 1);
  }

  static ({double upper, double lower}) _bandAsymmetry(List<int> profile) {
    final int h = profile.length;
    final sorted = profile.where((v) => v > 0).toList()..sort();
    if (sorted.isEmpty) return (upper: 0, lower: 0);
    final int p98 = sorted[(sorted.length * 0.98).floor().clamp(0, sorted.length - 1)];
    final int bandThreshold = max(2, (p98 * 0.06).round());

    final bands = <List<int>>[];
    int? start;
    for (int y = 0; y <= h; y++) {
      final inBand = y < h && profile[y] >= bandThreshold;
      if (inBand && start == null) start = y;
      if (!inBand && start != null) {
        // Lines cut by the tile edge would bias the measurement.
        if (start > 0 && y < h) bands.add([start, y - 1]);
        start = null;
      }
    }
    if (bands.isEmpty) return (upper: 0, lower: 0);

    final heights = bands.map((b) => b[1] - b[0] + 1).toList()..sort();
    final int median = heights[heights.length ~/ 2];
    if (median < 4) return (upper: 0, lower: 0);

    double upper = 0;
    double lower = 0;
    for (final band in bands) {
      final int bandHeight = band[1] - band[0] + 1;
      if (bandHeight < median * 0.5 || bandHeight > median * 2.2) continue;
      int peak = 0;
      for (int y = band[0]; y <= band[1]; y++) {
        peak = max(peak, profile[y]);
      }
      final double coreThreshold = peak * 0.45;
      int c0 = band[0];
      while (c0 < band[1] && profile[c0] < coreThreshold) {
        c0++;
      }
      int c1 = band[1];
      while (c1 > band[0] && profile[c1] < coreThreshold) {
        c1--;
      }
      if (c1 - c0 < 1) continue;
      for (int y = band[0]; y < c0; y++) {
        upper += profile[y];
      }
      for (int y = c1 + 1; y <= band[1]; y++) {
        lower += profile[y];
      }
    }
    return (upper: upper, lower: lower);
  }

  static Uint8List _rotateMaskClockwise(Uint8List mask, int w, int h) {
    final out = Uint8List(mask.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        out[x * h + (h - 1 - y)] = mask[y * w + x];
      }
    }
    return out;
  }
}
