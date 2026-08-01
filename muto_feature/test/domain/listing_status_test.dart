import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/domain/entities/listing_status.dart';

/// Every ordered pair the machine must allow. Anything not listed here has to
/// be refused, which is what the exhaustive test below checks.
const Map<ListingStatus, Set<ListingStatus>> _expected = {
  ListingStatus.active: {
    ListingStatus.reserved,
    ListingStatus.sold,
    ListingStatus.hidden,
    ListingStatus.removed,
  },
  ListingStatus.reserved: {
    ListingStatus.active,
    ListingStatus.sold,
    ListingStatus.removed,
  },
  ListingStatus.sold: {ListingStatus.active, ListingStatus.removed},
  ListingStatus.hidden: {ListingStatus.active, ListingStatus.removed},
  ListingStatus.removed: <ListingStatus>{},
  ListingStatus.unknown: <ListingStatus>{},
};

void main() {
  group('ListingStatus transitions', () {
    test('every ordered pair matches the specification exactly', () {
      for (final from in ListingStatus.values) {
        for (final to in ListingStatus.values) {
          final allowed = _expected[from]!.contains(to);
          expect(
            from.canTransitionTo(to),
            allowed,
            reason:
                '${from.name} -> ${to.name} should be '
                '${allowed ? 'allowed' : 'refused'}',
          );
        }
      }
    });

    test('removed is terminal', () {
      expect(ListingStatus.removed.isTerminal, isTrue);
      expect(ListingStatus.removed.allowedNext, isEmpty);
    });

    test('an unrecognised status offers no actions', () {
      expect(ListingStatus.unknown.isTerminal, isTrue);
      expect(ListingStatus.unknown.isEditable, isFalse);
      expect(ListingStatus.unknown.isVisibleInBrowse, isFalse);
    });

    test('a sold listing can be relisted', () {
      expect(ListingStatus.sold.canTransitionTo(ListingStatus.active), isTrue);
    });

    test('no status can transition to itself', () {
      for (final status in ListingStatus.values) {
        expect(status.canTransitionTo(status), isFalse, reason: status.name);
      }
    });
  });

  group('ListingStatus visibility', () {
    test('only active and reserved appear in browse', () {
      expect(ListingStatus.active.isVisibleInBrowse, isTrue);
      expect(ListingStatus.reserved.isVisibleInBrowse, isTrue);
      expect(ListingStatus.sold.isVisibleInBrowse, isFalse);
      expect(ListingStatus.hidden.isVisibleInBrowse, isFalse);
      expect(ListingStatus.removed.isVisibleInBrowse, isFalse);
    });

    test('the owner sees everything except a removed listing', () {
      for (final status in ListingStatus.values) {
        expect(
          status.isVisibleToOwner,
          status != ListingStatus.removed,
          reason: status.name,
        );
      }
    });

    test('content is editable only while in circulation', () {
      expect(ListingStatus.active.isEditable, isTrue);
      expect(ListingStatus.reserved.isEditable, isTrue);
      expect(ListingStatus.hidden.isEditable, isTrue);
      expect(ListingStatus.sold.isEditable, isFalse);
      expect(ListingStatus.removed.isEditable, isFalse);
    });
  });

  group('ListingStatus wire values', () {
    test('round-trips every known status', () {
      for (final status in ListingStatus.values) {
        expect(ListingStatus.fromWire(status.wireValue), status);
      }
    });

    test('maps an unrecognised or absent value to unknown', () {
      expect(ListingStatus.fromWire('archived'), ListingStatus.unknown);
      expect(ListingStatus.fromWire(null), ListingStatus.unknown);
    });
  });
}
