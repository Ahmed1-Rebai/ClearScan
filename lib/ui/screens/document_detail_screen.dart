import 'package:flutter/material.dart';
import '../../core/ocr/ocr_service.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import '../../core/storage/pdf_service.dart';
import '../widgets/page_image.dart';
import 'camera_screen.dart';
import 'insights_screen.dart';
import 'scan_review_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final PageController _pager = PageController();
  final DocumentRepository _repo = DocumentRepository.instance;
  int _current = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: starting OCR notifies listeners, which must not happen during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doc = _repo.byId(widget.documentId);
      if (doc == null) return;
      if (!doc.isFullyRecognized && OcrService.instance.isAvailable) {
        OcrService.instance.processDocument(doc.id);
      } else if (doc.isFullyRecognized && doc.analysis == null) {
        OcrService.instance.refreshAnalysis(doc.id);
      }
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    setState(() => _current = index);
    if (_pager.hasClients) _pager.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _rename(ScannedDocument doc) async {
    final controller = TextEditingController(text: doc.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.isNotEmpty) {
      await _repo.updateDocument(doc.id, (d) => d.copyWith(title: title));
    }
  }

  Future<void> _delete(ScannedDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${doc.title}" and its ${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'} will be permanently deleted from this device.'),
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
    await _repo.deleteDocument(doc.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _exportPdf(ScannedDocument doc) async {
    setState(() => _exporting = true);
    try {
      await PdfService.shareOrPrintPdf(doc);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export the PDF: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _editPages(ScannedDocument doc) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ScanReviewScreen(documentId: doc.id)));
  }

  void _addPages(ScannedDocument doc) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CameraScreen(targetDocumentId: doc.id)));
  }

  void _openInsights(ScannedDocument doc) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => InsightsScreen(documentId: doc.id)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, OcrService.instance.progress]),
      builder: (context, _) {
        final doc = _repo.byId(widget.documentId);
        if (doc == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('This document no longer exists.')));
        }
        if (doc.pages.isNotEmpty && _current >= doc.pages.length) _current = doc.pages.length - 1;

        return LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Scaffold(
            appBar: AppBar(
              title: InkWell(
                onTap: () => _rename(doc),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(doc.title, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 15, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Share PDF',
                  onPressed: _exporting || doc.pages.isEmpty ? null : () => _exportPdf(doc),
                  icon: _exporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share),
                ),
                IconButton(
                  tooltip: 'Delete document',
                  onPressed: () => _delete(doc),
                  icon: const Icon(Icons.delete_outline),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _rename(doc);
                      case 'ocr':
                        OcrService.instance.processDocument(doc.id, force: true);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (OcrService.instance.isAvailable) const PopupMenuItem(value: 'ocr', child: Text('Recognize text again')),
                  ],
                ),
              ],
            ),
            body: Column(
              children: [
                _OcrStatusBanner(document: doc),
                Expanded(
                  child: doc.pages.isEmpty
                      ? const Center(child: Text('This document has no pages.'))
                      : wide
                          ? Row(
                              children: [
                                Expanded(flex: 6, child: _buildPages(doc, showHeaderActions: true)),
                                const VerticalDivider(width: 1),
                                Expanded(flex: 5, child: InsightsScreen(documentId: doc.id, embedded: true)),
                              ],
                            )
                          : _buildPages(doc, showHeaderActions: false),
                ),
                if (!wide)
                  _ActionBar(
                    actions: [
                      _BarAction(Icons.edit_note, 'Edit pages', () => _editPages(doc)),
                      _BarAction(Icons.add_a_photo_outlined, 'Add pages', () => _addPages(doc)),
                      _BarAction(Icons.insights_outlined, 'Insights', () => _openInsights(doc)),
                      _BarAction(Icons.picture_as_pdf_outlined, 'PDF', _exporting ? null : () => _exportPdf(doc)),
                    ],
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildPages(ScannedDocument doc, {required bool showHeaderActions}) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Page ${_current + 1} of ${doc.pageCount}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
              if (showHeaderActions) ...[
                TextButton.icon(onPressed: () => _editPages(doc), icon: const Icon(Icons.edit_note), label: const Text('Edit pages')),
                TextButton.icon(onPressed: () => _addPages(doc), icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add pages')),
              ],
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pager,
            itemCount: doc.pageCount,
            onPageChanged: (index) => setState(() => _current = index),
            itemBuilder: (context, index) => InteractiveViewer(
              maxScale: 5,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: PageImage(path: doc.pages[index].displayImagePath),
              ),
            ),
          ),
        ),
        if (doc.pageCount > 1)
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: doc.pageCount,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final selected = index == _current;
                return GestureDetector(
                  onTap: () => _jumpTo(index),
                  child: Container(
                    width: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: PageImage(path: doc.pages[index].displayImagePath, fit: BoxFit.cover, cacheWidth: 120),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _OcrStatusBanner extends StatelessWidget {
  final ScannedDocument document;

  const _OcrStatusBanner({required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = OcrService.instance.progress.value[document.id];
    if (progress != null) {
      final total = progress.total == 0 ? 1 : progress.total;
      return Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recognizing text… page ${(progress.done + 1).clamp(1, total)} of $total',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.done / total),
            ],
          ),
        ),
      );
    }
    if (!OcrService.instance.isAvailable && !document.isFullyRecognized) {
      return Material(
        color: Colors.amber.withValues(alpha: 0.12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.amber),
              SizedBox(width: 10),
              Expanded(child: Text('Text recognition runs on Android and iOS devices.')),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _BarAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BarAction(this.icon, this.label, this.onTap);
}

/// Equal-width actions with scaled-down labels: never overflows, even at large text sizes.
class _ActionBar extends StatelessWidget {
  final List<_BarAction> actions;

  const _ActionBar({required this.actions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              for (final action in actions)
                Expanded(
                  child: TextButton(
                    onPressed: action.onTap,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(action.icon),
                        const SizedBox(height: 2),
                        FittedBox(child: Text(action.label, maxLines: 1)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
