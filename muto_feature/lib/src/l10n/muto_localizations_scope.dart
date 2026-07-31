import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/muto_localizations.dart';
import 'muto_locales.dart';

/// Installs the feature's own localizations over whatever the host provides.
///
/// A host is not obliged to register our delegate, so the feature scopes its
/// own and derives the language from the host's ambient locale.
class MutoLocalizationsScope extends StatelessWidget {
  const MutoLocalizationsScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: MutoLocales.resolve(Localizations.maybeLocaleOf(context)),
      delegates: const <LocalizationsDelegate<Object>>[
        MutoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: child,
    );
  }
}
