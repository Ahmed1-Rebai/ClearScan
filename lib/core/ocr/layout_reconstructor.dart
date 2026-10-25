import 'dart:math';

/// A recognized text line in page pixel coordinates.
class OcrLineBox {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;
  final double? angle;

  const OcrLineBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
    this.angle,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  OcrLineBox withText(String newText) => OcrLineBox(
        text: newText,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        confidence: confidence,
        angle: angle,
      );
}

class ReconstructedLayout {
  /// Reading-order text. Cells on one row that are far apart are joined by three spaces.
  final String text;

  /// Cleaned lines in reading order.
  final List<OcrLineBox> lines;

  const ReconstructedLayout(this.text, this.lines);
}

/// Rebuilds reading order from OCR line boxes with a recursive XY-cut:
/// full-width headers before columns, left column before right column, and
/// label/amount pairs of tables and receipts kept on the same row.
class LayoutReconstructor {
  static const String cellSeparator = '   ';

  static ReconstructedLayout reconstruct(List<OcrLineBox> input) {
    final lines = input.map(_cleanLine).whereType<OcrLineBox>().toList();
    if (lines.isEmpty) return const ReconstructedLayout('', []);

    final heights = lines.map((l) => l.height).toList()..sort();
    final double lineHeight = max(1.0, heights[heights.length ~/ 2]);
    final double pageWidth = lines.map((l) => l.right).reduce(max) - lines.map((l) => l.left).reduce(min);
    // Paragraph breaks are gaps clearly larger than this page's normal line spacing.
    final double paragraphGap = max(lineHeight * 0.6, _typicalLineGap(lines, lineHeight) * 1.8);

    final regions = <List<OcrLineBox>>[];
    _xyCut(lines, lineHeight, paragraphGap, pageWidth, regions, 0);

    final ordered = <OcrLineBox>[];
    final paragraphs = <String>[];
    for (final region in regions) {
      final rows = _rows(region);
      final buffer = StringBuffer();
      List<OcrLineBox>? previous;
      for (final row in rows) {
        ordered.addAll(row);
        final rowText = _joinRow(row, lineHeight);
        if (previous != null) {
          final gap = row.map((l) => l.top).reduce(min) - previous.map((l) => l.bottom).reduce(max);
          final current = buffer.toString();
          if (gap > paragraphGap) {
            buffer.write('\n\n');
          } else if (_endsWithBreakableHyphen(current) && _startsLowercase(rowText)) {
            final trimmed = current.substring(0, current.length - 1);
            buffer
              ..clear()
              ..write(trimmed);
          } else {
            buffer.write('\n');
          }
        }
        buffer.write(rowText);
        previous = row;
      }
      if (buffer.isNotEmpty) paragraphs.add(buffer.toString());
    }
    return ReconstructedLayout(paragraphs.join('\n\n').trim(), ordered);
  }

  /// Median vertical gap between a line and the next line below it in the same column.
  static double _typicalLineGap(List<OcrLineBox> lines, double lineHeight) {
    final gaps = <double>[];
    for (final a in lines) {
      double? best;
      for (final b in lines) {
        if (identical(a, b) || b.top < a.bottom - lineHeight * 0.3) continue;
        final overlap = min(a.right, b.right) - max(a.left, b.left);
        if (overlap < 0.3 * min(a.width, b.width)) continue;
        final gap = b.top - a.bottom;
        if (best == null || gap < best) best = gap;
      }
      if (best != null && best >= 0 && best < lineHeight * 4) gaps.add(best);
    }
    if (gaps.length < 3) return lineHeight * 0.6;
    gaps.sort();
    return gaps[gaps.length ~/ 2];
  }

  static void _xyCut(
    List<OcrLineBox> lines,
    double lineHeight,
    double paragraphGap,
    double pageWidth,
    List<List<OcrLineBox>> out,
    int depth,
  ) {
    if (lines.length <= 1 || depth > 24) {
      out.add(lines);
      return;
    }
    final hGap = _largestGap(lines, horizontal: true);
    final vGap = _largestGap(lines, horizontal: false);
    final double hThreshold = max(lineHeight * 0.9, paragraphGap);
    final double vThreshold = max(lineHeight * 1.2, pageWidth * 0.02);

    final double hScore = hGap == null ? 0 : hGap.size / hThreshold;
    double vScore = vGap == null ? 0 : vGap.size / vThreshold;
    if (vScore >= 1 && !_acceptColumnCut(lines, vGap!.position)) vScore = 0;

    if (hScore >= 1 && hScore >= vScore) {
      final top = lines.where((l) => l.centerY < hGap!.position).toList();
      final bottom = lines.where((l) => l.centerY >= hGap!.position).toList();
      if (top.isEmpty || bottom.isEmpty) {
        out.add(lines);
        return;
      }
      _xyCut(top, lineHeight, paragraphGap, pageWidth, out, depth + 1);
      _xyCut(bottom, lineHeight, paragraphGap, pageWidth, out, depth + 1);
    } else if (vScore >= 1) {
      final left = lines.where((l) => (l.left + l.right) / 2 < vGap!.position).toList();
      final right = lines.where((l) => (l.left + l.right) / 2 >= vGap!.position).toList();
      if (left.isEmpty || right.isEmpty) {
        out.add(lines);
        return;
      }
      _xyCut(left, lineHeight, paragraphGap, pageWidth, out, depth + 1);
      _xyCut(right, lineHeight, paragraphGap, pageWidth, out, depth + 1);
    } else {
      out.add(lines);
    }
  }

