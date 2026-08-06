import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_report_repository.dart';
import 'package:muto_feature/src/domain/entities/client_request_id.dart';
import 'package:muto_feature/src/domain/entities/identity.dart';
import 'package:muto_feature/src/domain/entities/report_reason.dart';
import 'package:muto_feature/src/domain/failures.dart';

const Identity _viewer = Identity(
  userId: 'usr_001',
  displayName: 'Aruzhan',
  isVerified: true,
);

void main() {
  late MockReportRepository reports;

  setUp(() {
    reports = MockReportRepository(
      viewer: () => _viewer,
      latency: const MockLatency.none(),
    );
  });

  Future<void> send(
    String listingId, {
    required String requestId,
    ReportReason reason = ReportReason.misleading,
    String? note,
  }) {
    return reports.submit(
      listingId: listingId,
      reason: reason,
      note: note,
      requestId: ClientRequestId(requestId),
    );
  }

  test('a report is recorded with its reason and its note', () async {
    await send('lst_001', requestId: 'req-1', note: '  not what it says  ');

    expect(reports.received, hasLength(1));
    expect(reports.received.single.listingId, 'lst_001');
    expect(reports.received.single.reporterId, _viewer.userId);
    expect(reports.received.single.note, 'not what it says');
  });

  test('a retry with the same token sends nothing twice', () async {
    await send('lst_001', requestId: 'req-1');
    await send('lst_001', requestId: 'req-1');

    expect(reports.received, hasLength(1));
  });

  test(
    'reporting the same listing again is accepted and recorded once',
    () async {
      await send('lst_001', requestId: 'req-1');
      await send('lst_001', requestId: 'req-2');

      // the second call answers exactly like the first, so nothing about what
      // anyone else has done leaks back
      expect(reports.received, hasLength(1));
    },
  );

  test('a reason that needs a note is refused without one', () {
    expect(
      () => send('lst_001', requestId: 'req-1', reason: ReportReason.other),
      throwsA(isA<UnexpectedFailure>()),
    );
  });

  test('a burst is rate limited', () async {
    for (var i = 0; i < MockReportRepository.burstLimit; i++) {
      await send('lst_00$i', requestId: 'req-$i');
    }

    expect(
      () => send('lst_999', requestId: 'req-last'),
      throwsA(isA<RateLimitedFailure>()),
    );
  });

  test('being offline is a network failure, not a lost report', () {
    final offline = MockReportRepository(
      viewer: () => _viewer,
      latency: const MockLatency.none(),
      faults: MockFaults()..offline = true,
    );

    expect(
      () => offline.submit(
        listingId: 'lst_001',
        reason: ReportReason.prohibited,
        requestId: const ClientRequestId('req-1'),
      ),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
