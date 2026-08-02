import 'dart:math';
import 'dart:typed_data';

import '../../domain/entities/image_ref.dart';
import '../../domain/failures.dart';
import '../../domain/repositories/image_locator.dart';
import '../../domain/repositories/image_repository.dart';
import '../../domain/validation/image_rules.dart';
import 'mock_environment.dart';

/// Bytes for images staged during this session.
///
/// Nothing here is written to disk: a staged image that is never redeemed
/// disappears with the session, which is the behaviour the real staging step
/// is specified to have.
final class StagedImageStore {
  final Map<String, Uint8List> _bytes = {};

  void put(String id, Uint8List bytes) => _bytes[id] = bytes;

  Uint8List? get(String id) => _bytes[id];

  void clear() => _bytes.clear();
}

final class MockImageRepository implements ImageRepository {
  MockImageRepository({
    required StagedImageStore store,
    this.latency = const MockLatency(),
    MockFaults? faults,
    Random? random,
  }) : _store = store,
       faults = faults ?? MockFaults(),
       _random = random ?? Random(20260804);

  final StagedImageStore _store;
  final MockLatency latency;
  final MockFaults faults;
  final Random _random;

  @override
  Future<ImageRef> stage(StagedImage image) async {
    final issue = ImageRules.check(image);
    if (issue != null) throw const UnexpectedFailure(statusCode: 422);

    await Future<void>.delayed(latency.upload);
    faults.checkWritable();

    final id = 'stg_${_random.nextInt(0x7FFFFFFF).toRadixString(16)}';
    _store.put(id, image.bytes);
    return ImageRef(id: id, version: 'v1');
  }
}

/// Resolves a reference either to a staged image held in memory or to one of
/// the bundled sample pictures. An id with neither resolves to null so the
/// caller shows its failure state.
final class MockImageLocator implements ImageLocator {
  const MockImageLocator({
    required StagedImageStore store,
    required this.bundled,
  }) : _store = store;

  final StagedImageStore _store;

  /// Sample image ids that exist in the bundle.
  final Set<String> bundled;

  @override
  ImageLocation? locate(ImageRef ref) {
    final staged = _store.get(ref.id);
    if (staged != null) return MemoryImageLocation(staged);
    if (bundled.contains(ref.id)) {
      return BundledImageLocation('assets/sample/images/${ref.id}.png');
    }
    return null;
  }
}
