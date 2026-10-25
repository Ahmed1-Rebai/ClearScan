import 'dart:io';
import 'dart:typed_data';
import 'package:cam_scan/core/cv/cv_isolate_service.dart';
import 'package:cam_scan/core/models/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/synthetic_images.dart';

void main() {
  group('CvIsolateService background isolates', () {
    late img.Image testImage;
    late Uint8List testJpgBytes;

    setUp(() {
      testImage = img.Image(width: 400, height: 500)..clear(img.ColorRgb8(240, 240, 240));
      testJpgBytes = Uint8List.fromList(img.encodeJpg(testImage));
    });

    test('decodeImageAsync decodes bytes', () async {
      final decoded = await CvIsolateService.decodeImageAsync(testJpgBytes);
      expect(decoded!.width, 400);
      expect(decoded.height, 500);
    });

    test('warpPerspectiveAsync computes the warp', () async {
      const corners = DocumentCorners(
        topLeft: Offset(20, 20),
        topRight: Offset(380, 25),
        bottomRight: Offset(375, 480),
        bottomLeft: Offset(25, 475),
      );
      final warped = await CvIsolateService.warpPerspectiveAsync(testImage, corners);
      expect(warped.width, greaterThan(300));
      expect(warped.height, greaterThan(400));
    });

    test('applyFilterAndEncodeAsync filters and encodes in one hop', () async {
      final bytes = await CvIsolateService.applyFilterAndEncodeAsync(testImage, ScanFilterType.magicColor);
      expect(img.decodeJpg(bytes)!.width, 400);
    });

    test('rotateAsync rotates clockwise', () async {
      final rotated = await CvIsolateService.rotateAsync(testImage, 90);
      expect(rotated.width, 500);
      expect(rotated.height, 400);
    });

    test('processPageAsync runs the full pipeline and turns sideways text upright', () async {
      final dir = await Directory.systemTemp.createTemp('clearscan_cv_');
      addTearDown(() => dir.delete(recursive: true));
      // A page whose text runs bottom-to-top (photographed sideways).
      final sideways = syntheticTextPage(width: 900, height: 1200);
      final raw = File('${dir.path}/raw.jpg')..writeAsBytesSync(img.encodeJpg(sideways));
      final rotatedRaw = File('${dir.path}/rotated.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.copyRotate(img.decodeJpg(raw.readAsBytesSync())!, angle: 270)));

      final result = await CvIsolateService.processPageAsync(
        rawPath: rotatedRaw.path,
        outputPath: '${dir.path}/out.jpg',
        filter: ScanFilterType.magicColor,
        autoOrient: true,
      );
      expect(result.rotation, 90);
      final out = img.decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!;
      expect(out.height, greaterThan(out.width), reason: 'the portrait page is upright again');
    });
  });
}
