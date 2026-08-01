import '../entities/identity.dart';

/// Resolves the host's access token into the student the server says it
/// belongs to.
///
/// The feature never inspects the token, never stores it, and never infers an
/// identity or a verification state from it.
abstract interface class SessionRepository {
  Future<Identity> resolve(String accessToken);
}
