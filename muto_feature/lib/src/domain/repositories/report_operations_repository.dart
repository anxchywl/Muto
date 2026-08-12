import '../entities/operational_report.dart';
import '../entities/page.dart';

abstract interface class ReportOperationsRepository {
  Future<Page<OperationalReport>> reports({Cursor? cursor});
}
