import 'listing_status.dart';
import 'report_reason.dart';

final class OperationalReport {
  const OperationalReport({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingStatus,
    required this.reason,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final ListingStatus listingStatus;
  final ReportReason reason;
  final String? note;
  final DateTime createdAt;
}
