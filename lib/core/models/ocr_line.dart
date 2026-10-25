/// One recognized text line, with its box normalized to 0..1 of the page image.
class OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? confidence;

  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence,
  });

  double get width => right - left;
  double get height => bottom - top;

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  Map<String, dynamic> toJson() => {
        't': text,
        'b': [_round(left), _round(top), _round(right), _round(bottom)],
        if (confidence != null) 'c': _round(confidence!),
      };

  factory OcrLine.fromJson(Map<String, dynamic> json) {
    final box = (json['b'] as List<dynamic>).map((v) => (v as num).toDouble()).toList();
    return OcrLine(
      text: json['t'] as String,
      left: box[0],
      top: box[1],
      right: box[2],
      bottom: box[3],
      confidence: (json['c'] as num?)?.toDouble(),
    );
  }
}
