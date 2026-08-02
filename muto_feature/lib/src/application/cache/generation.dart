/// Guards against a response arriving after the account it was requested for
/// has gone away.
///
/// A load captures the generation when it starts and refuses to write its
/// result if the generation has moved on since. Without this, a slow request
/// begun as one student can land in the next student's session.
final class CacheGeneration {
  int _value = 0;

  int get value => _value;

  int bump() => ++_value;

  bool isCurrent(int captured) => captured == _value;
}
