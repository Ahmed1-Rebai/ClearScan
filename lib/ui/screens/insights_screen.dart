import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/analysis/document_qa.dart';
import '../../core/models/document.dart';
import '../../core/models/document_analysis.dart';
import '../../core/ocr/ocr_service.dart';
import '../../core/storage/document_repository.dart';

/// Extracted fields, Q&A and recognized text for a document.
/// [embedded] hides the back button when shown as a side panel.
class InsightsScreen extends StatefulWidget {
  final String documentId;
  final bool embedded;

  const InsightsScreen({super.key, required this.documentId, this.embedded = false});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _ChatMessage {
  final bool fromUser;
  final String text;

  const _ChatMessage(this.fromUser, this.text);
}

class _InsightsScreenState extends State<InsightsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final TextEditingController _question = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  final List<_ChatMessage> _chat = [];
  bool _analysisRequested = false;

  @override
  void dispose() {
    _tabs.dispose();
    _question.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _ask(ScannedDocument doc) {
    final question = _question.text.trim();
    if (question.isEmpty) return;
    _question.clear();
    final reply = DocumentQa.answer(question: question, documentText: doc.combinedText, analysis: doc.analysis);
    setState(() {
      _chat.add(_ChatMessage(true, question));
      _chat.add(_ChatMessage(false, reply));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final repo = DocumentRepository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([repo, OcrService.instance.progress]),
      builder: (context, _) {
        final doc = repo.byId(widget.documentId);
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Document insights', overflow: TextOverflow.ellipsis),
                Text(
                  'On-device · nothing leaves your phone',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(icon: Icon(Icons.fact_check_outlined), text: 'Overview'),
                Tab(icon: Icon(Icons.question_answer_outlined), text: 'Ask'),
                Tab(icon: Icon(Icons.notes), text: 'Text'),
              ],
            ),
          ),
          body: doc == null
              ? const Center(child: Text('This document no longer exists.'))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildOverview(doc, theme),
                    _buildChat(doc, theme),
                    _buildText(doc, theme),
                  ],
                ),
        );
      },
    );
  }

  /// Shown instead of results while OCR is pending, running or unavailable.
  Widget? _statusView(ScannedDocument doc, ThemeData theme) {
    final progress = OcrService.instance.progress.value[doc.id];
    if (progress != null || (OcrService.instance.isRunning(doc.id) && !doc.isFullyRecognized)) {
      final total = progress?.total ?? doc.pageCount;
      final done = progress?.done ?? 0;
      return _Message(
        icon: Icons.document_scanner_outlined,
        title: 'Recognizing text…',
        body: 'Page ${(done + 1).clamp(1, total == 0 ? 1 : total)} of $total. This runs entirely on your device.',
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: LinearProgressIndicator(value: total == 0 ? null : done / total),
        ),
      );
    }
    if (!doc.isFullyRecognized) {
      if (!OcrService.instance.isAvailable) {
        return const _Message(
          icon: Icons.phonelink_erase_outlined,
          title: 'Text recognition unavailable',
          body: 'On-device OCR runs on Android and iOS. Open this document on your phone to extract its text.',
        );
      }
      return _Message(
        icon: Icons.text_snippet_outlined,
        title: 'Text not recognized yet',
        body: 'Run text recognition to extract fields and search this document.',
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FilledButton.icon(
            onPressed: () => OcrService.instance.processDocument(doc.id),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Recognize text'),
          ),
        ),
      );
    }
    if (doc.combinedText.trim().isEmpty) {
      return _Message(
        icon: Icons.search_off,
        title: 'No text found',
        body: 'No readable text was found on these pages. Re-crop them tightly, use better light, or try the B&W filter.',
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: OutlinedButton.icon(
            onPressed: () => OcrService.instance.processDocument(doc.id, force: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildOverview(ScannedDocument doc, ThemeData theme) {
    final status = _statusView(doc, theme);
    if (status != null) return status;
    final analysis = doc.analysis;
    if (analysis == null) {
      if (!_analysisRequested) {
        _analysisRequested = true;
        // Not during build: refreshing notifies listeners.
        WidgetsBinding.instance.addPostFrameCallback((_) => OcrService.instance.refreshAnalysis(doc.id));
      }
      return const Center(child: CircularProgressIndicator());
    }
    _analysisRequested = false;
    final primary = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(icon: Icons.category_outlined, label: analysis.documentType.displayName, color: primary),
                    if (analysis.language != null) _Pill(icon: Icons.translate, label: analysis.language!, color: theme.colorScheme.tertiary),
                    _Pill(icon: Icons.layers_outlined, label: '${doc.pageCount} page${doc.pageCount == 1 ? '' : 's'}', color: theme.colorScheme.secondary),
                  ],
                ),
                const SizedBox(height: 12),
                Text(analysis.summary, style: theme.textTheme.bodyLarge),
                if (analysis.suggestedAction != null) ...[
                  const SizedBox(height: 12),
                  _Callout(icon: Icons.task_alt, text: analysis.suggestedAction!, color: Colors.amber.shade700),
                ],
                for (final warning in analysis.warnings) ...[
                  const SizedBox(height: 8),
                  _Callout(icon: Icons.warning_amber_rounded, text: warning, color: Colors.deepOrange),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle('Extracted fields', trailing: '${analysis.extractedFields.length}'),
        const SizedBox(height: 8),
        if (analysis.extractedFields.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No labeled fields (totals, dates, references…) were found. Only values printed next to a clear label are extracted, so nothing is guessed.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < analysis.extractedFields.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FieldRow(field: analysis.extractedFields[i], onCopy: (f) => _copy(f.value, f.key)),
                ],
              ],
            ),
          ),
        if (analysis.lineItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle('Line items', trailing: '${analysis.lineItems.length}'),
          const SizedBox(height: 8),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Qty'), numeric: true),
                  DataColumn(label: Text('Unit'), numeric: true),
                  DataColumn(label: Text('Total'), numeric: true),
                ],
                rows: [
                  for (final item in analysis.lineItems)
                    DataRow(cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(item.description, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text('${item.quantity}')),
                      DataCell(Text(item.unitPrice)),
                      DataCell(Text(item.totalPrice, style: const TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                ],
              ),
            ),
          ),
        ],
        if (analysis.keyPoints.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Sections & highlights'),
          const SizedBox(height: 8),
          for (final point in analysis.keyPoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chevron_right, color: primary, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(point)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          'Extracted by: ${analysis.modelName} · OCR: ${OcrService.instance.engine.name}',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildChat(ScannedDocument doc, ThemeData theme) {
    final status = _statusView(doc, theme);
    if (status != null) return status;
    final primary = theme.colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: _chat.isEmpty
              ? const _Message(
                  icon: Icons.question_answer_outlined,
                  title: 'Ask about this document',
                  body: 'Try "What is the total?", "When is it due?" or any word from the text. Answers quote the document and never guess.',
                )
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _chat.length,
                  itemBuilder: (context, index) {
                    final message = _chat[index];
                    return Align(
                      alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: message.fromUser ? primary : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SelectableText(
                            message.text,
                            style: TextStyle(color: message.fromUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _question,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(doc),
                      decoration: InputDecoration(
                        hintText: 'Ask about this document…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(onPressed: () => _ask(doc), icon: const Icon(Icons.send), tooltip: 'Ask'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildText(ScannedDocument doc, ThemeData theme) {
    final status = _statusView(doc, theme);
    if (status != null) return status;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45, color: theme.colorScheme.onSurface.withValues(alpha: 0.9));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Recognized text', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            TextButton.icon(
              onPressed: () => _copy(doc.combinedText, 'Text'),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy all'),
            ),
          ],
        ),
        for (int i = 0; i < doc.pages.length; i++) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Page ${i + 1}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              if (doc.pages[i].ocrConfidence != null)
                Text(
                  'confidence ${(doc.pages[i].ocrConfidence! * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SelectableText(
              (doc.pages[i].ocrText ?? '').trim().isEmpty ? '(no text found on this page)' : doc.pages[i].ocrText!,
              style: mono,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: OcrService.instance.isAvailable ? () => OcrService.instance.processDocument(doc.id, force: true) : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Recognize again'),
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  final ExtractedField field;
  final void Function(ExtractedField) onCopy;

  const _FieldRow({required this.field, required this.onCopy});

  IconData get _icon {
    switch (field.category) {
      case 'financial':
        return Icons.payments_outlined;
      case 'date':
        return Icons.event_outlined;
      case 'identity':
        return Icons.badge_outlined;
      case 'contact':
        return Icons.contact_mail_outlined;
      default:
        return Icons.label_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final showEvidence = field.evidence != null && field.evidence!.trim() != field.value.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(_icon, color: theme.colorScheme.primary, size: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.key, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                const SizedBox(height: 2),
                Text(field.value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (showEvidence) ...[
                  const SizedBox(height: 4),
                  Text(
                    'from: "${field.evidence}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, size: 18, color: muted),
            tooltip: 'Copy',
            onPressed: () => onCopy(field),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Callout({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        ),
        if (trailing != null) Text(trailing!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  const _Message({required this.icon, required this.title, required this.body, this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              ?child,
            ],
          ),
        ),
      ),
    );
  }
}
