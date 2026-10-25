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
  });
}

