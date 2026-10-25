import 'dart:typed_data';
import 'package:cam_scan/core/cv/edge_detector.dart';
import 'package:cam_scan/core/cv/filter_engine.dart';
import 'package:cam_scan/core/cv/image_buffers.dart';
import 'package:cam_scan/core/cv/image_ingest.dart';
import 'package:cam_scan/core/cv/orientation_detector.dart';
import 'package:cam_scan/core/cv/perspective_transformer.dart';
import 'package:cam_scan/core/models/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/synthetic_images.dart';

void main() {
  group('Document edge detection', () {
    test('finds a skewed page on a cluttered desk', () {
      final page = [
        img.Point(330, 140),
        img.Point(880, 175),
        img.Point(850, 830),
        img.Point(290, 800),
      ];
      final photo = syntheticDeskPhoto(page: page);
      final corners = DocumentEdgeDetector.detectCorners(photo).toList();
      for (int i = 0; i < 4; i++) {
        expect((corners[i] - Offset(page[i].x.toDouble(), page[i].y.toDouble())).distance, lessThan(25),
            reason: 'corner $i: ${corners[i]} vs ${page[i]}');
      }
    });

    test('a page filling the whole frame resolves to the full image', () {
      final closeUp = syntheticTextPage(width: 900, height: 1200);
      final corners = DocumentEdgeDetector.detectCorners(closeUp);
      expect(corners.topLeft, const Offset(0, 0));
      expect(corners.bottomRight, const Offset(900, 1200));
    });
  });

  group('Text orientation detection', () {
    final page = syntheticTextPage();
    for (final contentRotation in const [0, 90, 180, 270]) {
      test('content rotated $contentRotation° clockwise is detected', () {
        final rotated = ImageBuffers.rotate(page, contentRotation);
        final estimate = TextOrientationDetector.detect(rotated);
        expect(estimate.rotation, (360 - contentRotation) % 360, reason: '$estimate');
        expect(estimate.isReliable, isTrue, reason: '$estimate');
      });
    }

    test('a blank page is left alone', () {
      final blank = img.Image(width: 600, height: 800)..clear(img.ColorRgb8(250, 250, 250));
      final estimate = TextOrientationDetector.detect(blank);
      expect(estimate.rotation, 0);
    });
  });

  group('Perspective warp', () {
    test('rectifies a quad into a planar image of matching size', () {
      final source = img.Image(width: 400, height: 300)..clear(img.ColorRgb8(30, 30, 30));
      img.fillRect(source, x1: 60, y1: 50, x2: 340, y2: 250, color: img.ColorRgb8(240, 240, 240));
      const corners = DocumentCorners(
        topLeft: Offset(60, 50),
        topRight: Offset(340, 50),
        bottomRight: Offset(340, 250),
        bottomLeft: Offset(60, 250),
      );
      final warped = PerspectiveTransformer.warpPerspective(source, corners);
      expect(warped.width, closeTo(280, 2));
      expect(warped.height, closeTo(200, 2));
      expect(warped.getPixel(warped.width ~/ 2, warped.height ~/ 2).r, greaterThan(200));
    });

    test('caps the output size for huge photos', () {
      final source = img.Image(width: 4000, height: 3000);
      final warped = PerspectiveTransformer.warpPerspective(source, DocumentCorners.fullImage(4000, 3000));
      expect(warped.width, PerspectiveTransformer.maxOutputDimension);
    });
  });

  group('Filters', () {
    // Paper lit unevenly (bright → shadowed) with dark text strokes.
    img.Image shadowedPage() {
      final page = img.Image(width: 400, height: 300);
      for (int y = 0; y < 300; y++) {
        for (int x = 0; x < 400; x++) {
          final paper = 230 - (x * 110 ~/ 400);
          page.setPixelRgb(x, y, paper, paper, paper - 5);
        }
      }
      for (int y = 40; y < 280; y += 30) {
        img.fillRect(page, x1: 30, y1: y, x2: 370, y2: y + 4, color: img.ColorRgb8(15, 15, 15));
      }
      return page;
    }

    test('Magic Color whitens shadowed paper and keeps text dark', () {
      final out = DocumentFilterEngine.applyFilter(shadowedPage(), ScanFilterType.magicColor);
      expect(out.getPixel(20, 20).r, greaterThanOrEqualTo(235), reason: 'bright paper');
      expect(out.getPixel(380, 20).r, greaterThanOrEqualTo(235), reason: 'shadowed paper');
      expect(out.getPixel(200, 42).r, lessThan(80), reason: 'text stroke');
    });

    test('Sharp B&W is binary and robust to shadows', () {
      final out = DocumentFilterEngine.applyFilter(shadowedPage(), ScanFilterType.sharpBW);
      for (final p in out) {
        expect(p.r == 0 || p.r == 255, isTrue);
      }
      expect(out.getPixel(385, 20).r, 255, reason: 'shadowed paper must not turn black');
      expect(out.getPixel(360, 42).r, 0, reason: 'text in the shadow stays black');
    });

    test('gray filters survive JPEG encoding as gray (not red)', () {
      for (final filter in [ScanFilterType.sharpBW, ScanFilterType.grayscale]) {
        final out = DocumentFilterEngine.applyFilter(shadowedPage(), filter);
        final decoded = img.decodeJpg(Uint8List.fromList(img.encodeJpg(out)))!;
        final paper = decoded.getPixel(20, 20);
        expect((paper.r - paper.g).abs(), lessThan(8), reason: '$filter paper must be neutral gray/white');
        expect((paper.r - paper.b).abs(), lessThan(8), reason: '$filter paper must be neutral gray/white');
        expect(paper.g, greaterThan(200), reason: '$filter paper must be light');
      }
    });

    test('Magic Color makes slightly blurry gray text black, keeping stroke edges', () {
      final page = img.Image(width: 300, height: 120)..clear(img.ColorRgb8(205, 203, 198));
      // A soft stroke: core at 110, anti-aliased edges at 160.
      img.fillRect(page, x1: 20, y1: 50, x2: 280, y2: 51, color: img.ColorRgb8(160, 160, 160));
      img.fillRect(page, x1: 20, y1: 52, x2: 280, y2: 55, color: img.ColorRgb8(110, 110, 110));
      img.fillRect(page, x1: 20, y1: 56, x2: 280, y2: 57, color: img.ColorRgb8(160, 160, 160));
      final out = DocumentFilterEngine.applyFilter(page, ScanFilterType.magicColor);
      expect(out.getPixel(150, 53).r, lessThan(40), reason: 'stroke core becomes black');
      expect(out.getPixel(150, 50).r, lessThan(200), reason: 'stroke edge is kept, not whitened away');
      expect(out.getPixel(150, 10).r, 255, reason: 'paper becomes white');
    });

    test('Grayscale, Lighten and Original keep dimensions', () {
      final src = shadowedPage();
      for (final filter in [ScanFilterType.grayscale, ScanFilterType.lighten, ScanFilterType.original]) {
        final out = DocumentFilterEngine.applyFilter(src, filter);
        expect(out.width, src.width);
        expect(out.height, src.height);
      }
    });
  });

  group('Image ingestion', () {
    test('bakes EXIF orientation into the pixels', () {
      final landscape = img.Image(width: 40, height: 20);
      landscape.exif.imageIfd.orientation = 6;
      final normalized = ImageIngest.normalize(Uint8List.fromList(img.encodeJpg(landscape)));
      final decoded = img.decodeJpg(normalized)!;
      expect(decoded.width, 20);
      expect(decoded.height, 40);
      expect(decoded.exif.imageIfd.orientation ?? 1, 1);
    });

    test('passes upright JPEGs through unchanged', () {
      final bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 64, height: 48)));
      expect(identical(ImageIngest.normalize(bytes), bytes), isTrue);
    });

    test('rejects undecodable data', () {
      expect(() => ImageIngest.normalize(Uint8List.fromList(List.filled(64, 7))), throwsA(isA<UnsupportedImageException>()));
    });
  });

  group('ImageBuffers', () {
    test('rotation by quarter turns maps pixels correctly', () {
      final src = img.Image(width: 3, height: 2);
      src.setPixelRgb(0, 0, 255, 0, 0); // top-left red
      final cw = ImageBuffers.rotate(src, 90);
      expect(cw.width, 2);
      expect(cw.height, 3);
      expect(cw.getPixel(1, 0).r, 255, reason: 'top-left moves to top-right after 90° clockwise');
      final back = ImageBuffers.rotate(cw, 270);
      expect(back.getPixel(0, 0).r, 255);
    });
  });
}
