import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_ui/muto_ui.dart';

void main() {
  group('ListingImage', () {
    testWidgets('shows a placeholder when there is no provider at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 100,
            height: 100,
            child: ListingImage(provider: null, semanticLabel: 'A lamp'),
          ),
        ),
      );

      expect(find.byIcon(Icons.image_outlined), findsNothing);
      expect(find.byType(Image), findsNothing);
      // no network image ever attempted, so nothing to wait out — the
      // placeholder is the first and only frame
      expect(find.bySemanticsLabel('A lamp'), findsOneWidget);
    });

    testWidgets(
      'falls back to the same placeholder when the image cannot decode',
      (tester) async {
        // empty bytes are not a real image, so this fails to decode exactly
        // the way a broken upload or a stale reference would
        final broken = MemoryImage(Uint8List(0));

        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 100,
              height: 100,
              child: ListingImage(provider: broken, semanticLabel: 'A desk'),
            ),
          ),
        );
        // lets the failed decode round-trip through the image pipeline and
        // reach ListingImage's own errorBuilder
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('A desk'), findsOneWidget);
      },
    );
  });
}
