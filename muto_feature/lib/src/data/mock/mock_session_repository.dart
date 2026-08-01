import '../../domain/entities/identity.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/session_repository.dart';
import 'mock_environment.dart';

/// Stands in for the session endpoint.
///
/// It needs no credentials of any kind, which is the point: development never
/// carries a password or a token that could be committed by accident.
final class MockSessionRepository implements SessionRepository {
  MockSessionRepository({
    required Identity identity,
    this.latency = const MockLatency(),
    MockFaults? faults,
  }) : _identity = identity,
       faults = faults ?? MockFaults();

  Identity _identity;
  final MockLatency latency;
  final MockFaults faults;

  /// Lets development switch to an unverified student and check that
  /// publishing and contact stay closed.
  set identity(Identity value) => _identity = value;

  @override
  Future<Identity> resolve(String accessToken) async {
    await Future<void>.delayed(latency.read);
    if (faults.sessionExpired || accessToken.trim().isEmpty) {
      throw const UnauthorizedFailure();
    }
    if (faults.offline) throw const NetworkFailure();
    return _identity;
  }
}
