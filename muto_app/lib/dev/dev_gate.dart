import 'package:flutter/foundation.dart';

const bool _devAccessRequested = bool.fromEnvironment(
  'ENABLE_DEV_ACCESS',
  defaultValue: true,
);

/// Whether this build may open the marketplace without a real host session.
///
/// Both halves must hold. A release build cannot turn this on however the
/// define is set, which is what stops a shipped binary from carrying a
/// development door.
bool get isDevelopmentAccessAllowed => developmentAccessAllowed(
  isDebugMode: kDebugMode,
  requested: _devAccessRequested,
);

@visibleForTesting
bool developmentAccessAllowed({
  required bool isDebugMode,
  required bool requested,
}) => isDebugMode && requested;

/// A placeholder session for the standalone host.
///
/// It is not a credential and it authorises nothing: the sample repositories
/// accept any non-empty string. There is deliberately nothing here that could
/// be mistaken for a secret or leak into a commit.
const String developmentSessionToken = 'sample-session';
