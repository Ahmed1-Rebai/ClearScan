import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  String _selectedTag = 'All';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    await DocumentRepository.instance.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  List<ScannedDocument> get _filteredDocuments {
    final docs = DocumentRepository.instance.documents;
    return docs.where((doc) {
      final matchesSearch = doc.title.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTag = _selectedTag == 'All' || doc.tags.contains(_selectedTag);
      return matchesSearch && matchesTag;
    }).toList();
  }

  Future<void> _importDocument() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isNotEmpty && files.first.path != null) {
      final bytes = await File(files.first.path!).readAsBytes();
      final rawPath = await DocumentRepository.instance.saveRawPageImage(bytes);
      final page = ScannedPage(rawImagePath: rawPath);

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CropScreen(page: page)),
        );
        setState(() {});
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Image.asset(
              'assets/images/clearscan_logo.png',
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => const Icon(Icons.document_scanner, color: Color(0xFF00E5FF)),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ClearScan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                Text('LOCAL AI SCANNER', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0 (Release)\n\n'
              '• 100% On-Device Processing\n'
              '• Zero Third-Party Cloud APIs\n'
              '• Local Gemma Intelligence & OCR\n'
              '• Adaptive Homography Dewarping\n'
              '• Signature Magic Color Filter\n'
              '• Searchable Multi-Page PDF Export',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filteredDocuments;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/clearscan_icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.document_scanner, color: Color(0xFF00E5FF)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'ClearScan',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.3),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: const Text(
                'LOCAL AI',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF00E5FF), letterSpacing: 0.8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            tooltip: 'About ClearScan',
            onPressed: _showAboutDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, color: Colors.white70),
            tooltip: 'Import Image',
            onPressed: _importDocument,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : LayoutBuilder(
              builder: (context, constraints) {
                // Responsive Grid Configuration
                final double width = constraints.maxWidth;
                int crossAxisCount = 2;
                double childAspectRatio = 0.72;

                if (width >= 1200) {
                  crossAxisCount = 5;
                  childAspectRatio = 0.75;
                } else if (width >= 900) {
                  crossAxisCount = 4;
                  childAspectRatio = 0.75;
                } else if (width >= 600) {
                  crossAxisCount = 3;
                  childAspectRatio = 0.74;
                } else if (width < 380) {
                  crossAxisCount = 1;
                  childAspectRatio = 1.35;
                }

                return Column(
                  children: [
                    // Search Bar & Filter Tags
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search documents, invoices, receipts...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),

                    // Filter Tags Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: ['All', 'Invoices', 'Receipts', 'Contracts', 'Notes', 'IDs'].map((tag) {
                          final isSelected = _selectedTag == tag;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(tag),
                              selected: isSelected,
                              selectedColor: const Color(0xFF0066FF).withOpacity(0.3),
                              checkmarkColor: const Color(0xFF00E5FF),
                              backgroundColor: const Color(0xFF131B2E),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                              ),
                              labelStyle: TextStyle(
                                color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              onSelected: (_) => setState(() => _selectedTag = tag),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Document Grid / Empty State
                    Expanded(
                      child: docs.isEmpty
                          ? _buildEmptyState()
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: childAspectRatio,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                return _buildDocumentCard(doc);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: const Color(0xFF050C1A),
        elevation: 4,
        icon: const Icon(Icons.camera_alt_rounded, size: 22),
        label: const Text(
          'Scan Document',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.2),
        ),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CameraScreen()),
          );
          setState(() {});
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Image.asset(
                'assets/images/clearscan_full.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.document_scanner, size: 72, color: Color(0xFF00E5FF)),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                '100% On-Device Document Intelligence. Your scans, OCR, and Gemma AI insights never leave your phone memory.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.45),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Start Camera Scan', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CameraScreen()),
                    );
                    setState(() {});
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF131B2E),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF1E293B)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.photo_library_outlined, size: 18, color: Color(0xFF38BDF8)),
                  label: const Text('Import Image', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _importDocument,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(ScannedDocument doc) {
    final previewPath = doc.previewImagePath;
    final formattedDate = DateFormat('MMM d • HH:mm').format(doc.createdAt);

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => DocumentDetailScreen(document: doc)),
        );
        setState(() {});
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E293B)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail Preview Container
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  previewPath != null && File(previewPath).existsSync()
                      ? Image.file(
                          File(previewPath),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: const Color(0xFF0F172A),
                          child: const Center(
                            child: Icon(Icons.description_outlined, size: 42, color: Colors.white24),
                          ),
                        ),
                  // Top Gradient & Page Count Pill
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_outlined, size: 11, color: Color(0xFF00E5FF)),
                          const SizedBox(width: 3),
                          Text(
                            '${doc.pageCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Bottom Metadata
            Container(
              padding: const EdgeInsets.all(10.0),
              color: const Color(0xFF131B2E),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.psychology, size: 12, color: Color(0xFF00E5FF)),
                          const SizedBox(width: 3),
                          Text(
                            'Gemma AI',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF).withOpacity(0.9)),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
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
