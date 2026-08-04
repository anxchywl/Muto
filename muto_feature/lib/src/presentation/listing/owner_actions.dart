import '../../domain/entities/listing_status.dart';
import '../../l10n/generated/muto_localizations.dart';

/// A status change the owner may make, worded for what it means rather than
/// for the state it moves to.
final class OwnerAction {
  const OwnerAction({
    required this.next,
    required this.label,
    this.isDestructive = false,
  });

  final ListingStatus next;
  final String label;
  final bool isDestructive;
}

/// Derived from the transition map, never from a hardcoded list, so a screen
/// cannot offer something the rules would refuse.
List<OwnerAction> ownerActionsFor(
  ListingStatus status,
  MutoLocalizations strings,
) {
  return [
    for (final next in status.allowedNext)
      OwnerAction(
        next: next,
        label: _labelFor(next, strings),
        isDestructive: next == ListingStatus.removed,
      ),
  ];
}

String _labelFor(ListingStatus next, MutoLocalizations strings) {
  return switch (next) {
    ListingStatus.reserved => strings.actionReserve,
    ListingStatus.sold => strings.actionMarkSold,
    ListingStatus.hidden => strings.actionHide,
    ListingStatus.removed => strings.actionRemove,
    ListingStatus.active => strings.actionMakeAvailable,
    ListingStatus.unknown => strings.actionMakeAvailable,
  };
}
