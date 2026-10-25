import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import 'camera_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final docs = _filteredDocuments;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.document_scanner, color: Colors.tealAccent),
            SizedBox(width: 10),
            Text('CamScanner Local AI'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),

                // Tags Filter
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
                          selectedColor: Colors.teal.withOpacity(0.3),
                          checkmarkColor: Colors.tealAccent,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.tealAccent : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (_) => setState(() => _selectedTag = tag),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Document Grid / List
                Expanded(
                  child: docs.isEmpty
                      ? _buildEmptyState()
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            return _buildDocumentCard(doc);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.camera_alt),
        label: const Text('New Scan', style: TextStyle(fontWeight: FontWeight.bold)),
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
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield, size: 64, color: Colors.tealAccent.withOpacity(0.6)),
            const SizedBox(height: 16),
            const Text(
              'Zero Cloud • 100% On-Device',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Your scans, OCR, and Gemma AI insights never leave your phone.\nTap "New Scan" to scan your first document.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(ScannedDocument doc) {
    final previewPath = doc.previewImagePath;
    final formattedDate = DateFormat('MMM d, yyyy • HH:mm').format(doc.createdAt);

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
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: previewPath != null && File(previewPath).existsSync()
                  ? Image.file(
                      File(previewPath),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.grey[850],
                      child: const Center(
                        child: Icon(Icons.description, size: 48, color: Colors.white24),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${doc.pageCount} ${doc.pageCount == 1 ? 'page' : 'pages'}',
                        style: const TextStyle(fontSize: 11, color: Colors.tealAccent),
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

