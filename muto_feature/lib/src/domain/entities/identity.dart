/// The signed-in student, as resolved by the host session.
///
/// [isVerified] is asserted by the server and is the gate for publishing and
/// for seeing seller contact details. The client never decides it.
final class Identity {
  const Identity({
    required this.userId,
    required this.displayName,
    required this.isVerified,
  });

  final String userId;
  final String displayName;
  final bool isVerified;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Identity &&
          other.userId == userId &&
          other.displayName == displayName &&
          other.isVerified == isVerified;

  @override
  int get hashCode => Object.hash(userId, displayName, isVerified);
}
