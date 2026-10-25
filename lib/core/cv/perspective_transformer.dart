import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import '../models/document.dart';
import 'image_buffers.dart';

/// Perspective transformation and document de-warping engine.
/// Computes the projective homography matrix and resamples pixels with bilinear interpolation.
class PerspectiveTransformer {
  /// Long-side cap for rectified pages: ~300 DPI for A4, enough for small print OCR.
  static const int maxOutputDimension = 3000;

  /// Warps the quadrilateral defined by [corners] in [sourceImage] to a flat, rectified rectangle.
  static img.Image warpPerspective(
    img.Image sourceImage,
    DocumentCorners corners, {
    int maxOutputDimension = maxOutputDimension,
  }) {
    final Offset tl = corners.topLeft;
    final Offset tr = corners.topRight;
    final Offset br = corners.bottomRight;
    final Offset bl = corners.bottomLeft;

    double targetW = max(_distance(tl, tr), _distance(bl, br));
    double targetH = max(_distance(tl, bl), _distance(tr, br));

    final double maxDim = max(targetW, targetH);
    if (maxDim > maxOutputDimension) {
      final double scaleDown = maxOutputDimension / maxDim;
      targetW *= scaleDown;
      targetH *= scaleDown;
    }

    final int dstW = targetW.round().clamp(16, maxOutputDimension);
    final int dstH = targetH.round().clamp(16, maxOutputDimension);

    // Inverse mapping: destination (x, y) -> source (u, v).
    final List<double> m = _computeHomography(
      srcPts: [
        const Offset(0, 0),
        Offset(dstW - 1.0, 0),
        Offset(dstW - 1.0, dstH - 1.0),
        Offset(0, dstH - 1.0),
      ],
      dstPts: [tl, tr, br, bl],
    );

    final Uint8List src = ImageBuffers.rgbBytes(sourceImage);
    final int srcW = sourceImage.width;
    final int srcH = sourceImage.height;
    final double maxU = srcW - 1.0;
    final double maxV = srcH - 1.0;
    final Uint8List out = Uint8List(dstW * dstH * 3);

    int o = 0;
    for (int y = 0; y < dstH; y++) {
      double nu = m[1] * y + m[2];
      double nv = m[4] * y + m[5];
      double dw = m[7] * y + m[8];
      for (int x = 0; x < dstW; x++, nu += m[0], nv += m[3], dw += m[6]) {
        if (dw.abs() < 1e-9) {
          o += 3;
          continue;
        }
        final double u = (nu / dw).clamp(0.0, maxU);
        final double v = (nv / dw).clamp(0.0, maxV);
        final int x0 = u.toInt();
        final int y0 = v.toInt();
        final int x1 = x0 < srcW - 1 ? x0 + 1 : x0;
        final int y1 = y0 < srcH - 1 ? y0 + 1 : y0;
        final double fx = u - x0;
        final double fy = v - y0;
        final double w00 = (1 - fx) * (1 - fy);
        final double w10 = fx * (1 - fy);
        final double w01 = (1 - fx) * fy;
        final double w11 = fx * fy;
        final int i00 = (y0 * srcW + x0) * 3;
        final int i10 = (y0 * srcW + x1) * 3;
        final int i01 = (y1 * srcW + x0) * 3;
        final int i11 = (y1 * srcW + x1) * 3;
        out[o++] = (src[i00] * w00 + src[i10] * w10 + src[i01] * w01 + src[i11] * w11 + 0.5).toInt();
        out[o++] = (src[i00 + 1] * w00 + src[i10 + 1] * w10 + src[i01 + 1] * w01 + src[i11 + 1] * w11 + 0.5).toInt();
        out[o++] = (src[i00 + 2] * w00 + src[i10 + 2] * w10 + src[i01 + 2] * w01 + src[i11 + 2] * w11 + 0.5).toInt();
      }
    }

    return ImageBuffers.fromRgb(dstW, dstH, out);
  }

  static double _distance(Offset p1, Offset p2) {
    final double dx = p1.dx - p2.dx;
    final double dy = p1.dy - p2.dy;
    return sqrt(dx * dx + dy * dy);
  }

  /// Computes the 3x3 Projective Transformation Matrix mapping [srcPts] to [dstPts]
  /// using Direct Linear Transform (DLT) with Gaussian elimination.
  static List<double> _computeHomography({
    required List<Offset> srcPts,
    required List<Offset> dstPts,
  }) {
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
      a[r1][6] = -sx * dx;
      a[r1][7] = -sy * dx;
      b[r1] = dx;

      a[r2][3] = sx;
      a[r2][4] = sy;
      a[r2][5] = 1.0;
      a[r2][6] = -sx * dy;
      a[r2][7] = -sy * dy;
      b[r2] = dy;
    }

    final List<double> h = _solveGaussian(a, b);
    return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0];
  }

  /// Gaussian elimination solver with partial pivoting for numerical stability.
  static List<double> _solveGaussian(List<List<double>> a, List<double> b) {
    final int n = b.length;
    for (int i = 0; i < n; i++) {
      int maxRow = i;
      double maxVal = a[i][i].abs();
      for (int k = i + 1; k < n; k++) {
        if (a[k][i].abs() > maxVal) {
          maxVal = a[k][i].abs();
          maxRow = k;
        }
      }

      final List<double> tempA = a[i];
      a[i] = a[maxRow];
      a[maxRow] = tempA;

      final double tempB = b[i];
      b[i] = b[maxRow];
      b[maxRow] = tempB;

      final double pivot = a[i][i];
      if (pivot.abs() < 1e-12) continue;

      for (int j = i; j < n; j++) {
        a[i][j] /= pivot;
      }
      b[i] /= pivot;

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
