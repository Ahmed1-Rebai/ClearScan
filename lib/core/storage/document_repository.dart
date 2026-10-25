import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/document.dart';

/// Local offline repository managing scanned documents and their high-res page images.
class DocumentRepository {
  static final DocumentRepository instance = DocumentRepository._internal();
  DocumentRepository._internal();

  List<ScannedDocument> _documents = [];
  bool _initialized = false;

  List<ScannedDocument> get documents => List.unmodifiable(_documents);

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadFromDisk();
    _initialized = true;
  }

  /// Saves or updates a [document] to local storage.
  Future<void> saveDocument(ScannedDocument document) async {
    final int index = _documents.indexWhere((d) => d.id == document.id);
    if (index >= 0) {
      _documents[index] = document;
    } else {
      _documents.insert(0, document);
    }
    await _persistIndex();
  }

  /// Deletes a document and its stored image files.
  Future<void> deleteDocument(String id) async {
    final doc = _documents.firstWhere((d) => d.id == id, orElse: () => throw Exception('Doc not found'));
    for (final page in doc.pages) {
      final rawF = File(page.rawImagePath);
      if (await rawF.exists()) await rawF.delete();
      if (page.processedImagePath != null) {
        final procF = File(page.processedImagePath!);
        if (await procF.exists()) await procF.delete();
      }
    }
    _documents.removeWhere((d) => d.id == id);
    await _persistIndex();
  }

  /// Saves a newly captured raw image bytes to disk and returns its file path.
  Future<String> saveRawPageImage(Uint8List bytes) async {
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory(p.join(appDir.path, 'scans', 'raw'));
    if (!await scansDir.exists()) await scansDir.create(recursive: true);

    final filename = 'raw_${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.jpg';
    final file = File(p.join(scansDir.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Encodes and saves a processed [img.Image] to disk and returns its file path.
  Future<String> saveProcessedPageImage(img.Image image, String pageId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final procDir = Directory(p.join(appDir.path, 'scans', 'processed'));
    if (!await procDir.exists()) await procDir.create(recursive: true);

    final filename = 'proc_${pageId}.jpg';
    final file = File(p.join(procDir.path, filename));
    final encoded = img.encodeJpg(image, quality: 92);
    await file.writeAsBytes(encoded);
    return file.path;
  }

  Future<void> _loadFromDisk() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final indexFile = File(p.join(appDir.path, 'documents_index.json'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _documents = list.map((item) => ScannedDocument.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      _documents = [];
    }
  }

  Future<void> _persistIndex() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final indexFile = File(p.join(appDir.path, 'documents_index.json'));
      final data = jsonEncode(_documents.map((d) => d.toJson()).toList());
      await indexFile.writeAsString(data);
    } catch (_) {}
  }
}

