/// Which data source the build was assembled with.
///
/// This is decided once, where the feature is constructed, and never inferred
/// deeper in the tree.
enum MutoBackend { sample, remote }

final class MutoConfig {
  const MutoConfig._({required this.backend, this.baseUri});

  const MutoConfig.sample() : this._(backend: MutoBackend.sample);

  MutoConfig.remote({required Uri baseUri, bool allowInsecureHttp = false})
    : backend = MutoBackend.remote,
      baseUri = _normalizedBaseUri(baseUri, allowInsecureHttp);

  final MutoBackend backend;
  final Uri? baseUri;

  /// Drives the indicator that says nothing on screen came from a server. It
  /// is derived, never set by hand, so it cannot drift from the truth.
  bool get usesSampleData => backend == MutoBackend.sample;

  static Uri _normalizedBaseUri(Uri value, bool allowInsecureHttp) {
    if (!value.hasScheme || !value.hasAuthority) {
      throw ArgumentError.value(value, 'baseUri', 'must be an absolute URI');
    }
    if (value.scheme != 'http' && value.scheme != 'https') {
      throw ArgumentError.value(value, 'baseUri', 'must use HTTP or HTTPS');
    }
    if (value.scheme == 'http' && !allowInsecureHttp) {
      throw ArgumentError.value(
        value,
        'baseUri',
        'must use HTTPS unless insecure local development is explicit',
      );
    }
    if (value.userInfo.isNotEmpty || value.hasQuery || value.hasFragment) {
      throw ArgumentError.value(
        value,
        'baseUri',
        'must not contain credentials, a query, or a fragment',
      );
    }
    return value.replace(path: value.path.replaceFirst(RegExp(r'/+$'), ''));
  }
}
