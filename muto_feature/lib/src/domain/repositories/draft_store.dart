import '../entities/client_request_id.dart';
import '../entities/listing.dart';
import '../entities/page.dart';

/// An unfinished listing, kept so a student who leaves the editor does not
/// lose what they typed.
final class StoredDraft {
  const StoredDraft({
    required this.draft,
    required this.requestId,
    this.editingListingId,
    this.expectedVersion,
  });

  final ListingDraft draft;

  /// Minted once and reused by every retry, so publishing twice cannot create
  /// two listings.
  final ClientRequestId requestId;

  /// Set when the draft is an edit rather than something new.
  final String? editingListingId;

  final Version? expectedVersion;
}

/// Local, per-account storage for the editor.
///
/// The account is named on every call rather than held inside, so one
/// student's unfinished listing can never be read under another's session.
abstract interface class DraftStore {
  Future<StoredDraft?> read(String userId);

  Future<void> write(String userId, StoredDraft draft);

  Future<void> clear(String userId);
}
