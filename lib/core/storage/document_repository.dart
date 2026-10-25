import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../cv/cv_isolate_service.dart';
import '../cv/image_ingest.dart';
import '../models/document.dart';

/// Local offline repository for scanned documents and their page images.
///
/// Notifies listeners on every change so screens stay in sync with background
/// work (e.g. OCR finishing while a document is open).
class DocumentRepository extends ChangeNotifier {
  static final DocumentRepository instance = DocumentRepository._internal();
  DocumentRepository._internal();

  List<ScannedDocument> _documents = [];
  bool _initialized = false;
  Directory? _baseDir;
  Future<void> _writeQueue = Future.value();

  List<ScannedDocument> get documents => List.unmodifiable(_documents);

  ScannedDocument? byId(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  @visibleForTesting
  void useBaseDirectoryForTesting(Directory dir) {
    _baseDir = dir;
    _documents = [];
    _initialized = false;
    _writeQueue = Future.value();
  }

  Future<Directory> get _base async => _baseDir ??= await getApplicationDocumentsDirectory();

  Future<Directory> _subdir(String name) async {
    final dir = Directory(p.join((await _base).path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadFromDisk();
    _initialized = true;
    unawaited(collectGarbage());
  }

  /// Inserts or replaces [document].
  Future<void> saveDocument(ScannedDocument document) {
    final index = _documents.indexWhere((d) => d.id == document.id);
    if (index >= 0) {
      _documents[index] = document;
    } else {
      _documents.insert(0, document);
    }
    notifyListeners();
    return _persist();
  }

  /// Applies [transform] to the latest stored version, so concurrent edits are not lost.
  Future<ScannedDocument?> updateDocument(String id, ScannedDocument Function(ScannedDocument current) transform) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index < 0) return null;
    final updated = transform(_documents[index]);
    _documents[index] = updated;
    notifyListeners();
    await _persist();
    return updated;
  }

  /// Deletes a document and its page images.
  Future<void> deleteDocument(String id) async {
    final doc = byId(id);
    if (doc == null) return;
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
    await deleteFiles(doc.pages.expand((page) => [page.rawImagePath, page.processedImagePath]));
  }

  /// Stores captured / imported image bytes as an upright, size-capped JPEG and returns its path.
  Future<String> importImageBytes(Uint8List bytes) async {
    final Uint8List normalized;
    if (ImageIngest.needsNativeDecode(bytes)) {
      final image = await ImageIngest.decodeNativeDownscaled(bytes);
      normalized = await CvIsolateService.encodeJpgAsync(image, quality: 94);
    } else {
      normalized = await CvIsolateService.normalizeCaptureAsync(bytes);
    }
    final dir = await _subdir(p.join('scans', 'raw'));
    final file = File(p.join(dir.path, 'raw_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(normalized, flush: true);
    return file.path;
  }

  /// A fresh path for a processed page image (unique per version, so image caches never go stale).
  Future<String> newProcessedPath(String pageId) async {
    final dir = await _subdir(p.join('scans', 'processed'));
    return p.join(dir.path, 'proc_${pageId}_${DateTime.now().microsecondsSinceEpoch}.jpg');
  }

  Future<Directory> exportsDirectory() => _subdir('exports');

  Future<Directory> tempDirectory() => _subdir(p.join('scans', 'tmp'));

  Future<void> deleteFiles(Iterable<String?> paths) async {
    for (final path in paths) {
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Removes page images that no document references (e.g. from cancelled scans).
  /// Only touches files older than [minAge] so in-progress scan sessions are safe.
  Future<int> collectGarbage({Duration minAge = const Duration(hours: 24)}) async {
    final referenced = <String>{
      for (final d in _documents)
        for (final page in d.pages) ...[page.rawImagePath, if (page.processedImagePath != null) page.processedImagePath!],
    };
    final cutoff = DateTime.now().subtract(minAge);
    int removed = 0;
    for (final sub in [p.join('scans', 'raw'), p.join('scans', 'processed'), p.join('scans', 'tmp')]) {
      final dir = Directory(p.join((await _base).path, sub));
      try {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File || referenced.contains(entity.path)) continue;
          if ((await entity.lastModified()).isBefore(cutoff)) {
            await entity.delete();
            removed++;
          }
        }
      } on FileSystemException catch (e) {
        debugPrint('DocumentRepository: cleanup skipped $sub: $e');
      }
    }
    return removed;
  }

  Future<void> _loadFromDisk() async {
    try {
      final indexFile = File(p.join((await _base).path, 'documents_index.json'));
      if (await indexFile.exists()) {
        final List<dynamic> list = jsonDecode(await indexFile.readAsString());
        _documents = list.map((item) => ScannedDocument.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('DocumentRepository: could not load index: $e');
      _documents = [];
    }
  }

  Future<void> _persist() {
    _writeQueue = _writeQueue.then((_) => _writeIndex()).catchError((Object e) {
      debugPrint('DocumentRepository: could not save index: $e');
    });
    return _writeQueue;
  }

  Future<void> _writeIndex() async {
    final indexFile = File(p.join((await _base).path, 'documents_index.json'));
    final tmp = File('${indexFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(_documents.map((d) => d.toJson()).toList()), flush: true);
    await tmp.rename(indexFile.path);
  }
}
