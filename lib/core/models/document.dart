import 'dart:ui';
import 'package:uuid/uuid.dart';

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

  List<Offset> toList() => [topLeft, topRight, bottomRight, bottomLeft];

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
class ScannedPage {
  final String id;
  final String rawImagePath;
  final String? processedImagePath;
  final DocumentCorners? corners;
  final ScanFilterType filterType;
  final int rotationDegrees; // 0, 90, 180, 270
  final DateTime createdAt;
  final String? ocrText;

  ScannedPage({
    String? id,
    required this.rawImagePath,
    this.processedImagePath,
    this.corners,
    this.filterType = ScanFilterType.magicColor,
    this.rotationDegrees = 0,
    DateTime? createdAt,
    this.ocrText,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  ScannedPage copyWith({
    String? rawImagePath,
    String? processedImagePath,
    DocumentCorners? corners,
    ScanFilterType? filterType,
    int? rotationDegrees,
    String? ocrText,
  }) {
    return ScannedPage(
      id: id,
      rawImagePath: rawImagePath ?? this.rawImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      corners: corners ?? this.corners,
      filterType: filterType ?? this.filterType,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      createdAt: createdAt,
      ocrText: ocrText ?? this.ocrText,
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
  final Map<String, dynamic>? gemmaMetadata;

  ScannedDocument({
    String? id,
    required this.title,
    required this.pages,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.gemmaMetadata,
  })  : id = id ?? const Uuid().v4(),
        tags = tags ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get pageCount => pages.length;

  String? get previewImagePath =>
      pages.isNotEmpty ? (pages.first.processedImagePath ?? pages.first.rawImagePath) : null;

  ScannedDocument copyWith({
    String? title,
    List<ScannedPage>? pages,
    List<String>? tags,
    DateTime? updatedAt,
    Map<String, dynamic>? gemmaMetadata,
  }) {
    return ScannedDocument(
      id: id,
      title: title ?? this.title,
      pages: pages ?? this.pages,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      gemmaMetadata: gemmaMetadata ?? this.gemmaMetadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'pages': pages.map((p) => p.toJson()).toList(),
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'gemmaMetadata': gemmaMetadata,
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
      gemmaMetadata: json['gemmaMetadata'] as Map<String, dynamic>?,
    );
  }
}

