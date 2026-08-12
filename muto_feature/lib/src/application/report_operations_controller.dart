import 'package:flutter/foundation.dart';

import '../domain/entities/operational_report.dart';
import '../domain/entities/page.dart';
import '../domain/failures.dart';
import '../domain/repositories/report_operations_repository.dart';

enum ReportOperationsStatus { idle, loading, ready, failed }

final class ReportOperationsController extends ChangeNotifier {
  ReportOperationsController(this._repository, {required this.onUnauthorized});

  final ReportOperationsRepository _repository;
  final VoidCallback onUnauthorized;
  ReportOperationsStatus _status = ReportOperationsStatus.idle;
  List<OperationalReport> _items = const [];
  Cursor? _nextCursor;
  MutoFailure? _failure;
  int _attempt = 0;

  ReportOperationsStatus get status => _status;
  List<OperationalReport> get items => _items;
  MutoFailure? get failure => _failure;
  bool get hasMore => _nextCursor != null;

  Future<void> load() async {
    if (_status == ReportOperationsStatus.loading) return;
    final attempt = ++_attempt;
    _status = ReportOperationsStatus.loading;
    _failure = null;
    notifyListeners();
    try {
      final page = await _repository.reports();
      if (attempt != _attempt) return;
      _items = page.items;
      _nextCursor = page.nextCursor;
      _status = ReportOperationsStatus.ready;
    } on UnauthorizedFailure {
      if (attempt != _attempt) return;
      onUnauthorized();
      return;
    } on MutoFailure catch (failure) {
      if (attempt != _attempt) return;
      _failure = failure;
      _status = ReportOperationsStatus.failed;
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _status == ReportOperationsStatus.loading) return;
    final attempt = ++_attempt;
    _status = ReportOperationsStatus.loading;
    notifyListeners();
    try {
      final page = await _repository.reports(cursor: cursor);
      if (attempt != _attempt) return;
      _items = [..._items, ...page.items];
      _nextCursor = page.nextCursor;
      _status = ReportOperationsStatus.ready;
    } on UnauthorizedFailure {
      if (attempt != _attempt) return;
      onUnauthorized();
      return;
    } on MutoFailure catch (failure) {
      if (attempt != _attempt) return;
      _failure = failure;
      _status = ReportOperationsStatus.failed;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _attempt++;
    super.dispose();
  }
}
