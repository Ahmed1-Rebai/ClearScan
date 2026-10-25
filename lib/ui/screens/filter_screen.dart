import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/cv/cv_isolate_service.dart';
import '../../core/cv/filter_engine.dart';
import '../../core/models/document.dart';
import '../../core/storage/document_repository.dart';
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

    // Process filter and JPEG encoding in a single background isolate call
    final bytes = await CvIsolateService.applyFilterAndEncodeAsync(_currentImage, filter);
    _filterCache[filter] = bytes;

    if (mounted) {
      setState(() {
        _previewBytes = bytes;
        _isProcessing = false;
      });
    }
  }

  Future<void> _rotateImage() async {
    setState(() => _isProcessing = true);
    final rotated = await CvIsolateService.rotateAsync(_currentImage, 90);
    _currentImage = rotated;
    _filterCache.clear();
    await _applyFilter(_selectedFilter);
  }

  Future<void> _saveAndFinish() async {
    setState(() => _isProcessing = true);

    // Apply selected filter to full-res image in background isolate
    final filtered = await CvIsolateService.applyFilterAsync(_currentImage, _selectedFilter);
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
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Enhance Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded),
            tooltip: 'Rotate 90°',
            onPressed: _isProcessing ? null : _rotateImage,
          ),
          TextButton.icon(
            onPressed: _isProcessing ? null : _saveAndFinish,
            icon: Icon(Icons.check, color: primaryColor),
            label: Text(
              'Save',
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
            ),
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
                  : CircularProgressIndicator(color: primaryColor),
            ),
          ),
          if (_isProcessing)
            LinearProgressIndicator(color: primaryColor, backgroundColor: Colors.transparent),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterOption(ScanFilterType.magicColor, 'Magic Color', Icons.auto_awesome, theme),
                    _buildFilterOption(ScanFilterType.sharpBW, 'Sharp B&W', Icons.contrast, theme),
                    _buildFilterOption(ScanFilterType.grayscale, 'Grayscale', Icons.filter_b_and_w, theme),
                    _buildFilterOption(ScanFilterType.lighten, 'Lighten', Icons.wb_sunny_outlined, theme),
                    _buildFilterOption(ScanFilterType.original, 'Original', Icons.image_outlined, theme),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(
    ScanFilterType filter,
    String label,
    IconData icon,
    ThemeData theme,
  ) {
    final bool isSelected = _selectedFilter == filter;
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: InkWell(
        onTap: _isProcessing ? null : () => _applyFilter(filter),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor.withOpacity(isDark ? 0.2 : 0.12)
                : (isDark ? Colors.black26 : Colors.black.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? primaryColor
                  : theme.colorScheme.outlineVariant.withOpacity(0.4),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? primaryColor
                    : theme.colorScheme.onSurface.withOpacity(0.7),
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? primaryColor
                      : theme.colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
