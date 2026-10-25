import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cam_scan/core/models/document.dart';
import 'package:cam_scan/core/cv/edge_detector.dart';
import 'package:cam_scan/core/cv/perspective_transformer.dart';
import 'package:cam_scan/core/cv/filter_engine.dart';

void main() {
  group('Computer Vision Engine Tests', () {
    late img.Image testImage;

    setUp(() {
      // Create a 400x300 image with a white document on a dark background
      testImage = img.Image(width: 400, height: 300);
      img.fill(testImage, color: img.ColorRgb8(30, 30, 30));

      // Draw a white rectangle simulating a page (60..340, 50..250)
      for (int y = 50; y < 250; y++) {
        for (int x = 60; x < 340; x++) {
          testImage.setPixelRgba(x, y, 240, 240, 240, 255);
        }
      }

      // Add simulated dark text lines
      for (int y = 80; y < 220; y += 20) {
        for (int x = 80; x < 300; x++) {
          testImage.setPixelRgba(x, y, 10, 10, 10, 255);
        }
      }
    });

    test('DocumentEdgeDetector detects document boundaries', () {
      final DocumentCorners corners = DocumentEdgeDetector.detectCorners(testImage);

      expect(corners.topLeft.dx, lessThan(corners.topRight.dx));
      expect(corners.bottomLeft.dx, lessThan(corners.bottomRight.dx));
      expect(corners.topLeft.dy, lessThan(corners.bottomLeft.dy));
      expect(corners.topRight.dy, lessThan(corners.bottomRight.dy));

      // Check bounds approximately match the drawn page (60..340, 50..250)
      expect(corners.topLeft.dx, closeTo(60, 35));
      expect(corners.topLeft.dy, closeTo(50, 35));
      expect(corners.bottomRight.dx, closeTo(340, 35));
      expect(corners.bottomRight.dy, closeTo(250, 35));
    });

    test('PerspectiveTransformer rectifies quadrilateral to planar image', () {
      const DocumentCorners corners = DocumentCorners(
        topLeft: Offset(60, 50),
        topRight: Offset(340, 50),
        bottomRight: Offset(340, 250),
        bottomLeft: Offset(60, 250),
      );

      final img.Image warped = PerspectiveTransformer.warpPerspective(testImage, corners);

      expect(warped.width, closeTo(280, 5));
      expect(warped.height, closeTo(200, 5));

      // Center pixel of warped document should be document color
      final img.Pixel center = warped.getPixel(warped.width ~/ 2, warped.height ~/ 2);
      expect(center.r, greaterThan(0));
    });

    test('DocumentFilterEngine applies Magic Color filter correctly', () {
      final img.Image magic = DocumentFilterEngine.applyFilter(testImage, ScanFilterType.magicColor);

      expect(magic.width, equals(testImage.width));
      expect(magic.height, equals(testImage.height));

      // White area should remain high luminance
      final img.Pixel paper = magic.getPixel(150, 150);
      expect(paper.r, greaterThanOrEqualTo(180));
    });

    test('DocumentFilterEngine applies Sharp B&W binarization', () {
      final img.Image bw = DocumentFilterEngine.applyFilter(testImage, ScanFilterType.sharpBW);

      expect(bw.width, equals(testImage.width));
      expect(bw.height, equals(testImage.height));

      // Every pixel in sharpBW must be either 0 or 255
      for (final p in bw) {
        expect(p.r == 0 || p.r == 255, isTrue);
      }
    });

    test('DocumentFilterEngine applies Grayscale and Lighten', () {
      final img.Image gray = DocumentFilterEngine.applyFilter(testImage, ScanFilterType.grayscale);
      expect(gray.width, equals(testImage.width));

      final img.Image light = DocumentFilterEngine.applyFilter(testImage, ScanFilterType.lighten);
      expect(light.width, equals(testImage.width));
    });
  });
}

