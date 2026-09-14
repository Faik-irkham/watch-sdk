import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/main.dart';

import 'watch_harness.dart';

const _methods = MethodChannel('samsung_health/method');
const _heartRate = EventChannel('samsung_health/heart_rate');

/// Dua belas pembacaan absah: bpm 75/76/77 bergantian, IBI 800/820
/// bergantian. Rata-rata 76, rentang 75–77, 11 selisih ±20 ms → RMSSD 20.
List<Map<String, Object?>> _session() => [
      for (var i = 0; i < 12; i++)
        {
          'event': 'data',
          'heartRate': 75 + i % 3,
          'heartRateStatus': 1,
          'ibi': [800 + (i % 2) * 20],
          'ibiStatus': [0],
          'timestamp': 1000 + i * 1000,
        },
    ];

void main() {
  setUpAll(loadWatchFonts);

  late List<bool> screenOn;

  Future<void> measureAndStop(WidgetTester tester, double textScale) async {
    useWatchScreen(tester, textScale: textScale);
    screenOn = [];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      if (call.method == 'keepScreenOn') {
        screenOn.add((call.arguments as Map)['on'] as bool);
        return null;
      }
      return true;
    });
    messenger.setMockStreamHandler(
      _heartRate,
      MockStreamHandler.inline(
        onListen: (_, sink) => _session().forEach(sink.success),
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_heartRate, null);
    });

    await tester.pumpWidget(const SamsungHealthApp());
    await tester.tap(find.widgetWithText(FilledButton, 'Mulai'));
    await tester.pumpAndSettle();
    expect(screenOn, [true], reason: 'layar dijaga menyala saat mulai');

    await tester.tap(find.widgetWithText(FilledButton, 'Berhenti'));
    // Lanjutan `await subscription.cancel()` baru jalan saat event loop
    // sungguhan berputar; lihat spo2_limit_test.dart.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  for (final scale in watchTextScales) {
    testWidgets('ringkasan sesi setelah berhenti · skala huruf $scale', (tester) async {
      await measureAndStop(tester, scale);

      expect(find.text('Rata-rata 76 bpm · 75–77\nHRV 20 ms'), findsOneWidget);
      expect(screenOn, [true, false], reason: 'flag dilepas saat berhenti');
      expect(tester.takeException(), isNull);
      expectInsideRoundScreen(tester);
      expectNoBrokenWords(tester);
    });
  }
}
