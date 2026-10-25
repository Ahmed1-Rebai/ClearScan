import 'package:cam_scan/core/analysis/document_analyzer.dart';
import 'package:cam_scan/core/analysis/document_qa.dart';
import 'package:cam_scan/core/analysis/money.dart';
import 'package:cam_scan/core/analysis/text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'document_analyzer_test.dart' show tpSheet, tunisianInvoice;

void main() {
  group('Money.parse', () {
    test('English, French and three-decimal formats', () {
      expect(Money.parse('3,464.00'), 3464.0);
      expect(Money.parse('1.234,56'), 1234.56);
      expect(Money.parse('1 234,56'), 1234.56);
      expect(Money.parse('12,50'), 12.5);
      expect(Money.parse('45.9'), 45.9);
      expect(Money.parse('12,500'), 12500.0);
      expect(Money.parse('12,500', currency: 'DT'), 12.5);
      expect(Money.parse('1 250,000', currency: 'TND'), 1250.0);
    });
  });

  group('Money.findAll', () {
    test('ignores dates, times and percentages', () {
      final found = Money.findAll('Le 25/10/2026 à 14:07, TVA 19% : total 45.90€');
      expect(found.map((m) => m.raw), ['45.90€']);
      expect(found.single.currency, '€');
      expect(found.single.value, 45.9);
    });

    test('keeps currency codes and thousands separators', () {
      final found = Money.findAll('Net à payer 1 191,000 DT');
      expect(found.single.raw, '1 191,000 DT');
      expect(found.single.value, 1191.0);
      expect(found.single.looksMonetary, isTrue);
    });

    test('dominant currency', () {
      expect(Money.dominantCurrency('A 10,000 DT\nB 2,500 DT\nC \$3.00'), 'DT');
      expect(Money.dominantCurrency('no money here'), isNull);
    });
  });

  group('TextNormalizer', () {
    test('folding keeps length and strips accents', () {
      const s = "Date d'échéance";
      final folded = TextNormalizer.fold(s);
      expect(folded, "date d'echeance");
      expect(folded.length, s.length);
    });

    test('whole-word phrase matching', () {
      expect(TextNormalizer.containsPhrase('les factures envoyees', 'facture'), isFalse);
      expect(TextNormalizer.containsPhrase('facture n° 12', 'facture n'), isTrue);
      expect(TextNormalizer.containsPhrase('subtotal: 5', 'total'), isFalse);
    });
  });

  group('DocumentQa answers only from the document', () {
    test('says so when there is no total instead of guessing', () {
      final analysis = DocumentAnalyzer.analyze(tpSheet);
      final reply = DocumentQa.answer(question: 'What is the total amount?', documentText: tpSheet, analysis: analysis);
      expect(reply, 'No total amount is printed in this document.');
    });

    test('answers totals and due dates with their source line (French questions)', () {
      final analysis = DocumentAnalyzer.analyze(tunisianInvoice);
      final total = DocumentQa.answer(question: 'Quel est le montant total ?', documentText: tunisianInvoice, analysis: analysis);
      expect(total, contains('1 191,000 DT'));
      expect(total, contains('Net à payer'));
      final due = DocumentQa.answer(question: "Quelle est la date d'échéance ?", documentText: tunisianInvoice, analysis: analysis);
      expect(due, contains('11/11/2026'));
    });

    test('keyword questions quote matching lines', () {
      final analysis = DocumentAnalyzer.analyze(tpSheet);
      final reply = DocumentQa.answer(question: 'Which exercise uses the Streaming model?', documentText: tpSheet, analysis: analysis);
      expect(reply, contains('modèle Streaming'));
      expect(reply, isNot(contains('**')));
    });

    test('unknown topics are reported as not found', () {
      final analysis = DocumentAnalyzer.analyze(tpSheet);
      final reply = DocumentQa.answer(question: 'zebra giraffe', documentText: tpSheet, analysis: analysis);
      expect(reply, startsWith('I could not find anything'));
    });
  });
}
