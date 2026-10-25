import 'package:cam_scan/core/analysis/document_analyzer.dart';
import 'package:cam_scan/core/models/document_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

String? valueOf(DocumentAnalysis a, String key) {
  for (final f in a.extractedFields) {
    if (f.key == key || f.key.startsWith('$key ')) return f.value;
  }
  return null;
}

/// Every extracted value (and its evidence) must be copied verbatim from the text.
void expectGrounded(DocumentAnalysis a, String text) {
  for (final f in a.extractedFields) {
    expect(text.contains(f.value), isTrue, reason: '${f.key}="${f.value}" is not in the document text');
    for (final part in (f.evidence ?? '').split(' / ').where((p) => p.isNotEmpty)) {
      expect(text.contains(part), isTrue, reason: 'evidence "$part" is not in the document text');
    }
  }
}

const tpSheet = '''Faculté des Sciences de Sfax
Département d'informatique et des communications
Matière : services Web
TP N°2
Année Universitaire 2026-2027
Exercice 1 :
Voici un fichier XML décrivant des étudiants et leurs coordonnées. Transformez cette structure en écrivant son équivalent au format JSON, faites les adaptations et développements nécessaires.
<?xml version="1.0" encoding="ISO-8859-1" ?>
<etudiants>
<etudiant id="0001">
<prenom>Ali</prenom>
<telephone type="fixe" numéro="(216) 74 000 111"/>
</etudiant>
Exercice 2 :
Vous devez créer un programme en JAVA afin d'écrire un tableau de voitures dans un fichier JSON, avec le modèle Streaming.
Exercice 3 :
Vous devez créer un programme en JAVA afin de récupérer les données d'un fichier JSON (personne.json) avec le modèle Objet.''';

const accountingCourse = '''PARTIE I : LES SUPPORTS DE SAISIE ET DE COMMUNICATION DE L'INFORMATION FINANCIERE
La comptabilité utilise un certain nombre de documents dont certains émanent de l'entreprise (exemple : Les factures envoyées aux clients et les chèques signés par l'entreprise) et d'autres des tiers (exemple les factures reçues des fournisseurs et les avis bancaires et postaux).
CHAPITRE 1 : LES SUPPORTS DE COMMUNICATION DE L'INFORMATION (BILAN ET ETAT DE RESULTAT)
Objectifs du chapitre
- Comprendre le terme BILAN et ses composantes
Plan du chapitre
- Notion du bilan
Total des capitaux propres   120 000''';

const tunisianInvoice = '''SOCIETE ALPHA SARL
Matricule fiscal : 1234567/A/M/000
FACTURE N° FA-2026-0042
Date : 12/10/2026
Date d'échéance : 11/11/2026
Client : Beta Services
Désignation   Qté   P.U   Total
Maintenance serveur   2   400,000   800,000
Licence logiciel   1   200,000   200,000
Total HT   1 000,000 DT
TVA 19%   190,000 DT
Timbre fiscal   1,000 DT
Net à payer   1 191,000 DT
IBAN : TN59 1000 6035 1835 9847 8831''';

const englishInvoice = '''ACME CLOUD SOLUTIONS LLC
Invoice #: INV-2026-8819
Date: 2026-10-25
Due Date: 2026-11-08
Bill To: John Doe
Item 1: Dedicated Server GPU Tier 3 x 2 @ \$100.00 = \$200.00
Subtotal: \$200.00
Tax (9%): \$18.00
Total Amount: \$218.00
Email: billing@acme-cloud.com''';

const receipt = '''TARGET STORE #0412
Date: 10/24/2026
Cashier: Sarah M.
1 Organic Milk     \$4.50
1 Whole Wheat Bread \$3.20
Subtotal: \$7.70
Total: \$7.70
Cash: \$10.00
Change Due: \$2.30
Thank you for shopping!''';

