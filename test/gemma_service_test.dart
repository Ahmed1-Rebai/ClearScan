import 'package:flutter_test/flutter_test.dart';
import 'package:cam_scan/core/models/gemma_analysis.dart';
import 'package:cam_scan/core/ai/gemma_local_service.dart';
import 'package:cam_scan/core/ai/gemma_prompt_builder.dart';

void main() {
  group('Gemma On-Device Local AI Tests', () {
    late GemmaLocalService gemma;

    setUp(() {
      gemma = GemmaLocalService.instance;
    });

    test('Prompt builder generates strict Gemma turn format', () {
      final prompt = GemmaPromptBuilder.buildDocumentAnalysisPrompt('Invoice #100\nTotal: \$50.00');
      expect(prompt, contains('<start_of_turn>user'));
      expect(prompt, contains('<end_of_turn>'));
      expect(prompt, contains('<start_of_turn>model'));
      expect(prompt, contains('Invoice #100'));
    });

    test('Gemma classifies Invoice and extracts total, date, reference', () async {
      const sampleInvoice = '''
ACME CLOUD SOLUTIONS LLC
Invoice #: INV-2026-8819
Date: 2026-10-25
Bill To: John Doe
Description: Dedicated Server GPU Tier 3
Subtotal: \$200.00
Tax: \$18.00
Total Amount: \$218.00
Payment due in 14 days
''';

      final analysis = await gemma.analyzeDocument(sampleInvoice);

      expect(analysis.documentType, equals(DocumentType.invoice));
      expect(analysis.summary, contains('ACME CLOUD SOLUTIONS LLC'));
      expect(analysis.summary, contains('\$218.00'));

      // Check extracted fields
      final totalField = analysis.extractedFields.firstWhere((f) => f.key == 'Total Amount');
      expect(totalField.value, contains('\$218.00'));

      final dateField = analysis.extractedFields.firstWhere((f) => f.key == 'Document Date');
      expect(dateField.value, equals('2026-10-25'));

      final refField = analysis.extractedFields.firstWhere((f) => f.key == 'Reference #');
      expect(refField.value, contains('INV-2026-8819'));
    });

    test('Gemma classifies Receipt and extracts purchase information', () async {
      const sampleReceipt = '''
TARGET STORE #0412
Date: 10/24/2026
Cashier: Sarah M.
1 Organic Milk     \$4.50
1 Whole Wheat Bread \$3.20
Subtotal: \$7.70
Total: \$7.70
Cash: \$10.00
Change Due: \$2.30
Thank you for shopping!
''';

      final analysis = await gemma.analyzeDocument(sampleReceipt);

      expect(analysis.documentType, equals(DocumentType.receipt));
      expect(analysis.summary, contains('TARGET STORE'));
      expect(analysis.summary, contains('\$7.70'));
    });

    test('Gemma answers document Q&A questions offline', () async {
      const sampleDoc = '''
Contract Agreement
Effective Date: 2026-11-01
Parties: NovaGate LLC and Ahmed Rebai
The total compensation is \$8,500.00 payable upon milestone completion.
Notice of termination must be provided 30 days in advance.
''';

      final q1 = await gemma.askDocumentQuestion(
        documentText: sampleDoc,
        question: 'What is the total compensation amount?',
      );
      expect(q1, contains('\$8,500.00'));

      final q2 = await gemma.askDocumentQuestion(
        documentText: sampleDoc,
        question: 'When is the effective date?',
      );
      expect(q2, contains('2026-11-01'));

      final q3 = await gemma.askDocumentQuestion(
        documentText: sampleDoc,
        question: 'Who is the contractor or party?',
      );
      expect(q3, contains('Contract Agreement'));
    });

    test('Gemma extracts structured line items from invoice tables', () async {
      const sampleTabularInvoice = '''
TechFlow Cloud Corp
Invoice: #TF-2026-102
Date: 2026-10-25
Item 1: Ultra High-Speed Neural NPU Server x 2 @ \$1,200.00 = \$2,400.00
Item 2: On-Device Gemma Optimization License x 1 @ \$650.00 = \$650.00
Tax ID: US-EIN-9928192
IBAN: US82WXYZ1234567890123456
Subtotal: \$3,050.00
Tax: \$250.00
Total Amount: \$3,300.00
''';

      final analysis = await gemma.analyzeDocument(sampleTabularInvoice);

      expect(analysis.lineItems.length, equals(2));
      expect(analysis.lineItems[0].description, contains('Neural NPU Server'));
      expect(analysis.lineItems[0].quantity, equals(2));
      expect(analysis.lineItems[0].unitPrice, equals('\$1,200.00'));
      expect(analysis.lineItems[0].totalPrice, equals('\$2,400.00'));

      // Check IBAN & Tax ID extracted
      final ibanField = analysis.extractedFields.firstWhere((f) => f.key == 'IBAN / Account');
      expect(ibanField.value, equals('US82WXYZ1234567890123456'));

      final taxField = analysis.extractedFields.firstWhere((f) => f.key == 'Tax / VAT ID');
      expect(taxField.value, equals('US-EIN-9928192'));
    });
  });
}

