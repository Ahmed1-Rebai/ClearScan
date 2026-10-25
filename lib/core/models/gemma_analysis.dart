/// Extended document categories identified by ClearScan on-device intelligence.
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
      case DocumentType.notes:
        return 'Handwritten Notes';
      case DocumentType.whiteboard:
        return 'Whiteboard';
      case DocumentType.book:
        return 'Book / Article';
      case DocumentType.other:
        return 'Document';
    }
  }
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

/// A structured key-value field extracted from document text.
class ExtractedField {
  final String key;
  final String value;
  final double confidence;
  final String? category; // 'financial', 'identity', 'date', 'contact', 'legal'

  const ExtractedField({
    required this.key,
    required this.value,
    this.confidence = 1.0,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'confidence': confidence,
        'category': category,
      };

  factory ExtractedField.fromJson(Map<String, dynamic> json) => ExtractedField(
        key: json['key'] as String,
        value: json['value'] as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        category: json['category'] as String?,
      );
}

/// Comprehensive on-device analysis produced by Gemma.
class GemmaDocumentAnalysis {
  final DocumentType documentType;
  final String summary;
  final List<ExtractedField> extractedFields;
  final List<DocumentLineItem> lineItems;
  final List<String> keyPoints;
  final String? suggestedAction;
  final String rawOcrText;
  final DateTime analyzedAt;
  final String modelName;

  GemmaDocumentAnalysis({
    required this.documentType,
    required this.summary,
    required this.extractedFields,
    this.lineItems = const [],
    required this.keyPoints,
    this.suggestedAction,
    required this.rawOcrText,
    DateTime? analyzedAt,
    this.modelName = 'Gemma 2B (On-Device)',
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
      };

  factory GemmaDocumentAnalysis.fromJson(Map<String, dynamic> json) {
    return GemmaDocumentAnalysis(
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
      keyPoints: (json['keyPoints'] as List<dynamic>?)
              ?.map((p) => p.toString())
              .toList() ??
          [],
      suggestedAction: json['suggestedAction'] as String?,
      rawOcrText: json['rawOcrText'] as String? ?? '',
      analyzedAt: json['analyzedAt'] != null
          ? DateTime.parse(json['analyzedAt'] as String)
          : DateTime.now(),
      modelName: json['modelName'] as String? ?? 'Gemma 2B (On-Device)',
    );
  }
}
