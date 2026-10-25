import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import '../../main.dart';
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

  void _toggleTheme() {
    if (themeNotifier.value == ThemeMode.dark) {
      themeNotifier.value = ThemeMode.light;
    } else {
      themeNotifier.value = ThemeMode.dark;
    }
  }

  void _showAboutDialog() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Image.asset(
              'assets/images/clearscan_logo.png',
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => Icon(Icons.document_scanner, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ClearScan',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  'LOCAL AI SCANNER',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Text(
          'Version 1.1.0\n\n'
          '• 100% On-Device Processing\n'
          '• Zero Third-Party Cloud APIs\n'
          '• Local Gemma Intelligence & OCR\n'
          '• Background Isolate Acceleration (Zero ANR)\n'
          '• Adaptive Homography Dewarping\n'
          '• Signature Magic Color Filter\n'
          '• Light & Dark Theme Support\n'
          '• Searchable Multi-Page PDF Export',
          style: TextStyle(fontSize: 13, height: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
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
                errorBuilder: (_, __, ___) => Icon(Icons.document_scanner, color: primaryColor),
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
                color: primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primaryColor.withOpacity(0.4)),
              ),
              child: Text(
                'LOCAL AI',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: primaryColor, letterSpacing: 0.8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: _toggleTheme,
          ),
          IconButton(
            icon: Icon(Icons.info_outline, color: theme.colorScheme.onSurface.withOpacity(0.8)),
            tooltip: 'About ClearScan',
            onPressed: _showAboutDialog,
          ),
          IconButton(
            icon: Icon(Icons.file_upload_outlined, color: theme.colorScheme.onSurface.withOpacity(0.8)),
            tooltip: 'Import Image',
            onPressed: _importDocument,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : LayoutBuilder(
              builder: (context, constraints) {
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
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search documents, invoices, receipts...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.4),
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(Icons.search, color: primaryColor, size: 20),
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
                              selectedColor: primaryColor.withOpacity(isDark ? 0.25 : 0.15),
                              checkmarkColor: primaryColor,
                              backgroundColor: theme.colorScheme.surface,
                              side: BorderSide(
                                color: isSelected ? primaryColor : theme.colorScheme.outlineVariant,
                              ),
                              labelStyle: TextStyle(
                                color: isSelected ? primaryColor : theme.colorScheme.onSurface.withOpacity(0.75),
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
                          ? _buildEmptyState(theme, primaryColor)
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
                                return _buildDocumentCard(doc, theme, primaryColor, isDark);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
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

  Widget _buildEmptyState(ThemeData theme, Color primaryColor) {
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
                    primaryColor.withOpacity(0.18),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Image.asset(
                'assets/images/clearscan_full.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.document_scanner, size: 72, color: primaryColor),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                '100% On-Device Document Intelligence. Your scans, OCR, and Gemma AI insights never leave your phone memory.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                  fontSize: 13,
                  height: 1.45,
                ),
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
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor),
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
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(Icons.photo_library_outlined, size: 18, color: primaryColor),
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

  Widget _buildDocumentCard(ScannedDocument doc, ThemeData theme, Color primaryColor, bool isDark) {
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
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
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
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          child: Center(
                            child: Icon(
                              Icons.description_outlined,
                              size: 42,
                              color: theme.colorScheme.onSurface.withOpacity(0.3),
                            ),
                          ),
                        ),
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
                          Icon(Icons.layers_outlined, size: 11, color: primaryColor),
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
              color: theme.colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.psychology, size: 12, color: primaryColor),
                          const SizedBox(width: 3),
                          Text(
                            'Gemma AI',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
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
