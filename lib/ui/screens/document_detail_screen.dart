import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import '../../core/storage/pdf_service.dart';
import 'crop_screen.dart';
import 'gemma_insights_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  final ScannedDocument document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  late ScannedDocument _doc;
  int _currentPageIndex = 0;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
  }

  Future<void> _renameDocument() async {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final controller = TextEditingController(text: _doc.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Rename Document',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      final updated = _doc.copyWith(title: newTitle);
      await DocumentRepository.instance.saveDocument(updated);
      setState(() => _doc = updated);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      await PdfService.shareOrPrintPdf(_doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _reCropCurrentPage() async {
    if (_doc.pages.isEmpty) return;
    final page = _doc.pages[_currentPageIndex];

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CropScreen(
          page: page,
          parentDocument: _doc,
        ),
      ),
    );
  }

  Future<void> _deleteDocument() async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Document?',
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete this document and all its scanned pages from local storage.',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DocumentRepository.instance.deleteDocument(_doc.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWideScreen = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            title: InkWell(
              onTap: _renameDocument,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _doc.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit, size: 15, color: primaryColor),
                  ],
                ),
              ),
            ),
            actions: [
              if (!isWideScreen)
                IconButton(
                  icon: Icon(Icons.psychology, color: primaryColor),
                  tooltip: 'Gemma Local AI Insights',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GemmaInsightsScreen(document: _doc),
                      ),
                    );
                  },
                ),
              IconButton(
                icon: _isGeneratingPdf
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor))
                    : Icon(Icons.share_outlined, color: theme.colorScheme.onSurface.withOpacity(0.8)),
                tooltip: 'Export & Share PDF',
                onPressed: _isGeneratingPdf ? null : _exportPdf,
              ),
              PopupMenuButton<String>(
                iconColor: theme.colorScheme.onSurface.withOpacity(0.8),
                color: theme.colorScheme.surface,
                onSelected: (val) {
                  if (val == 'delete') _deleteDocument();
                  if (val == 'rename') _renameDocument();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename', style: TextStyle(color: theme.colorScheme.onSurface)),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Document', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
          body: _doc.pages.isEmpty
              ? Center(
                  child: Text(
                    'No pages in this document',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                )
              : isWideScreen
                  ? _buildWideScreenLayout(theme, primaryColor)
                  : _buildMobileLayout(theme, primaryColor),
        );
      },
    );
  }

  Widget _buildMobileLayout(ThemeData theme, Color primaryColor) {
    return Column(
      children: [
        // Top Page Counter & AI Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${_currentPageIndex + 1} of ${_doc.pageCount}',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GemmaInsightsScreen(document: _doc),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: primaryColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Gemma Intelligence',
                        style: TextStyle(color: primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main Page View (Interactive Viewer)
        Expanded(
          child: PageView.builder(
            itemCount: _doc.pageCount,
            onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
            itemBuilder: (context, index) {
              final page = _doc.pages[index];
              final imgPath = page.processedImagePath ?? page.rawImagePath;
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    File(imgPath),
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
        ),

        // Bottom Page Control Bar
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  onPressed: _reCropCurrentPage,
                  icon: Icon(Icons.crop, color: primaryColor),
                  label: Text('Re-Crop', style: TextStyle(color: primaryColor)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GemmaInsightsScreen(document: _doc),
                      ),
                    );
                  },
                  icon: const Icon(Icons.psychology, size: 18),
                  label: const Text('Gemma AI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: _exportPdf,
                  icon: Icon(Icons.picture_as_pdf_outlined, color: primaryColor),
                  label: Text('Export PDF', style: TextStyle(color: primaryColor)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideScreenLayout(ThemeData theme, Color primaryColor) {
    return Row(
      children: [
        // Left: Interactive Document Preview
        Expanded(
          flex: 6,
          child: Container(
            color: theme.scaffoldBackgroundColor,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page ${_currentPageIndex + 1} of ${_doc.pageCount}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor),
                            ),
                            onPressed: _reCropCurrentPage,
                            icon: const Icon(Icons.crop, size: 16),
                            label: const Text('Re-Crop Page'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: theme.colorScheme.onPrimary,
                            ),
                            onPressed: _exportPdf,
                            icon: const Icon(Icons.picture_as_pdf, size: 16),
                            label: const Text('Export PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    itemCount: _doc.pageCount,
                    onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
                    itemBuilder: (context, index) {
                      final page = _doc.pages[index];
                      final imgPath = page.processedImagePath ?? page.rawImagePath;
                      return InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Image.file(File(imgPath), fit: BoxFit.contain),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Vertical Divider
        Container(width: 1, color: theme.colorScheme.outlineVariant),

        // Right Pane: Integrated Gemma AI Insights
        Expanded(
          flex: 5,
          child: GemmaInsightsScreen(document: _doc),
        ),
      ],
    );
  }
}
