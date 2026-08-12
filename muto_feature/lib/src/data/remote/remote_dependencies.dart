import 'package:http/http.dart' as http;

import '../../application/muto_scope.dart';
import '../../config/muto_config.dart';
import '../local/preferences_draft_store.dart';
import '../local/preferences_search_history_store.dart';
import 'remote_api_client.dart';
import 'remote_auth.dart';
import 'remote_repositories.dart';

MutoDependencies createRemoteDependencies({
  required Uri baseUri,
  bool allowInsecureHttp = false,
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) {
  final validatedBaseUri = MutoConfig.remote(
    baseUri: baseUri,
    allowInsecureHttp: allowInsecureHttp,
  ).baseUri!;
  final auth = RemoteAuthState();
  final api = RemoteApiClient(
    baseUri: validatedBaseUri,
    auth: auth,
    client: client,
    timeout: timeout,
  );
  return MutoDependencies(
    backend: MutoBackend.remote,
    session: RemoteSessionRepository(api),
    listings: RemoteListingRepository(api),
    sellers: RemoteSellerRepository(api),
    favorites: RemoteFavoritesRepository(api),
    reports: RemoteReportRepository(api),
    reportOperations: RemoteReportOperationsRepository(api),
    images: RemoteImageRepository(api),
    imageLocator: RemoteImageLocator(api),
    drafts: const PreferencesDraftStore(),
    searchHistory: const PreferencesSearchHistoryStore(),
  );
}
