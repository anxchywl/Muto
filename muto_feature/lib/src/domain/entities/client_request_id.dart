/// Idempotency token for a create.
///
/// One is minted per editor session and reused by every retry, so a publish
/// that times out and is tried again produces one listing rather than two.
final class ClientRequestId {
  const ClientRequestId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientRequestId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ClientRequestId($value)';
}
