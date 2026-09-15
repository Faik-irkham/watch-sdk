import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/main.dart';
import 'package:hr_sdk_004/widgets/interval_view.dart';

import 'watch_harness.dart';

const _methods = MethodChannel('samsung_health/method');
const _channels = {
  'hr': EventChannel('samsung_health/heart_rate'),
  'acc': EventChannel('samsung_health/accelerometer'),
  'spo2': EventChannel('samsung_health/spo2'),
};

/// Dua belas pembacaan absah: rata-rata 76 bpm, 11 selisih IBI ±20 ms → HRV 20.
List<Map<String, Object?>> _heartRate() => [
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

Map<String, Object?> _spo2(int status, [int value = 98]) => {
      'event': 'data',
      'spo2': value,
      'spo2Status': status,
      'heartRate': 76,
      'accuracyFlag': 0,
      'timestamp': 70000,
    };

const _completed = {'event': 'status', 'state': 'completed', 'message': 'selesai'};

void main() {
  setUpAll(loadWatchFonts);

  /// Urutan dengar/batal tiap sensor, sebagaimana diterima sisi Android.
  late List<String> log;
  late List<bool> screenOn;

  /// Hitung mundur di layar. Waktu palsu test ikut maju selama pumpAndSettle
  /// menunggu animasi ketukan tombol, jadi nilainya bisa sudah turun satu detik.
  void expectCountdown(Duration expected) {
    final shown = {
      formatCountdown(expected),
      formatCountdown(expected - const Duration(seconds: 1)),
    };
    expect(
      find.byWidgetPredicate((w) => w is Text && shown.contains(w.data)),
      findsOneWidget,
      reason: 'hitung mundur sekitar ${formatCountdown(expected)}',
    );
  }

  Future<void> startInterval(
    WidgetTester tester, {
    required List<Map<String, Object?>> spo2Events,
  }) async {
    useWatchScreen(tester);
    log = [];
    screenOn = [];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      if (call.method == 'keepScreenOn') {
        screenOn.add((call.arguments as Map)['on'] as bool);
        return null;
      }
      return true;
    });
    final events = <String, List<Map<String, Object?>>>{
      'hr': _heartRate(),
      'acc': [
        {
          'event': 'data',
          'samples': [
            {'x': 0, 'y': 0, 'z': 4096, 'timestamp': 1000},
          ],
        },
      ],
      'spo2': spo2Events,
    };
    for (final MapEntry(key: name, value: channel) in _channels.entries) {
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            log.add('dengar $name');
            events[name]!.forEach(sink.success);
          },
          onCancel: (_) => log.add('batal $name'),
        ),
      );
    }
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      for (final channel in _channels.values) {
        messenger.setMockStreamHandler(channel, null);
      }
    });

    await tester.pumpWidget(const SamsungHealthApp());
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(4);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mulai'));
    await tester.pumpAndSettle();
  }

  testWidgets('satu siklus: detak jantung dan akselerometer, lalu SpO₂ sendirian',
      (tester) async {
    await startInterval(tester, spo2Events: [_spo2(0, 0), _spo2(2), _completed]);
    expect(log, ['dengar hr', 'dengar acc']);
    expect(screenOn, [true]);

    await tester.pump(IntervalView.heartRateWindow);
    await tester.pumpAndSettle();
    // SpO₂ baru mulai setelah kedua sensor menerus dibatalkan.
    expect(log, [
      'dengar hr',
      'dengar acc',
      'batal hr',
      'batal acc',
      'dengar spo2',
      'batal spo2',
    ]);
    expect(find.text('76 bpm · HRV 20 ms\nSpO₂ 98%'), findsOneWidget);
    expect(find.text('jeda · 1 siklus selesai'), findsOneWidget);
    expectCountdown(const Duration(minutes: 4));

    await tester.pump(const Duration(minutes: 4));
    await tester.pumpAndSettle();
    expect(log.skip(6), ['dengar hr', 'dengar acc'],
        reason: 'siklus kedua dimulai 5 menit setelah siklus pertama');

    await tester.tap(find.widgetWithText(FilledButton, 'Berhenti'));
    await tester.pumpAndSettle();
    expect(log.skip(8), ['batal hr', 'batal acc']);
    expect(screenOn, [true, false], reason: 'layar menyala sepanjang mode, termasuk saat jeda');
    expect(find.text('Dihentikan setelah 1 siklus'), findsOneWidget);
  });

  testWidgets('SpO₂ yang tidak selesai dihentikan di detik ke-30', (tester) async {
    await startInterval(tester, spo2Events: [_spo2(0, 0)]);
    await tester.pump(IntervalView.heartRateWindow);
    await tester.pumpAndSettle();
    expect(log.last, 'dengar spo2');

    await tester.pump(IntervalView.spo2Limit);
    await tester.pumpAndSettle();
    expect(log.last, 'batal spo2');
    expect(find.text('76 bpm · HRV 20 ms\nSpO₂ tidak selesai'), findsOneWidget);
    // 60 detik detak jantung + 30 detik SpO₂ → sisa jeda 3,5 menit.
    expectCountdown(const Duration(minutes: 3, seconds: 30));
  });

  test('hitung mundur', () {
    expect(formatCountdown(const Duration(seconds: 42)), '0:42');
    expect(formatCountdown(const Duration(minutes: 3, seconds: 59)), '3:59');
    expect(formatCountdown(Duration.zero), '0:00');
  });
}
