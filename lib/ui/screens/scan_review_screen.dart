import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/cv/cv_isolate_service.dart';
import '../../core/cv/image_ingest.dart';
import '../../core/models/document.dart';
import '../../core/ocr/ocr_service.dart';
import '../../core/storage/document_repository.dart';
import '../gallery_import.dart';
import '../widgets/page_image.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';
import 'filter_screen.dart';

/// Reviews the pages of a scan before saving them as one document:
/// new photos are auto-cropped, oriented and enhanced in the background, and
/// every page can be re-cropped, re-filtered, rotated, deleted or reordered.
///
/// With [documentId], edits that existing document (optionally appending [newRawPaths]).
class ScanReviewScreen extends StatefulWidget {
  final String? documentId;
  final List<String> newRawPaths;

  const ScanReviewScreen({super.key, this.documentId, this.newRawPaths = const []});

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ReviewPage {
  ScannedPage page;
  bool busy;
  String? error;

  _ReviewPage(this.page, {this.busy = false});
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  final List<_ReviewPage> _pages = [];
  final PageController _pager = PageController();
  int _current = 0;
  bool _saving = false;
  bool _dirty = false;
  bool _queueRunning = false;
  ScannedDocument? _existing;

  /// Files created in this session; deleted if the session is discarded.
  final Set<String> _sessionFiles = {};

  /// Files of the stored document that edits replaced; deleted once saved.
  final Set<String> _replacedFiles = {};
  final List<ScannedPage> _removedExisting = [];

  /// Ids of pages re-rendered or rotated in this session.
  final Set<String> _edited = {};

  bool get _anyBusy => _pages.any((p) => p.busy || p.page.processedImagePath == null && p.error == null);

  @override
  void initState() {
    super.initState();
    final id = widget.documentId;
    if (id != null) {
      _existing = DocumentRepository.instance.byId(id);
      _pages.addAll(_existing?.pages.map(_ReviewPage.new) ?? const []);
    }
    if (widget.newRawPaths.isNotEmpty) {
      final firstNew = _pages.length;
      for (final path in widget.newRawPaths) {
        _sessionFiles.add(path);
        _pages.add(_ReviewPage(ScannedPage(rawImagePath: path), busy: true));
      }
      _dirty = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(firstNew));
      _runQueue();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _addRawPages(List<String> rawPaths) {
    if (rawPaths.isEmpty) return;
    final firstNew = _pages.length;
    setStateIfMounted(() {
      for (final path in rawPaths) {
        _sessionFiles.add(path);
        _pages.add(_ReviewPage(ScannedPage(rawImagePath: path), busy: true));
      }
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(firstNew));
    _runQueue();
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    } else {
      fn();
    }
  }

  void _jumpTo(int index) {
    if (!mounted || index < 0 || index >= _pages.length) return;
    setState(() => _current = index);
    if (_pager.hasClients) _pager.jumpToPage(index);
  }

  /// Processes new pages one at a time (keeps memory bounded for large batches).
  Future<void> _runQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    try {
      while (mounted) {
        _ReviewPage? next;
        for (final p in _pages) {
          if (p.page.processedImagePath == null && p.error == null) {
            next = p;
            break;
          }
        }
        if (next == null) break;
        await _render(next, autoOrient: true);
      }
    } finally {
      _queueRunning = false;
    }
  }

  /// Re-renders a page from its raw photo with its current corners, rotation and filter.
  Future<void> _render(_ReviewPage entry, {bool autoOrient = false}) async {
    setStateIfMounted(() {
      entry.busy = true;
      entry.error = null;
    });
    try {
      final output = await DocumentRepository.instance.newProcessedPath(entry.page.id);
      _sessionFiles.add(output);
      final result = await CvIsolateService.processPageAsync(
        rawPath: entry.page.rawImagePath,
        outputPath: output,
        filter: entry.page.filterType,
        corners: entry.page.corners,
        rotation: entry.page.rotationDegrees,
        autoOrient: autoOrient,
      );
      _retire(entry.page.processedImagePath);
      _edited.add(entry.page.id);
      setStateIfMounted(() {
        entry.page = entry.page.copyWith(
          processedImagePath: output,
          corners: result.corners,
          rotationDegrees: result.rotation,
          clearOcr: true,
        );
        entry.busy = false;
        _dirty = true;
      });
    } catch (e) {
      setStateIfMounted(() {
        entry.busy = false;
        entry.error = e is UnsupportedImageException ? e.message : 'This photo could not be processed.';
      });
    }
  }

  /// An outdated processed image: delete now if this session created it, else after saving.
  void _retire(String? path) {
    if (path == null) return;
    if (_sessionFiles.remove(path)) {
      DocumentRepository.instance.deleteFiles([path]);
    } else {
      _replacedFiles.add(path);
    }
  }

  Future<void> _crop(_ReviewPage entry) async {
    final corners = await Navigator.push<DocumentCorners>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(rawImagePath: entry.page.rawImagePath, initialCorners: entry.page.corners)),
    );
    if (corners == null || !mounted) return;
    entry.page = entry.page.copyWith(corners: corners);
    await _render(entry);
  }

  Future<void> _enhance(_ReviewPage entry) async {
    final filter = await Navigator.push<ScanFilterType>(
      context,
      MaterialPageRoute(builder: (_) => FilterScreen(page: entry.page)),
    );
    if (filter == null || filter == entry.page.filterType || !mounted) return;
    entry.page = entry.page.copyWith(filterType: filter);
    await _render(entry);
  }

  Future<void> _rotate(_ReviewPage entry) async {
    final source = entry.page.processedImagePath;
    if (source == null) return;
    setState(() => entry.busy = true);
    try {
      // Rotating the finished page is much faster than re-rendering from the raw photo.
      final output = await DocumentRepository.instance.newProcessedPath(entry.page.id);
      _sessionFiles.add(output);
      await CvIsolateService.rotateImageFileAsync(source, output, 90);
      _retire(source);
      _edited.add(entry.page.id);
      setStateIfMounted(() {
        entry.page = entry.page.copyWith(
          processedImagePath: output,
          rotationDegrees: (entry.page.rotationDegrees + 90) % 360,
          clearOcr: true,
        );
        _dirty = true;
      });
    } finally {
      setStateIfMounted(() => entry.busy = false);
    }
  }

  void _delete(int index) {
    final entry = _pages[index];
    setState(() {
      _pages.removeAt(index);
      if (_sessionFiles.contains(entry.page.rawImagePath)) {
        final files = [entry.page.rawImagePath, entry.page.processedImagePath];
        _sessionFiles.removeAll(files);
        DocumentRepository.instance.deleteFiles(files);
      } else {
        _removedExisting.add(entry.page);
      }
      _current = _current.clamp(0, (_pages.length - 1).clamp(0, 1 << 30));
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_current));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final moved = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, moved);
      _current = newIndex;
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(newIndex));
  }

  Future<void> _addPages() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scan with camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Import from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    final List<String> paths;
    if (source == 'camera') {
      paths = await Navigator.push<List<String>>(
            context,
            MaterialPageRoute(builder: (_) => const CameraScreen(returnCaptures: true)),
          ) ??
          const [];
    } else {
      paths = await importImagesFromGallery(context);
    }
    if (mounted) _addRawPages(paths);
  }

  Future<void> _save() async {
    if (_pages.isEmpty || _anyBusy || _saving) return;
    final failed = _pages.indexWhere((p) => p.error != null);
    if (failed >= 0) {
      _jumpTo(failed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Page ${failed + 1} could not be processed. Delete it to save.')),
      );
      return;
    }
    setState(() => _saving = true);
    final repo = DocumentRepository.instance;
    final pages = [for (final p in _pages) p.page];

    ScannedDocument? doc;
    if (_existing != null) {
      doc = await repo.updateDocument(_existing!.id, (current) {
        // Pages not edited here take their latest stored version (OCR may have finished meanwhile).
        final latest = {for (final page in current.pages) page.id: page};
        final merged = [
          for (final page in pages)
            if (!_edited.contains(page.id) && latest[page.id] != null) latest[page.id]! else page,
        ];
        return current.copyWith(pages: merged, clearAnalysis: true);
      });
    }
    if (doc == null) {
      doc = ScannedDocument(title: 'Scan ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.now())}', pages: pages);
      await repo.saveDocument(doc);
    }
    await repo.deleteFiles([
      ..._replacedFiles,
      for (final p in _removedExisting) ...[p.rawImagePath, p.processedImagePath],
    ]);
    _sessionFiles.clear();
    _replacedFiles.clear();
    _dirty = false;
    unawaited(OcrService.instance.processDocument(doc.id));

    if (!mounted) return;
    if (_existing == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: doc!.id)));
    } else {
      Navigator.pop(context, true);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(_existing == null ? 'The scanned pages will be deleted.' : 'Your changes to this document will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await DocumentRepository.instance.deleteFiles(_sessionFiles);
    _sessionFiles.clear();
    _dirty = false;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _anyBusy;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? 'Review scan' : 'Edit pages'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _pages.isEmpty || busy || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(_pages.length > 1 ? 'Save (${_pages.length})' : 'Save'),
              ),
            ),
          ],
        ),
        body: _pages.isEmpty ? _buildEmpty(theme) : _buildPages(theme),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear_outlined, size: 56, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No pages yet', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _addPages, icon: const Icon(Icons.add), label: const Text('Add pages')),
          ],
        ),
      ),
    );
  }

  Widget _buildPages(ThemeData theme) {
    final entry = _pages[_current.clamp(0, _pages.length - 1)];
    final canEdit = !entry.busy && entry.page.processedImagePath != null;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pager,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) => _PagePreview(entry: _pages[index]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Page ${_current + 1} of ${_pages.length}',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _PageAction(icon: Icons.crop, label: 'Crop', onTap: canEdit ? () => _crop(entry) : null),
              _PageAction(icon: Icons.auto_awesome, label: 'Enhance', onTap: canEdit ? () => _enhance(entry) : null),
              _PageAction(icon: Icons.rotate_right, label: 'Rotate', onTap: canEdit ? () => _rotate(entry) : null),
              _PageAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: entry.busy ? null : () => _delete(_current.clamp(0, _pages.length - 1)),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 112,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                itemCount: _pages.length,
                onReorder: _reorder,
                footer: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _AddTile(onTap: _addPages),
                ),
                itemBuilder: (context, index) => Padding(
                  key: ValueKey(_pages[index].page.id),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _Thumbnail(
                    entry: _pages[index],
                    number: index + 1,
                    selected: index == _current,
                    onTap: () => _jumpTo(index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PagePreview extends StatelessWidget {
  final _ReviewPage entry;

  const _PagePreview({required this.entry});

  @override
  Widget build(BuildContext context) {
    final path = entry.page.processedImagePath;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path != null)
            InteractiveViewer(maxScale: 4, child: PageImage(path: path))
          else if (entry.error == null)
            PageImage(path: entry.page.rawImagePath, cacheWidth: 900),
          if (entry.error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(entry.error!, textAlign: TextAlign.center),
              ),
            ),
          if (entry.busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Cropping and enhancing…', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PageAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 2),
            FittedBox(child: Text(label, maxLines: 1)),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final _ReviewPage entry;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  const _Thumbnail({required this.entry, required this.number, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final path = entry.page.processedImagePath ?? entry.page.rawImagePath;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? primary : theme.colorScheme.outlineVariant, width: selected ? 2.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageImage(path: path, fit: BoxFit.cover, cacheWidth: 160),
            if (entry.busy) const ColoredBox(color: Color(0x66000000), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
            if (entry.error != null) const ColoredBox(color: Color(0x99000000), child: Icon(Icons.error_outline, color: Colors.orangeAccent)),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
                child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 66,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: theme.colorScheme.primary),
            FittedBox(child: Text('Add', style: TextStyle(color: theme.colorScheme.primary))),
          ],
        ),
      ),
    );
  }
}
