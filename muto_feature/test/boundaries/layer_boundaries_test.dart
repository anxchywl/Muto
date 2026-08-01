import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The layer rules are a build-time promise, not a review convention. This
/// scans the source so a violation fails the suite rather than surviving to
/// the next reader.
Iterable<File> _dartFilesIn(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) return const <File>[];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

List<String> _importsOf(File file) {
  return file
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.startsWith('import ') || line.startsWith('export '))
      .toList();
}

void _expectNoImportMatching(
  String directory,
  Pattern forbidden, {
  required String because,
}) {
  final offenders = <String>[];
  for (final file in _dartFilesIn(directory)) {
    for (final line in _importsOf(file)) {
      if (line.contains(forbidden)) {
        offenders.add('${file.path}: $line');
      }
    }
  }
  expect(offenders, isEmpty, reason: because);
}

void main() {
  group('domain purity', () {
    test('domain does not import Flutter', () {
      _expectNoImportMatching(
        'lib/src/domain',
        'package:flutter/',
        because:
            'domain is pure Dart so its rules can be tested and reused '
            'without a widget binding',
      );
    });

    test('domain does not import a networking or storage package', () {
      for (final package in const [
        'package:http/',
        'package:shared_preferences/',
        'package:image_picker/',
        'package:cached_network_image/',
      ]) {
        _expectNoImportMatching(
          'lib/src/domain',
          package,
          because: 'domain must not know how data is fetched or stored',
        );
      }
    });

    test('domain does not import the application or data layers', () {
      for (final layer in const ['/application/', '/data/', '/presentation/']) {
        _expectNoImportMatching(
          'lib/src/domain',
          layer,
          because: 'dependencies point inward, towards the domain',
        );
      }
    });
  });

  group('presentation isolation', () {
    test('presentation does not import the data layer', () {
      _expectNoImportMatching(
        'lib/src/presentation',
        '/data/',
        because:
            'screens talk to controllers, never to a repository '
            'implementation',
      );
    });
  });
}
