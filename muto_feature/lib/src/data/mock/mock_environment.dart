import '../../domain/failures.dart';

/// Latency the mocks pretend to have.
///
/// Real timings are what make loading states, in-flight de-duplication and
/// cancellation visible during development. Tests set this to zero.
final class MockLatency {
  const MockLatency({
    this.read = const Duration(milliseconds: 320),
    this.write = const Duration(milliseconds: 520),
    this.upload = const Duration(milliseconds: 900),
  });

  const MockLatency.none()
    : read = Duration.zero,
      write = Duration.zero,
      upload = Duration.zero;

  final Duration read;
  final Duration write;
  final Duration upload;
}

/// Failures the mocks can be told to produce, so every branch of the error
/// policy can be exercised without a server to break.
final class MockFaults {
  MockFaults();

  /// Every call fails as if the device had no connection.
  bool offline = false;

  /// The next write fails with a version conflict, then clears itself.
  bool conflictOnNextWrite = false;

  /// Every call fails as if the session had expired.
  bool sessionExpired = false;

  void checkReadable() {
    if (sessionExpired) throw const UnauthorizedFailure();
    if (offline) throw const NetworkFailure();
  }

  void checkWritable() {
    checkReadable();
  }

  bool consumeConflict() {
    if (!conflictOnNextWrite) return false;
    conflictOnNextWrite = false;
    return true;
  }
}
