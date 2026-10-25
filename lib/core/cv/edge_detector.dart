import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'image_buffers.dart';

/// Pure-Dart document boundary detector.
///
/// Finds dominant straight edges with a Hough transform and picks the
/// quadrilateral whose four sides are best supported by edges and that
/// encloses a region brighter than its surroundings (paper on a desk).
/// Falls back to the full image when nothing convincing is found.
class DocumentEdgeDetector {
  static const int processingMaxDim = 512;

  /// Detects the 4 corners of a document in the given [image], in image pixel coordinates.
  static DocumentCorners detectCorners(img.Image image) {
    final int origW = image.width;
    final int origH = image.height;
    final double scale = min(1.0, processingMaxDim / max(origW, origH));
    final int w = max(8, (origW * scale).round());
    final int h = max(8, (origH * scale).round());

    final gray = _blur(ImageBuffers.resizeGray(ImageBuffers.luminance(image), origW, origH, w, h), w, h);
    final quad = _detectQuad(gray, w, h);
    if (quad == null) return DocumentCorners.fullImage(origW.toDouble(), origH.toDouble());

    final inv = 1.0 / scale;
    return DocumentCorners.fromList(quad
        .map((p) => Offset((p.dx * inv).clamp(0.0, origW.toDouble()), (p.dy * inv).clamp(0.0, origH.toDouble())))
        .toList());
  }

  /// Score of an image-border side: a page edge must beat this to be preferred over "full frame".
  static const double _borderSideScore = 0.42;

  static List<Offset>? _detectQuad(Uint8List gray, int w, int h) {
    final edges = _edgeMap(gray, w, h);
    final lines = _houghLines(edges.mask, w, h);
    // Image borders let close-ups (page filling the frame) resolve to full frame,
    // and pages cut by the frame use the border for the missing side.
    final horizontals = [
      _Line.border(pi / 2, 0),
      _Line.border(pi / 2, h - 1.0),
      ...lines.where((l) => l.isHorizontal),
    ];
    final verticals = [
      _Line.border(0, 0),
      _Line.border(0, w - 1.0),
      ...lines.where((l) => !l.isHorizontal),
    ];

    final double imageArea = (w * h).toDouble();
    List<Offset>? best;
    bool bestIsFullFrame = true;
    double bestScore = 0;

    for (int a = 0; a < horizontals.length; a++) {
      for (int b = a + 1; b < horizontals.length; b++) {
        var top = horizontals[a];
        var bottom = horizontals[b];
        if (top.midY(w) > bottom.midY(w)) {
          final t = top;
          top = bottom;
          bottom = t;
        }
        if (bottom.midY(w) - top.midY(w) < h * 0.2) continue;
        for (int c = 0; c < verticals.length; c++) {
          for (int d = c + 1; d < verticals.length; d++) {
            var left = verticals[c];
            var right = verticals[d];
            if (left.midX(h) > right.midX(h)) {
              final t = left;
              left = right;
              right = t;
            }
            if (right.midX(h) - left.midX(h) < w * 0.2) continue;

            final tl = top.intersect(left);
            final tr = top.intersect(right);
            final br = bottom.intersect(right);
            final bl = bottom.intersect(left);
            if (tl == null || tr == null || br == null || bl == null) continue;
            final quad = [tl, tr, br, bl];
            if (!_insideWithMargin(quad, w, h, 0.04)) continue;
            if (!DocumentCorners.fromList(quad).isConvex) continue;
            final area = _polygonArea(quad);
            if (area < imageArea * 0.12) continue;
            if (!_reasonableAngles(quad)) continue;

            final sides = [top, right, bottom, left];
            final center = quad.reduce((p, q) => p + q) / 4;
            double sideTotal = 0;
            int realSides = 0;
            for (int i = 0; i < 4; i++) {
              if (sides[i].isBorder) {
                sideTotal += _borderSideScore;
                continue;
              }
              realSides++;
              final p0 = quad[i];
              final p1 = quad[(i + 1) % 4];
              final support = _edgeSupport(edges.mask, w, h, p0, p1);
              final contrast = _sideContrast(gray, w, h, p0, p1, center);
              // A printed rule has paper on both sides (contrast ≈ 0) and must not beat the border.
              sideTotal += support * (_borderSideScore + (contrast * 3.5).clamp(-_borderSideScore, 0.7));
            }
            final score = (sideTotal / 4) * (0.35 + 0.65 * min(1.0, area / imageArea));
            if (score > bestScore) {
              bestScore = score;
              best = quad;
              bestIsFullFrame = realSides == 0;
            }
          }
        }
      }
    }

    return bestIsFullFrame ? null : best;
  }

