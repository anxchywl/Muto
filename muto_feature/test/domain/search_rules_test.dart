import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/validation/search_rules.dart';

void main() {
  group('a term', () {
    test('loses line breaks and surrounding space', () {
      expect(SearchRules.normalizeTerm('  lamp\nclip  '), 'lamp clip');
    });

    test('is nothing when it is only whitespace', () {
      expect(SearchRules.normalizeTerm('   '), isNull);
    });

    test('is cut to the bound rather than refused', () {
      final term = SearchRules.normalizeTerm('a' * 200);
      expect(term!.length, SearchRules.termMax);
    });

    test('is too short to suggest on until it means something', () {
      expect(SearchRules.isSuggestible('l'), isFalse);
      expect(SearchRules.isSuggestible('la'), isTrue);
    });
  });

  group('recent terms', () {
    test('put the newest first', () {
      final recent = SearchRules.remember(const ['lamp'], 'desk');
      expect(recent, ['desk', 'lamp']);
    });

    test('do not repeat a term that differs only in case', () {
      final recent = SearchRules.remember(const ['Lamp', 'desk'], 'lamp');
      expect(recent, ['lamp', 'desk']);
    });

    test('stop at the bound', () {
      var recent = const <String>[];
      for (var i = 0; i < SearchRules.recentMax + 4; i++) {
        recent = SearchRules.remember(recent, 'term $i');
      }

      expect(recent.length, SearchRules.recentMax);
      expect(recent.first, 'term ${SearchRules.recentMax + 3}');
    });

    test('drop the one that was forgotten', () {
      expect(SearchRules.forget(const ['lamp', 'desk'], 'LAMP'), ['desk']);
    });
  });

  group('reading a stored list back', () {
    test('drops entries an older build could have written', () {
      final terms = SearchRules.sanitize(const ['lamp', '  ', 'lamp', 'desk']);
      expect(terms, ['lamp', 'desk']);
    });

    test('applies the bound whatever was on disk', () {
      final terms = SearchRules.sanitize([
        for (var i = 0; i < 40; i++) 'term $i',
      ]);
      expect(terms.length, SearchRules.recentMax);
    });
  });
}