void main() {
  group('Grounded extraction never invents fields', () {
    test('French TP sheet: academic, no money, header fields from the text', () {
      final a = DocumentAnalyzer.analyze(tpSheet);
      expect(a.documentType, DocumentType.academic);
      expect(a.language, 'French');
      expect(a.extractedFields.where((f) => f.category == 'financial'), isEmpty);
      expect(valueOf(a, 'Total'), isNull);
      expect(valueOf(a, 'Subtotal'), isNull);
      expect(valueOf(a, 'Institution'), 'Faculté des Sciences de Sfax');
      expect(valueOf(a, 'Subject'), 'services Web');
      expect(valueOf(a, 'Academic year'), '2026-2027');
      expect(valueOf(a, 'Title'), 'TP N°2');
      // Sample data inside an exercise is not the document's contact information.
      expect(valueOf(a, 'Phone'), isNull);
      expect(a.keyPoints, containsAll(['Exercice 1 :', 'Exercice 2 :', 'Exercice 3 :']));
      expect(a.suggestedAction, isNull);
      expectGrounded(a, tpSheet);
    });

    test('accounting course that mentions "factures" is not an invoice', () {
      final a = DocumentAnalyzer.analyze(accountingCourse);
      expect(a.documentType, DocumentType.academic);
      expect(valueOf(a, 'Total'), isNull, reason: 'a balance-sheet total in a course is not an amount to pay');
      expect(a.lineItems, isEmpty);
      expectGrounded(a, accountingCourse);
    });

    test('titles must look like headings; numbered sections become highlights', () {
      const page = '''Par exemple, pour une entreprise industrielle, le cycle d'exploitation recouvre
les opérations suivantes : approvisionnements, production, distribution.
3.2. Les actifs non courants
Un actif est non courant lorsqu'il est destiné à être utilisé de façon permanente.
3.2.1. Les actifs immobilisés
L'actif immobilisé comprend trois catégories.''';
      final a = DocumentAnalyzer.analyze(page);
      expect(valueOf(a, 'Title'), '3.2. Les actifs non courants');
      expect(a.keyPoints, ['3.2. Les actifs non courants', '3.2.1. Les actifs immobilisés']);
    });

    test('a chart of accounts (balance sheet) is not a bank statement', () {
      // OCR of a real scan: words like "solde", "créditeurs" alone must not decide the type.
      const text = '''CAPITAUX PROPRES
ET PASSIFS   COMPTES ASSOCIÉS
101   Capital social
Réserves et primes liées au capital   108   Compte de l'exploitant
Résultat de l'exercice.   131   Résultat bénéficiaire
Concours bancaires et autres passifs financiers   45   Débiteurs divers et Créditeurs divers (solde créditeur)
Fournisseurs   401   Fournisseurs d'exploitation (solde débiteur)
Provisions   15   Provisions pour risques et charges (crédit bail)''';
      final a = DocumentAnalyzer.analyze(text);
      expect(a.documentType, isNot(DocumentType.bankStatement));
      expect(a.documentType.isFinancial, isFalse);
      expect(valueOf(a, 'Vendor / Issuer'), isNull);
    });

    test('title from a heading cell sharing its row, and OCR-merged "Exercice1"', () {
      // OCR of a real TP sheet (with recognition errors in the header).
      const text = '''!acultc des Sccces de Sfav
Dkpatencnt d'intomatique et des
Annéc Universitane 2026-2027
Matière servces Web   But Json   Exercice 2:
TD N°2   Vous devcz créc un programme cn JAVA afin d'écrire un tableau de vostures dans un fichier
Exercice1:   ("voitures":A''';
      final a = DocumentAnalyzer.analyze(text);
      expect(a.documentType, DocumentType.academic);
      expect(valueOf(a, 'Title'), 'TD N°2');
    });

    test('a long garbled sentence is never used as the title', () {
      const text = '''Le patuhoe epresente lensemlble des bens et CmCes lmt entregteet proprtare tneele
emplos finaneeN OU ais) et des tlettes qe celle cI dot a ses drvers
le patrimine de l'entrepise est composé de''';
      expect(valueOf(DocumentAnalyzer.analyze(text), 'Title'), isNull);
    });

    test('"matière" in the body of a course is not a Subject field', () {
      final body = List.generate(12, (i) => 'Ligne $i du cours sur les stocks et la production.').join('\n');
      final text = 'CHAPITRE 2 : LES STOCKS\n$body\nMatière premières et emballages achetés pour la production';
      expect(valueOf(DocumentAnalyzer.analyze(text), 'Subject'), isNull);
    });

    test('empty text yields an empty analysis', () {
      final a = DocumentAnalyzer.analyze('   ');
      expect(a.extractedFields, isEmpty);
      expect(a.documentType, DocumentType.other);
    });

    test('a number after the word "total" in prose is not a total amount', () {
      const contract = '''SERVICE AGREEMENT
This agreement is made between the parties named below.
The contractor shall work a total of 30 days on the project.
Termination requires written notice. Signed by both parties.''';
      final a = DocumentAnalyzer.analyze(contract);
      expect(a.documentType, DocumentType.contract);
      expect(valueOf(a, 'Total'), isNull);
      expectGrounded(a, contract);
    });

    test('invoice without a printed total reports no total', () {
      const text = '''INVOICE
Invoice No: 778-B
Date: 2026-01-05
Consulting services   \$1,200.00''';
      final a = DocumentAnalyzer.analyze(text);
      expect(a.documentType, DocumentType.invoice);
      expect(valueOf(a, 'Total'), isNull);
      expect(valueOf(a, 'Invoice number'), '778-B');
      expect(a.lineItems.single.totalPrice, '\$1,200.00');
    });
  });

  group('Financial documents', () {
    test('Tunisian invoice: TND amounts, VAT rate, stamp duty, verified totals', () {
      final a = DocumentAnalyzer.analyze(tunisianInvoice);
      expect(a.documentType, DocumentType.invoice);
      expect(a.language, 'French');
      expect(valueOf(a, 'Vendor / Issuer'), 'SOCIETE ALPHA SARL');
      expect(valueOf(a, 'Total'), '1 191,000 DT');
      expect(valueOf(a, 'Subtotal'), '1 000,000 DT');
      expect(a.extractedFields.firstWhere((f) => f.key.startsWith('Tax / VAT (')).key, 'Tax / VAT (19%)');
      expect(valueOf(a, 'Tax / VAT'), '190,000 DT');
      expect(valueOf(a, 'Stamp duty'), '1,000 DT');
      expect(valueOf(a, 'Invoice number'), 'FA-2026-0042');
      expect(valueOf(a, 'Invoice date'), '12/10/2026');
      expect(valueOf(a, 'Due date'), '11/11/2026');
      expect(valueOf(a, 'Customer'), 'Beta Services');
      expect(valueOf(a, 'Tax / VAT ID'), '1234567/A/M/000');
      expect(valueOf(a, 'IBAN'), 'TN59 1000 6035 1835 9847 8831');
      expect(a.keyPoints, contains('Totals check out: subtotal + taxes = total'));
      expect(a.warnings, isEmpty);
      expect(a.suggestedAction, 'Pay before 11/11/2026');
      expect(a.lineItems.map((i) => i.description), ['Maintenance serveur', 'Licence logiciel']);
      expect(a.lineItems.map((i) => i.quantity), [2, 1]);
      expect(a.lineItems.first.unitPrice, '400,000');
      expect(a.lineItems.first.totalPrice, '800,000');
      expectGrounded(a, tunisianInvoice);
    });

    test('English invoice: classification, totals, references and dates', () {
      final a = DocumentAnalyzer.analyze(englishInvoice);
      expect(a.documentType, DocumentType.invoice);
      expect(a.summary, contains('ACME CLOUD SOLUTIONS LLC'));
      expect(a.summary, contains('\$218.00'));
      expect(valueOf(a, 'Total'), '\$218.00');
      expect(valueOf(a, 'Subtotal'), '\$200.00');
      expect(valueOf(a, 'Tax / VAT'), '\$18.00');
      expect(valueOf(a, 'Invoice number'), 'INV-2026-8819');
      expect(valueOf(a, 'Invoice date'), '2026-10-25');
      expect(valueOf(a, 'Due date'), '2026-11-08');
      expect(valueOf(a, 'Email'), 'billing@acme-cloud.com');
      expect(a.extractedFields.firstWhere((f) => f.key == 'Total').confidence, greaterThan(0.95));
      final item = a.lineItems.single;
      expect(item.description, contains('Dedicated Server GPU Tier 3'));
      expect(item.quantity, 2);
      expect(item.unitPrice, '\$100.00');
      expect(item.totalPrice, '\$200.00');
      expectGrounded(a, englishInvoice);
    });

    test('receipt: total is not confused with subtotal, cash or change', () {
      final a = DocumentAnalyzer.analyze(receipt);
      expect(a.documentType, DocumentType.receipt);
      expect(a.summary, contains('TARGET STORE'));
      expect(valueOf(a, 'Total'), '\$7.70');
      expect(a.lineItems.map((i) => i.description), ['Organic Milk', 'Whole Wheat Bread']);
      expectGrounded(a, receipt);
    });

    test('"Sub Total" is not taken as the grand total', () {
      const text = '''COFFEE CORNER
Receipt
Latte   \$4.00
Sub Total   \$4.00
Tax   \$0.36
Total   \$4.36''';
      final a = DocumentAnalyzer.analyze(text);
      expect(valueOf(a, 'Total'), '\$4.36');
      expect(valueOf(a, 'Subtotal'), '\$4.00');
      expect(valueOf(a, 'Tax / VAT'), '\$0.36');
    });

    test('total printed on the line after its label (split OCR columns)', () {
      const text = '''FACTURE
Facture N° 2026/77
Montant HT
500,00 €
TVA 20 %
100,00 €
Net à payer
600,00 €''';
      final a = DocumentAnalyzer.analyze(text);
      expect(valueOf(a, 'Total'), '600,00 €');
      expect(valueOf(a, 'Subtotal'), '500,00 €');
      expect(valueOf(a, 'Tax / VAT'), '100,00 €');
      expect(a.warnings, isEmpty);
      expectGrounded(a, text);
    });

    test('inconsistent totals produce a warning', () {
      const text = '''INVOICE
Invoice No: 99-1
Subtotal: \$500.00
Total: \$50.00''';
      final a = DocumentAnalyzer.analyze(text);
      expect(a.warnings, isNotEmpty);
    });

    test('invalid IBAN-like strings are ignored', () {
      const text = '''INVOICE
Invoice No: 12345
IBAN: US82WXYZ1234567890123456
Total: \$10.00''';
      final a = DocumentAnalyzer.analyze(text);
      expect(valueOf(a, 'IBAN'), isNull);
    });
  });

  group('IBAN checksum', () {
    test('valid and invalid IBANs', () {
      expect(DocumentAnalyzer.isValidIban('TN5910006035183598478831'), isTrue);
      expect(DocumentAnalyzer.isValidIban('FR7630006000011234567890189'), isTrue);
      expect(DocumentAnalyzer.isValidIban('DE89370400440532013000'), isTrue);
      expect(DocumentAnalyzer.isValidIban('DE89370400440532013001'), isFalse);
      expect(DocumentAnalyzer.isValidIban('US82WXYZ1234567890123456'), isFalse);
    });
  });
}
