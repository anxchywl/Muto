import 'package:flutter_test/flutter_test.dart';
import 'package:muto_app/dev/dev_gate.dart';
import 'package:muto_app/host_app.dart';
import 'package:muto_feature/muto_feature.dart';

void main() {
  group('development access', () {
    test('a release build cannot enable it however the flag is set', () {
      expect(
        developmentAccessAllowed(isDebugMode: false, requested: true),
        isFalse,
        reason: 'a shipped binary must not carry a development door',
      );
      expect(
        developmentAccessAllowed(isDebugMode: false, requested: false),
        isFalse,
      );
    });

    test('a debug build honours the flag', () {
      expect(
        developmentAccessAllowed(isDebugMode: true, requested: true),
        isTrue,
      );
      expect(
        developmentAccessAllowed(isDebugMode: true, requested: false),
        isFalse,
      );
    });
  });

  test('the development session token is not a credential', () {
    // it exists so the sample repositories have a non-empty string to accept
    expect(developmentSessionToken, isNotEmpty);
    expect(developmentSessionToken.length, lessThan(32));
  });

  testWidgets('the host refuses to open when access is not allowed', (
    tester,
  ) async {
    await tester.pumpWidget(const HostApp(allowDevelopmentAccess: false));
    await tester.pump();

    expect(find.byType(MutoFeature), findsNothing);
    expect(find.textContaining('debug build'), findsOneWidget);
  });
}
