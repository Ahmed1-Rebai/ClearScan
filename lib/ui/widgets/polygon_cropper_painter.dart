import 'package:flutter/material.dart';
import '../../core/models/document.dart';

/// CustomPainter for rendering interactive 4-corner document cropping overlay.
class PolygonCropperPainter extends CustomPainter {
  final DocumentCorners corners;
  final int? activeCornerIndex;
  final Color primaryColor;

  PolygonCropperPainter({
    required this.corners,
    this.activeCornerIndex,
    this.primaryColor = const Color(0xFF00E5FF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<Offset> pts = corners.toList();

    // 1. Dim the exterior area outside the document
    final Path fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path docPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    final Path dimPath = Path.combine(PathOperation.difference, fullPath, docPath);
    canvas.drawPath(dimPath, Paint()..color = Colors.black.withOpacity(0.55));

    // 2. Draw 3x3 internal perspective alignment grid
    final Paint gridPaint = Paint()
      ..color = primaryColor.withOpacity(0.25)
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 2; i++) {
      final double t = i / 3.0;
      // Horizontal grid lines
      final Offset left = Offset.lerp(pts[0], pts[3], t)!;
      final Offset right = Offset.lerp(pts[1], pts[2], t)!;
      canvas.drawLine(left, right, gridPaint);

      // Vertical grid lines
      final Offset top = Offset.lerp(pts[0], pts[1], t)!;
      final Offset bottom = Offset.lerp(pts[3], pts[2], t)!;
      canvas.drawLine(top, bottom, gridPaint);
    }

    // 3. Draw Document Bounding Quad Lines
    final Paint borderPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(docPath, borderPaint);

    // 4. Draw Corner Handles & Midpoints
    final Paint handleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final Paint handleBorder = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint activeHandleFill = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final pt = pts[i];
      final bool isActive = activeCornerIndex == i;

      // Outer glow/shadow
      canvas.drawCircle(pt, isActive ? 16 : 12, Paint()..color = Colors.black.withOpacity(0.35));

      // Handle circle
      canvas.drawCircle(pt, isActive ? 14 : 10, isActive ? activeHandleFill : handleFill);
      canvas.drawCircle(pt, isActive ? 14 : 10, handleBorder);

      // Inner dot
      canvas.drawCircle(pt, 3.5, Paint()..color = isActive ? Colors.white : primaryColor);
    }

    // Draw edge midpoint indicators
    final Paint midPointPaint = Paint()
      ..color = primaryColor.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final int next = (i + 1) % 4;
      final Offset mid = Offset.lerp(pts[i], pts[next], 0.5)!;
      canvas.drawCircle(mid, 5.0, midPointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PolygonCropperPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.activeCornerIndex != activeCornerIndex ||
        oldDelegate.primaryColor != primaryColor;
  }
}

