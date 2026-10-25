import 'dart:io';
import 'package:flutter/material.dart';

/// A page image from disk. [cacheWidth] keeps thumbnails from decoding 3000px pages.
class PageImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  const PageImage({super.key, required this.path, this.fit = BoxFit.contain, this.cacheWidth});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(child: Icon(Icons.broken_image_outlined, color: scheme.onSurface.withValues(alpha: 0.35))),
      ),
    );
  }
}
