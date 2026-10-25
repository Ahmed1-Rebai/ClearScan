/// Prompt templates formatted for on-device Gemma 2B/3B and PaliGemma models.
class GemmaPromptBuilder {
  static const String startTurnUser = '<start_of_turn>user\n';
  static const String endTurn = '<end_of_turn>\n';
  static const String startTurnModel = '<start_of_turn>model\n';

  /// Builds a structured extraction prompt for Gemma to parse a document into JSON.
  static String buildDocumentAnalysisPrompt(String documentText) {
    return '$startTurnUser'
        'You are a private, on-device document assistant. '
        'Analyze the following text scanned from a document and output a strict JSON object with these keys:\n'
        '- "documentType": one of ["receipt", "invoice", "contract", "idCard", "businessCard", "notes", "whiteboard", "book", "other"]\n'
        '- "summary": concise 1-2 sentence overview of what this document is\n'
        '- "keyPoints": array of 3-5 main bullet points or highlights\n'
        '- "suggestedAction": optional action needed (e.g., "Pay by due date", "Sign page 2")\n'
        '- "fields": array of objects with "key", "value", and "category" (e.g. Total, Date, Vendor, Account #, Address, Tax)\n\n'
        'Scanned Document Text:\n'
        '"""\n'
        '$documentText\n'
        '"""\n\n'
        'Output ONLY the JSON object. Do not include markdown code block backticks.$endTurn'
        '$startTurnModel';
  }

  /// Builds a conversational Q&A prompt about a scanned document.
  static String buildDocumentQAPrompt({
    required String documentText,
    required List<Map<String, String>> conversationHistory,
    required String userQuestion,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.write(startTurnUser);
    buffer.write('Document Context:\n"""\n$documentText\n"""\n\n');
    buffer.write('Answer questions based strictly on the document context provided above.$endTurn');
    buffer.write(startTurnModel);
    buffer.write('Understood. I will answer questions about this document.$endTurn');

    // Add prior turns
    for (final turn in conversationHistory) {
      if (turn.containsKey('user')) {
        buffer.write('${startTurnUser}${turn['user']}$endTurn');
      }
      if (turn.containsKey('model')) {
        buffer.write('${startTurnModel}${turn['model']}$endTurn');
      }
    }

    // Add current question
    buffer.write('${startTurnUser}$userQuestion$endTurn');
    buffer.write(startTurnModel);

    return buffer.toString();
  }

  /// Builds a document translation / markdown cleanup prompt.
  static String buildCleanupPrompt(String rawOcrText) {
    return '$startTurnUser'
        'Format the following OCR raw text into clean, structured Markdown with proper headings, lists, and corrected typos. '
        'Preserve all numbers and names exactly as written:\n\n'
        '"""\n$rawOcrText\n"""$endTurn'
        '$startTurnModel';
  }
}