  /// Largest empty band between line projections; [horizontal] means a band between rows.
  static ({double position, double size})? _largestGap(List<OcrLineBox> lines, {required bool horizontal}) {
    final intervals = lines
        .map((l) => horizontal ? [l.top, l.bottom] : [l.left, l.right])
        .toList()
      ..sort((a, b) => a[0].compareTo(b[0]));
    double reach = intervals.first[1];
    ({double position, double size})? best;
    for (int i = 1; i < intervals.length; i++) {
      final start = intervals[i][0];
      if (start > reach) {
        final size = start - reach;
        if (best == null || size > best.size) best = (position: (start + reach) / 2, size: size);
      }
      reach = max(reach, intervals[i][1]);
    }
    return best;
  }

  /// A vertical cut separates columns of prose, but must not split the label and
  /// value columns of a table or receipt (whose lines sit on the same rows).
  static bool _acceptColumnCut(List<OcrLineBox> lines, double x) {
    final left = lines.where((l) => (l.left + l.right) / 2 < x).toList();
    final right = lines.where((l) => (l.left + l.right) / 2 >= x).toList();
    final smaller = left.length <= right.length ? left : right;
    final other = identical(smaller, left) ? right : left;
    if (smaller.isEmpty) return false;
    int partners = 0;
    int prosePairs = 0;
    for (final a in smaller) {
      for (final b in other) {
        final overlap = min(a.bottom, b.bottom) - max(a.top, b.top);
        if (overlap >= 0.5 * min(a.height, b.height)) {
          partners++;
          if (_isProse(a.text) && _isProse(b.text)) prosePairs++;
          break;
        }
      }
    }
    if (partners < smaller.length * 0.6) return true;
    return prosePairs >= partners * 0.5;
  }

  static bool _isProse(String text) {
    if (text.length < 14) return false;
    final letters = text.runes.where((r) => _isLetter(String.fromCharCode(r))).length;
    return letters >= text.length * 0.6;
  }

  /// Groups lines into rows by vertical overlap, each row sorted left to right.
  static List<List<OcrLineBox>> _rows(List<OcrLineBox> lines) {
    final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <List<OcrLineBox>>[];
    for (final line in sorted) {
      List<OcrLineBox>? target;
      for (final row in rows.reversed.take(3)) {
        final rowTop = row.map((l) => l.top).reduce(min);
        final rowBottom = row.map((l) => l.bottom).reduce(max);
        final rowHeight = rowBottom - rowTop;
        final overlap = min(rowBottom, line.bottom) - max(rowTop, line.top);
        final collides = row.any((l) => min(l.right, line.right) - max(l.left, line.left) > 0.3 * min(l.width, line.width));
        if (!collides && overlap >= 0.5 * min(rowHeight, line.height)) {
          target = row;
          break;
        }
      }
      if (target != null) {
        target.add(line);
      } else {
        rows.add([line]);
      }
    }
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    rows.sort((a, b) => a.map((l) => l.top).reduce(min).compareTo(b.map((l) => l.top).reduce(min)));
    return rows;
  }

  static String _joinRow(List<OcrLineBox> row, double lineHeight) {
    final buffer = StringBuffer(row.first.text);
    for (int i = 1; i < row.length; i++) {
      final gap = row[i].left - row[i - 1].right;
      buffer.write(gap > lineHeight * 0.8 ? cellSeparator : ' ');
      buffer.write(row[i].text);
    }
    return buffer.toString();
  }

  static OcrLineBox? _cleanLine(OcrLineBox line) {
    final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    final hasAlnum = RegExp(r'[0-9A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(text);
    if (!hasAlnum && text.length <= 2) return null;
    return line.withText(fixElisions(text.split(' ').map(fixNumericToken).join(' ')));
  }

  static final RegExp _misreadElision = RegExp(r"(?<![A-Za-zÀ-ÿ0-9])([I1|])(['’])([a-zà-öø-ÿ]+)");

  /// Serif "l'" (French elision) is often read as "I'", "1'" or "|'":
  /// "I'entreprise" → "l'entreprise". English "I'm / I've / I'll / I'd" are kept.
  static String fixElisions(String text) {
    return text.replaceAllMapped(_misreadElision, (m) {
      final rest = m.group(3)!;
      if (m.group(1) == 'I' && const {'m', 've', 'll', 'd'}.contains(rest)) return m.group(0)!;
      return 'l${m.group(2)}$rest';
    });
  }

  /// Repairs letter/digit confusions inside predominantly numeric tokens
  /// ("1O0,00" → "100,00", "l50.00" → "150.00"); other tokens are left untouched.
  static String fixNumericToken(String token) {
    final alnum = token.runes.map(String.fromCharCode).where((c) => RegExp(r'[0-9A-Za-z]').hasMatch(c)).toList();
    final digits = alnum.where((c) => RegExp(r'[0-9]').hasMatch(c)).length;
    if (digits < 2 || digits < alnum.length * 0.6) return token;
    final chars = token.split('');
    bool isDigit(int i) => i >= 0 && i < chars.length && RegExp(r'[0-9]').hasMatch(chars[i]);
    for (int i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (!(isDigit(i - 1) || isDigit(i + 1))) continue;
      if (c == 'O' || c == 'o') chars[i] = '0';
      if (c == 'l' || c == 'I' || c == '|') chars[i] = '1';
    }
    return chars.join();
  }

  static bool _endsWithBreakableHyphen(String text) =>
      RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{2}-$').hasMatch(text);

  static bool _startsLowercase(String text) => RegExp(r'^[a-zà-öø-ÿ]').hasMatch(text);

  static bool _isLetter(String c) => RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(c);
}
