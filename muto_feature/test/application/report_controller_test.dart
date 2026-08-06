import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/cache/generation.dart';
import 'package:muto_feature/src/application/report_controller.dart';
import 'package:muto_feature/src/domain/entities/client_request_id.dart';
import 'package:muto_feature/src/domain/entities/report_reason.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/report_repository.dart';
import 'package:muto_feature/src/domain/validation/report_rules.dart';

final class _FakeReports implements ReportRepository {
  _FakeReports({this.failures = 0});

  /// How many attempts fail before one is allowed through.
  int failures;

  final List<ClientRequestId> tokens = [];
  final List<String?> notes = [];

  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) async {
    tokens.add(requestId);
    if (failures > 0) {
      failures--;
      throw const NetworkFailure();
    }
    notes.add(note);
  }
}

/// A send that never settles, so a second tap can be tried while the first is
/// still in flight.
final class _HangingReports implements ReportRepository {
  int calls = 0;

  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) {
    calls++;
    return Completer<void>().future;
  }
}

void main() {
  late CacheGeneration generation;
  var unauthorized = 0;

  ReportController build(ReportRepository reports) => ReportController(
    reports: reports,
    listingId: 'lst_001',
    generation: generation,
    onUnauthorized: () => unauthorized++,
  );

  setUp(() {
    generation = CacheGeneration();
    unauthorized = 0;
  });

  test('nothing can be sent until a reason is chosen', () async {
    final controller = build(_FakeReports());

    expect(controller.canSubmit, isFalse);
    expect(await controller.submit(), isFalse);

    controller.select(ReportReason.misleading);
    expect(controller.canSubmit, isTrue);
  });

  test('a missing note is shown only once sending was attempted', () async {
    final controller = build(_FakeReports())..select(ReportReason.other);

    expect(controller.issue, isNull);
    expect(await controller.submit(), isFalse);
    expect(controller.issue, ReportIssue.noteMissing);
  });

  test('a note is normalized before it is sent', () async {
    final reports = _FakeReports();
    final controller = build(reports)
      ..select(ReportReason.other)
      ..noteChanged('  it is  not real  ');

    expect(await controller.submit(), isTrue);
    expect(reports.notes.single, 'it is not real');
    expect(controller.status, ReportStatus.sent);
  });

  test('a second tap while the first is in flight sends nothing', () async {
    final reports = _HangingReports();
    final controller = build(reports)..select(ReportReason.prohibited);

    unawaited(controller.submit());
    await controller.submit();

    expect(reports.calls, 1);
    expect(controller.canSubmit, isFalse);
  });

  test('a retry after a failure reuses the token it already minted', () async {
    final reports = _FakeReports(failures: 1);
    final controller = build(reports)..select(ReportReason.offensive);

    expect(await controller.submit(), isFalse);
    expect(controller.status, ReportStatus.failed);
    expect(controller.failure, isA<NetworkFailure>());

    expect(await controller.submit(), isTrue);
    expect(reports.tokens, hasLength(2));
    expect(reports.tokens.first, reports.tokens.last);
  });

  test('an expired session is reported to the host', () async {
    final controller = build(_ExpiredReports())
      ..select(ReportReason.misleading);

    expect(await controller.submit(), isFalse);
    expect(unauthorized, 1);
  });

  test(
    'a report still in flight when the account changes never lands',
    () async {
      final reports = _GatedReports();
      final controller = build(reports)..select(ReportReason.misleading);

      final pending = controller.submit();
      generation.bump();
      reports.release();

      expect(await pending, isFalse);
      // nothing is written back into a sheet that belongs to a session which has
      // already gone away
      expect(controller.status, ReportStatus.sending);
    },
  );
}

/// A send held open until the test lets it finish.
final class _GatedReports implements ReportRepository {
  final Completer<void> _held = Completer<void>();

  void release() => _held.complete();

  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) => _held.future;
}

final class _ExpiredReports implements ReportRepository {
  @override
  Future<void> submit({
    required String listingId,
    required ReportReason reason,
    String? note,
    required ClientRequestId requestId,
  }) async {
    throw const UnauthorizedFailure();
  }
}
