/// Why a student is reporting a listing.
///
/// The set is short and fixed. A longer list makes the choice harder without
/// making the report more useful to whoever reads it.
enum ReportReason {
  /// Something that may not be sold or given away on campus.
  prohibited('prohibited'),

  /// The listing does not describe what is actually being offered.
  misleading('misleading'),

  /// Text or photos that target or offend someone.
  offensive('offensive'),

  /// Anything else, which is why a note is required with it.
  other('other');

  const ReportReason(this.wireValue);

  final String wireValue;

  static ReportReason? fromWire(String? value) {
    for (final reason in ReportReason.values) {
      if (reason.wireValue == value) return reason;
    }
    return null;
  }

  bool get requiresNote => this == ReportReason.other;
}
