import '../models/document_analysis.dart';
import 'text_normalizer.dart';

/// Answers questions about a document using only its OCR text and extracted
/// fields. When the answer is not in the document, it says so instead of guessing.
class DocumentQa {
  static const _stopWords = {
    'what', 'which', 'when', 'where', 'who', 'whom', 'whose', 'why', 'how', 'the', 'this', 'that', 'there', 'is', 'are',
    'was', 'were', 'does', 'did', 'can', 'could', 'about', 'tell', 'give', 'show', 'find', 'document', 'please', 'with',
    'quel', 'quelle', 'quels', 'quelles', 'quand', 'comment', 'pourquoi', 'combien', 'est', 'sont', 'dans', 'pour', 'avec',
    'le', 'la', 'les', 'des', 'une', 'qui', 'que', 'quoi', 'moi', 'donne', 'dis', 'cette', 'ce',
  };

  static String answer({
    required String question,
    required String documentText,
    DocumentAnalysis? analysis,
  }) {
    if (documentText.trim().isEmpty) {
      return 'No text has been recognized for this document yet, so there is nothing to answer from.';
    }
    final q = TextNormalizer.fold(question).replaceAll("'", ' ');
    final fields = analysis?.extractedFields ?? const <ExtractedField>[];

    bool asks(List<String> words) => words.any((w) => TextNormalizer.containsPhrase(q, w));

    ExtractedField? field(String key) {
      for (final f in fields) {
        if (f.key == key || f.key.startsWith('$key ')) return f;
      }
      return null;
    }

    String cite(ExtractedField f) =>
        f.evidence != null && f.evidence != f.value ? '${f.key}: ${f.value}\nSource: "${f.evidence}"' : '${f.key}: ${f.value}';

    if (asks(['due', 'echeance', 'deadline', 'pay by', 'date limite'])) {
      final due = field('Due date') ?? field('Deadline');
      return due != null ? cite(due) : 'No due date is printed in this document.';
    }
    if (asks(['tax', 'vat', 'tva', 'taxe', 'taxes'])) {
      final tax = field('Tax / VAT');
      return tax != null ? cite(tax) : 'No tax or VAT amount was found in this document.';
    }
    if (asks(['subtotal', 'sous total', 'hors taxe', 'ht'])) {
      final subtotal = field('Subtotal');
      return subtotal != null ? cite(subtotal) : 'No subtotal is printed in this document.';
    }
    if (asks(['total', 'montant', 'amount', 'how much', 'combien', 'price', 'prix', 'cost', 'cout', 'pay', 'payer'])) {
      final total = field('Total');
      if (total != null) return cite(total);
      return 'No total amount is printed in this document.';
    }
    if (asks(['date', 'when', 'quand', 'dated'])) {
      final dates = fields.where((f) => f.category == 'date').toList();
      if (dates.isNotEmpty) return dates.map(cite).join('\n\n');
      return 'No date was found in this document.';
    }
    if (asks(['who', 'qui', 'vendor', 'fournisseur', 'issuer', 'company', 'societe', 'store', 'magasin', 'emetteur', 'institution', 'university', 'universite', 'faculte'])) {
      final who = field('Vendor / Issuer') ?? field('Institution') ?? field('Customer');
      if (who != null) return cite(who);
    }
    if (asks(['email', 'mail', 'courriel'])) {
      final email = field('Email');
      return email != null ? cite(email) : 'No email address was found in this document.';
    }
    if (asks(['phone', 'tel', 'telephone', 'mobile', 'gsm'])) {
      final phone = field('Phone');
      return phone != null ? cite(phone) : 'No phone number was found in this document.';
    }
    if (asks(['iban', 'rib', 'bank account', 'compte bancaire'])) {
      final iban = field('IBAN') ?? field('RIB');
      return iban != null ? cite(iban) : 'No IBAN or bank account number was found in this document.';
    }
    if (analysis != null && asks(['items', 'item', 'articles', 'products', 'produits', 'bought', 'achete', 'lines'])) {
      if (analysis.lineItems.isEmpty) return 'No itemized lines were detected in this document.';
      return analysis.lineItems.map((i) => '• ${i.description} × ${i.quantity} — ${i.totalPrice}').join('\n');
    }
    if (analysis != null && asks(['summary', 'summarize', 'summarise', 'resume', 'resumer', 'about', 'overview', 'sujet'])) {
      final points = analysis.keyPoints.isEmpty ? '' : '\n\n${analysis.keyPoints.map((p) => '• $p').join('\n')}';
      return '${analysis.summary}$points';
    }

    final matches = _bestLines(question, documentText);
    if (matches.isEmpty) {
      return 'I could not find anything about "$question" in the recognized text.';
    }
    return 'From the document:\n${matches.map((l) => '"$l"').join('\n')}';
  }

  static List<String> _bestLines(String question, String text) {
    final queryTokens = TextNormalizer.tokens(question).where((t) => t.length >= 3 && !_stopWords.contains(t)).toSet();
    if (queryTokens.isEmpty) return const [];
    final scored = <(String, double)>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('--- Page')) continue;
      final lineTokens = TextNormalizer.tokens(line).toSet();
      double score = 0;
      for (final q in queryTokens) {
        if (lineTokens.contains(q)) {
          score += 1;
        } else if (q.length >= 5 && lineTokens.any((t) => t.length >= 5 && t.substring(0, 5) == q.substring(0, 5))) {
          score += 0.5;
        }
      }
      if (score > 0) scored.add((line, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final best = scored.isEmpty ? 0.0 : scored.first.$2;
    return scored.where((s) => s.$2 >= best * 0.75).take(3).map((s) => s.$1).toList();
  }
}
