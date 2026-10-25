import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/storage/document_repository.dart';

/// Lets the user pick one or more images and stores them as raw page photos.
/// Returns the stored paths (empty when cancelled). Unreadable files are skipped and reported.
Future<List<String>> importImagesFromGallery(BuildContext context) async {
  final List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(type: FileType.image);
  } catch (_) {
    if (context.mounted) _snack(context, 'Could not open the image picker.');
    return const [];
  }
  if (files.isEmpty || !context.mounted) return const [];

  final done = ValueNotifier<int>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<int>(
          valueListenable: done,
          builder: (context, value, _) => Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 16),
              Expanded(child: Text('Importing ${value + 1 > files.length ? files.length : value + 1} of ${files.length}…')),
            ],
          ),
        ),
      ),
    ),
  );

  final paths = <String>[];
  int failures = 0;
  for (final file in files) {
    try {
      paths.add(await DocumentRepository.instance.importImageBytes(await file.readAsBytes()));
    } catch (_) {
      failures++;
    }
    done.value++;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  done.dispose();
  if (failures > 0 && context.mounted) {
    _snack(context, 'Skipped $failures file${failures == 1 ? '' : 's'} that could not be read (use JPEG or PNG).');
  }
  return paths;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
