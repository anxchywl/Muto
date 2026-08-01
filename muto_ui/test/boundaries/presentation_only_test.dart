import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// muto_ui is presentation only. Its pubspec already withholds networking and
/// storage; this catches the remaining way the boundary could be crossed.
void main() {
  test('muto_ui does not depend on the feature or on data concerns', () {
    final forbidden = <String>[
      'package:muto_feature/',
      'package:http/',
      'package:shared_preferences/',
      'dart:io',
    ];

    final offenders = <String>[];
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sources) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        for (final package in forbidden) {
          if (trimmed.contains(package)) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'widgets receive data as parameters and never fetch it',
    );
  });
}
