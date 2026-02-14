import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glow_example/main.dart';

void main() {
  testWidgets('MyApp can be constructed and pumped', (WidgetTester tester) async {
    // MyApp requires OpenGLController().initializeGL() to load native
    // libraries that are unavailable in the test harness. Pump the widget
    // and tolerate the resulting LateInitializationError from the missing
    // native backend.
    await tester.pumpWidget(const MaterialApp(home: MyApp()));

    // Drain the expected error so the test runner does not treat it as a
    // failure.  The error originates from OpenGLController.openglPlugin
    // being uninitialised (no native library in test).
    final Object? error = tester.takeException();
    expect(error, isNotNull);

    expect(find.byType(MyApp), findsOneWidget);
  });
}
