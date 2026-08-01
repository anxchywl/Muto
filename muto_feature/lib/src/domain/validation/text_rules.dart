/// Normalisation applied to every piece of text a student types or the app
/// receives.
///
/// Bidirectional overrides and invisible control characters are stripped
/// because they let a crafted title render as something other than what it
/// contains.
abstract final class TextRules {
  static const int titleMin = 3;
  static const int titleMax = 80;
  static const int descriptionMax = 2000;
  static const int wantedItemsMax = 200;

  /// Code point ranges that must never survive into stored or rendered text.
  /// Tab, newline and carriage return are deliberately absent — they are
  /// handled as whitespace further down rather than stripped.
  static const List<(int, int)> _unsafeRanges = [
    (0x0000, 0x0008), // c0 controls before tab
    (0x000B, 0x000C), // vertical tab, form feed
    (0x000E, 0x001F), // c0 controls after carriage return
    (0x007F, 0x009F), // delete and c1 controls
    (0x200B, 0x200F), // zero width space through right-to-left mark
    (0x202A, 0x202E), // bidi embedding and override
    (0x2060, 0x2064), // word joiner and invisible operators
    (0x2066, 0x206F), // bidi isolates and deprecated formatting
    (0xFEFF, 0xFEFF), // byte order mark
  ];

  static final RegExp _unsafe = RegExp(_buildUnsafePattern());
  static final RegExp _horizontalRuns = RegExp(r'[ \t]{2,}');
  static final RegExp _blankLineRuns = RegExp(r'\n{3,}');
  static final RegExp _lineBreaks = RegExp(r'[\r\n]+');

  static String _buildUnsafePattern() {
    final pattern = StringBuffer('[');
    for (final (start, end) in _unsafeRanges) {
      pattern.write(_escape(start));
      if (end != start) {
        pattern
          ..write('-')
          ..write(_escape(end));
      }
    }
    pattern.write(']');
    return pattern.toString();
  }

  static String _escape(int codePoint) =>
      '\\u${codePoint.toRadixString(16).padLeft(4, '0')}';

  /// For single-line fields: no line breaks survive.
  static String normalizeLine(String input) {
    return input
        .replaceAll(_unsafe, '')
        .replaceAll(_lineBreaks, ' ')
        .replaceAll(_horizontalRuns, ' ')
        .trim();
  }

  /// For multi-line fields: paragraphs survive, runaway blank lines do not.
  static String normalizeBlock(String input) {
    return input
        .replaceAll(_unsafe, '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_horizontalRuns, ' ')
        .replaceAll(_blankLineRuns, '\n\n')
        .trim();
  }

  static bool isBlank(String? input) =>
      input == null || normalizeLine(input).isEmpty;
}
