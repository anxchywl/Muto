import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:muto_feature/muto_feature.dart';

import 'dev/dev_gate.dart';

/// Standalone host. It owns the application shell — theme, locale and
/// lifecycle — and mounts the marketplace inside it.
///
/// This is development scaffolding. In a real host the session comes from that
/// host's own authentication, not from here.
class HostApp extends StatefulWidget {
  const HostApp({super.key, this.allowDevelopmentAccess, this.backend});

  /// Overrides the gate. Only a test sets this — the suite runs in debug mode,
  /// so the closed path is otherwise unreachable from a test binary.
  @visibleForTesting
  final bool? allowDevelopmentAccess;

  @visibleForTesting
  final MutoBackend? backend;

  @override
  State<HostApp> createState() => _HostAppState();
}

class _HostAppState extends State<HostApp> {
  late final MutoConfig _config = _createConfig();
  late final Future<MutoDependencies> _dependencies = _createDependencies();
  String _accessToken = configuredUserAccessToken;

  Future<void> _switchDevelopmentRole() async {
    if (!isDevelopmentAccessAllowed) return;
    final adminToken = _config.backend == MutoBackend.sample
        ? 'sample-admin-session'
        : configuredAdminAccessToken;
    final userToken = _config.backend == MutoBackend.sample
        ? 'sample-session'
        : configuredUserAccessToken;
    setState(() {
      _accessToken = _accessToken == adminToken ? userToken : adminToken;
    });
  }

  MutoConfig _createConfig() {
    if (widget.backend == MutoBackend.sample) return const MutoConfig.sample();
    if (!usesRemoteBackend) return const MutoConfig.sample();
    if (configuredApiBaseUrl.isEmpty) {
      throw StateError('MUTO_API_BASE_URL is required in remote mode');
    }
    return MutoConfig.remote(
      baseUri: Uri.parse(configuredApiBaseUrl),
      allowInsecureHttp: true,
    );
  }

  Future<MutoDependencies> _createDependencies() async {
    if (_config.backend == MutoBackend.sample) {
      return createSampleDependencies();
    }
    return createRemoteDependencies(
      baseUri: _config.baseUri!,
      allowInsecureHttp: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => MutoLocalizations.of(context).appTitle,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      supportedLocales: MutoLocales.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        MutoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // the placeholder session is the only way in here, so a build that may
      // not use it has nothing to show
      home: !(widget.allowDevelopmentAccess ?? isDevelopmentAccessAllowed)
          ? const _DevelopmentAccessClosed()
          : FutureBuilder<MutoDependencies>(
              future: _dependencies,
              builder: (context, snapshot) {
                // a failure here used to look exactly like loading, which hid a
                // broken asset path behind a spinner that never stopped
                if (snapshot.hasError) {
                  return _StartupFailure(error: snapshot.error!);
                }
                final dependencies = snapshot.data;
                if (dependencies == null) {
                  return const Scaffold(body: Center(child: AppLoader()));
                }
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: MutoFeature(
                    key: ValueKey<String>(_accessToken),
                    session: MutoHostSession(accessToken: _accessToken),
                    dependencies: dependencies,
                    config: _config,
                    onDevelopmentRoleSwitch: _switchDevelopmentRole,
                  ),
                );
              },
            ),
    );
  }
}

/// What a build with development access switched off shows.
///
/// The standalone host has no authentication of its own, so without the
/// placeholder session there is nothing it can legitimately open. Saying so is
/// the point: this host is not the thing that ships.
class _DevelopmentAccessClosed extends StatelessWidget {
  const _DevelopmentAccessClosed();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Text(
            'This host runs only as a debug build with development access '
            'enabled. Mount muto_feature inside a real host instead.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Development scaffolding: the standalone host has no way to recover from a
/// bad build, so it says what went wrong instead of spinning.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Text(
            '$error',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}
