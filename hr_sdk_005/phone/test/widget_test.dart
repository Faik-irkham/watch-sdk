import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_phone/dashboard_page.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/watch_receiver.dart';

/// Penyimpanan palsu tanpa berkas, supaya test widget tidak menunggu I/O
/// sungguhan yang tidak berjalan di waktu palsu test.
class FakeStore extends EdgeStore {
  FakeStore(this.value);

  final EdgeSnapshot value;

  @override
  Future<EdgeSnapshot> snapshot() async => value;
}

Future<void> showDashboard(
  WidgetTester tester,
  EdgeSnapshot snapshot, {
  WatchLinkState link = const WatchLinkState(),
}) async {
  final store = FakeStore(snapshot);
  final receiver = WatchReceiver(store: store)..link.value = link;
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardPage(store: store, receiver: receiver),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('jam tersambung lewat BLE dan nilai terbaru tiap sensor', (
    tester,
  ) async {
    await showDashboard(
      tester,
      EdgeSnapshot(
        counts: const {'heart_rate': 1234, 'spo2': 3, 'accelerometer': 45000},
        latest: const {
          'heart_rate': {'measured_at': 1000, 'bpm': 76},
          'spo2': {'measured_at': 2000, 'spo2_percent': 98},
          'accelerometer': {'measured_at': 3000, 'x': 12, 'y': -50, 'z': 4080},
        },
        lastReceivedAt: DateTime(2026, 9, 15, 14, 5, 9),
      ),
      link: const WatchLinkState(
        phase: LinkPhase.connected,
        name: 'Galaxy Watch4',
        pending: 12,
      ),
    );

    expect(find.text('Galaxy Watch4'), findsOneWidget);
    expect(find.textContaining('antrean di jam: 12'), findsOneWidget);
    expect(find.text('76 bpm'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('x 12 · y -50 · z 4080'), findsOneWidget);
    expect(find.textContaining('1234 data'), findsOneWidget);
    expect(
      find.text('Belum ada kiriman sejak aplikasi dibuka'),
      findsOneWidget,
    );
  });

  testWidgets('jam belum tersambung dan belum ada data', (tester) async {
    await showDashboard(tester, const EdgeSnapshot());

    expect(find.text('Jam belum tersambung'), findsOneWidget);
    expect(find.text('Belum ada data diterima'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(3));
  });

  testWidgets('galat BLE ditampilkan dengan pesannya', (tester) async {
    await showDashboard(
      tester,
      const EdgeSnapshot(),
      link: const WatchLinkState(
        phase: LinkPhase.error,
        message: 'Izin Bluetooth ditolak',
      ),
    );

    expect(find.text('Galat BLE'), findsOneWidget);
    expect(find.textContaining('Izin Bluetooth ditolak'), findsOneWidget);
  });
}
