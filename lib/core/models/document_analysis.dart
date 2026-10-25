/// Document categories identified by ClearScan's on-device analysis.
enum DocumentType {
  receipt,
  invoice,
  contract,
  idCard,
  businessCard,
  bankStatement,
  taxDocument,
  medicalPrescription,
  certificate,
  academic,
  notes,
  whiteboard,
  book,
  other,
}

extension DocumentTypeExtension on DocumentType {
  String get displayName {
    switch (this) {
      case DocumentType.receipt:
        return 'Receipt';
      case DocumentType.invoice:
        return 'Invoice';
      case DocumentType.contract:
        return 'Contract / Agreement';
      case DocumentType.idCard:
        return 'ID / Passport';
      case DocumentType.businessCard:
        return 'Business Card';
      case DocumentType.bankStatement:
        return 'Bank Statement';
      case DocumentType.taxDocument:
        return 'Tax Document';
      case DocumentType.medicalPrescription:
        return 'Medical / Prescription';
      case DocumentType.certificate:
        return 'Certificate / Diploma';
      case DocumentType.academic:
        return 'Course / Exercise Sheet';
      case DocumentType.notes:
        return 'Notes';
      case DocumentType.whiteboard:
        return 'Whiteboard';
      case DocumentType.book:
        return 'Book / Article';
      case DocumentType.other:
        return 'Document';
    }
  }

  bool get isFinancial =>
      this == DocumentType.invoice ||
      this == DocumentType.receipt ||
      this == DocumentType.bankStatement ||
      this == DocumentType.taxDocument;
}

/// A structured line item (e.g. from an invoice or receipt table).
class DocumentLineItem {
  final String description;
  final int quantity;
  final String unitPrice;
  final String totalPrice;

  const DocumentLineItem({
    required this.description,
    this.quantity = 1,
    required this.unitPrice,
    required this.totalPrice,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
      };

  factory DocumentLineItem.fromJson(Map<String, dynamic> json) => DocumentLineItem(
        description: json['description'] as String,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: json['unitPrice'] as String,
        totalPrice: json['totalPrice'] as String,
      );
}

/// A key-value field extracted from the document text.
///
/// [value] is always copied verbatim from the OCR text and [evidence] is the
/// full source line it was read from, so every field can be traced back.
class ExtractedField {
  final String key;
  final String value;
  final double confidence;
  final String? category; // 'financial', 'identity', 'date', 'contact', 'legal'
  final String? evidence;

  const ExtractedField({
    required this.key,
    required this.value,
    this.confidence = 1.0,
    this.category,
    this.evidence,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'confidence': confidence,
        'category': category,
        if (evidence != null) 'evidence': evidence,
      };

  factory ExtractedField.fromJson(Map<String, dynamic> json) => ExtractedField(
        key: json['key'] as String,
        value: json['value'] as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        category: json['category'] as String?,
        evidence: json['evidence'] as String?,
      );
}

/// On-device analysis of a document's OCR text.
class DocumentAnalysis {
  final DocumentType documentType;
  final String summary;
  final List<ExtractedField> extractedFields;
  final List<DocumentLineItem> lineItems;
  final List<String> keyPoints;
  final String? suggestedAction;
  final String rawOcrText;
  final DateTime analyzedAt;
  final String modelName;
  final String? language;
  final List<String> warnings;

  DocumentAnalysis({
    required this.documentType,
    required this.summary,
    required this.extractedFields,
    this.lineItems = const [],
    required this.keyPoints,
    this.suggestedAction,
    required this.rawOcrText,
    DateTime? analyzedAt,
    this.modelName = 'On-device rule-based extractor',
    this.language,
    this.warnings = const [],
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'documentType': documentType.name,
        'summary': summary,
        'extractedFields': extractedFields.map((f) => f.toJson()).toList(),
        'lineItems': lineItems.map((item) => item.toJson()).toList(),
        'keyPoints': keyPoints,
        'suggestedAction': suggestedAction,
        'rawOcrText': rawOcrText,
        'analyzedAt': analyzedAt.toIso8601String(),
        'modelName': modelName,
        if (language != null) 'language': language,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  factory DocumentAnalysis.fromJson(Map<String, dynamic> json) {
    return DocumentAnalysis(
      documentType: DocumentType.values.firstWhere(
        (e) => e.name == json['documentType'],
        orElse: () => DocumentType.other,
      ),
      summary: json['summary'] as String? ?? '',
      extractedFields: (json['extractedFields'] as List<dynamic>?)
              ?.map((f) => ExtractedField.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      lineItems: (json['lineItems'] as List<dynamic>?)
              ?.map((item) => DocumentLineItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      keyPoints: (json['keyPoints'] as List<dynamic>?)?.map((p) => p.toString()).toList() ?? [],
      suggestedAction: json['suggestedAction'] as String?,
      rawOcrText: json['rawOcrText'] as String? ?? '',
      analyzedAt: json['analyzedAt'] != null ? DateTime.parse(json['analyzedAt'] as String) : DateTime.now(),
      modelName: json['modelName'] as String? ?? 'On-device rule-based extractor',
      language: json['language'] as String?,
      warnings: (json['warnings'] as List<dynamic>?)?.map((w) => w.toString()).toList() ?? const [],
    );
  }
}
