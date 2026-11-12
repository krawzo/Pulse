import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/app/pulse_windows_accessibility_boundary.dart';

void main() {
  Widget app({required bool enabled}) => MaterialApp(
        builder: (context, child) => PulseWindowsAccessibilityBoundary(
          enabled: enabled,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Center(
            child: Semantics(
              label: 'Faixa acessível',
              child: const Text('Faixa visível'),
            ),
          ),
        ),
      );

  testWidgets('Windows workaround keeps visual content and omits semantics',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(enabled: false));
    expect(find.text('Faixa visível'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pulse-windows-accessibility-workaround')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Faixa acessível')), findsNothing);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('explicit Windows opt-in restores screen-reader semantics',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(enabled: true));
    expect(
      find.byKey(const ValueKey('pulse-windows-accessibility-workaround')),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('Faixa acessível')), findsOneWidget);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('other platforms keep accessibility enabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(enabled: false));
    expect(
      find.byKey(const ValueKey('pulse-windows-accessibility-workaround')),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('Faixa acessível')), findsOneWidget);
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
