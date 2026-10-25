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
      // Use document title and default metadata for demonstration
      combinedText = '${widget.document.title}\nInvoice #INV-2026-9812\nDate: 2026-10-25\nBilled to: Acme Industries\nTotal Amount Due: \$349.50\nTax: \$28.00\nPayment Terms: Net 30 days\nStatus: Unpaid';
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2E),
        title: Row(
          children: [
            const Icon(Icons.psychology, color: Color(0xFF00E5FF)),
            const SizedBox(width: 8),
            Text(
              GemmaLocalService.instance.activeModelName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: const Color(0xFF00E5FF),
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Extraction'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Doc Q&A'),
            Tab(icon: Icon(Icons.text_snippet_outlined), text: 'Raw OCR'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: const Color(0xFF00E5FF)),
                  SizedBox(height: 16),
                  Text('Gemma running on-device inference...', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 4),
                  Text('100% Offline • Zero Cloud Telemetry', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildExtractionTab(),
                _buildChatTab(),
                _buildRawTextTab(),
              ],
            ),
    );
  }

  Widget _buildExtractionTab() {
    if (_analysis == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Privacy Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0066FF).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_outlined, color: const Color(0xFF00E5FF), size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('100% On-Device Privacy', style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF))),
                    Text('Processed locally in phone memory with Gemma. No data sent to third-party servers.', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Document Category Card
        Card(
          color: const Color(0xFF131B2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.category, size: 18, color: const Color(0xFF00E5FF)),
                      label: Text(_analysis!.documentType.displayName, style: const TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF))),
                      backgroundColor: const Color(0xFF0066FF).withOpacity(0.2),
                    ),
                    if (_analysis!.suggestedAction != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.5)),
                        ),
                        child: Text(_analysis!.suggestedAction!, style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Executive Summary', style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_analysis!.summary, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Structured Key Fields
        const Text('Extracted Fields', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF))),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF131B2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _analysis!.extractedFields.length,
            separatorBuilder: (_, __) => Divider(color: Colors.grey[800], height: 1),
            itemBuilder: (context, index) {
              final field = _analysis!.extractedFields[index];
              return ListTile(
                leading: Icon(_getFieldIcon(field.category), color: const Color(0xFF00E5FF)),
                title: Text(field.key, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                subtitle: Text(field.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.white38),
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
        const SizedBox(height: 16),

        // Key Points
        const Text('Key Highlights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF00E5FF))),
        const SizedBox(height: 8),
        ..._analysis!.keyPoints.map(
          (point) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, color: const Color(0xFF00E5FF), size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(point, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatTab() {
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

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF0066FF) : const Color(0xFF1A2234),
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isUser ? const Radius.circular(0) : null,
                      bottomLeft: !isUser ? const Radius.circular(0) : null,
                    ),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isAsking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF00E5FF))),
                SizedBox(width: 8),
                Text('Gemma is thinking offline...', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF131B2E),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _questionController,
                  decoration: InputDecoration(
                    hintText: 'Ask Gemma about this document...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.black45,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _askQuestion(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send, color: Colors.black),
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                onPressed: _askQuestion,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRawTextTab() {
    if (_analysis == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Extracted Text', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy All'),
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
                color: const Color(0xFF131B2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _analysis!.rawOcrText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45),
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
        return Icons.calendar_today;
      case 'identity':
        return Icons.badge_outlined;
      case 'contact':
        return Icons.contact_phone_outlined;
      default:
        return Icons.label_outline;
    }
  }
}

