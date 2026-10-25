import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/analysis/text_normalizer.dart';
import '../../core/models/document.dart';
import '../../core/models/document_analysis.dart';
import '../../core/ocr/ocr_service.dart';
import '../../core/storage/app_settings.dart';
import '../../core/storage/document_repository.dart';
import '../gallery_import.dart';
import '../widgets/page_image.dart';
import 'camera_screen.dart';
import 'document_detail_screen.dart';
import 'scan_review_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _search = TextEditingController();
  DocumentType? _typeFilter;

  /// Ids of documents selected (by long-press) for deletion.
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ScannedDocument doc, List<String> queryTokens) {
    if (_typeFilter != null && doc.analysis?.documentType != _typeFilter) return false;
    if (queryTokens.isEmpty) return true;
    final haystack = TextNormalizer.fold('${doc.title}\n${doc.combinedText}');
    return queryTokens.every(haystack.contains);
  }

  Future<void> _scan() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()));
  }

  Future<void> _import() async {
    final paths = await importImagesFromGallery(context);
    if (!mounted || paths.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ScanReviewScreen(newRawPaths: paths)));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count document${count == 1 ? '' : 's'}?'),
        content: const Text('Their pages and recognized text will be permanently removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ids = _selected.toList();
    for (final id in ids) {
      await DocumentRepository.instance.deleteDocument(id);
    }
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${ids.length} document${ids.length == 1 ? '' : 's'}')));
  }

  void _showAbout() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/images/clearscan_logo.png',
              width: 36,
              height: 36,
              errorBuilder: (_, _, _) => Icon(Icons.document_scanner, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('ClearScan', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            'Version 1.2.0\n\n'
            '• Everything runs on this device: no cloud, no tracking\n'
            '• Automatic page detection, orientation and enhancement\n'
            '• Multi-page documents with reordering\n'
            '• On-device text recognition (OCR)\n'
            '• Field extraction that only reports what is printed\n'
            '• Searchable PDF export',
            style: TextStyle(height: 1.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final repo = DocumentRepository.instance;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel selection', onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Select all',
                    onPressed: () => setState(() => _selected.addAll(repo.documents.map((d) => d.id))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Delete selected',
                    onPressed: _deleteSelected,
                  ),
                ],
              )
            : AppBar(
                titleSpacing: 16,
                title: const _AppTitle(),
                actions: [
                  PopupMenuButton<ThemeMode>(
                    icon: Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
                    tooltip: 'Theme',
                    onSelected: AppSettings.setThemeMode,
                    itemBuilder: (context) => [
                      for (final (mode, label) in const [
                        (ThemeMode.system, 'System default'),
                        (ThemeMode.light, 'Light'),
                        (ThemeMode.dark, 'Dark'),
                      ])
                        CheckedPopupMenuItem(value: mode, checked: AppSettings.themeMode.value == mode, child: Text(label)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.add_photo_alternate_outlined), tooltip: 'Import images', onPressed: _import),
                  IconButton(icon: const Icon(Icons.info_outline), tooltip: 'About ClearScan', onPressed: _showAbout),
                ],
              ),
        body: ListenableBuilder(
          listenable: Listenable.merge([repo, OcrService.instance.progress]),
          builder: (context, _) {
            final all = repo.documents;
            final types = {for (final d in all) ?d.analysis?.documentType}.toList()..sort((a, b) => a.index.compareTo(b.index));
            if (_typeFilter != null && !types.contains(_typeFilter)) _typeFilter = null;
            final queryTokens = TextNormalizer.fold(_search.text).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
            final docs = all.where((d) => _matches(d, queryTokens)).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search titles and scanned text…',
                      prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                if (types.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      children: [
                        _TypeChip(label: 'All', selected: _typeFilter == null, onTap: () => setState(() => _typeFilter = null)),
                        for (final type in types)
                          _TypeChip(
                            label: type.displayName,
                            selected: _typeFilter == type,
                            onTap: () => setState(() => _typeFilter = type),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: all.isEmpty
                      ? _EmptyState(onScan: _scan, onImport: _import)
                      : docs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No documents match your search.', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            // Card height grows with the user's text size so the footer never overflows.
                            mainAxisExtent: 168 + MediaQuery.textScalerOf(context).scale(44),
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            return _DocumentCard(
                              document: doc,
                              selected: _selected.contains(doc.id),
                              onLongPress: () => _toggleSelection(doc.id),
                              onTap: _selecting
                                  ? () => _toggleSelection(doc.id)
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: doc.id)),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _scan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }
}

/// Logo, name and badge; scales down instead of overflowing on narrow screens.
class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/clearscan_icon.png',
              width: 30,
              height: 30,
              errorBuilder: (_, _, _) => Icon(Icons.document_scanner, color: primary),
            ),
          ),
          const SizedBox(width: 10),
          const Text('ClearScan'),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: primary.withValues(alpha: 0.4)),
            ),
            child: Text(
              'LOCAL AI',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: primary, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final ScannedDocument document;
  final VoidCallback onTap;

  final bool selected;
  final VoidCallback onLongPress;

  const _DocumentCard({required this.document, required this.onTap, required this.selected, required this.onLongPress});

  String _status() {
    if (OcrService.instance.progress.value.containsKey(document.id)) return 'Recognizing text…';
    final analysis = document.analysis;
    if (analysis != null) return analysis.documentType.displayName;
    if (!document.isFullyRecognized) return OcrService.instance.isAvailable ? 'Text pending' : 'Not recognized';
    return document.combinedText.isEmpty ? 'No text found' : 'Document';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = document.previewImagePath;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.primary, width: 3),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preview != null)
                    PageImage(path: preview, fit: BoxFit.cover, cacheWidth: 440)
                  else
                    ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.description_outlined, color: muted),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_outlined, size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(
                            '${document.pageCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 28, semanticLabel: 'Selected'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _status(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          DateFormat('d MMM').format(document.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onImport;

  const _EmptyState({required this.onScan, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
              child: Image.asset(
                'assets/images/clearscan_full.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(Icons.document_scanner, size: 72, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Scan documents, extract their text and key fields — all on your phone. Nothing is uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.65), height: 1.45),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(onPressed: onScan, icon: const Icon(Icons.document_scanner_outlined), label: const Text('Scan pages')),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Import images'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
