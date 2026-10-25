import 'dart:math';
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../models/document.dart';

/// Perspective transformation and document de-warping engine.
/// Computes the projective homography matrix and resamples pixels with bilinear interpolation.
class PerspectiveTransformer {
  /// Warps the quadrilateral defined by [corners] in [sourceImage] to a flat, rectified rectangle.
  static img.Image warpPerspective(img.Image sourceImage, DocumentCorners corners) {
    final Offset tl = corners.topLeft;
    final Offset tr = corners.topRight;
    final Offset br = corners.bottomRight;
    final Offset bl = corners.bottomLeft;

    // 1. Calculate destination dimensions based on max opposing edge lengths
    final double widthTop = _distance(tl, tr);
    final double widthBottom = _distance(bl, br);
    final int dstW = max(widthTop, widthBottom).round().clamp(100, 4000);

    final double heightLeft = _distance(tl, bl);
    final double heightRight = _distance(tr, br);
    final int dstH = max(heightLeft, heightRight).round().clamp(100, 4000);

    final img.Image result = img.Image(width: dstW, height: dstH, numChannels: sourceImage.numChannels);

    // 2. Compute 3x3 Inverse Homography Matrix: dst (x,y) -> src (u,v)
    final List<double> matrix = _computeHomography(
      srcPts: [
        const Offset(0, 0),
        Offset(dstW.toDouble() - 1, 0),
        Offset(dstW.toDouble() - 1, dstH.toDouble() - 1),
        Offset(0, dstH.toDouble() - 1),
      ],
      dstPts: [tl, tr, br, bl],
    );

    final double m00 = matrix[0], m01 = matrix[1], m02 = matrix[2];
    final double m10 = matrix[3], m11 = matrix[4], m12 = matrix[5];
    final double m20 = matrix[6], m21 = matrix[7], m22 = matrix[8];

    final int srcW = sourceImage.width;
    final int srcH = sourceImage.height;

    // 3. Resample every target pixel with Bilinear Interpolation
    for (int y = 0; y < dstH; y++) {
      for (int x = 0; x < dstW; x++) {
        final double wPrime = m20 * x + m21 * y + m22;
        if (wPrime.abs() < 1e-7) continue;

        final double invW = 1.0 / wPrime;
        final double srcX = (m00 * x + m01 * y + m02) * invW;
        final double srcY = (m10 * x + m11 * y + m12) * invW;

        if (srcX >= 0 && srcX < srcW - 1 && srcY >= 0 && srcY < srcH - 1) {
          _sampleAndSetBilinear(sourceImage, result, x, y, srcX, srcY);
        } else if (srcX >= 0 && srcX < srcW && srcY >= 0 && srcY < srcH) {
          final p = sourceImage.getPixel(srcX.floor(), srcY.floor());
          result.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
        }
      }
    }

    return result;
  }

  static double _distance(Offset p1, Offset p2) {
    final double dx = p1.dx - p2.dx;
    final double dy = p1.dy - p2.dy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Bilinear interpolation sampler for anti-aliased sub-pixel mapping.
  static void _sampleAndSetBilinear(
    img.Image src,
    img.Image dst,
    int dstX,
    int dstY,
    double x,
    double y,
  ) {
    final int x1 = x.floor();
    final int y1 = y.floor();
    final int x2 = min(x1 + 1, src.width - 1);
    final int y2 = min(y1 + 1, src.height - 1);

    final double fx = x - x1;
    final double fy = y - y1;
    final double ifx = 1.0 - fx;
    final double ify = 1.0 - fy;

    final img.Pixel p11 = src.getPixel(x1, y1);
    final img.Pixel p21 = src.getPixel(x2, y1);
    final img.Pixel p12 = src.getPixel(x1, y2);
    final img.Pixel p22 = src.getPixel(x2, y2);

    final double r = (p11.r * ifx + p21.r * fx) * ify + (p12.r * ifx + p22.r * fx) * fy;
    final double g = (p11.g * ifx + p21.g * fx) * ify + (p12.g * ifx + p22.g * fx) * fy;
    final double b = (p11.b * ifx + p21.b * fx) * ify + (p12.b * ifx + p22.b * fx) * fy;
    final double a = (p11.a * ifx + p21.a * fx) * ify + (p12.a * ifx + p22.a * fx) * fy;

    dst.setPixelRgba(
      dstX,
      dstY,
      r.round().clamp(0, 255),
      g.round().clamp(0, 255),
      b.round().clamp(0, 255),
      a.round().clamp(0, 255),
    );
  }

  /// Computes the 3x3 Projective Transformation Matrix mapping [srcPts] to [dstPts]
  /// using Direct Linear Transform (DLT) with Gaussian elimination.
  static List<double> _computeHomography({
    required List<Offset> srcPts,
    required List<Offset> dstPts,
  }) {
    // 8x8 Linear System: A * h = b
    final List<List<double>> a = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final List<double> b = List<double>.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final double sx = srcPts[i].dx;
      final double sy = srcPts[i].dy;
      final double dx = dstPts[i].dx;
      final double dy = dstPts[i].dy;

      final int r1 = i * 2;
      final int r2 = r1 + 1;

      a[r1][0] = sx;
      a[r1][1] = sy;
      a[r1][2] = 1.0;
      a[r1][3] = 0.0;
      a[r1][4] = 0.0;
      a[r1][5] = 0.0;
      a[r1][6] = -sx * dx;
      a[r1][7] = -sy * dx;
      b[r1] = dx;

      a[r2][0] = 0.0;
      a[r2][0] = 0.0;
      a[r2][2] = 0.0;
      a[r2][3] = sx;
      a[r2][4] = sy;
      a[r2][5] = 1.0;
      a[r2][6] = -sx * dy;
      a[r2][7] = -sy * dy;
      b[r2] = dy;
    }

    final List<double> h = _solveGaussian(a, b);
    return [
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ];
  }

  /// Gaussian elimination solver with partial pivoting for numerical stability.
  static List<double> _solveGaussian(List<List<double>> a, List<double> b) {
    final int n = b.length;
    for (int i = 0; i < n; i++) {
      // Pivot selection
      int maxRow = i;
      double maxVal = a[i][i].abs();
      for (int k = i + 1; k < n; k++) {
        if (a[k][i].abs() > maxVal) {
          maxVal = a[k][i].abs();
          maxRow = k;
        }
      }

      // Swap rows
      final List<double> tempA = a[i];
      a[i] = a[maxRow];
      a[maxRow] = tempA;

      final double tempB = b[i];
      b[i] = b[maxRow];
      b[maxRow] = tempB;

      // Normalize row
      final double pivot = a[i][i];
      if (pivot.abs() < 1e-12) continue;

      for (int j = i; j < n; j++) {
        a[i][j] /= pivot;
      }
      b[i] /= pivot;

      // Eliminate other rows
      for (int k = 0; k < n; k++) {
        if (k != i) {
          final double factor = a[k][i];
          for (int j = i; j < n; j++) {
            a[k][j] -= factor * a[i][j];
          }
          b[k] -= factor * b[i];
        }
      }
    }
    return b;
  }
}

