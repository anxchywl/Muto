import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/entities/client_request_id.dart';
import '../domain/entities/image_ref.dart';
import '../domain/entities/listing.dart';
import '../domain/entities/page.dart';
import '../domain/failures.dart';
import '../domain/repositories/draft_store.dart';
import '../domain/repositories/image_repository.dart';
import '../domain/repositories/listing_repository.dart';
import '../domain/validation/image_rules.dart';
import '../domain/validation/listing_rules.dart';
import 'cache/generation.dart';
import 'cache/listing_cache.dart';

/// Drives one pass through the editor, whether that is a new listing or a
/// change to an existing one.
///
/// The request id is minted once and kept with the draft. A publish that times
/// out and is tried again therefore reaches the same identity, which is what
/// stops one hesitant student from creating two listings.
final class ListingEditorController extends ChangeNotifier {
  ListingEditorController({
    required ListingRepository listings,
    required ImageRepository images,
    required DraftStore drafts,
    required ListingCache cache,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
    required String userId,
    required ListingDraft initial,
    ClientRequestId? requestId,
    this.editingListingId,
    this.expectedVersion,
    Random? random,
  }) : _listings = listings,
       _images = images,
       _drafts = drafts,
       _cache = cache,
       _generation = generation,
       _onUnauthorized = onUnauthorized,
       _userId = userId,
       _draft = initial,
       _requestId = requestId ?? _mintRequestId(random ?? Random.secure());

  /// A blank listing, with the defaults a student is most likely to want.
  factory ListingEditorController.blank({
    required ListingRepository listings,
    required ImageRepository images,
    required DraftStore drafts,
    required ListingCache cache,
    required CacheGeneration generation,
    required VoidCallback onUnauthorized,
    required String userId,
    required ListingDraft blank,
    Random? random,
  }) {
    return ListingEditorController(
      listings: listings,
      images: images,
      drafts: drafts,
      cache: cache,
      generation: generation,
      onUnauthorized: onUnauthorized,
      userId: userId,
      initial: blank,
      random: random,
    );
  }

  final ListingRepository _listings;
  final ImageRepository _images;
  final DraftStore _drafts;
  final ListingCache _cache;
  final CacheGeneration _generation;
  final VoidCallback _onUnauthorized;
  final String _userId;
  final ClientRequestId _requestId;

  final String? editingListingId;
  final Version? expectedVersion;

  ListingDraft _draft;
  bool _isSaving = false;
  bool _isStagingImage = false;
  bool _showIssues = false;
  MutoFailure? _failure;
  ImageIssue? _imageIssue;

  ListingDraft get draft => _draft;
  bool get isSaving => _isSaving;
  bool get isStagingImage => _isStagingImage;
  MutoFailure? get failure => _failure;
  ImageIssue? get imageIssue => _imageIssue;
  bool get isEditing => editingListingId != null;

  ClientRequestId get requestId => _requestId;

  ListingValidation get validation => ListingRules.validate(_draft);

  /// Issues stay quiet until the student has tried to publish, so a form does
  /// not scold someone for not having finished typing yet.
  ListingValidation get visibleIssues =>
      _showIssues ? validation : const ListingValidation.valid();

  bool get canAddImage => _draft.images.length < ListingRules.maxImages;

  void edit(ListingDraft Function(ListingDraft current) change) {
    _draft = change(_draft);
    _failure = null;
    notifyListeners();
    _persist();
  }

  Future<void> addImage(StagedImage image) async {
    if (!canAddImage) {
      _imageIssue = null;
      _failure = null;
      notifyListeners();
      return;
    }

    final issue = ImageRules.check(image);
    if (issue != null) {
      _imageIssue = issue;
      notifyListeners();
      return;
    }

    final generation = _generation.value;
    _isStagingImage = true;
    _imageIssue = null;
    _failure = null;
    notifyListeners();

    try {
      final ref = await _images.stage(image);
      if (!_generation.isCurrent(generation)) return;
      _draft = _draft.copyWith(images: [..._draft.images, ref]);
      _persist();
    } on MutoFailure catch (failure) {
      if (!_generation.isCurrent(generation)) return;
      _record(failure);
    } finally {
      if (_generation.isCurrent(generation)) {
        _isStagingImage = false;
        notifyListeners();
      }
    }
  }

  void removeImage(ImageRef ref) {
    _draft = _draft.copyWith(
      images: [
        for (final image in _draft.images)
          if (image != ref) image,
      ],
    );
    notifyListeners();
    _persist();
  }

  /// Publishes or saves. Returns null when nothing was written, so a screen
  /// only leaves the editor on a real result.
  Future<Listing?> submit() async {
    final normalized = ListingRules.normalize(_draft);
    if (!ListingRules.validate(normalized).isValid) {
      _showIssues = true;
      notifyListeners();
      return null;
    }
    if (_isSaving) return null;

    final generation = _generation.value;
    _isSaving = true;
    _failure = null;
    notifyListeners();

    try {
      final id = editingListingId;
      final expected = expectedVersion;
      final saved = id == null || expected == null
          ? await _listings.create(normalized, requestId: _requestId)
          : await _listings.update(id, normalized, expected: expected);

      if (!_generation.isCurrent(generation)) return null;
      _cache.patch(saved);
      await _drafts.clear(_userId);
      return saved;
    } on MutoFailure catch (failure) {
      if (!_generation.isCurrent(generation)) return null;
      _record(failure);
      return null;
    } finally {
      if (_generation.isCurrent(generation)) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> discard() async {
    await _drafts.clear(_userId);
  }

  void _record(MutoFailure failure) {
    _failure = failure;
    if (failure is UnauthorizedFailure) _onUnauthorized();
  }

  void _persist() {
    // best effort: losing a draft is a small annoyance, but failing to save one
    // must never interrupt typing
    unawaited(
      _drafts
          .write(
            _userId,
            StoredDraft(
              draft: _draft,
              requestId: _requestId,
              editingListingId: editingListingId,
              expectedVersion: expectedVersion,
            ),
          )
          .catchError((Object _) {}),
    );
  }

  static ClientRequestId _mintRequestId(Random random) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = List.generate(
      3,
      (_) => random.nextInt(0xFFFFFFFF).toRadixString(36),
    ).join('-');
    return ClientRequestId('$stamp-$noise');
  }
}
