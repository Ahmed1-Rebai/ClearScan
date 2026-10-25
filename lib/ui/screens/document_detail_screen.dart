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
    final controller = TextEditingController(text: _doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Document', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Document Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF050C1A),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Document?'),
        content: const Text('This will permanently delete this document and all its scanned pages from local storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWideScreen = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: const Color(0xFF0B0F19),
          appBar: AppBar(
            backgroundColor: const Color(0xFF131B2E),
            title: InkWell(
              onTap: _renameDocument,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(_doc.title, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 15, color: Color(0xFF00E5FF)),
                  ],
                ),
              ),
            ),
            actions: [
              if (!isWideScreen)
                IconButton(
                  icon: const Icon(Icons.psychology, color: Color(0xFF00E5FF)),
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
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                    : const Icon(Icons.share_outlined, color: Colors.white70),
                tooltip: 'Export & Share PDF',
                onPressed: _isGeneratingPdf ? null : _exportPdf,
              ),
              PopupMenuButton<String>(
                iconColor: Colors.white70,
                color: const Color(0xFF131B2E),
                onSelected: (val) {
                  if (val == 'delete') _deleteDocument();
                  if (val == 'rename') _renameDocument();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete Document', style: TextStyle(color: Colors.redAccent))),
                ],
              ),
            ],
          ),
          body: _doc.pages.isEmpty
              ? const Center(child: Text('No pages in this document', style: TextStyle(color: Colors.white54)))
              : isWideScreen
                  ? _buildWideScreenLayout()
                  : _buildMobileLayout(),
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Top Page Counter & AI Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF131B2E),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page ${_currentPageIndex + 1} of ${_doc.pageCount}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
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
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 14),
                      SizedBox(width: 4),
                      Text('Gemma Intelligence', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
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
          color: const Color(0xFF131B2E),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextButton.icon(
                onPressed: _reCropCurrentPage,
                icon: const Icon(Icons.crop, color: Color(0xFF00E5FF)),
                label: const Text('Re-Crop', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
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
                label: const Text('Gemma AI'),
              ),
              TextButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF00E5FF)),
                label: const Text('Export PDF', style: TextStyle(color: Color(0xFF00E5FF))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWideScreenLayout() {
    return Row(
      children: [
        // Left: Interactive Document Preview
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFF0B0F19),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: const Color(0xFF131B2E),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page ${_currentPageIndex + 1} of ${_doc.pageCount}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00E5FF),
                              side: const BorderSide(color: Color(0xFF00E5FF)),
                            ),
                            onPressed: _reCropCurrentPage,
                            icon: const Icon(Icons.crop, size: 16),
                            label: const Text('Re-Crop Page'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E5FF),
                              foregroundColor: const Color(0xFF050C1A),
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
        Container(width: 1, color: const Color(0xFF1E293B)),

        // Right Pane: Integrated Gemma AI Insights
        Expanded(
          flex: 5,
          child: GemmaInsightsScreen(document: _doc),
        ),
      ],
    );
  }
}
