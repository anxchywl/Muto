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
