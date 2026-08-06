import '../../domain/entities/client_request_id.dart';
import '../../domain/entities/identity.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/validation/report_rules.dart';
import 'mock_environment.dart';

/// One report, as the receiving side would hold it.
final class MockReport {
  const MockReport({
    required this.listingId,
    required this.reporterId,
    required this.reason,
    this.note,
  });

  final String listingId;
  final String reporterId;
  final ReportReason reason;
  final String? note;
}

/// An in-memory stand-in for the reporting endpoint.
///
/// It enforces what the real one will: a retry sends nothing twice, reporting
/// the same listing again is accepted without saying whether it was already
/// reported, and a burst is refused.
final class MockReportRepository implements ReportRepository {
  MockReportRepository({
    required Identity Function() viewer,
    this.latency = const MockLatency(),
    MockFaults? faults,
  }) : _viewer = viewer,
       faults = faults ?? MockFaults();

  /// Reports one account may send before it has to wait.
  static const int burstLimit = 5;

  static const Duration window = Duration(minutes: 10);

  final Identity Function() _viewer;
  final MockLatency latency;
  final MockFaults faults;

  final List<MockReport> _received = [];
  final Set<String> _requestIds = <String>{};
  final Map<String, List<DateTime>> _sentAt = {};

  List<MockReport> get received => List<MockReport>.unmodifiable(_received);

  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) async {
    await Future<void>.delayed(latency.write);
    faults.checkWritable();

    // a retry of a report that already landed is not a second report
    if (_requestIds.contains(requestId.value)) return;

    final normalized = ReportRules.normalizeNote(note);
    if (ReportRules.validate(reason, normalized) != null) {
      throw const UnexpectedFailure(statusCode: 422);
    }

    final reporterId = _viewer().userId;
    if (_isOverLimit(reporterId)) {
      throw const RateLimitedFailure(retryAfter: window);
    }

    _requestIds.add(requestId.value);
    _sentAt.putIfAbsent(reporterId, () => []).add(DateTime.now());

    // reporting the same listing twice is accepted and recorded once, so the
    // answer never tells the reporter what anyone else has done
    final seen = _received.any(
      (report) =>
          report.listingId == listingId && report.reporterId == reporterId,
    );
    if (seen) return;

    _received.add(
      MockReport(
        listingId: listingId,
        reporterId: reporterId,
        reason: reason,
        note: normalized,
      ),
    );
  }

  bool _isOverLimit(String reporterId) {
    final since = DateTime.now().subtract(window);
    final recent = _sentAt[reporterId] ?? const <DateTime>[];
    return recent.where((moment) => moment.isAfter(since)).length >= burstLimit;
  }
}
