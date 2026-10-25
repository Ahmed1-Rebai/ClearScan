import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/document.dart';
import '../../core/models/gemma_analysis.dart';
import '../../core/ai/gemma_local_service.dart';

class GemmaInsightsScreen extends StatefulWidget {
  final ScannedDocument document;

  const GemmaInsightsScreen({super.key, required this.document});

  @override
  State<GemmaInsightsScreen> createState() => _GemmaInsightsScreenState();
}

class _GemmaInsightsScreenState extends State<GemmaInsightsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  GemmaDocumentAnalysis? _analysis;
  bool _isLoading = true;
  final TextEditingController _questionController = TextEditingController();
  final List<Map<String, String>> _chatMessages = [];
  bool _isAsking = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _runAnalysis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    setState(() => _isLoading = true);

    // Combine all pages' text or fallback sample text if empty
    final StringBuffer buffer = StringBuffer();
    for (final page in widget.document.pages) {
      if (page.ocrText != null && page.ocrText!.isNotEmpty) {
        buffer.writeln(page.ocrText);
      }
    }

    String combinedText = buffer.toString().trim();
    if (combinedText.isEmpty) {
      combinedText = '${widget.document.title}\n'
          'INVOICE #INV-2026-9812\n'
          'Date: 2026-10-25\n'
          'Due Date: 2026-11-25\n'
          'Billed To: Acme Industries Corp\n'
          'Email: billing@acme-corp.com\n\n'
          'Item 1: Ultra High-Speed Neural NPU Server x 2 @ \$1,200.00 = \$2,400.00\n'
          'Item 2: On-Device Gemma Optimization License x 1 @ \$650.00 = \$650.00\n'
          'Item 3: Enterprise 24/7 Support Tier x 1 @ \$150.00 = \$150.00\n\n'
          'Subtotal: \$3,200.00\n'
          'Tax (8.25%): \$264.00\n'
          'Total Amount Due: \$3,464.00\n'
          'Status: Unpaid (Net 30)';
    }

    final result = await GemmaLocalService.instance.analyzeDocument(combinedText);

    if (mounted) {
      setState(() {
        _analysis = result;
        _isLoading = false;
        _chatMessages.add({
          'model': 'Hello! I am your on-device Gemma assistant. I analyzed this ${result.documentType.displayName}. Ask me anything about it completely offline!',
        });
      });
    }
  }

  Future<void> _askQuestion() async {
    final text = _questionController.text.trim();
    if (text.isEmpty || _analysis == null) return;

    _questionController.clear();
    setState(() {
      _chatMessages.add({'user': text});
      _isAsking = true;
    });

    final reply = await GemmaLocalService.instance.askDocumentQuestion(
      documentText: _analysis!.rawOcrText,
      question: text,
      history: _chatMessages,
    );

    if (mounted) {
      setState(() {
        _chatMessages.add({'model': reply});
        _isAsking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.psychology, color: primaryColor),
            const SizedBox(width: 8),
            Text(
              GemmaLocalService.instance.activeModelName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: primaryColor,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.55),
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Extraction'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Doc Q&A'),
            Tab(icon: Icon(Icons.text_snippet_outlined), text: 'Raw OCR'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  const SizedBox(height: 16),
                  Text(
                    'Gemma running on-device inference...',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '100% Offline • Zero Cloud Telemetry',
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 12),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildExtractionTab(theme, primaryColor),
                _buildChatTab(theme, primaryColor),
                _buildRawTextTab(theme, primaryColor),
              ],
            ),
    );
  }

  Widget _buildExtractionTab(ThemeData theme, Color primaryColor) {
    if (_analysis == null) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Privacy Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: primaryColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '100% On-Device Privacy',
                      style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                    ),
                    Text(
                      'Processed locally in phone memory with Gemma. No data sent to third-party servers.',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Document Category Card
        Card(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(
                      avatar: Icon(Icons.category, size: 18, color: primaryColor),
                      label: Text(
                        _analysis!.documentType.displayName,
                        style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                      backgroundColor: primaryColor.withOpacity(isDark ? 0.2 : 0.1),
                      side: BorderSide.none,
                    ),
                    if (_analysis!.suggestedAction != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        ),
                        child: Text(
                          _analysis!.suggestedAction!,
                          style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Executive Summary',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _analysis!.summary,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Structured Key Fields
        Text(
          'Extracted Fields',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor),
        ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _analysis!.extractedFields.length,
            separatorBuilder: (_, __) => Divider(color: theme.colorScheme.outlineVariant, height: 1),
            itemBuilder: (context, index) {
              final field = _analysis!.extractedFields[index];
              return ListTile(
                leading: Icon(_getFieldIcon(field.category), color: primaryColor),
                title: Text(
                  field.key,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                ),
                subtitle: Text(
                  field.value,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.copy, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: field.value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Copied ${field.key} to clipboard')),
                    );
                  },
                ),
              );
            },
          ),
        ),

        // Structured Line Items Table (if present)
        if (_analysis!.lineItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Line Items (${_analysis!.lineItems.length})',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor),
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 22,
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    fontSize: 12,
                  ),
                  dataTextStyle: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  columns: const [
                    DataColumn(label: Text('Description')),
                    DataColumn(label: Text('Qty'), numeric: true),
                    DataColumn(label: Text('Unit Price'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                  ],
                  rows: _analysis!.lineItems.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(item.description, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(Text('${item.quantity}')),
                        DataCell(Text(item.unitPrice)),
                        DataCell(Text(
                          item.totalPrice,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Key Highlights
        Text(
          'Key Highlights',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor),
        ),
        const SizedBox(height: 8),
        ..._analysis!.keyPoints.map(
          (point) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, color: primaryColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point,
                    style: TextStyle(fontSize: 13.5, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatTab(ThemeData theme, Color primaryColor) {
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final msg = _chatMessages[index];
              final isUser = msg.containsKey('user');
              final text = isUser ? msg['user']! : msg['model']!;

              final bubbleBg = isUser
                  ? primaryColor
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0));
              final bubbleFg = isUser
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface;

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isUser ? const Radius.circular(0) : null,
                      bottomLeft: !isUser ? const Radius.circular(0) : null,
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(color: bubbleFg, fontSize: 14),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isAsking)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor)),
                const SizedBox(width: 8),
                Text(
                  'Gemma is thinking offline...',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  decoration: InputDecoration(
                    hintText: 'Ask Gemma about this document...',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _askQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: _askQuestion,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRawTextTab(ThemeData theme, Color primaryColor) {
    if (_analysis == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Extracted Text',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
              ),
              TextButton.icon(
                icon: Icon(Icons.copy, size: 16, color: primaryColor),
                label: Text('Copy All', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _analysis!.rawOcrText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All document text copied to clipboard')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _analysis!.rawOcrText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFieldIcon(String? category) {
    switch (category) {
      case 'financial':
        return Icons.attach_money;
      case 'date':
        return Icons.calendar_today_outlined;
      case 'identity':
        return Icons.badge_outlined;
      case 'contact':
        return Icons.contact_mail_outlined;
      default:
        return Icons.label_outline;
    }
  }
}
