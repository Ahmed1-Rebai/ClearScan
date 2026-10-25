import 'dart:math';
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../models/document.dart';

/// Pure-Dart Document Edge and Corner Detector.
/// Detects rectangular document boundaries in camera captures and images without native C++ bloat.
class DocumentEdgeDetector {
  static const int processingMaxDim = 600;

  /// Detects the 4 corners of a document in the given [image].
  /// Returns [DocumentCorners] in original image coordinates.
  static DocumentCorners detectCorners(img.Image image) {
    final int origW = image.width;
    final int origH = image.height;

    // 1. Calculate downscale ratio for real-time performance
    final double scale = max(origW, origH) > processingMaxDim
        ? processingMaxDim / max(origW, origH)
        : 1.0;

    final int targetW = (origW * scale).round();
    final int targetH = (origH * scale).round();

    final img.Image downscaled = img.copyResize(
      image,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );

    // 2. Convert to grayscale & apply Gaussian blur to suppress noise
    final img.Image gray = img.grayscale(downscaled);
    final img.Image blurred = img.gaussianBlur(gray, radius: 2);

    // 3. Compute Sobel Edge Gradients
    final List<int> edgeMap = _computeSobelEdges(blurred);

    // 4. Find candidate corners using extreme projections
    final DocumentCorners? detected = _findQuadCorners(
      edgeMap,
      targetW,
      targetH,
    );

    if (detected != null) {
      // Scale back to original resolution
      final double invScale = 1.0 / scale;
      return DocumentCorners(
        topLeft: Offset(detected.topLeft.dx * invScale, detected.topLeft.dy * invScale),
        topRight: Offset(detected.topRight.dx * invScale, detected.topRight.dy * invScale),
        bottomRight: Offset(detected.bottomRight.dx * invScale, detected.bottomRight.dy * invScale),
        bottomLeft: Offset(detected.bottomLeft.dx * invScale, detected.bottomLeft.dy * invScale),
      );
    }

    // Fallback: inset 6% from boundary
    return DocumentCorners.defaultRect(origW.toDouble(), origH.toDouble());
  }

  /// Calculates Sobel gradient magnitude for each pixel.
  static List<int> _computeSobelEdges(img.Image imgGray) {
    final int w = imgGray.width;
    final int h = imgGray.height;
    final List<int> edges = List<int>.filled(w * h, 0);

    // Threshold for strong edges
    const int threshold = 55;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        // Pixel neighbors in 3x3 window
        final int p00 = imgGray.getPixel(x - 1, y - 1).r.toInt();
        final int p01 = imgGray.getPixel(x, y - 1).r.toInt();
        final int p02 = imgGray.getPixel(x + 1, y - 1).r.toInt();

        final int p10 = imgGray.getPixel(x - 1, y).r.toInt();
        final int p12 = imgGray.getPixel(x + 1, y).r.toInt();

        final int p20 = imgGray.getPixel(x - 1, y + 1).r.toInt();
        final int p21 = imgGray.getPixel(x, y + 1).r.toInt();
        final int p22 = imgGray.getPixel(x + 1, y + 1).r.toInt();

        // Sobel kernels
        // Gx: [-1 0 1; -2 0 2; -1 0 1]
        // Gy: [-1 -2 -1; 0 0 0; 1 2 1]
        final int gx = (p02 + 2 * p12 + p22) - (p00 + 2 * p10 + p20);
        final int gy = (p20 + 2 * p21 + p22) - (p00 + 2 * p01 + p02);

        final int mag = (gx.abs() + gy.abs());
        if (mag > threshold) {
          edges[y * w + x] = mag;
        }
      }
    }

    return edges;
  }

  /// Finds the 4 quadrilateral corners by projecting edge pixels along diagonals:
  /// - Top-Left: minimizes (x + y)
  /// - Bottom-Right: maximizes (x + y)
  /// - Top-Right: maximizes (x - y)
  /// - Bottom-Left: minimizes (x - y)
  static DocumentCorners? _findQuadCorners(List<int> edgeMap, int w, int h) {
    int minSum = 99999999;
    int maxSum = -99999999;
    int minDiff = 99999999;
    int maxDiff = -99999999;

    Point<int>? tl;
    Point<int>? br;
    Point<int>? tr;
    Point<int>? bl;

    int edgeCount = 0;

    // Exclude outer margin border (first/last 2% to avoid table borders)
    final int marginX = (w * 0.02).round();
    final int marginY = (h * 0.02).round();

    for (int y = marginY; y < h - marginY; y++) {
      final int rowOffset = y * w;
      for (int x = marginX; x < w - marginX; x++) {
        final int mag = edgeMap[rowOffset + x];
        if (mag > 0) {
          edgeCount++;
          final int sum = x + y;
          final int diff = x - y;

          if (sum < minSum) {
            minSum = sum;
            tl = Point<int>(x, y);
          }
          if (sum > maxSum) {
            maxSum = sum;
            br = Point<int>(x, y);
          }
          if (diff > maxDiff) {
            maxDiff = diff;
            tr = Point<int>(x, y);
          }
          if (diff < minDiff) {
            minDiff = diff;
            bl = Point<int>(x, y);
          }
        }
      }
    }

    // Verify sufficient edge support and quadrilateral validity
    if (edgeCount < (w * h * 0.005) || tl == null || tr == null || br == null || bl == null) {
      return null;
    }

    // Calculate approximate area of the detected polygon
    final double area = _shoelaceArea([
      Offset(tl.x.toDouble(), tl.y.toDouble()),
      Offset(tr.x.toDouble(), tr.y.toDouble()),
      Offset(br.x.toDouble(), br.y.toDouble()),
      Offset(bl.x.toDouble(), bl.y.toDouble()),
    ]);

    final double totalArea = (w * h).toDouble();
    // Must occupy at least 15% and at most 98% of viewfinder
    if (area < totalArea * 0.15 || area > totalArea * 0.98) {
      return null;
    }

    return DocumentCorners(
      topLeft: Offset(tl.x.toDouble(), tl.y.toDouble()),
      topRight: Offset(tr.x.toDouble(), tr.y.toDouble()),
      bottomRight: Offset(br.x.toDouble(), br.y.toDouble()),
      bottomLeft: Offset(bl.x.toDouble(), bl.y.toDouble()),
    );
  }

  /// Calculates polygon area using the Shoelace formula.
  static double _shoelaceArea(List<Offset> pts) {
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final int j = (i + 1) % pts.length;
      area += pts[i].dx * pts[j].dy;
      area -= pts[j].dx * pts[i].dy;
    }
    return (area / 2.0).abs();
  }
}
