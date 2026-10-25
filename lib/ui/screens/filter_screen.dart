import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/cv/filter_engine.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
import '../../core/ai/gemma_local_service.dart';
import 'document_detail_screen.dart';

class FilterScreen extends StatefulWidget {
  final ScannedPage page;
  final img.Image warpedImage;
  final ScannedDocument? parentDocument;

  const FilterScreen({
    super.key,
    required this.page,
    required this.warpedImage,
    this.parentDocument,
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late img.Image _currentImage;
  ScanFilterType _selectedFilter = ScanFilterType.magicColor;
  bool _isProcessing = false;
  Uint8List? _previewBytes;
  final Map<ScanFilterType, Uint8List> _filterCache = {};

  @override
  void initState() {
    super.initState();
    _currentImage = widget.warpedImage;
    _applyFilter(_selectedFilter);
  }

  Future<void> _applyFilter(ScanFilterType filter) async {
    setState(() {
      _selectedFilter = filter;
      _isProcessing = true;
    });

    if (_filterCache.containsKey(filter)) {
      setState(() {
        _previewBytes = _filterCache[filter];
        _isProcessing = false;
      });
      return;
    }

    // Process filter
    final filtered = DocumentFilterEngine.applyFilter(_currentImage, filter);
    final bytes = Uint8List.fromList(img.encodeJpg(filtered, quality: 90));
    _filterCache[filter] = bytes;

    if (mounted) {
      setState(() {
        _previewBytes = bytes;
        _isProcessing = false;
      });
    }
  }

  void _rotateImage() {
    setState(() => _isProcessing = true);
    _currentImage = img.copyRotate(_currentImage, angle: 90);
    _filterCache.clear();
    _applyFilter(_selectedFilter);
  }

  Future<void> _saveAndFinish() async {
    setState(() => _isProcessing = true);

    final filtered = DocumentFilterEngine.applyFilter(_currentImage, _selectedFilter);
    final processedPath = await DocumentRepository.instance.saveProcessedPageImage(
      filtered,
      widget.page.id,
    );

    final updatedPage = widget.page.copyWith(
      processedImagePath: processedPath,
      filterType: _selectedFilter,
    );

    // Save into document
    ScannedDocument doc;
    if (widget.parentDocument != null) {
      final existingPages = List<ScannedPage>.from(widget.parentDocument!.pages);
      final pageIndex = existingPages.indexWhere((p) => p.id == updatedPage.id);
      if (pageIndex >= 0) {
        existingPages[pageIndex] = updatedPage;
      } else {
        existingPages.add(updatedPage);
      }
      doc = widget.parentDocument!.copyWith(pages: existingPages);
    } else {
      doc = ScannedDocument(
        title: 'Scan_${DateTime.now().month}_${DateTime.now().day}_${DateTime.now().hour}${DateTime.now().minute}',
        pages: [updatedPage],
      );
    }

    await DocumentRepository.instance.saveDocument(doc);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => DocumentDetailScreen(document: doc),
        ),
        (route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Enhance Scan'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right),
            tooltip: 'Rotate 90°',
            onPressed: _isProcessing ? null : _rotateImage,
          ),
          TextButton.icon(
            onPressed: _isProcessing ? null : _saveAndFinish,
            icon: const Icon(Icons.check, color: const Color(0xFF00E5FF)),
            label: const Text('Save', style: TextStyle(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _previewBytes != null
                  ? Image.memory(
                      _previewBytes!,
                      fit: BoxFit.contain,
                    )
                  : const CircularProgressIndicator(color: const Color(0xFF00E5FF)),
            ),
          ),
          if (_isProcessing)
            const LinearProgressIndicator(color: const Color(0xFF00E5FF), backgroundColor: Colors.transparent),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: const Color(0xFF131B2E),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildFilterOption(ScanFilterType.magicColor, 'Magic Color', Icons.auto_awesome),
                  _buildFilterOption(ScanFilterType.sharpBW, 'Sharp B&W', Icons.contrast),
                  _buildFilterOption(ScanFilterType.grayscale, 'Grayscale', Icons.filter_b_and_w),
                  _buildFilterOption(ScanFilterType.lighten, 'Lighten', Icons.wb_sunny_outlined),
                  _buildFilterOption(ScanFilterType.original, 'Original', Icons.image),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(ScanFilterType filter, String label, IconData icon) {
    final bool isSelected = _selectedFilter == filter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: InkWell(
        onTap: () => _applyFilter(filter),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0066FF).withOpacity(0.25) : Colors.black45,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white24,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF00E5FF) : Colors.white70, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

