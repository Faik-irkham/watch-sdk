import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hr_sdk_001/main.dart';

void main() {
  testWidgets('shows placeholder before any measurement', (tester) async {
    await tester.pumpWidget(const HeartRateApp());

    expect(find.text('--'), findsOneWidget);
    expect(find.text('bpm'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mulai'), findsOneWidget);
  });
}
