import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hr_sdk_002/main.dart';

void main() {
  testWidgets('starts on the heart rate page with a placeholder', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    expect(find.text('bpm'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mulai'), findsOneWidget);
  });

  testWidgets('swiping reveals the SpO2 page', (tester) async {
    await tester.pumpWidget(const SamsungHealthApp());

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('% SpO₂'), findsOneWidget);
    expect(find.text('bpm'), findsNothing);
  });
}
