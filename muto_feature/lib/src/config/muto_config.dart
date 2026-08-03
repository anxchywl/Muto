/// Which data source the build was assembled with.
///
/// This is decided once, where the feature is constructed, and never inferred
/// deeper in the tree.
enum MutoBackend { sample, remote }

final class MutoConfig {
  const MutoConfig({required this.backend});

  const MutoConfig.sample() : backend = MutoBackend.sample;

  final MutoBackend backend;

  /// Drives the indicator that says nothing on screen came from a server. It
  /// is derived, never set by hand, so it cannot drift from the truth.
  bool get usesSampleData => backend == MutoBackend.sample;
}