  /// Mean brightness step across a side: positive when the inside (towards [center]) is brighter.
  static double _sideContrast(Uint8List gray, int w, int h, Offset a, Offset b, Offset center) {
    double sum = 0;
    int n = 0;
    for (int s = 1; s < 16; s++) {
      final p = Offset.lerp(a, b, s / 16)!;
      final toCenter = center - p;
      final unit = toCenter / max(toCenter.distance, 1e-6);
      final pin = p + unit * 6;
      final pout = p - unit * 6;
      if (!_inBounds(pin, w, h) || !_inBounds(pout, w, h)) continue;
      sum += gray[pin.dy.toInt() * w + pin.dx.toInt()] - gray[pout.dy.toInt() * w + pout.dx.toInt()];
      n++;
    }
    return n == 0 ? 0 : sum / n / 255;
  }

  static Uint8List _blur(Uint8List src, int w, int h) {
    // Two passes of a 5-tap binomial filter ≈ small Gaussian; suppresses text texture.
    var a = src;
    for (int pass = 0; pass < 2; pass++) {
      final tmp = Uint8List(a.length);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int s = 0;
          for (int k = -2; k <= 2; k++) {
            s += a[y * w + (x + k).clamp(0, w - 1)] * const [1, 4, 6, 4, 1][k + 2];
          }
          tmp[y * w + x] = s >> 4;
        }
      }
      final out = Uint8List(a.length);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int s = 0;
          for (int k = -2; k <= 2; k++) {
            s += tmp[(y + k).clamp(0, h - 1) * w + x] * const [1, 4, 6, 4, 1][k + 2];
          }
          out[y * w + x] = s >> 4;
        }
      }
      a = out;
    }
    return a;
  }

  /// Sobel magnitude with non-maximum suppression; keeps roughly the strongest 10% of edges.
  static ({Uint8List mask}) _edgeMap(Uint8List g, int w, int h) {
    final mag = Float64List(w * h);
    final dir = Uint8List(w * h); // 0: horizontal gradient, 1: vertical, 2: diag /, 3: diag \
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = (g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - 1] + g[i + w - 1]);
        final gy = (g[i + w - 1] + 2 * g[i + w] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - w] + g[i - w + 1]);
        mag[i] = sqrt((gx * gx + gy * gy).toDouble());
        final ax = gx.abs();
        final ay = gy.abs();
        if (ax > ay * 2.4) {
          dir[i] = 0;
        } else if (ay > ax * 2.4) {
          dir[i] = 1;
        } else {
          dir[i] = (gx > 0) == (gy > 0) ? 3 : 2;
        }
      }
    }

    final nonZero = <double>[];
    for (final m in mag) {
      if (m > 0) nonZero.add(m);
    }
    if (nonZero.isEmpty) return (mask: Uint8List(w * h));
    nonZero.sort();
    final threshold = max(24.0, nonZero[(nonZero.length * 0.88).floor()]);

    final mask = Uint8List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final m = mag[i];
        if (m < threshold) continue;
        double n1, n2;
        switch (dir[i]) {
          case 0:
            n1 = mag[i - 1];
            n2 = mag[i + 1];
            break;
          case 1:
            n1 = mag[i - w];
            n2 = mag[i + w];
            break;
          case 2:
            n1 = mag[i - w + 1];
            n2 = mag[i + w - 1];
            break;
          default:
            n1 = mag[i - w - 1];
            n2 = mag[i + w + 1];
        }
        if (m >= n1 && m >= n2) mask[i] = 1;
      }
    }
    return (mask: mask);
  }

  static List<_Line> _houghLines(Uint8List mask, int w, int h) {
    const int thetaBins = 360;
    final double diag = sqrt(w * w + h * h);
    final int rhoBins = (diag * 2).ceil() + 1;
    final acc = Int32List(thetaBins * rhoBins);
    final cosT = Float64List(thetaBins);
    final sinT = Float64List(thetaBins);
    for (int t = 0; t < thetaBins; t++) {
      final theta = t * pi / thetaBins;
      cosT[t] = cos(theta);
      sinT[t] = sin(theta);
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] == 0) continue;
        for (int t = 0; t < thetaBins; t++) {
          final rho = (x * cosT[t] + y * sinT[t] + diag).round();
          acc[t * rhoBins + rho]++;
        }
      }
    }

    // Peaks with non-maximum suppression in (theta, rho) space.
    final minVotes = max(20, (min(w, h) * 0.15).round());
    final peaks = <_Line>[];
    for (int t = 0; t < thetaBins; t++) {
      for (int r = 0; r < rhoBins; r++) {
        final v = acc[t * rhoBins + r];
        if (v < minVotes) continue;
        bool isMax = true;
        for (int dt = -5; dt <= 5 && isMax; dt++) {
          final tt = (t + dt + thetaBins) % thetaBins;
          for (int dr = -6; dr <= 6; dr++) {
            final rr = r + dr;
            if (rr < 0 || rr >= rhoBins || (dt == 0 && dr == 0)) continue;
            final other = acc[tt * rhoBins + rr];
            if (other > v || (other == v && (tt * rhoBins + rr) < (t * rhoBins + r))) {
              isMax = false;
              break;
            }
          }
        }
        if (isMax) peaks.add(_Line(t * pi / thetaBins, r - diag, v));
      }
    }
    peaks.sort((a, b) => b.votes.compareTo(a.votes));

    // Keep the strongest few in each orientation family; ignore steep diagonals and near-duplicates.
    final result = <_Line>[];
    int hCount = 0, vCount = 0;
    for (final l in peaks) {
      final deg = l.theta * 180 / pi;
      final bool horizontal = (deg - 90).abs() <= 35;
      final bool vertical = deg <= 35 || deg >= 145;
      if (result.any((r) => r.isHorizontal == l.isHorizontal && r.isNear(l, w, h))) continue;
      if (horizontal && hCount < 8) {
        result.add(l);
        hCount++;
      } else if (vertical && vCount < 8) {
        result.add(l);
        vCount++;
      }
      if (hCount >= 8 && vCount >= 8) break;
    }
    return result;
  }

  /// Fraction of sample points along segment a→b that lie on (or next to) an edge pixel.
  static double _edgeSupport(Uint8List mask, int w, int h, Offset a, Offset b) {
    final len = (b - a).distance;
    final samples = max(8, len ~/ 2);
    int hits = 0;
    for (int i = 0; i <= samples; i++) {
      final p = Offset.lerp(a, b, i / samples)!;
      final x = p.dx.round();
      final y = p.dy.round();
      bool hit = false;
      for (int dy = -2; dy <= 2 && !hit; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          final xx = x + dx;
          final yy = y + dy;
          if (xx >= 0 && yy >= 0 && xx < w && yy < h && mask[yy * w + xx] == 1) {
            hit = true;
            break;
          }
        }
      }
      if (hit) hits++;
    }
    return hits / (samples + 1);
  }

  static bool _inBounds(Offset p, int w, int h) => p.dx >= 0 && p.dy >= 0 && p.dx < w && p.dy < h;

  static bool _insideWithMargin(List<Offset> quad, int w, int h, double margin) {
    final mx = w * margin;
    final my = h * margin;
    return quad.every((p) => p.dx >= -mx && p.dy >= -my && p.dx <= w + mx && p.dy <= h + my);
  }

  /// Rejects quads with corner angles far from 90° (perspective allows some skew).
  static bool _reasonableAngles(List<Offset> quad) {
    for (int i = 0; i < 4; i++) {
      final prev = quad[(i + 3) % 4] - quad[i];
      final next = quad[(i + 1) % 4] - quad[i];
      final cosAngle = (prev.dx * next.dx + prev.dy * next.dy) / (prev.distance * next.distance + 1e-9);
      final angle = acos(cosAngle.clamp(-1.0, 1.0)) * 180 / pi;
      if (angle < 45 || angle > 135) return false;
    }
    return true;
  }

  static double _polygonArea(List<Offset> pts) {
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].dx * pts[j].dy - pts[j].dx * pts[i].dy;
    }
    return (area / 2.0).abs();
  }
}

