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
  const HostApp({super.key});

  @override
  State<HostApp> createState() => _HostAppState();
}

class _HostAppState extends State<HostApp> {
  late final Future<MutoDependencies> _dependencies =
      createSampleDependencies();

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
      home: FutureBuilder<MutoDependencies>(
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
          return MutoFeature(
            session: MutoHostSession(accessToken: developmentSessionToken),
            dependencies: dependencies,
            config: const MutoConfig.sample(),
          );
        },
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
