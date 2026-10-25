import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Floating circular loupe widget that magnifies the area around the user's touch.
class MagnifierLoupe extends StatelessWidget {
  final Offset position;
  final ui.Image? image;
  final Size displaySize;
  final double loupeRadius;
  final double magnification;

  const MagnifierLoupe({
    super.key,
    required this.position,
    required this.image,
    required this.displaySize,
    this.loupeRadius = 55.0,
    this.magnification = 2.2,
  });

  @override
  Widget build(BuildContext context) {
    if (image == null) return const SizedBox.shrink();

    // Position loupe offset above the finger so it's not obscured
    final double loupeX = position.dx - loupeRadius;
    final double loupeY = position.dy - loupeRadius * 2.3;

    return Positioned(
      left: loupeX.clamp(10.0, displaySize.width - loupeRadius * 2 - 10),
      top: loupeY.clamp(10.0, displaySize.height - loupeRadius * 2 - 10),
      child: Container(
        width: loupeRadius * 2,
        height: loupeRadius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black,
          border: Border.all(color: const Color(0xFF00E5FF), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Stack(
            children: [
              CustomPaint(
                size: Size(loupeRadius * 2, loupeRadius * 2),
                painter: _LoupeImagePainter(
                  image: image!,
                  touchPoint: position,
                  displaySize: displaySize,
                  magnification: magnification,
                ),
              ),
              // Crosshair indicator at the exact center
              Center(
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _CrosshairPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoupeImagePainter extends CustomPainter {
  final ui.Image image;
  final Offset touchPoint;
  final Size displaySize;
  final double magnification;

  _LoupeImagePainter({
    required this.image,
    required this.touchPoint,
    required this.displaySize,
    required this.magnification,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = image.width / displaySize.width;
    final double scaleY = image.height / displaySize.height;

    final double imgCenterX = touchPoint.dx * scaleX;
    final double imgCenterY = touchPoint.dy * scaleY;

    final double cropW = (size.width / magnification) * scaleX;
    final double cropH = (size.height / magnification) * scaleY;

    final Rect srcRect = Rect.fromCenter(
      center: Offset(imgCenterX, imgCenterY),
      width: cropW,
      height: cropH,
    );

    final Rect dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(image, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(covariant _LoupeImagePainter oldDelegate) =>
      oldDelegate.touchPoint != touchPoint;
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.5;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawLine(Offset(cx - 8, cy), Offset(cx + 8, cy), paint);
    canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), paint);
    canvas.drawCircle(Offset(cx, cy), 3, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