class _Line {
  final double theta;
  final double rho;
  final int votes;
  final bool isBorder;

  _Line(this.theta, this.rho, this.votes) : isBorder = false;

  _Line.border(this.theta, this.rho)
      : votes = 0,
        isBorder = true;

  /// Normal angle near 90° means the line itself is near horizontal.
  bool get isHorizontal => (theta * 180 / pi - 90).abs() <= 35;

  bool isNear(_Line o, int w, int h) {
    return isHorizontal
        ? (midY(w) - o.midY(w)).abs() < 10 && (_tiltDeg - o._tiltDeg).abs() < 4
        : (midX(h) - o.midX(h)).abs() < 10 && (_tiltDeg - o._tiltDeg).abs() < 4;
  }

  /// Signed deviation of the line from its axis, in degrees (handles the 0°/180° wrap).
  double get _tiltDeg {
    final deg = theta * 180 / pi;
    if (isHorizontal) return deg - 90;
    return deg > 90 ? deg - 180 : deg;
  }

  double midY(int w) {
    final s = sin(theta);
    return s.abs() < 1e-9 ? 0 : (rho - (w / 2) * cos(theta)) / s;
  }

  double midX(int h) {
    final c = cos(theta);
    return c.abs() < 1e-9 ? 0 : (rho - (h / 2) * sin(theta)) / c;
  }

  Offset? intersect(_Line o) {
    final det = cos(theta) * sin(o.theta) - sin(theta) * cos(o.theta);
    if (det.abs() < 1e-9) return null;
    final x = (rho * sin(o.theta) - o.rho * sin(theta)) / det;
    final y = (o.rho * cos(theta) - rho * cos(o.theta)) / det;
    return Offset(x, y);
  }
}
