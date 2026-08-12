import '../../domain/entities/operational_report.dart';
import '../../domain/entities/page.dart';
import '../../domain/repositories/report_operations_repository.dart';

final class MockReportOperationsRepository
    implements ReportOperationsRepository {
  const MockReportOperationsRepository();

  @override
  Future<Page<OperationalReport>> reports({Cursor? cursor}) async =>
      const Page.empty();
}
