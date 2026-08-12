final class RemoteAuthState {
  static int _nextSessionNamespace = 0;

  String? _accessToken;
  int _sessionNamespace = 0;

  String? get accessToken => _accessToken;
  int get sessionNamespace => _sessionNamespace;

  void beginSession(String accessToken) {
    if (_accessToken == accessToken) return;
    _accessToken = accessToken;
    _sessionNamespace = ++_nextSessionNamespace;
  }

  void clearIfCurrent(String accessToken) {
    if (_accessToken == accessToken) _accessToken = null;
  }
}
