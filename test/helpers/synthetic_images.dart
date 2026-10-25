import 'package:image/image.dart' as img;

const _sentences = [
  'The quick brown fox jumps over the lazy dog.',
  'Exercice 1 : transformez cette structure en JSON.',
  'La comptabilite utilise un certain nombre de documents',
  'dont certains emanent de l entreprise elle-meme.',
  'Total des capitaux propres et passifs du bilan',
  'Vous devez creer un programme en Java afin de',
  'recuperer les donnees du fichier personne.json',
  'Typography quality: big jumpy glyphs (pq) [db]',
];

/// A white page with lines of dark text drawn with a real bitmap font.
img.Image syntheticTextPage({int width = 1000, int height = 1400, int lines = 28, int lineGap = 44}) {
  final page = img.Image(width: width, height: height);
  img.fill(page, color: img.ColorRgb8(248, 248, 245));
  for (int i = 0; i < lines; i++) {
    final y = 60 + i * lineGap;
    if (y > height - 60) break;
    img.drawString(page, _sentences[i % _sentences.length], font: img.arial24, x: 60, y: y, color: img.ColorRgb8(25, 25, 30));
  }
  return page;
}

/// A white page (as a convex quad) with text-like rows on a dark, cluttered desk.
img.Image syntheticDeskPhoto({
  int width = 1200,
  int height = 900,
  List<img.Point> page = const [],
}) {
  final photo = img.Image(width: width, height: height);
  img.fill(photo, color: img.ColorRgb8(96, 72, 52));
  // Clutter: a cable and a sticky note.
  img.drawLine(photo, x1: 0, y1: 60, x2: width, y2: 140, color: img.ColorRgb8(20, 20, 20), thickness: 6);
  img.fillRect(photo, x1: 30, y1: 600, x2: 180, y2: 760, color: img.ColorRgb8(230, 210, 90));
  img.fillPolygon(photo, vertices: page, color: img.ColorRgb8(240, 240, 236));
  // Text-like rows well inside the page (the quad's skew is far smaller than the margins).
  final top = page.map((p) => p.y).reduce((a, b) => a < b ? a : b).toInt();
  final bottom = page.map((p) => p.y).reduce((a, b) => a > b ? a : b).toInt();
  final minX = page.map((p) => p.x).reduce((a, b) => a < b ? a : b).toInt();
  final maxX = page.map((p) => p.x).reduce((a, b) => a > b ? a : b).toInt();
  for (int y = top + 80; y < bottom - 80; y += 28) {
    img.drawLine(photo, x1: minX + 100, y1: y, x2: maxX - 100, y2: y + 3, color: img.ColorRgb8(40, 40, 40), thickness: 4);
  }
  return photo;
}
