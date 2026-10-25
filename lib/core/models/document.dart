import 'dart:ui';
import 'package:uuid/uuid.dart';
import 'document_analysis.dart';
import 'ocr_line.dart';

export 'ocr_line.dart';

/// Available document enhancement filters.
enum ScanFilterType {
  original,
  magicColor,
  sharpBW,
  grayscale,
  lighten,
}

/// The 4 ordered corners of a detected or adjusted document quad:
/// [topLeft, topRight, bottomRight, bottomLeft] in normalized 0.0-1.0 or pixel coordinates.
class DocumentCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Default full-image rectangle
  factory DocumentCorners.defaultRect(double width, double height) {
    return DocumentCorners(
      topLeft: Offset(width * 0.05, height * 0.05),
      topRight: Offset(width * 0.95, height * 0.05),
      bottomRight: Offset(width * 0.95, height * 0.95),
      bottomLeft: Offset(width * 0.05, height * 0.95),
    );
  }

  factory DocumentCorners.fullImage(double width, double height) {
    return DocumentCorners(
      topLeft: Offset.zero,
      topRight: Offset(width, 0),
      bottomRight: Offset(width, height),
      bottomLeft: Offset(0, height),
    );
  }

  factory DocumentCorners.fromList(List<Offset> pts) {
    return DocumentCorners(topLeft: pts[0], topRight: pts[1], bottomRight: pts[2], bottomLeft: pts[3]);
  }

  List<Offset> toList() => [topLeft, topRight, bottomRight, bottomLeft];

  DocumentCorners scale(double sx, double sy) {
    return DocumentCorners.fromList(toList().map((p) => Offset(p.dx * sx, p.dy * sy)).toList());
  }

  /// True when the quad is a simple convex polygon in clockwise order, i.e. safe to warp.
  bool get isConvex {
    final pts = toList();
    for (int i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final c = pts[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross <= 0) return false;
    }
    return true;
  }

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  Map<String, dynamic> toJson() => {
        'topLeft': {'dx': topLeft.dx, 'dy': topLeft.dy},
        'topRight': {'dx': topRight.dx, 'dy': topRight.dy},
        'bottomRight': {'dx': bottomRight.dx, 'dy': bottomRight.dy},
        'bottomLeft': {'dx': bottomLeft.dx, 'dy': bottomLeft.dy},
      };

  factory DocumentCorners.fromJson(Map<String, dynamic> json) {
    return DocumentCorners(
      topLeft: Offset(
        (json['topLeft']['dx'] as num).toDouble(),
        (json['topLeft']['dy'] as num).toDouble(),
      ),
      topRight: Offset(
        (json['topRight']['dx'] as num).toDouble(),
        (json['topRight']['dy'] as num).toDouble(),
      ),
      bottomRight: Offset(
        (json['bottomRight']['dx'] as num).toDouble(),
        (json['bottomRight']['dy'] as num).toDouble(),
      ),
      bottomLeft: Offset(
        (json['bottomLeft']['dx'] as num).toDouble(),
        (json['bottomLeft']['dy'] as num).toDouble(),
      ),
    );
  }
}

/// Represents a single page within a multi-page document.
///
/// The processed image is always derived from [rawImagePath] by warping with
/// [corners], rotating by [rotationDegrees] (clockwise) and applying [filterType].
class ScannedPage {
  final String id;
  final String rawImagePath;
  final String? processedImagePath;
  final DocumentCorners? corners;
  final ScanFilterType filterType;
  final int rotationDegrees; // 0, 90, 180, 270
  final DateTime createdAt;

  /// Null until OCR has run; empty when OCR found no text.
  final String? ocrText;
  final List<OcrLine> ocrLines;
  final double? ocrConfidence;

