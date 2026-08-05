import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muto_feature/src/data/mock/mock_environment.dart';
import 'package:muto_feature/src/data/mock/mock_image_repository.dart';
import 'package:muto_feature/src/domain/entities/image_ref.dart';
import 'package:muto_feature/src/domain/failures.dart';
import 'package:muto_feature/src/domain/repositories/image_locator.dart';
import 'package:muto_feature/src/domain/repositories/image_repository.dart';
import 'package:muto_feature/src/domain/validation/image_rules.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

Uint8List _png() =>
    File('assets/sample/images/sample-01.png').readAsBytesSync();

StagedImage _staged({
  Uint8List? bytes,
  int width = 600,
  int height = 450,
  String mimeType = 'image/png',
}) {
  return StagedImage(
    bytes: bytes ?? _png(),
    mimeType: mimeType,
    width: width,
    height: height,
  );
}

void main() {
  group('ImageRules.detectMimeType', () {
    test('recognises a real png from its leading bytes', () {
      expect(ImageRules.detectMimeType(_png()), 'image/png');
    });

    test('recognises jpeg and webp signatures', () {
      expect(
        ImageRules.detectMimeType(_bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00])),
        'image/jpeg',
      );
      expect(
        ImageRules.detectMimeType(
          _bytes([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x00, 0x00, 0x00, 0x00,
            0x57, 0x45, 0x42, 0x50, // WEBP
          ]),
        ),
        'image/webp',
      );
    });

    test('refuses a file that only claims to be an image', () {
      // a gif, and a text file renamed to look like a photo
      expect(
        ImageRules.detectMimeType(_bytes([0x47, 0x49, 0x46, 0x38])),
        isNull,
      );
      expect(ImageRules.detectMimeType(_bytes([0x68, 0x69])), isNull);
    });

    test('does not read past the end of a truncated file', () {
      expect(ImageRules.detectMimeType(_bytes([0xFF, 0xD8])), isNull);
      expect(ImageRules.detectMimeType(Uint8List(0)), isNull);
    });
  });

  group('ImageRules.check', () {
    test('accepts a sample image', () {
      expect(ImageRules.check(_staged()), isNull);
    });

    test('rejects content whose bytes are not an allowed image', () {
      expect(
        ImageRules.check(_staged(bytes: _bytes([0x47, 0x49, 0x46, 0x38]))),
        ImageIssue.unsupportedType,
      );
    });

    test('trusts the bytes over the declared type', () {
      final lying = _staged(
        bytes: _bytes(List<int>.filled(64, 0x41)),
        mimeType: 'image/png',
      );
      expect(ImageRules.check(lying), ImageIssue.unsupportedType);
    });

    test('rejects an image below the minimum dimension', () {
      expect(
        ImageRules.check(_staged(width: 100, height: 100)),
        ImageIssue.tooSmall,
      );
    });

    test('rejects an implausible pixel count', () {
      expect(
        ImageRules.check(_staged(width: 30000, height: 30000)),
        ImageIssue.tooManyPixels,
      );
    });
  });

  group('MockImageRepository', () {
    test('stages an acceptable image and returns a reference', () async {
      final store = StagedImageStore();
      final repository = MockImageRepository(
        store: store,
        latency: const MockLatency.none(),
      );

      final ref = await repository.stage(_staged());
      expect(ref.id, startsWith('stg_'));
      expect(store.get(ref.id), isNotNull);
    });

    test('refuses to stage content that fails the rules', () async {
      final repository = MockImageRepository(
        store: StagedImageStore(),
        latency: const MockLatency.none(),
      );
      expect(
        () => repository.stage(_staged(bytes: _bytes([0x00, 0x01]))),
        throwsA(isA<UnexpectedFailure>()),
      );
    });

    test('a staged image does not survive the store being cleared', () async {
      final store = StagedImageStore();
      final repository = MockImageRepository(
        store: store,
        latency: const MockLatency.none(),
      );
      final ref = await repository.stage(_staged());
      store.clear();
      expect(store.get(ref.id), isNull);
    });
  });

  group('MockImageLocator', () {
    test('resolves a staged reference from memory', () async {
      final store = StagedImageStore();
      final repository = MockImageRepository(
        store: store,
        latency: const MockLatency.none(),
      );
      final locator = MockImageLocator(store: store, bundled: const {});

      final ref = await repository.stage(_staged());
      expect(locator.locate(ref), isA<MemoryImageLocation>());
    });

    test('resolves a bundled reference to its asset path', () {
      final locator = MockImageLocator(
        store: StagedImageStore(),
        bundled: const {'sample-01'},
      );
      final location = locator.locate(
        const ImageRef(id: 'sample-01', version: 'v1'),
      );
      expect(
        location,
        const BundledImageLocation(
          'packages/muto_feature/assets/sample/images/sample-01.png',
        ),
      );
    });

    test('returns null for a reference that resolves to nothing', () {
      final locator = MockImageLocator(
        store: StagedImageStore(),
        bundled: const {'sample-01'},
      );
      expect(
        locator.locate(const ImageRef(id: 'sample-missing', version: 'v1')),
        isNull,
        reason: 'the caller renders a failure state rather than guessing',
      );
    });
  });
}
