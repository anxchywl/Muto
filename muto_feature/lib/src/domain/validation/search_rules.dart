import 'text_rules.dart';

/// What the search box accepts and what it is allowed to remember.
///
/// Recent terms are the student's own words kept on their device, so the
/// bounds here are about keeping the list readable rather than about safety —
/// safety is [TextRules], which every term passes through first.
abstract final class SearchRules {
  static const int termMax = 80;
  static const int recentMax = 8;
  static const int suggestionMax = 6;

  /// Below this a prefix matches nearly everything, so suggesting is noise
  /// rather than help.
  static const int suggestMinLength = 2;

  /// Null for anything that would search for nothing.
  static String? normalizeTerm(String input) {
    final term = TextRules.normalizeLine(input);
    if (term.isEmpty) return null;
    return term.length > termMax ? term.substring(0, termMax).trim() : term;
  }

  static bool isSuggestible(String term) => term.length >= suggestMinLength;

  /// Most recent first, no case-insensitive repeats, bounded.
  static List<String> remember(List<String> existing, String term) {
    final kept = <String>[term];
    for (final previous in existing) {
      if (kept.length == recentMax) break;
      if (_sameTerm(previous, term)) continue;
      kept.add(previous);
    }
    return List<String>.unmodifiable(kept);
  }

  static List<String> forget(List<String> existing, String term) {
    return List<String>.unmodifiable([
      for (final previous in existing)
        if (!_sameTerm(previous, term)) previous,
    ]);
  }

  /// Drops anything unusable and applies the bound, which is what a list read
  /// back from storage has to survive.
  static List<String> sanitize(Iterable<String> terms) {
    final kept = <String>[];
    for (final raw in terms) {
      final term = normalizeTerm(raw);
      if (term == null) continue;
      if (kept.any((previous) => _sameTerm(previous, term))) continue;
      kept.add(term);
      if (kept.length == recentMax) break;
    }
    return List<String>.unmodifiable(kept);
  }

  static bool _sameTerm(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();
}
