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

const String _configuredBackend = String.fromEnvironment(
  'MUTO_BACKEND',
  defaultValue: 'sample',
);

const String configuredApiBaseUrl = String.fromEnvironment('MUTO_API_BASE_URL');

const String configuredUserAccessToken = String.fromEnvironment(
  'MUTO_ACCESS_TOKEN',
  defaultValue: developmentSessionToken,
);

const String configuredAdminAccessToken = String.fromEnvironment(
  'MUTO_ADMIN_ACCESS_TOKEN',
  defaultValue: 'sample-admin-session',
);

bool get usesRemoteBackend {
  switch (_configuredBackend) {
    case 'sample':
      return false;
    case 'remote':
      return true;
    default:
      throw StateError('MUTO_BACKEND must be sample or remote');
  }
}
