/// An amount found verbatim in the text.
class MoneyMatch {
  /// Exactly as printed (e.g. "1 250,000 DT", "$3,464.00").
  final String raw;
  final double? value;
  final String? currency;
  final int start;
  final int end;
  final bool hasDecimals;

  const MoneyMatch({
    required this.raw,
    required this.value,
    required this.currency,
    required this.start,
    required this.end,
    required this.hasDecimals,
  });

  /// Strong evidence that this number is money rather than a quantity or an id.
  bool get looksMonetary => currency != null || hasDecimals;
}

/// Parses amounts in English (1,234.56), French (1 234,56 / 1.234,56) and
/// three-decimal currencies such as the Tunisian dinar (12,500 DT = 12.5).
class Money {
  static const _symbols = r'[$€£¥₹]';
  static const _codes = r'USD|EUR|GBP|TND|DT|D\.T\.?|MAD|DH|DZD|DA|CAD|AUD|CHF|XOF|XAF|SAR|AED|EGP|LYD';

  // Boundaries exclude dates (25/10/2026, 2026-10-25), times (14:07), percentages and ids.
  static final RegExp _amount = RegExp(
    '(?<![\\w.,/:-])'
    '(?:(?<cur1>$_symbols|$_codes)\\s?)?'
    r'(?<num>\d{1,3}(?:[   .,]\d{3})+(?:[.,]\d{1,3})?|\d+(?:[.,]\d{1,3})?)'
    '(?:\\s?(?<cur2>$_symbols|$_codes|dinars?|euros?|dollars?)(?![A-Za-z]))?'
    r'(?![\w%/]|[.,:\-]\d|\s?%)',
    caseSensitive: false,
  );

  static const _threeDecimalCurrencies = {'TND', 'DT', 'D.T', 'D.T.', 'DINAR', 'DINARS', 'KWD', 'BHD', 'OMR', 'JOD', 'LYD'};

  /// All amount-like numbers in [text], in order.
  static List<MoneyMatch> findAll(String text, {String? defaultCurrency}) {
    final matches = <MoneyMatch>[];
    for (final m in _amount.allMatches(text)) {
      final num = m.namedGroup('num')!;
      final currency = (m.namedGroup('cur1') ?? m.namedGroup('cur2'))?.toUpperCase();
      final raw = m.group(0)!.trim();
      final value = parse(num, currency: currency ?? defaultCurrency);
      matches.add(MoneyMatch(
        raw: raw,
        value: value,
        currency: currency,
        start: m.start,
        end: m.end,
        hasDecimals: _decimalSeparator(num.replaceAll(RegExp(r'[   ]'), ''), currency ?? defaultCurrency) != null,
      ));
    }
    return matches;
  }

  /// Numeric value of a printed amount, or null if it cannot be interpreted.
  static double? parse(String printed, {String? currency}) {
    final s = printed.replaceAll(RegExp(r'[   ]'), '');
    final decimal = _decimalSeparator(s, currency);
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '.' || c == ',') {
        if (c == decimal && i == s.lastIndexOf(decimal!)) buffer.write('.');
      } else {
        buffer.write(c);
      }
    }
    return double.tryParse(buffer.toString());
  }

  /// Most frequent explicit currency in [text], used to interpret bare numbers.
  static String? dominantCurrency(String text) {
    final counts = <String, int>{};
    for (final m in findAll(text)) {
      if (m.currency != null) counts[m.currency!] = (counts[m.currency!] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  static String? _decimalSeparator(String s, String? currency) {
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) return lastDot > lastComma ? '.' : ',';
    if (lastDot < 0 && lastComma < 0) return null;
    final sep = lastComma >= 0 ? ',' : '.';
    final occurrences = sep.allMatches(s).length;
    if (occurrences > 1) return null;
    final digitsAfter = s.length - s.lastIndexOf(sep) - 1;
    if (digitsAfter == 3) {
      final cur = currency?.toUpperCase().replaceAll(' ', '');
      return cur != null && _threeDecimalCurrencies.contains(cur) ? sep : null;
    }
    return sep;
  }
}
