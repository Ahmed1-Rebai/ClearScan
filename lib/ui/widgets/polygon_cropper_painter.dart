import 'package:flutter/material.dart';
import '../../core/models/document.dart';

/// Paints the interactive 4-corner crop overlay (corners in display coordinates).
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

    final Path fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path docPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, docPath),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final Paint gridPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.25)
      ..strokeWidth = 1.0;
    for (int i = 1; i <= 2; i++) {
      final double t = i / 3.0;
      canvas.drawLine(Offset.lerp(pts[0], pts[3], t)!, Offset.lerp(pts[1], pts[2], t)!, gridPaint);
      canvas.drawLine(Offset.lerp(pts[0], pts[1], t)!, Offset.lerp(pts[3], pts[2], t)!, gridPaint);
    }

    canvas.drawPath(
      docPath,
      Paint()
        ..color = primaryColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    final Paint handleFill = Paint()..color = Colors.white;
    final Paint handleBorder = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final Paint activeHandleFill = Paint()..color = primaryColor;

    for (int i = 0; i < 4; i++) {
      final pt = pts[i];
      final bool isActive = activeCornerIndex == i;
      canvas.drawCircle(pt, isActive ? 16 : 12, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(pt, isActive ? 14 : 10, isActive ? activeHandleFill : handleFill);
      canvas.drawCircle(pt, isActive ? 14 : 10, handleBorder);
      canvas.drawCircle(pt, 3.5, Paint()..color = isActive ? Colors.white : primaryColor);
    }

    final Paint midPointPaint = Paint()..color = primaryColor.withValues(alpha: 0.8);
    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(Offset.lerp(pts[i], pts[(i + 1) % 4], 0.5)!, 5.0, midPointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PolygonCropperPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.activeCornerIndex != activeCornerIndex ||
        oldDelegate.primaryColor != primaryColor;
  }
}
