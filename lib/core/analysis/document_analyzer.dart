import 'dart:math';
import '../models/document_analysis.dart';
import 'money.dart';
import 'text_normalizer.dart';

class _Line {
  final String text;
  final String folded;
  final int index;
  final int page;

  _Line(this.text, this.index, this.page) : folded = TextNormalizer.fold(text);
}

class _LabelHit {
  final _Line line;
  final int labelStart;
  final int labelEnd;
  final int priority;

  const _LabelHit(this.line, this.labelStart, this.labelEnd, this.priority);

  /// The label opens the line (after bullets/spaces) or is directly followed by ':'.
  bool get isLeading =>
      RegExp(r'^[\s\-•*·>]*$').hasMatch(line.folded.substring(0, labelStart)) ||
      RegExp(r'^\s*:').hasMatch(line.folded.substring(labelEnd));
}

class _AmountCandidate {
  final MoneyMatch money;
  final _Line line;
  final String evidence;
  final int priority;

  const _AmountCandidate(this.money, this.line, this.evidence, this.priority);
}

/// Grounded, rule-based document understanding.
///
/// Every extracted value is copied verbatim from a line of the OCR text that
/// carries an explicit label (e.g. "Total TTC", "Facture N°"), and that line is
/// kept as evidence. Nothing is inferred or invented: if a document has no
/// total, no total is reported.
class DocumentAnalyzer {
  static const String engineName = 'On-device rule-based extractor';

