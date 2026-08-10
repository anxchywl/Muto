import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:muto_ui/muto_ui.dart';

import '../application/muto_scope.dart';
import '../application/session_controller.dart';
import '../config/muto_config.dart';
import '../l10n/generated/muto_localizations.dart';
import '../l10n/muto_localizations_scope.dart';
import 'shell/muto_shell.dart';

/// A session handed to the feature by whatever is hosting it.
///
/// The token is used to resolve an identity and is never stored. The feature
/// asks for a new one through `onSessionExpired` rather than trying to refresh
/// anything itself.
final class MutoHostSession {
  const MutoHostSession({required this.accessToken})
    : assert(accessToken != '', 'a host session needs a token');

  final String accessToken;
}

/// The marketplace, ready to be mounted inside a host application.
///
/// It brings its own navigation, its own strings and its own state, and it
/// does not create a MaterialApp — theme, locale and lifecycle stay with the
/// host.
class MutoFeature extends StatefulWidget {
  const MutoFeature({
    super.key,
    required MutoHostSession session,
    required this.dependencies,
    required this.config,
    this.onSessionExpired,
  }) : _session = session;

  final MutoHostSession _session;
  final MutoDependencies dependencies;
  final MutoConfig config;
  final VoidCallback? onSessionExpired;

  @override
  State<MutoFeature> createState() => _MutoFeatureState();
}

class _MutoFeatureState extends State<MutoFeature> {
  @override
  Widget build(BuildContext context) {
    return MutoLocalizationsScope(
      // a new token builds a new scope, so nothing from the previous session
      // can survive into this one
      child: MutoScope(
        key: ValueKey<String>(widget._session.accessToken),
        dependencies: widget.dependencies,
        onSessionExpired: widget.onSessionExpired,
        child: _SessionGate(accessToken: widget._session.accessToken),
      ),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.accessToken});

  final String accessToken;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(MutoScope.of(context).session.resolve(widget.accessToken));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = MutoScope.of(context).session;
    final strings = MutoLocalizations.of(context);

    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        switch (session.status) {
          case SessionStatus.ready:
            // the shell is the first route of the feature's own navigator, so
            // the editor can cover the tabs rather than open inside one
            return Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const MutoShell(),
              ),
            );
          case SessionStatus.idle:
          case SessionStatus.resolving:
            return Scaffold(
              body: Center(
                child: Semantics(
                  label: strings.startingUp,
                  child: const AppLoader(),
                ),
              ),
            );
          case SessionStatus.expired:
            return Scaffold(
              body: StateMessage(
                icon: AppIcons.lock,
                title: strings.sessionExpiredTitle,
                message: strings.sessionExpiredMessage,
              ),
            );
          case SessionStatus.failed:
            return Scaffold(
              body: StateMessage(
                icon: AppIcons.alertCircle,
                title: strings.sessionFailedTitle,
                message: strings.errorGeneric,
                actionLabel: strings.actionRetry,
                onAction: () => unawaited(session.resolve(widget.accessToken)),
              ),
            );
        }
      },
    );
  }
}
