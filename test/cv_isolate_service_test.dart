import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cam_scan/core/cv/cv_isolate_service.dart';
import 'package:cam_scan/core/cv/filter_engine.dart';
import 'package:cam_scan/core/models/document.dart';

void main() {
  group('CvIsolateService Background Isolate Worker Tests', () {
    late img.Image testImage;
    late Uint8List testJpgBytes;

    setUp(() {
      testImage = img.Image(width: 400, height: 500);
      img.fill(testImage, color: img.ColorRgb8(240, 240, 240));
      testJpgBytes = Uint8List.fromList(img.encodeJpg(testImage));
    });

    test('decodeImageAsync decodes bytes in background isolate', () async {
      final decoded = await CvIsolateService.decodeImageAsync(testJpgBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(400));
      expect(decoded!.height, equals(500));
    });

    test('detectCornersAsync executes Sobel Canny detection in background isolate', () async {
      final corners = await CvIsolateService.detectCornersAsync(testImage);
      expect(corners.topLeft.dx, greaterThanOrEqualTo(0));
      expect(corners.bottomRight.dx, lessThanOrEqualTo(400));
    });

    test('warpPerspectiveAsync computes perspective warp in background isolate', () async {
      final corners = DocumentCorners(
        topLeft: const Offset(20, 20),
        topRight: const Offset(380, 25),
        bottomRight: const Offset(375, 480),
        bottomLeft: const Offset(25, 475),
      );

      final warped = await CvIsolateService.warpPerspectiveAsync(testImage, corners);
      expect(warped.width, greaterThan(100));
      expect(warped.height, greaterThan(100));
    });

    test('applyFilterAndEncodeAsync executes filter and JPEG compression in single isolate', () async {
      final bytes = await CvIsolateService.applyFilterAndEncodeAsync(
        testImage,
        ScanFilterType.magicColor,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));
    });

    test('rotateAsync rotates image in background isolate', () async {
      final rotated = await CvIsolateService.rotateAsync(testImage, 90);
      expect(rotated.width, equals(500));
      expect(rotated.height, equals(400));
    });
  });
}
