import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muto_ui/muto_ui.dart';

Future<void> _pump(WidgetTester tester, {required bool selected}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SelectableChip(
            label: 'Textbooks',
            selected: selected,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a chip is tall enough to hit with a finger', (tester) async {
    await _pump(tester, selected: false);

    final size = tester.getSize(find.byType(SelectableChip));
    expect(size.height, greaterThanOrEqualTo(SelectableChip.minHeight));
  });

  testWidgets('a chip says whether it is chosen, not only shows it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, selected: true);

    final node = tester.getSemantics(find.byType(SelectableChip));
    expect(node.label, 'Textbooks');
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('a long label is cut rather than allowed to overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            child: SelectableChip(
              label: 'A label far wider than the space it was given',
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
  });
}
