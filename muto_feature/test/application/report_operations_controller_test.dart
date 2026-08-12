import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/application/report_operations_controller.dart';
import 'package:muto_feature/src/domain/entities/operational_report.dart';
import 'package:muto_feature/src/domain/entities/page.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';
import 'package:muto_feature/src/domain/entities/report_reason.dart';
import 'package:muto_feature/src/domain/repositories/report_operations_repository.dart';

void main() {
  test('loads and appends the private operator report feed', () async {
    final repository = _ReportOperationsFake();
    final controller = ReportOperationsController(
      repository,
      onUnauthorized: () {},
    );

    await controller.load();
    expect(controller.items.map((item) => item.id), ['first']);
    expect(controller.hasMore, isTrue);

    await controller.loadMore();
    expect(controller.items.map((item) => item.id), ['first', 'second']);
    expect(controller.hasMore, isFalse);
    expect(repository.cursors, [null, 'next']);
  });
}

class _ReportOperationsFake implements ReportOperationsRepository {
  final List<String?> cursors = [];

  @override
  Future<Page<OperationalReport>> reports({Cursor? cursor}) async {
    cursors.add(cursor?.value);
    return Page(
      items: [_report(cursor == null ? 'first' : 'second')],
      nextCursor: cursor == null ? const Cursor('next') : null,
    );
  }
}

OperationalReport _report(String id) => OperationalReport(
  id: id,
  listingId: 'listing-$id',
  listingTitle: 'Listing $id',
  listingStatus: ListingStatus.active,
  reason: ReportReason.misleading,
  createdAt: DateTime.utc(2026),
);
