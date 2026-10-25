import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
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
        title: const Text('Rename Document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Document Title'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
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
        title: const Text('Delete Document?'),
        content: const Text('This will permanently delete this document and all its scanned pages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
    final currentPage = _doc.pages.isNotEmpty ? _doc.pages[_currentPageIndex] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: InkWell(
          onTap: _renameDocument,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(_doc.title, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 16, color: Colors.tealAccent),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology, color: Colors.tealAccent),
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf),
            tooltip: 'Export Searchable PDF',
            onPressed: _isGeneratingPdf ? null : _exportPdf,
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'delete') _deleteDocument();
              if (val == 'rename') _renameDocument();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete Document', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: _doc.pages.isEmpty
          ? const Center(child: Text('No pages in this document', style: TextStyle(color: Colors.white54)))
          : Column(
              children: [
                // Top Page Counter & AI Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.grey[900],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Page ${_currentPageIndex + 1} of ${_doc.pageCount}',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
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
                            color: Colors.teal.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, color: Colors.tealAccent, size: 14),
                              SizedBox(width: 4),
                              Text('Gemma Intelligence', style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
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
                  color: Colors.grey[900],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton.icon(
                        onPressed: _reCropCurrentPage,
                        icon: const Icon(Icons.crop, color: Colors.tealAccent),
                        label: const Text('Re-Crop', style: TextStyle(color: Colors.tealAccent)),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
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
                        icon: const Icon(Icons.psychology),
                        label: const Text('Gemma AI'),
                      ),
                      TextButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(Icons.share, color: Colors.tealAccent),
                        label: const Text('Share PDF', style: TextStyle(color: Colors.tealAccent)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

