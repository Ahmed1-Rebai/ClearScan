/// Accent-insensitive, case-insensitive text helpers for French/English documents.
class TextNormalizer {
  static const Map<String, String> _fold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'œ': 'o', 'æ': 'a', 'ß': 's',
    '’': "'", '‘': "'", '´': "'", '`': "'",
    '“': '"', '”': '"', '«': '"', '»': '"',
    '–': '-', '—': '-', '‐': '-',
    ' ': ' ', ' ': ' ',
  };

  /// Lowercases and strips diacritics so "Échéance" matches "echeance".
  /// Length-preserving for Latin text, so indices map back to the original string.
  static String fold(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final c = input[i];
      final lower = c.toLowerCase();
      final mapped = _fold[lower] ?? lower;
      buffer.write(mapped.length == 1 ? mapped : c);
    }
    return buffer.toString();
  }

  static final RegExp _wordSplit = RegExp(r"[^a-z0-9]+");

  /// Folded alphanumeric tokens.
  static List<String> tokens(String input) =>
      fold(input).split(_wordSplit).where((t) => t.isNotEmpty).toList();

  /// Whether [foldedText] contains [foldedPhrase] as whole words.
  static bool containsPhrase(String foldedText, String foldedPhrase) {
    int from = 0;
    while (true) {
      final i = foldedText.indexOf(foldedPhrase, from);
      if (i < 0) return false;
      final before = i == 0 ? ' ' : foldedText[i - 1];
      final endIndex = i + foldedPhrase.length;
      final after = endIndex >= foldedText.length ? ' ' : foldedText[endIndex];
      if (!_isWordChar(before) && !_isWordChar(after)) return true;
      from = i + 1;
    }
  }

  /// Number of whole-word occurrences of [foldedPhrase].
  static int countPhrase(String foldedText, String foldedPhrase) {
    int count = 0;
    int from = 0;
    while (true) {
      final i = foldedText.indexOf(foldedPhrase, from);
      if (i < 0) return count;
      final before = i == 0 ? ' ' : foldedText[i - 1];
      final endIndex = i + foldedPhrase.length;
      final after = endIndex >= foldedText.length ? ' ' : foldedText[endIndex];
      if (!_isWordChar(before) && !_isWordChar(after)) count++;
      from = i + 1;
    }
  }

  static bool _isWordChar(String c) => RegExp(r'[a-z0-9]').hasMatch(c);

  static final RegExp _letter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');

  static int letterCount(String s) => _letter.allMatches(s).length;

  static double letterRatio(String s) {
    final compact = s.replaceAll(RegExp(r'\s'), '');
    return compact.isEmpty ? 0 : letterCount(compact) / compact.length;
  }
}
