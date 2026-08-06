/// A seller, as much of one as a marketplace without ratings needs.
///
/// There is no reputation here on purpose: what a buyer can usefully know is
/// who the seller is, that the university verified them, and what else they
/// have listed.
final class SellerProfile {
  const SellerProfile({
    required this.sellerId,
    required this.displayName,
    required this.isVerified,
    required this.activeListingCount,
    required this.firstListedAt,
  });

  final String sellerId;
  final String displayName;

  /// Asserted by whatever resolved the profile. The client never decides it.
  final bool isVerified;

  final int activeListingCount;

  /// When their first listing appeared, which is the only history a student
  /// can see about someone else.
  final DateTime firstListedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SellerProfile &&
          other.sellerId == sellerId &&
          other.displayName == displayName &&
          other.isVerified == isVerified &&
          other.activeListingCount == activeListingCount &&
          other.firstListedAt == firstListedAt;

  @override
  int get hashCode => Object.hash(
    sellerId,
    displayName,
    isVerified,
    activeListingCount,
    firstListedAt,
  );
}
