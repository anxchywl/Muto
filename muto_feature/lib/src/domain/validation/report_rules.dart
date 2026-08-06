import '../entities/report_reason.dart';
import 'text_rules.dart';

enum ReportIssue { noteMissing, noteTooLong }

/// What a report has to contain before it is worth sending.
///
/// The bound exists so a report stays a report: a short statement of what is
/// wrong, not a channel for a conversation the app deliberately does not have.
abstract final class ReportRules {
  static const int noteMax = 500;

  static String? normalizeNote(String? input) {
    if (input == null) return null;
    final note = TextRules.normalizeBlock(input);
    return note.isEmpty ? null : note;
  }

  static ReportIssue? validate(ReportReason reason, String? note) {
    final normalized = normalizeNote(note);
    if (reason.requiresNote && normalized == null) {
      return ReportIssue.noteMissing;
    }
    if (normalized != null && normalized.length > noteMax) {
      return ReportIssue.noteTooLong;
    }
    return null;
  }
}
