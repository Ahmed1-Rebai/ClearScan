import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/cv/cv_isolate_service.dart';
import '../../core/models/document.dart';

/// Live preview of enhancement filters on a page. Pops with the chosen [ScanFilterType].
///
/// Previews are rendered at reduced resolution for speed; the final page is
/// re-rendered at full resolution by the caller.
class FilterScreen extends StatefulWidget {
  final ScannedPage page;

  const FilterScreen({super.key, required this.page});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  static const _filters = [
    (ScanFilterType.magicColor, 'Magic Color', Icons.auto_awesome),
    (ScanFilterType.sharpBW, 'B&W', Icons.contrast),
    (ScanFilterType.grayscale, 'Grayscale', Icons.filter_b_and_w),
    (ScanFilterType.lighten, 'Lighten', Icons.wb_sunny_outlined),
    (ScanFilterType.original, 'Original', Icons.image_outlined),
  ];

  img.Image? _base;
  final Map<ScanFilterType, Uint8List> _previews = {};
  late ScanFilterType _selected = widget.page.filterType;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _base = await CvIsolateService.renderPreviewBaseAsync(
        rawPath: widget.page.rawImagePath,
        corners: widget.page.corners,
        rotation: widget.page.rotationDegrees,
      );
      await _select(_selected);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not render the page preview.');
    }
  }

  Future<void> _select(ScanFilterType filter) async {
    setState(() {
      _selected = filter;
      _busy = !_previews.containsKey(filter);
    });
    if (_previews.containsKey(filter) || _base == null) return;
    final bytes = await CvIsolateService.applyFilterAndEncodeAsync(_base!, filter, quality: 85);
    if (!mounted) return;
    setState(() {
      _previews[filter] = bytes;
      if (_selected == filter) _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final preview = _previews[_selected];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhance'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: const Icon(Icons.check),
            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _error != null
                    ? Text(_error!)
                    : preview != null
                        ? Image.memory(preview, fit: BoxFit.contain, gaplessPlayback: true)
                        : CircularProgressIndicator(color: primary),
              ),
            ),
          ),
          SizedBox(height: 3, child: _busy ? LinearProgressIndicator(color: primary) : null),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Row(
                  children: [
                    for (final (filter, label, icon) in _filters)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _FilterChoice(
                          label: label,
                          icon: icon,
                          selected: filter == _selected,
                          onTap: _base == null ? null : () => _select(filter),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _FilterChoice({required this.label, required this.icon, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final fg = selected ? primary : theme.colorScheme.onSurface.withValues(alpha: 0.8);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.14) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? primary : theme.colorScheme.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
