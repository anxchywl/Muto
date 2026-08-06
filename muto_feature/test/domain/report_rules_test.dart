import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/entities/report_reason.dart';
import 'package:muto_feature/src/domain/validation/report_rules.dart';

void main() {
  test('a chosen reason is enough on its own', () {
    expect(ReportRules.validate(ReportReason.misleading, null), isNull);
  });

  test('"something else" says nothing without a note', () {
    expect(
      ReportRules.validate(ReportReason.other, '   '),
      ReportIssue.noteMissing,
    );
    expect(ReportRules.validate(ReportReason.other, 'a fake seller'), isNull);
  });

  test('a note is bounded', () {
    expect(
      ReportRules.validate(ReportReason.prohibited, 'a' * 501),
      ReportIssue.noteTooLong,
    );
  });

  test('a note keeps its paragraphs and loses its control characters', () {
    // a right-to-left override, built from its code point so this file reads
    // the same way it renders
    final note = 'first${String.fromCharCode(0x202E)}line\n\nsecond ';

    expect(ReportRules.normalizeNote(note), 'firstline\n\nsecond');
  });

  test('an empty note is nothing rather than an empty string', () {
    expect(ReportRules.normalizeNote(''), isNull);
  });
}
