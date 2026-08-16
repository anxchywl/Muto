import 'package:flutter/foundation.dart';

import '../domain/entities/listing.dart';
import '../domain/failures.dart';
import '../domain/repositories/favorites_repository.dart';
import 'cache/generation.dart';

/// Which listings the signed-in student has saved.
///
/// Kept apart from the favorites feed because the heart on a card has to be
/// right long before that feed is ever opened.
final class FavoritesController extends ChangeNotifier {
  FavoritesController({
    required FavoritesRepository repository,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
  }) : _repository = repository,
       _generation = generation,
       _onUnauthorized = onUnauthorized;

  final FavoritesRepository _repository;
  final CacheGeneration _generation;
  final VoidCallback _onUnauthorized;

  Set<String> _saved = <String>{};
  final Map<String, Listing> _optimisticAdds = <String, Listing>{};
  final Set<String> _inFlight = <String>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool isSaved(String listingId) => _saved.contains(listingId);

  bool isBusy(String listingId) => _inFlight.contains(listingId);

  List<Listing> get optimisticListings => _optimisticAdds.values.toList();

  Future<void> load() async {
    final generation = _generation.value;
    try {
      final saved = await _repository.savedIds();
      if (!_generation.isCurrent(generation)) return;
      _saved = Set<String>.of(saved);
      _optimisticAdds.removeWhere((id, _) => _saved.contains(id));
      _loaded = true;
      notifyListeners();
    } on MutoFailure catch (failure) {
      if (failure is UnauthorizedFailure) _onUnauthorized();
    }
  }

  /// Flips the heart at once and puts it back if the write fails, so the
  /// control never sits there doing nothing while a request is in flight.
  Future<void> toggle(String listingId, {Listing? listing}) async {
    if (_inFlight.contains(listingId)) return;

    final wasSaved = _saved.contains(listingId);
    final generation = _generation.value;

    _inFlight.add(listingId);
    if (wasSaved) {
      _saved.remove(listingId);
      _optimisticAdds.remove(listingId);
    } else {
      _saved.add(listingId);
      if (listing != null) _optimisticAdds[listingId] = listing;
    }
    notifyListeners();

    try {
      if (wasSaved) {
        await _repository.remove(listingId);
      } else {
        await _repository.add(listingId);
      }
    } on MutoFailure catch (failure) {
      if (!_generation.isCurrent(generation)) return;
      if (wasSaved) {
        _saved.add(listingId);
        if (listing != null) _optimisticAdds[listingId] = listing;
      } else {
        _saved.remove(listingId);
        _optimisticAdds.remove(listingId);
      }
      if (failure is UnauthorizedFailure) _onUnauthorized();
    } finally {
      if (_generation.isCurrent(generation)) {
        _inFlight.remove(listingId);
        notifyListeners();
      }
    }
  }
}
