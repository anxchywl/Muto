import 'package:app_ui/app_ui.dart';

import '../../domain/entities/listing_status.dart';
import '../../l10n/generated/muto_localizations.dart';

/// What an action's icon does once the move lands.
///
/// Each one acts out its own verb rather than every button collapsing into the
/// same tick: the point of a bar of five is that they are five different
/// things, and the moment of confirmation is the best chance to say so.
enum OwnerActionMotion {
  /// The clock's hand goes the whole way round.
  sweep,

  /// A second tick lands beside the first.
  confirm,

  /// The eye closes and is struck through.
  close,

  /// The arrows come back round to where they started.
  spin,

  /// Nothing at all — the screen is on its way out anyway.
  none,
}

/// A status change the owner may make, worded for what it means rather than
/// for the state it moves to.
final class OwnerAction {
  const OwnerAction({
    required this.next,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.motion,
    this.isDestructive = false,
  });

  final ListingStatus next;

  /// The full sentence, used where there is room to read it — a tooltip, a
  /// screen reader, a confirmation.
  final String label;

  /// One or two words, for the bar itself, where a caption sits under an icon
  /// and a full sentence would wrap into an unreadable stack.
  final String shortLabel;

  final AppIconData icon;

  /// How [icon] behaves at the moment this move lands.
  final OwnerActionMotion motion;

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
        shortLabel: _shortLabelFor(next, strings),
        icon: _iconFor(next),
        motion: _motionFor(next),
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

String _shortLabelFor(ListingStatus next, MutoLocalizations strings) {
  return switch (next) {
    ListingStatus.reserved => strings.actionShortReserve,
    ListingStatus.sold => strings.actionShortSold,
    ListingStatus.hidden => strings.actionShortHide,
    ListingStatus.removed => strings.actionShortRemove,
    ListingStatus.active => strings.actionShortRelist,
    ListingStatus.unknown => strings.actionShortRelist,
  };
}

OwnerActionMotion _motionFor(ListingStatus next) {
  return switch (next) {
    ListingStatus.reserved => OwnerActionMotion.sweep,
    ListingStatus.sold => OwnerActionMotion.confirm,
    ListingStatus.hidden => OwnerActionMotion.close,
    ListingStatus.active => OwnerActionMotion.spin,
    // removing closes the screen, so there is nobody left to watch
    ListingStatus.removed => OwnerActionMotion.none,
    ListingStatus.unknown => OwnerActionMotion.none,
  };
}

AppIconData _iconFor(ListingStatus next) {
  return switch (next) {
    ListingStatus.reserved => AppIcons.time,
    ListingStatus.sold => AppIcons.check,
    ListingStatus.hidden => AppIcons.visibilityOff,
    ListingStatus.removed => AppIcons.delete,
    ListingStatus.active => AppIcons.refresh,
    ListingStatus.unknown => AppIcons.refresh,
  };
}
