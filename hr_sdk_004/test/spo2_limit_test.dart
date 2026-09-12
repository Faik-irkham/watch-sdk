import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/main.dart';

const _methods = MethodChannel('samsung_health/method');
const _spo2 = EventChannel('samsung_health/spo2');
const _limitMessage = 'Batas 30 detik tercapai — silakan ukur ulang';

Map<String, Object?> _sample(int status, {int spo2 = 0}) => {
  'event': 'data',
  'spo2': spo2,
  'spo2Status': status,
  'heartRate': 80,
  'accuracyFlag': 0,
  'timestamp': 0,
};

/// `subscription.cancel()` mengembalikan future yang sudah selesai di zona
/// akar, sehingga lanjutan `await`-nya di `_stop` baru jalan saat event loop
/// sungguhan berputar; `tester.pump` (waktu palsu) tidak memutarnya.
Future<void> _finishStop(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// Pedoman resmi Samsung: pelacak on-demand dipakai paling lama 30 detik.
void main() {
  late bool cancelled;

  Future<void> startSpo2(
    WidgetTester tester,
    List<Map<String, Object?>> events,
  ) async {
    cancelled = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, (call) async => true);
    messenger.setMockStreamHandler(
      _spo2,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          for (final event in events) {
            sink.success(event);
          }
        },
        onCancel: (_) => cancelled = true,
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_spo2, null);
    });

    await tester.pumpWidget(const SamsungHealthApp());
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mulai'));
    await tester.pumpAndSettle();
  }

  testWidgets('pengukuran tanpa hasil akhir dihentikan tepat di detik ke-30', (
    tester,
  ) async {
    // Hanya "menghitung", tidak pernah selesai.
    await startSpo2(tester, [_sample(0)]);
    expect(find.widgetWithText(FilledButton, 'Berhenti'), findsOneWidget);

    await tester.pump(const Duration(seconds: 29));
    expect(find.widgetWithText(FilledButton, 'Berhenti'), findsOneWidget);
    expect(cancelled, isFalse);

    await tester.pump(const Duration(seconds: 1));
    await _finishStop(tester);
    expect(find.text(_limitMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mulai'), findsOneWidget);
    expect(
      cancelled,
      isTrue,
      reason: 'langganan ditutup, jadi sensor dimatikan',
    );
  });

  testWidgets('hasil yang selesai sebelum 30 detik tidak ditimpa batas waktu', (
    tester,
  ) async {
    await startSpo2(tester, [
      _sample(0),
      _sample(2, spo2: 98),
      {
        'event': 'status',
        'state': 'completed',
        'message': 'Pengukuran SpO2 berakhir',
      },
    ]);
    expect(find.text('98'), findsOneWidget);
    expect(find.text('Pengukuran selesai'), findsOneWidget);

    await tester.pump(const Duration(seconds: 31));
    await _finishStop(tester);
    expect(find.text('Pengukuran selesai'), findsOneWidget);
    expect(find.text(_limitMessage), findsNothing);
  });

  testWidgets(
    'berhenti manual tidak memunculkan pesan batas waktu belakangan',
    (tester) async {
      await startSpo2(tester, [_sample(0)]);
      await tester.tap(find.widgetWithText(FilledButton, 'Berhenti'));
      await _finishStop(tester);
      expect(find.text('Pengukuran dihentikan'), findsOneWidget);

      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Pengukuran dihentikan'), findsOneWidget);
      expect(find.text(_limitMessage), findsNothing);
    },
  );
}