  static DocumentAnalysis analyze(String text) {
    final clean = text.trim();
    if (clean.isEmpty) {
      return DocumentAnalysis(
        documentType: DocumentType.other,
        summary: 'No text was recognized on this document.',
        extractedFields: const [],
        keyPoints: const [],
        rawOcrText: '',
        modelName: engineName,
      );
    }

    final lines = _splitLines(clean);
    final folded = TextNormalizer.fold(clean);
    final currency = Money.dominantCurrency(clean);
    final type = classify(clean);
    final language = detectLanguage(clean);
    final pageCount = max(1, lines.map((l) => l.page).fold<int>(0, max));
    final wordCount = TextNormalizer.tokens(clean).length;

    final fields = <ExtractedField>[];
    final warnings = <String>[];
    final keyPoints = <String>[];

    // Identity of the issuer / title.
    if (type.isFinancial) {
      final vendor = _vendor(lines);
      if (vendor != null) fields.add(ExtractedField(key: 'Vendor / Issuer', value: vendor.text, confidence: 0.6, category: 'identity', evidence: vendor.text));
    } else {
      final institution = _firstLineWith(lines, const ['universite', 'university', 'faculte', 'faculty', 'institut', 'ecole', 'school', 'college', 'lycee']);
      if (institution != null) fields.add(ExtractedField(key: 'Institution', value: institution.text, confidence: 0.8, category: 'identity', evidence: institution.text));
      final title = _title(lines, type);
      if (title != null) {
        fields.add(ExtractedField(key: 'Title', value: title.text, confidence: 0.7, category: 'identity', evidence: title.line.text));
      }
      final subject = _labeledText(lines, const ['matiere', 'module', 'subject', 'course'], headerOnly: true);
      if (subject != null) fields.add(subject.copyWithKey('Subject'));
      final year = _academicYear(lines);
      if (year != null) fields.add(year);
    }

    if (type.isFinancial) {
      fields.addAll(_references(lines, type));
      final customer = _labeledText(lines, const ['bill to', 'billed to', 'sold to', 'customer', 'client', 'facture a', 'destinataire']);
      if (customer != null) fields.add(customer.copyWithKey('Customer'));
    }

    fields.addAll(_dates(lines, type));

    // Money: only for financial documents, or when an explicit currency is printed.
    final money = _moneyFields(lines, type, currency, warnings);
    fields.addAll(money.fields);

    fields.addAll(_identifiers(lines, type));
    fields.addAll(_contacts(clean, lines, type));

    final lineItems = type == DocumentType.invoice || type == DocumentType.receipt ? _lineItems(lines, currency) : <DocumentLineItem>[];

    final headings = _headings(lines);
    keyPoints.addAll(headings);
    if (money.verified) keyPoints.add('Totals check out: subtotal + taxes = total');
    if (lineItems.isNotEmpty) keyPoints.add('${lineItems.length} line item${lineItems.length == 1 ? '' : 's'} detected');

    String? field(String key) {
      for (final f in fields) {
        if (f.key == key || f.key.startsWith('$key ')) return f.value;
      }
      return null;
    }

    final summary = _summary(
      type: type,
      pageCount: pageCount,
      wordCount: wordCount,
      language: language,
      vendor: field('Vendor / Issuer'),
      institution: field('Institution'),
      title: field('Title'),
      total: field('Total'),
      date: field('Date') ?? field('Invoice date'),
      headings: headings,
    );

    String? action;
    final due = field('Due date');
    if (type == DocumentType.invoice && due != null) {
      action = 'Pay before $due';
    } else if (type == DocumentType.invoice && field('Total') != null) {
      action = 'Record this invoice (${field('Total')})';
    } else if (type == DocumentType.receipt && field('Total') != null) {
      action = 'Keep for your expense records';
    } else if (type == DocumentType.contract &&
        (TextNormalizer.containsPhrase(folded, 'signature') || TextNormalizer.containsPhrase(folded, 'signed'))) {
      action = 'Check that all parties have signed';
    }

    return DocumentAnalysis(
      documentType: type,
      summary: summary,
      extractedFields: fields,
      lineItems: lineItems,
      keyPoints: keyPoints.take(10).toList(),
      suggestedAction: action,
      rawOcrText: clean,
      modelName: engineName,
      language: language,
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Classification & language

  static const Map<DocumentType, Map<String, double>> _typeKeywords = {
    DocumentType.invoice: {
      'invoice': 3, 'facture': 3, 'bill to': 2, 'billed to': 2, 'invoice number': 3, 'invoice no': 3, 'facture n': 3,
      'echeance': 1.5, 'due date': 1.5, 'montant ttc': 2, 'total ttc': 2, 'total ht': 2, 'net a payer': 2.5,
      'tva': 1, 'vat': 1, 'matricule fiscal': 2, 'matricule fiscale': 2, 'payment terms': 1.5,
      'conditions de paiement': 1.5, 'remit to': 2, 'amount due': 2, 'balance due': 2, 'timbre fiscal': 2,
      'unit price': 1.5, 'prix unitaire': 1.5, 'qty': 0.5, 'quantite': 0.5,
    },
    DocumentType.receipt: {
      'receipt': 3, 'recu': 2, 'ticket de caisse': 3, 'ticket': 1.5, 'cashier': 2, 'caissier': 2, 'caissiere': 2,
      'change due': 2.5, 'rendu': 1.5, 'monnaie rendue': 2.5, 'cash': 1, 'especes': 1.5, 'carte bancaire': 1,
      'card': 0.5, 'visa': 0.5, 'mastercard': 0.5, 'thank you': 1, 'merci de votre visite': 2.5, 'merci': 0.5,
      'subtotal': 1, 'sous-total': 1, 'sous total': 1, 'store': 1, 'magasin': 1, 'tpe': 1,
    },
    DocumentType.contract: {
      'contract': 3, 'contrat': 3, 'agreement': 3, 'hereby': 2, 'witnesseth': 3, 'clause': 1.5,
      'terms and conditions': 2, 'conditions generales': 2, 'the parties': 2, 'les parties': 2,
      'lu et approuve': 2.5, 'signed': 1, 'termination': 1, 'resiliation': 1.5, 'whereas': 2, 'obligations': 1,
    },
    DocumentType.bankStatement: {
      'bank statement': 3, 'releve de compte': 3, 'releve bancaire': 3, 'account balance': 2, 'solde': 1.5,
      'statement period': 2.5, 'opening balance': 2, 'closing balance': 2, 'ancien solde': 2, 'nouveau solde': 2,
      'debit': 0.5, 'credit': 0.5, 'iban': 1,
    },
    DocumentType.taxDocument: {
      'tax return': 3, 'impot': 2, 'impots': 2, 'w-2': 3, 'internal revenue': 3, 'revenu imposable': 3,
      'avis d imposition': 3, 'declaration fiscale': 3, 'declaration de revenus': 3,
    },
    DocumentType.medicalPrescription: {
      'prescription': 3, 'ordonnance': 3, 'docteur': 1, 'doctor': 1, 'patient': 2, 'dosage': 2, 'posologie': 3,
      'comprime': 1, 'comprimes': 1, 'tablet': 1, 'tablets': 1, 'pharmacie': 1, 'pharmacy': 1, 'clinique': 1, 'clinic': 1,
    },
    DocumentType.certificate: {
      'certificate': 3, 'certificat': 3, 'attestation': 3, 'diploma': 3, 'diplome': 3, 'certifies that': 3,
      'certifie que': 3, 'atteste que': 3, 'awarded to': 2, 'decerne': 2,
    },
    DocumentType.idCard: {
      'passport': 3, 'passeport': 3, 'identity card': 3, 'carte d identite': 3, 'carte nationale': 3,
      'driver license': 3, 'driving licence': 3, 'permis de conduire': 3, 'nationality': 2, 'nationalite': 2,
      'date of birth': 2, 'date de naissance': 2, 'lieu de naissance': 2,
    },
    DocumentType.academic: {
      'exercice': 2, 'exercise': 2, 'tp': 1, 'td': 1, 'travaux pratiques': 2.5, 'travaux diriges': 2.5,
      'chapitre': 2, 'chapter': 2, 'cours': 1, 'lecture': 1, 'examen': 2, 'exam': 2, 'devoir': 2, 'homework': 2,
      'annee universitaire': 3, 'academic year': 3, 'annee scolaire': 3, 'universite': 1.5, 'university': 1.5,
      'faculte': 2, 'faculty': 1, 'enonce': 2, 'objectifs du chapitre': 3, 'plan du chapitre': 3, 'corrige': 2,
      'matiere': 1, 'enseignant': 1.5, 'semestre': 1.5, 'question': 0.5, 'application': 0.5,
    },
  };

  static DocumentType classify(String text) {
    final folded = TextNormalizer.fold(text).replaceAll("'", ' ');
    final scores = <DocumentType, double>{};
    _typeKeywords.forEach((type, keywords) {
      double score = 0;
      bool strong = false;
      keywords.forEach((keyword, weight) {
        final count = TextNormalizer.countPhrase(folded, keyword);
        score += weight * min(3, count);
        if (count > 0 && weight >= 2) strong = true;
      });
      // Weak words alone (e.g. "solde", "crédit" in a chart of accounts) never decide the type.
      scores[type] = strong ? score : 0;
    });
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0.0;

    DocumentType type = DocumentType.other;
    if (best.value >= 3 && best.value >= second * 1.25) type = best.key;

    if ((type == DocumentType.invoice || type == DocumentType.receipt) &&
        !Money.findAll(text).any((m) => m.looksMonetary)) {
      type = DocumentType.other;
    }

    if (type == DocumentType.other) {
      final lineCount = text.split('\n').where((l) => l.trim().isNotEmpty).length;
      final hasContact = RegExp(r'@[A-Za-z0-9-]+\.').hasMatch(text) || RegExp(r'\+\d{6,}').hasMatch(text.replaceAll(' ', ''));
      if (text.length <= 350 && lineCount <= 10 && hasContact) type = DocumentType.businessCard;
    }
    return type;
  }

  static const _frenchWords = {
    'le', 'la', 'les', 'des', 'du', 'de', 'et', 'est', 'un', 'une', 'pour', 'dans', 'par', 'sur', 'avec', 'au',
    'aux', 'ce', 'cette', 'qui', 'que', 'ne', 'pas', 'vous', 'nous', 'il', 'elle', 'sont', 'ou', 'leur', 'votre',
  };
  static const _englishWords = {
    'the', 'and', 'of', 'to', 'in', 'is', 'for', 'on', 'with', 'that', 'this', 'are', 'be', 'by', 'as', 'at',
    'from', 'it', 'an', 'or', 'your', 'you', 'we', 'our', 'will', 'not', 'have', 'has',
  };

  static String? detectLanguage(String text) {
    int fr = 0, en = 0;
    for (final t in TextNormalizer.tokens(text)) {
      if (_frenchWords.contains(t)) fr++;
      if (_englishWords.contains(t)) en++;
    }
    // Short business documents have few function words; accented letters are a strong French cue.
    final double french = fr + RegExp(r'[éèêëàâçùûôîïœ]', caseSensitive: false).allMatches(text).length * 0.5;
    if (french >= 3 && french >= en * 1.3) return 'French';
    if (en >= 3 && en >= french * 1.3) return 'English';
    if (en == 0 && french >= 2) return 'French';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Lines & labels

  static List<_Line> _splitLines(String text) {
    final result = <_Line>[];
    int page = 1;
    final marker = RegExp(r'^-{2,}\s*page\s+(\d+)\s*-{2,}$', caseSensitive: false);
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = marker.firstMatch(line);
      if (m != null) {
        page = int.parse(m.group(1)!);
        continue;
      }
      result.add(_Line(line, result.length, page));
    }
    return result;
  }

  /// Finds [labels] (folded phrases) in a line; returns the highest-priority hit per line.
  /// Labels earlier in the list have higher priority.
  static List<_LabelHit> _findLabels(List<_Line> lines, List<String> labels, {List<String> reject = const []}) {
    final hits = <_LabelHit>[];
    for (final line in lines) {
      if (reject.any((r) => TextNormalizer.containsPhrase(line.folded, r))) continue;
      for (int i = 0; i < labels.length; i++) {
        final end = _phraseEnd(line.folded, labels[i]);
        if (end != null) {
          hits.add(_LabelHit(line, end - labels[i].length, end, labels.length - i));
          break;
        }
      }
    }
    return hits;
  }

  static int? _phraseEnd(String folded, String phrase) {
    int from = 0;
    while (true) {
      final i = folded.indexOf(phrase, from);
      if (i < 0) return null;
      final before = i == 0 ? ' ' : folded[i - 1];
      final end = i + phrase.length;
      final after = end >= folded.length ? ' ' : folded[end];
      final wordBefore = RegExp(r'[a-z0-9]').hasMatch(before);
      final wordAfter = RegExp(r'[a-z0-9]').hasMatch(after);
      if (!wordBefore && !wordAfter) return end;
      from = i + 1;
    }
  }

  static final RegExp _labelSeparator = RegExp(
    r'^\s*(?:[:#°º.\-=]|n°|nº|no\b\.?|num(?:ero|éro)?\b\.?)?\s*(?:[:#°º.\-=]\s*)?',
    caseSensitive: false,
  );

  /// Text after a label (separators stripped), or the next line when the label stands alone.
  /// With [headerOnly], a label without a colon only counts in the first lines of the
  /// document ("Matière : services Web"), not in prose ("matière premières…").
  static ExtractedField? _labeledText(List<_Line> lines, List<String> labels, {bool headerOnly = false}) {
    for (final hit in _findLabels(lines, labels)) {
      if (!hit.isLeading) continue;
      final hasColon = RegExp(r'^\s*:').hasMatch(hit.line.folded.substring(hit.labelEnd));
      if (headerOnly && !hasColon && hit.line.index >= 10) continue;
      var rest = hit.line.text.substring(hit.labelEnd);
      rest = rest.replaceFirst(_labelSeparator, '').trim();
      rest = rest.split(RegExp(r'\s{3,}')).first.trim();
      String evidence = hit.line.text;
      if (rest.isEmpty && hit.line.index + 1 < lines.length) {
        final next = lines[hit.line.index + 1];
        if (TextNormalizer.letterRatio(next.text) >= 0.6 && next.text.length <= 60) {
          rest = next.text;
          evidence = '${hit.line.text} / ${next.text}';
        }
      }
      if (TextNormalizer.letterCount(rest) >= 3 && rest.length <= 80) {
        return ExtractedField(key: '', value: rest, confidence: 0.75, category: 'identity', evidence: evidence);
      }
    }
    return null;
  }

  static _Line? _firstLineWith(List<_Line> lines, List<String> words) {
    for (final line in lines.take(15)) {
      if (words.any((w) => TextNormalizer.containsPhrase(line.folded, w)) && line.text.length <= 90) return line;
    }
    return null;
  }

  static const _fieldWords = [
    'invoice', 'facture', 'receipt', 'recu', 'ticket', 'date', 'tel', 'phone', 'fax', 'total', 'page', 'client',
    'customer', 'bill', 'n', 'no', 'www', 'email', 'adresse', 'address',
  ];

  static _Line? _vendor(List<_Line> lines) {
    for (final line in lines.take(6)) {
      final t = line.text;
      if (t.length < 3 || t.length > 60) continue;
      if (TextNormalizer.letterCount(t) < 3 || TextNormalizer.letterRatio(t) < 0.5) continue;
      if (_fieldWords.any((w) => TextNormalizer.containsPhrase(line.folded, w))) continue;
      if (t.contains('@')) continue;
      return line;
    }
    return null;
  }

  // `(?![a-z])` instead of `\b` also accepts OCR-merged numbers such as "Exercice1".
  static final RegExp _headingStart = RegExp(
    r'^(chapitre|chapter|partie|part|section|exercice|exercise|question|article|annexe|application|td|tp|ds|objectifs?|plan|introduction|conclusion|lecon|lesson)(?![a-z])',
  );

  static final RegExp _numberedHeading = RegExp(r'^(\d{1,2}(\.\d{1,2})*\.?|[IVX]{1,4}[.\-)])\s+[A-ZÀ-ÖØ-Þa-zà-ÿ]');

  /// Short, capitalized, not a sentence fragment.
  static bool _looksLikeHeading(String t) {
    if (t.length < 4 || t.length > 90) return false;
    final words = t.split(RegExp(r'\s+')).length;
    if (words < 2 || words > 12) return false;
    if (RegExp(r'[,;]$').hasMatch(t) || (t.contains(',') && words > 6)) return false;
    if (TextNormalizer.letterRatio(t) < 0.6) return false;
    return RegExp(r'^[A-ZÀ-ÖØ-Þ0-9]').hasMatch(t);
  }

  static bool _isCapsHeading(String t) {
    final letters = TextNormalizer.letterCount(t);
    final upper = RegExp(r'[A-ZÀ-ÖØ-Þ]').allMatches(t).length;
    return letters >= 8 && upper >= letters * 0.85 && t.split(' ').length >= 2 && t.length <= 90;
  }

  /// The title text (a whole line or its first cell) and the line it came from.
  static ({String text, _Line line})? _title(List<_Line> lines, DocumentType type) {
    for (final line in lines.take(12)) {
      // A heading may share its row with another column: "TD N°2   Vous devez…".
      final cell = line.text.split(RegExp(r'\s{3,}')).first.trim();
      if (_headingStart.hasMatch(TextNormalizer.fold(cell)) && cell.length <= 90) return (text: cell, line: line);
    }
    for (final line in lines.take(8)) {
      if (_numberedHeading.hasMatch(line.text) && _looksLikeHeading(line.text)) return (text: line.text, line: line);
    }
    for (final line in lines.take(8)) {
      if (_isCapsHeading(line.text)) return (text: line.text, line: line);
    }
    for (final line in lines.take(5)) {
      // Last resort: only short lines, so a (possibly garbled) sentence is never taken as a title.
      if (_looksLikeHeading(line.text) && line.text.split(RegExp(r'\s+')).length <= 7) return (text: line.text, line: line);
    }
    return null;
  }

  static ExtractedField? _academicYear(List<_Line> lines) {
    final re = RegExp(r'(?:annee universitaire|annee scolaire|academic year|school year)\s*:?\s*(\d{4}\s?[-/]\s?\d{4})');
    for (final line in lines) {
      final m = re.firstMatch(line.folded);
      if (m != null) {
        return ExtractedField(
          key: 'Academic year',
          value: m.group(1)!,
          confidence: 0.9,
          category: 'date',
          evidence: line.text,
        );
      }
    }
    return null;
  }

  static List<String> _headings(List<_Line> lines) {
    final out = <String>[];
    final seen = <String>{};
    for (final line in lines) {
      final t = line.text;
      if (t.length < 4 || t.length > 90) continue;
      final isNamedHeading = _headingStart.hasMatch(line.folded) && t.split(' ').length <= 14;
      final isNumbered = _numberedHeading.hasMatch(t) && _looksLikeHeading(t);
      if ((isNamedHeading || isNumbered || _isCapsHeading(t)) && seen.add(line.folded)) out.add(t);
      if (out.length >= 8) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // References & identifiers

  static List<ExtractedField> _references(List<_Line> lines, DocumentType type) {
    final specs = <(String, List<String>)>[
      if (type == DocumentType.invoice)
        ('Invoice number', const ['invoice number', 'invoice no', 'invoice', 'numero de facture', 'facture n', 'facture no', 'facture']),
      ('Order / receipt number', const ['order number', 'order no', 'order', 'commande n', 'commande', 'receipt number', 'receipt no', 'receipt', 'ticket n', 'ticket no', 'ticket', 'transaction']),
      ('Reference', const ['reference', 'ref']),
    ];
    final value = RegExp(r'^([A-Za-z0-9][A-Za-z0-9/_.\-]{1,30})');
    final out = <ExtractedField>[];
    for (final (key, labels) in specs) {
      for (final hit in _findLabels(lines, labels)) {
        final rest = hit.line.text.substring(hit.labelEnd).replaceFirst(_labelSeparator, '');
        final m = value.firstMatch(rest.trimLeft());
        if (m == null) continue;
        final v = m.group(1)!.replaceAll(RegExp(r'[.\-]+$'), '');
        if (v.length < 3 || !RegExp(r'\d').hasMatch(v)) continue;
        out.add(ExtractedField(key: key, value: v, confidence: 0.85, category: 'identity', evidence: hit.line.text));
        break;
      }
    }
    return out;
  }

  static List<ExtractedField> _identifiers(List<_Line> lines, DocumentType type) {
    final out = <ExtractedField>[];

    final taxIdValue = RegExp(r'^([A-Za-z0-9][A-Za-z0-9 ./\-]{3,28}[A-Za-z0-9])');
    for (final hit in _findLabels(lines, const [
      'matricule fiscale', 'matricule fiscal', 'm.f', 'mf', 'tax id', 'tax no', 'vat number', 'vat no', 'vat reg',
      'tva intracommunautaire', 'numero de tva', 'code tva', 'siret', 'siren', 'ein', 'ice', 'nif', 'tin',
    ])) {
      var rest = hit.line.text.substring(hit.labelEnd).replaceFirst(_labelSeparator, '').trimLeft();
      rest = rest.split(RegExp(r'\s{3,}')).first;
      final m = taxIdValue.firstMatch(rest);
      if (m == null) continue;
      final v = m.group(1)!.trim();
      if (RegExp(r'\d').allMatches(v).length < 4) continue;
      out.add(ExtractedField(key: 'Tax / VAT ID', value: v, confidence: 0.85, category: 'identity', evidence: hit.line.text));
      break;
    }

    for (final line in lines) {
      final iban = _findIban(line.text);
      if (iban != null) {
        out.add(ExtractedField(key: 'IBAN', value: iban, confidence: 0.99, category: 'financial', evidence: line.text));
        break;
      }
    }

    for (final hit in _findLabels(lines, const ['rib'])) {
      final m = RegExp(r'(\d{2}\s?\d{3}\s?\d{13}\s?\d{2})').firstMatch(hit.line.text.substring(hit.labelEnd));
      if (m != null) {
        out.add(ExtractedField(key: 'RIB', value: m.group(1)!, confidence: 0.85, category: 'financial', evidence: hit.line.text));
        break;
      }
    }
    return out;
  }

  /// Returns the IBAN printed in [text] if one passes the ISO 13616 mod-97 checksum.
  static String? _findIban(String text) {
    for (final m in RegExp(r'\b([A-Z]{2}\d{2}(?:\s?[A-Z0-9]){11,30})').allMatches(text.toUpperCase())) {
      final printed = m.group(1)!;
      final compact = printed.replaceAll(' ', '');
      for (int len = min(34, compact.length); len >= 15; len--) {
        if (isValidIban(compact.substring(0, len))) {
          // Map back to the printed form (with its spaces) of that many characters.
          int seen = 0, i = 0;
          while (i < printed.length && seen < len) {
            if (printed[i] != ' ') seen++;
            i++;
          }
          return printed.substring(0, i).trim();
        }
      }
    }
    return null;
  }

  static bool isValidIban(String compact) {
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(compact)) return false;
    final rearranged = compact.substring(4) + compact.substring(0, 4);
    int remainder = 0;
    for (final rune in rearranged.runes) {
      final c = String.fromCharCode(rune);
      final digits = RegExp(r'\d').hasMatch(c) ? c : (rune - 55).toString();
      for (final d in digits.split('')) {
        remainder = (remainder * 10 + int.parse(d)) % 97;
      }
    }
    return remainder == 1;
  }

  static List<ExtractedField> _contacts(String text, List<_Line> lines, DocumentType type) {
    final out = <ExtractedField>[];
    final emails = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b').allMatches(text).map((m) => m.group(0)!).toSet();
    for (final e in emails.take(3)) {
      out.add(ExtractedField(key: 'Email', value: e, confidence: 0.98, category: 'contact', evidence: _lineContaining(lines, e)));
    }
    final sites = RegExp(r'\b(?:https?://|www\.)[^\s,;)>"]+', caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[.]+$'), ''))
        .toSet();
    for (final s in sites.take(2)) {
      out.add(ExtractedField(key: 'Website', value: s, confidence: 0.95, category: 'contact', evidence: _lineContaining(lines, s)));
    }

    // Exercise sheets often contain fake sample data (phone numbers in code), so skip them.
    if (type == DocumentType.academic) return out;
    final phone = RegExp(r'(\+?\(?\d[\d\s().\-]{6,20}\d)');
    for (final hit in _findLabels(lines, const ['telephone', 'tel', 'phone', 'mobile', 'mob', 'gsm', 'portable', 'cell', 'whatsapp', 'fax'])) {
      final m = phone.firstMatch(hit.line.text.substring(hit.labelEnd));
      if (m == null) continue;
      final digits = RegExp(r'\d').allMatches(m.group(1)!).length;
      if (digits < 8 || digits > 15) continue;
      final key = TextNormalizer.containsPhrase(hit.line.folded, 'fax') ? 'Fax' : 'Phone';
      if (out.any((f) => f.key == key)) continue;
      out.add(ExtractedField(key: key, value: m.group(1)!.trim(), confidence: 0.9, category: 'contact', evidence: hit.line.text));
    }
    return out;
  }

  static String? _lineContaining(List<_Line> lines, String value) {
    for (final l in lines) {
      if (l.text.contains(value)) return l.text;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Dates

  static const _frMonths = 'janvier|fevrier|février|mars|avril|mai|juin|juillet|aout|août|septembre|octobre|novembre|decembre|décembre';
  static const _enMonths = 'jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec';

  static final List<RegExp> _datePatterns = [
    RegExp(r'(?<![\d/.\-])(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?![\d/.\-])'),
    RegExp(r'(?<![\d/.\-])(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?![\d/.\-])'),
    RegExp('\\b(\\d{1,2}|1er)\\s+($_frMonths)\\s+(\\d{4})\\b', caseSensitive: false),
    RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+($_enMonths)[a-z]*\\.?,?\\s+(\\d{4})\\b', caseSensitive: false),
    RegExp('\\b($_enMonths)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b', caseSensitive: false),
  ];

  static bool _plausibleDate(RegExpMatch m, int patternIndex) {
    if (patternIndex == 0) {
      final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
      return y >= 1900 && y <= 2100 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31;
    }
    if (patternIndex == 1) {
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
      return a >= 1 && b >= 1 && ((a <= 31 && b <= 12) || (a <= 12 && b <= 31));
    }
    return true;
  }

  static List<ExtractedField> _dates(List<_Line> lines, DocumentType type) {
    const dueLabels = ['due date', 'date due', 'payment due', 'pay by', 'echeance', 'date limite', 'payable avant', 'a regler avant', 'a payer avant'];
    const issueLabels = ['invoice date', 'date de facture', 'date facture', 'date d emission', 'issue date', 'issued', 'emis le', 'fait le', 'date'];
    const birthLabels = ['date de naissance', 'date of birth', 'ne le', 'nee le', 'dob'];
    const expiryLabels = ['date d expiration', 'date of expiry', 'expiry', 'expiration', 'valable jusqu'];

    final out = <ExtractedField>[];
    final usedKeys = <String>{};
    ExtractedField? firstUnlabeled;

    for (final line in lines) {
      for (int p = 0; p < _datePatterns.length; p++) {
        for (final m in _datePatterns[p].allMatches(line.text)) {
          if (!_plausibleDate(m, p)) continue;
          final before = line.folded.substring(0, m.start).replaceAll("'", ' ');
          String? key;
          if (dueLabels.any((l) => TextNormalizer.containsPhrase(before, l))) {
            key = type.isFinancial ? 'Due date' : 'Deadline';
          } else if (birthLabels.any((l) => TextNormalizer.containsPhrase(before, l))) {
            key = 'Date of birth';
          } else if (expiryLabels.any((l) => TextNormalizer.containsPhrase(before, l))) {
            key = 'Expiry date';
          } else if (issueLabels.any((l) => TextNormalizer.containsPhrase(before, l))) {
            key = type == DocumentType.invoice ? 'Invoice date' : 'Date';
          }
          final f = ExtractedField(
            key: key ?? 'Date',
            value: m.group(0)!,
            confidence: key == null ? 0.7 : 0.9,
            category: 'date',
            evidence: line.text,
          );
          if (key == null) {
            firstUnlabeled ??= f;
          } else if (usedKeys.add(key)) {
            out.add(f);
          }
        }
      }
    }
    final hasMainDate = usedKeys.contains('Date') || usedKeys.contains('Invoice date');
    if (!hasMainDate && firstUnlabeled != null) out.insert(0, firstUnlabeled);
    return out;
  }

  // ---------------------------------------------------------------------------
  // Money

  static const _totalLabels = [
    'grand total', 'total general', 'net a payer', 'total a payer', 'montant a payer', 'total ttc', 'montant ttc',
    'total due', 'amount due', 'balance due', 'total amount', 'montant total', 'total', 'a payer',
  ];
  static const _subtotalLabels = [
    'subtotal', 'sub-total', 'sub total', 'sous-total', 'sous total', 'total ht', 'montant ht', 'total hors taxes',
    'total hors taxe', 'total h.t',
  ];
  static const _taxLabels = ['total tva', 'montant tva', 'tva', 't.v.a', 'vat', 'sales tax', 'gst', 'hst', 'tax', 'taxe', 'taxes'];
  static const _taxIdWords = [
    'tax id', 'tax no', 'vat no', 'vat number', 'vat reg', 'tva intracommunautaire', 'numero de tva', 'n° tva', 'code tva',
    'matricule',
  ];

  static ({List<ExtractedField> fields, bool verified}) _moneyFields(
    List<_Line> lines,
    DocumentType type,
    String? currency,
    List<String> warnings,
  ) {
    bool allowed(_AmountCandidate c) => type.isFinancial ? (c.money.value ?? 0) > 0 : c.money.currency != null;

    final totals = _amountsAfterLabels(lines, _totalLabels, currency, reject: (folded) {
      return RegExp(r'\b(sub|sous)[\s-]?total').hasMatch(folded) ||
          RegExp(r'\btotal\s+(ht|h\.t|hors|tva|vat|tax|taxes|qty|quantite|items|articles|pages|remise|discount|savings)\b').hasMatch(folded);
    }).where(allowed).toList();
    final subtotals = _amountsAfterLabels(lines, _subtotalLabels, currency).where(allowed).toList();
    final taxes = _amountsAfterLabels(lines, _taxLabels, currency, reject: (folded) {
      // Lines naming a total or subtotal (e.g. "Total TTC (TVA incluse)") carry that amount, not the tax.
      return _taxIdWords.any((w) => folded.contains(w)) ||
          RegExp(r'\b(ttc|ht|h\.t|hors tax\w*|net a payer|grand total|total due|amount due|balance due|incl\w*|including)\b')
              .hasMatch(folded) ||
          RegExp(r'\b(sub|sous)[\s-]?total').hasMatch(folded);
    }).where(allowed).toList();
    final stamps = type.isFinancial
        ? _amountsAfterLabels(lines, const ['timbre fiscal', 'droit de timbre', 'timbre'], currency).where(allowed).toList()
        : <_AmountCandidate>[];
    final discounts = _amountsAfterLabels(lines, const ['discount', 'remise', 'rabais'], currency).where(allowed).toList();

    _AmountCandidate? pick(List<_AmountCandidate> list) {
      if (list.isEmpty) return null;
      list.sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        return p != 0 ? p : b.line.index.compareTo(a.line.index);
      });
      return list.first;
    }

    final total = pick(totals);
    final subtotal = pick(subtotals);
    final tax = pick(taxes);
    final stamp = pick(stamps);
    final discount = pick(discounts);

    bool verified = false;
    double totalConfidence = 0.85;
    if (total?.money.value != null && subtotal?.money.value != null) {
      final expected = subtotal!.money.value! + (tax?.money.value ?? 0) + (stamp?.money.value ?? 0) - (discount?.money.value ?? 0);
      final t = total!.money.value!;
      if ((expected - t).abs() <= max(0.011, t * 0.005)) {
        verified = true;
        totalConfidence = 0.98;
      } else if (t + 0.01 < subtotal.money.value!) {
        warnings.add('The total (${total.money.raw}) is smaller than the subtotal (${subtotal.money.raw}). Please check the scan.');
        totalConfidence = 0.6;
      }
    }

    final fields = <ExtractedField>[];
    if (total != null) {
      fields.add(ExtractedField(key: 'Total', value: total.money.raw, confidence: totalConfidence, category: 'financial', evidence: total.evidence));
    }
    if (subtotal != null) {
      fields.add(ExtractedField(key: 'Subtotal', value: subtotal.money.raw, confidence: verified ? 0.95 : 0.8, category: 'financial', evidence: subtotal.evidence));
    }
    if (tax != null) {
      final rate = RegExp(r'(\d{1,2}(?:[.,]\d{1,2})?)\s?%').firstMatch(tax.line.text)?.group(1);
      fields.add(ExtractedField(
        key: rate == null ? 'Tax / VAT' : 'Tax / VAT ($rate%)',
        value: tax.money.raw,
        confidence: verified ? 0.95 : 0.8,
        category: 'financial',
        evidence: tax.evidence,
      ));
    }
    if (stamp != null) {
      fields.add(ExtractedField(key: 'Stamp duty', value: stamp.money.raw, confidence: 0.8, category: 'financial', evidence: stamp.evidence));
    }
    if (discount != null) {
      fields.add(ExtractedField(key: 'Discount', value: discount.money.raw, confidence: 0.75, category: 'financial', evidence: discount.evidence));
    }
    return (fields: fields, verified: verified);
  }

  /// Amounts printed after a label on the same line, or alone on the following line.
  static List<_AmountCandidate> _amountsAfterLabels(
    List<_Line> lines,
    List<String> labels,
    String? currency, {
    bool Function(String folded)? reject,
  }) {
    final out = <_AmountCandidate>[];
    for (final hit in _findLabels(lines, labels)) {
      if (reject != null && reject(hit.line.folded)) continue;
      final after = Money.findAll(hit.line.text, defaultCurrency: currency).where((m) => m.start >= hit.labelEnd).toList();
      if (after.isNotEmpty) {
        out.add(_AmountCandidate(after.last, hit.line, hit.line.text, hit.priority));
        continue;
      }
      if (hit.line.index + 1 < lines.length) {
        final next = lines[hit.line.index + 1];
        final amounts = Money.findAll(next.text, defaultCurrency: currency);
        if (amounts.length == 1 && amounts.first.raw.length >= next.text.trim().length * 0.7) {
          out.add(_AmountCandidate(amounts.first, next, '${hit.line.text} / ${next.text}', hit.priority));
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Line items

  static const _nonItemWords = [
    'total', 'subtotal', 'sous', 'tva', 'vat', 'tax', 'taxe', 'timbre', 'remise', 'discount', 'cash', 'especes',
    'change', 'rendu', 'carte', 'card', 'paye', 'paid', 'balance', 'solde', 'montant', 'payer', 'date', 'tel',
    'phone', 'iban', 'rib',
  ];

  static List<DocumentLineItem> _lineItems(List<_Line> lines, String? currency) {
    final items = <DocumentLineItem>[];
    for (final line in lines) {
      if (_nonItemWords.any((w) => TextNormalizer.containsPhrase(line.folded, w))) continue;
      final amounts = Money.findAll(line.text, defaultCurrency: currency).where((m) => m.looksMonetary).toList();
      if (amounts.isEmpty) continue;
      var description = line.text.substring(0, amounts.first.start);
      int quantity = 1;
      final qtyPatterns = [
        RegExp(r'(?:^|\s)[x×]\s?(\d{1,3})\b'),
        RegExp(r'\b(\d{1,3})\s?[x×](?:\s|$)'),
        RegExp(r'\bqty[:\s]*(\d{1,3})\b', caseSensitive: false),
        RegExp(r'^(\d{1,3})\s+(?=[A-Za-zÀ-ÿ])'),
        // Table rows: "Description   Qty   Unit price   Total".
        RegExp(r'\s(\d{1,4})\s*$'),
      ];
      for (final re in qtyPatterns) {
        final m = re.firstMatch(description);
        if (m != null) {
          quantity = int.parse(m.group(1)!);
          description = description.replaceRange(m.start, m.end, ' ');
          break;
        }
      }
      description = description
          .replaceFirst(RegExp(r'^\s*item\s*\d*\s*[:.\-]?\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'[@=:]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (TextNormalizer.letterCount(description) < 3) continue;
      items.add(DocumentLineItem(
        description: description,
        quantity: max(1, quantity),
        unitPrice: amounts.length >= 2 ? amounts[amounts.length - 2].raw : amounts.last.raw,
        totalPrice: amounts.last.raw,
      ));
      if (items.length >= 50) break;
    }
    return items;
  }

  // ---------------------------------------------------------------------------
  // Summary

  static String _summary({
    required DocumentType type,
    required int pageCount,
    required int wordCount,
    required String? language,
    required String? vendor,
    required String? institution,
    required String? title,
    required String? total,
    required String? date,
    required List<String> headings,
  }) {
    final parts = <String>[];
    final pages = pageCount > 1 ? '$pageCount-page ' : '';
    if (type.isFinancial) {
      var s = '$pages${type.displayName}';
      if (vendor != null) s += ' from $vendor';
      parts.add(s);
      if (total != null) parts.add('total $total');
      if (date != null) parts.add('dated $date');
      return '${parts.join(', ')}.';
    }
    var s = '$pages${type.displayName}';
    if (institution != null && type == DocumentType.academic) s += ' from $institution';
    parts.add(s);
    if (title != null && title != institution) parts.add('"$title"');
    final details = <String>['$wordCount words'];
    if (language != null) details.add('in $language');
    if (headings.length > 1) details.add('${headings.length} sections');
    return '${parts.join(' — ')} (${details.join(', ')}).';
  }
}

extension on ExtractedField {
  ExtractedField copyWithKey(String newKey) =>
      ExtractedField(key: newKey, value: value, confidence: confidence, category: category, evidence: evidence);
}
