import 'package:flutter/widgets.dart';

import '../domain/repositories/draft_store.dart';
import '../domain/repositories/favorites_repository.dart';
import '../domain/repositories/image_locator.dart';
import '../domain/repositories/image_repository.dart';
import '../domain/repositories/listing_repository.dart';
import '../domain/repositories/session_repository.dart';
import 'cache/generation.dart';
import 'cache/listing_cache.dart';
import 'listing_feed_controller.dart';
import 'session_controller.dart';

/// Everything the feature needs from the outside world, gathered in one place
/// so choosing sample data or a real backend is a single decision made once.
final class MutoDependencies {
  const MutoDependencies({
    required this.session,
    required this.listings,
    required this.favorites,
    required this.images,
    required this.imageLocator,
    required this.drafts,
  });

  final SessionRepository session;
  final ListingRepository listings;
  final FavoritesRepository favorites;
  final ImageRepository images;
  final ImageLocator imageLocator;
  final DraftStore drafts;
}

/// Owns the controllers for one mounting of the feature.
///
/// They are deliberately not global. Rebuilding the scope for a new session
/// makes it structurally impossible for one account's state to be read under
/// another's, instead of relying on every store remembering to clear itself.
class MutoScope extends StatefulWidget {
  const MutoScope({
    super.key,
    required this.dependencies,
    required this.child,
    this.onSessionExpired,
  });

  final MutoDependencies dependencies;
  final Widget child;
  final VoidCallback? onSessionExpired;

  static MutoScopeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MutoScopeData>();
    assert(scope != null, 'no MutoScope above this widget');
    return scope!;
  }

  @override
  State<MutoScope> createState() => _MutoScopeState();
}

class _MutoScopeState extends State<MutoScope> {
  late final CacheGeneration _generation;
  late final ListingCache _cache;
  late final SessionController _session;
  late final ListingFeedController _browse;
  late final ListingFeedController _mine;
  late final ListingFeedController _favorites;

  @override
  void initState() {
    super.initState();
    _generation = CacheGeneration();
    _cache = ListingCache();
    _session = SessionController(
      repository: widget.dependencies.session,
      generation: _generation,
      cache: _cache,
      onSessionExpired: widget.onSessionExpired,
    );
    _browse = _feed();
    _mine = _feed();
    _favorites = _feed();
  }

  ListingFeedController _feed() => ListingFeedController(
    cache: _cache,
    generation: _generation,
    onUnauthorized: _session.reportExpired,
  );

  @override
  void dispose() {
    _favorites.dispose();
    _mine.dispose();
    _browse.dispose();
    _session.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MutoScopeData(
      dependencies: widget.dependencies,
      generation: _generation,
      cache: _cache,
      session: _session,
      browse: _browse,
      mine: _mine,
      favorites: _favorites,
      child: widget.child,
    );
  }
}

class MutoScopeData extends InheritedWidget {
  const MutoScopeData({
    super.key,
    required this.dependencies,
    required this.generation,
    required this.cache,
    required this.session,
    required this.browse,
    required this.mine,
    required this.favorites,
    required super.child,
  });

  final MutoDependencies dependencies;
  final CacheGeneration generation;
  final ListingCache cache;
  final SessionController session;
  final ListingFeedController browse;
  final ListingFeedController mine;
  final ListingFeedController favorites;

  @override
  bool updateShouldNotify(MutoScopeData oldWidget) =>
      !identical(session, oldWidget.session) ||
      !identical(cache, oldWidget.cache);
}
