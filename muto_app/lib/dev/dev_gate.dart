import 'package:flutter/foundation.dart';

const bool _devAccessRequested = bool.fromEnvironment(
  'ENABLE_DEV_ACCESS',
  defaultValue: true,
);
const bool _standaloneReleaseAccess = bool.fromEnvironment(
  'ALLOW_STANDALONE_DEV_ACCESS',
  defaultValue: false,
);

/// Whether this build may open the marketplace without a real host session.
///
/// Release access requires an explicit development-build define.
bool get isDevelopmentAccessAllowed => developmentAccessAllowed(
  isDebugMode: kDebugMode,
  requested: _devAccessRequested,
  allowReleaseAccess: _standaloneReleaseAccess,
);

@visibleForTesting
bool developmentAccessAllowed({
  required bool isDebugMode,
  required bool requested,
  bool allowReleaseAccess = false,
}) => requested && (isDebugMode || allowReleaseAccess);

/// A local development session for the standalone host.
///
/// The backend development adapter resolves this token to the configured
/// development account. It is deliberately not a production credential.
const String developmentSessionToken = 'muto-local-only';

const String _configuredBackend = String.fromEnvironment(
  'MUTO_BACKEND',
  defaultValue: 'remote',
);

const String configuredApiBaseUrl = String.fromEnvironment('MUTO_API_BASE_URL');

const String configuredUserAccessToken = String.fromEnvironment(
  'MUTO_ACCESS_TOKEN',
  defaultValue: developmentSessionToken,
);

const String configuredAdminAccessToken = String.fromEnvironment(
  'MUTO_ADMIN_ACCESS_TOKEN',
  defaultValue: 'muto-admin-local-only',
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
