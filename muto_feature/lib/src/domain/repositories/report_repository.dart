import '../entities/client_request_id.dart';
import '../entities/report_reason.dart';

/// Sends a report about someone else's listing.
///
/// Reporting is one way. There is no queue, no verdict and no state a student
/// can watch, because this build has no moderation surface — a report is a
/// message to whoever runs the marketplace and nothing more.
abstract interface class ReportRepository {
  /// [requestId] is minted once per report, so a retry after a timeout cannot
  /// send the same report twice.
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  });
}
