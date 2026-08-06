import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/entities/client_request_id.dart';
import '../domain/entities/report_reason.dart';
import '../domain/failures.dart';
import '../domain/repositories/report_repository.dart';
import '../domain/validation/report_rules.dart';
import 'cache/generation.dart';

enum ReportStatus { editing, sending, sent, failed }

/// Drives one report of one listing.
///
/// Its whole job is to make sending exactly once easy: the token is minted
/// when the sheet opens and reused by every retry, and a second tap while a
/// send is in flight does nothing.
final class ReportController extends ChangeNotifier {
  ReportController({
    required ReportRepository reports,
    required String listingId,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
    Random? random,
  }) : _reports = reports,
       _listingId = listingId,
       _generation = generation,
       _onUnauthorized = onUnauthorized,
       _requestId = _mintRequestId(random ?? Random());

  final ReportRepository _reports;
  final String _listingId;
  final CacheGeneration _generation;
  final VoidCallback _onUnauthorized;
  final ClientRequestId _requestId;

  ReportReason? _reason;
  String _note = '';
  ReportStatus _status = ReportStatus.editing;
  MutoFailure? _failure;
  bool _showIssue = false;

  ReportReason? get reason => _reason;
  ReportStatus get status => _status;
  MutoFailure? get failure => _failure;

  /// Withheld until a send is attempted, so the sheet does not tell someone
  /// off for a field they have not reached yet.
  ReportIssue? get issue {
    if (!_showIssue) return null;
    final reason = _reason;
    if (reason == null) return null;
    return ReportRules.validate(reason, _note);
  }

  bool get isSending => _status == ReportStatus.sending;

  bool get canSubmit => _reason != null && !isSending;

  void select(ReportReason reason) {
    if (_reason == reason) return;
    _reason = reason;
    _showIssue = false;
    _failure = null;
    notifyListeners();
  }

  void noteChanged(String value) {
    _note = value;
    if (_showIssue) notifyListeners();
  }

  /// True once the report has landed. False means the sheet stays open with
  /// something to say.
  Future<bool> submit() async {
    final reason = _reason;
    if (reason == null || isSending) return false;

    if (ReportRules.validate(reason, _note) != null) {
      _showIssue = true;
      notifyListeners();
      return false;
    }

    final generation = _generation.value;
    _status = ReportStatus.sending;
    _failure = null;
    notifyListeners();

    try {
      await _reports.submit(
        listingId: _listingId,
        reason: reason,
        note: ReportRules.normalizeNote(_note),
        requestId: _requestId,
      );
      if (!_generation.isCurrent(generation)) return false;
      _status = ReportStatus.sent;
      notifyListeners();
      return true;
    } on MutoFailure catch (failure) {
      if (!_generation.isCurrent(generation)) return false;
      _failure = failure;
      _status = ReportStatus.failed;
      if (failure is UnauthorizedFailure) _onUnauthorized();
      notifyListeners();
      return false;
    }
  }

  static ClientRequestId _mintRequestId(Random random) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = List.generate(
      3,
      (_) => random.nextInt(0xFFFFFFFF).toRadixString(36),
    ).join('-');
    return ClientRequestId('$stamp-$noise');
  }
}
