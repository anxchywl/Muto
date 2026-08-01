import 'entities/page.dart';

/// Everything a repository is allowed to fail with.
///
/// A failure carries structure, never a message — presentation maps the type
/// to a localized string, so no user-facing text exists in this layer.
sealed class MutoFailure implements Exception {
  const MutoFailure();
}

/// The session is no longer valid. The feature clears session state and asks
/// the host for a new token exactly once.
final class UnauthorizedFailure extends MutoFailure {
  const UnauthorizedFailure();
}

/// The listing exists but does not belong to this account any more.
final class ForbiddenFailure extends MutoFailure {
  const ForbiddenFailure();
}

/// No such listing, or it is hidden from this viewer.
final class NotFoundFailure extends MutoFailure {
  const NotFoundFailure();
}

/// The listing was removed. Distinct from [NotFoundFailure] so an old link can
/// say what happened instead of implying a mistake.
final class GoneFailure extends MutoFailure {
  const GoneFailure();
}

/// The listing moved on since it was loaded. [current] is the version now on
/// the server, when it is known.
final class ConflictFailure extends MutoFailure {
  const ConflictFailure({this.current});

  final Version? current;
}

final class RateLimitedFailure extends MutoFailure {
  const RateLimitedFailure({this.retryAfter});

  final Duration? retryAfter;
}

/// The request never completed — offline, timed out, or the connection dropped.
final class NetworkFailure extends MutoFailure {
  const NetworkFailure();
}

/// Anything else, including a response this build could not make sense of.
final class UnexpectedFailure extends MutoFailure {
  const UnexpectedFailure({this.statusCode});

  final int? statusCode;
}
