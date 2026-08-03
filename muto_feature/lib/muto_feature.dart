/// The embeddable NU student marketplace feature.
///
/// This file is the entire public surface of the package. Everything under
/// `src/` is private to the feature and must not be imported by a host.
library;

export 'src/application/muto_scope.dart' show MutoDependencies;
export 'src/config/muto_config.dart' show MutoBackend, MutoConfig;
export 'src/data/mock/sample_dependencies.dart' show createSampleDependencies;
export 'src/l10n/generated/muto_localizations.dart' show MutoLocalizations;
export 'src/l10n/muto_locales.dart' show MutoLocales;
export 'src/l10n/muto_localizations_scope.dart' show MutoLocalizationsScope;
export 'src/presentation/muto_feature_widget.dart'
    show MutoFeature, MutoHostSession;
