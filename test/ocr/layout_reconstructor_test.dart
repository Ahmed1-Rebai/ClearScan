import 'package:cam_scan/core/ocr/layout_reconstructor.dart';
import 'package:cam_scan/core/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

OcrLineBox box(String text, double left, double top, {double width = 300, double height = 20, double? confidence}) =>
    OcrLineBox(text: text, left: left, top: top, right: left + width, bottom: top + height, confidence: confidence);

void main() {
  group('LayoutReconstructor', () {
    test('keeps receipt labels and amounts on the same row', () {
      // ML Kit often returns the label column and the amount column as separate blocks.
      final lines = [
        box('Latte', 40, 100, width: 120),
        box('Croissant', 40, 130, width: 160),
        box('Subtotal', 40, 160, width: 140),
        box('Total', 40, 190, width: 90),
        box('\$4.00', 600, 101, width: 80),
        box('\$2.50', 600, 131, width: 80),
        box('\$6.50', 600, 161, width: 80),
        box('\$6.50', 600, 191, width: 80),
      ];
      final text = LayoutReconstructor.reconstruct(lines).text;
      expect(text.split('\n'), [
        'Latte   \$4.00',
        'Croissant   \$2.50',
        'Subtotal   \$6.50',
        'Total   \$6.50',
      ]);
    });

    test('reads a two-column page column by column, after a full-width header', () {
      final lines = [
        box('TP N°2 — Services Web — Année universitaire 2026-2027', 40, 20, width: 1100),
        box('Exercice 1 : voici un fichier XML décrivant', 40, 100, width: 480),
        box('des étudiants et leurs coordonnées complètes.', 40, 128, width: 480),
        box('Exercice 2 : vous devez créer un programme', 640, 110, width: 480),
        box('en Java qui écrit un tableau de voitures.', 640, 138, width: 480),
        box('Transformez cette structure en JSON sans perte.', 40, 156, width: 480),
      ];
      final text = LayoutReconstructor.reconstruct(lines).text;
      final header = text.indexOf('TP N°2');
      final left1 = text.indexOf('Exercice 1');
      final left3 = text.indexOf('Transformez');
      final right1 = text.indexOf('Exercice 2');
      expect(header, lessThan(left1));
      expect(left1, lessThan(left3));
      expect(left3, lessThan(right1), reason: 'the whole left column comes before the right column');
    });

    test('joins words split by a line-end hyphen', () {
      final lines = [
        box('La comptabilité utilise un docu-', 40, 100),
        box('ment de synthèse annuel.', 40, 126),
      ];
      expect(LayoutReconstructor.reconstruct(lines).text, 'La comptabilité utilise un document de synthèse annuel.');
    });

    test('separates paragraphs and drops isolated noise', () {
      final lines = [
        box('First paragraph line.', 40, 100),
        box('|', 400, 105, width: 4),
        box('Second paragraph after a gap.', 40, 160),
      ];
      expect(LayoutReconstructor.reconstruct(lines).text, 'First paragraph line.\n\nSecond paragraph after a gap.');
    });

    test('widely spaced lines are not mistaken for paragraph breaks', () {
      // 1.5 line spacing: 20 px boxes with 16 px gaps; paragraphs separated by 50 px.
      final lines = [
        box('Le bilan est un tableau qui présente le patrimoine', 40, 100),
        box('de l’entreprise à une date donnée et il se compose', 40, 136),
        box('de deux colonnes : les actifs et les passifs.', 40, 172),
        box('Les actifs regroupent les emplois de l’entreprise.', 40, 242),
        box('Les passifs regroupent ses ressources financières.', 40, 278),
      ];
      final paragraphs = LayoutReconstructor.reconstruct(lines).text.split('\n\n');
      expect(paragraphs, hasLength(2));
      expect(paragraphs.first.split('\n'), hasLength(3));
    });

    test('fixes letter/digit confusions only inside numbers', () {
      expect(LayoutReconstructor.fixNumericToken('1O0,00'), '100,00');
      expect(LayoutReconstructor.fixNumericToken('l50.00'), '150.00');
      expect(LayoutReconstructor.fixNumericToken('2O26'), '2026');
      expect(LayoutReconstructor.fixNumericToken('ISO-8859-1'), 'ISO-8859-1');
      expect(LayoutReconstructor.fixNumericToken('Hello'), 'Hello');
      expect(LayoutReconstructor.fixNumericToken('Total'), 'Total');
    });

    test('repairs misread French elisions but keeps English contractions', () {
      expect(LayoutReconstructor.fixElisions("signés par I'entreprise"), "signés par l'entreprise");
      expect(LayoutReconstructor.fixElisions("dont 1'entreprise est"), "dont l'entreprise est");
      expect(LayoutReconstructor.fixElisions('à I’apport'), 'à l’apport');
      expect(LayoutReconstructor.fixElisions("I'm sure I'll go"), "I'm sure I'll go");
      expect(LayoutReconstructor.fixElisions("ISO'S"), "ISO'S");
    });

    test('empty input', () {
      expect(LayoutReconstructor.reconstruct(const []).text, '');
    });
  });

  group('OcrQuality', () {
    test('real text looks good, rotated-text gibberish does not', () {
      final good = OcrQuality.of([
        box('La comptabilité utilise un certain nombre de documents', 0, 0, confidence: 0.9),
        box('dont certains émanent de l’entreprise elle-même.', 0, 30, confidence: 0.85),
      ]);
      final bad = OcrQuality.of([
        box('l1 | ;: ii lI', 0, 0, confidence: 0.3),
        box('~ rr" ,1 _', 0, 30, confidence: 0.2),
      ]);
      expect(good.looksGood, isTrue);
      expect(bad.looksGood, isFalse);
      expect(good.score, greaterThan(bad.score * 5));
    });
  });
}