  ScannedPage({
    String? id,
    required this.rawImagePath,
    this.processedImagePath,
    this.corners,
    this.filterType = ScanFilterType.magicColor,
    this.rotationDegrees = 0,
    DateTime? createdAt,
    this.ocrText,
    this.ocrLines = const [],
    this.ocrConfidence,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get hasOcr => ocrText != null;

  String get displayImagePath => processedImagePath ?? rawImagePath;

  /// Use [clearOcr] whenever the processed image changes, since old text boxes no longer match.
  ScannedPage copyWith({
    String? rawImagePath,
    String? processedImagePath,
    DocumentCorners? corners,
    ScanFilterType? filterType,
    int? rotationDegrees,
    String? ocrText,
    List<OcrLine>? ocrLines,
    double? ocrConfidence,
    bool clearOcr = false,
  }) {
    return ScannedPage(
      id: id,
      rawImagePath: rawImagePath ?? this.rawImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      corners: corners ?? this.corners,
      filterType: filterType ?? this.filterType,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      createdAt: createdAt,
      ocrText: clearOcr ? ocrText : (ocrText ?? this.ocrText),
      ocrLines: clearOcr ? (ocrLines ?? const []) : (ocrLines ?? this.ocrLines),
      ocrConfidence: clearOcr ? ocrConfidence : (ocrConfidence ?? this.ocrConfidence),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rawImagePath': rawImagePath,
        'processedImagePath': processedImagePath,
        'corners': corners?.toJson(),
        'filterType': filterType.name,
        'rotationDegrees': rotationDegrees,
        'createdAt': createdAt.toIso8601String(),
        'ocrText': ocrText,
        if (ocrLines.isNotEmpty) 'ocrLines': ocrLines.map((l) => l.toJson()).toList(),
        if (ocrConfidence != null) 'ocrConfidence': ocrConfidence,
      };

  factory ScannedPage.fromJson(Map<String, dynamic> json) {
    return ScannedPage(
      id: json['id'] as String,
      rawImagePath: json['rawImagePath'] as String,
      processedImagePath: json['processedImagePath'] as String?,
      corners: json['corners'] != null
          ? DocumentCorners.fromJson(json['corners'] as Map<String, dynamic>)
          : null,
      filterType: ScanFilterType.values.firstWhere(
        (e) => e.name == json['filterType'],
        orElse: () => ScanFilterType.magicColor,
      ),
      rotationDegrees: (json['rotationDegrees'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      ocrText: json['ocrText'] as String?,
      ocrLines: (json['ocrLines'] as List<dynamic>?)
              ?.map((l) => OcrLine.fromJson(l as Map<String, dynamic>))
              .toList() ??
          const [],
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble(),
    );
  }
}

/// Represents a multi-page document file.
class ScannedDocument {
  final String id;
  final String title;
  final List<ScannedPage> pages;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Cached analysis of the combined OCR text; null until every page has OCR.
  final DocumentAnalysis? analysis;

  ScannedDocument({
    String? id,
    required this.title,
    required this.pages,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.analysis,
  })  : id = id ?? const Uuid().v4(),
        tags = tags ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get pageCount => pages.length;

  String? get previewImagePath => pages.isNotEmpty ? pages.first.displayImagePath : null;

  bool get isFullyRecognized => pages.isNotEmpty && pages.every((p) => p.hasOcr);

  /// All pages' OCR text, separated by page markers when there is more than one page.
  String get combinedText {
    final recognized = pages.where((p) => (p.ocrText ?? '').trim().isNotEmpty).toList();
    if (recognized.length <= 1) return recognized.isEmpty ? '' : recognized.first.ocrText!.trim();
    final buffer = StringBuffer();
    for (int i = 0; i < pages.length; i++) {
      final text = pages[i].ocrText?.trim() ?? '';
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('--- Page ${i + 1} ---\n');
      buffer.write(text);
    }
    return buffer.toString();
  }

  ScannedDocument copyWith({
    String? title,
    List<ScannedPage>? pages,
    List<String>? tags,
    DateTime? updatedAt,
    DocumentAnalysis? analysis,
    bool clearAnalysis = false,
  }) {
    return ScannedDocument(
      id: id,
      title: title ?? this.title,
      pages: pages ?? this.pages,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      analysis: clearAnalysis ? analysis : (analysis ?? this.analysis),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': pages.map((p) => p.toJson()).toList(),
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (analysis != null) 'analysis': analysis!.toJson(),
      };

  factory ScannedDocument.fromJson(Map<String, dynamic> json) {
    return ScannedDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      pages: (json['pages'] as List<dynamic>)
          .map((p) => ScannedPage.fromJson(p as Map<String, dynamic>))
          .toList(),
      tags: (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      analysis: json['analysis'] != null
          ? DocumentAnalysis.fromJson(json['analysis'] as Map<String, dynamic>)
          : null,
    );
  }
}

