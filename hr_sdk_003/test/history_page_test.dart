import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_003/measurement_store.dart';
import 'package:hr_sdk_003/widgets/history_page.dart';

Future<void> openHistory(
  WidgetTester tester,
  Future<History<HistoryEntry>> Function() load,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => HistoryPage.open(context, title: 'Riwayat uji', load: load),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan baris terbaru dan ringkasan jumlah', (tester) async {
    await openHistory(
      tester,
      () async => History([
        HistoryEntry(
          at: DateTime(2026, 9, 11, 14, 5, 9),
          value: '98%',
          detail: '83 bpm',
        ),
        HistoryEntry(at: DateTime(2026, 9, 11, 13, 0, 0), value: '97%'),
      ], 250),
    );

    expect(find.text('Riwayat uji'), findsOneWidget);
    expect(find.text('250 data · 2 terbaru'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(find.text('83 bpm'), findsOneWidget);
    expect(find.text('14:05:09\n11/09/2026'), findsOneWidget);
  });

  testWidgets('tabel kosong menampilkan keterangan', (tester) async {
    await openHistory(tester, () async => const History([], 0));

    expect(find.text('Belum ada data tersimpan'), findsOneWidget);
  });

  testWidgets('galat baca ditampilkan, bukan layar kosong', (tester) async {
    await openHistory(tester, () async => throw StateError('disk penuh'));

    expect(find.textContaining('Gagal membaca riwayat'), findsOneWidget);
  });

  testWidgets('geser kanan menutup halaman riwayat', (tester) async {
    await openHistory(tester, () async => const History([], 0));
    expect(find.text('Riwayat uji'), findsOneWidget);

    await tester.fling(find.byType(HistoryPage), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Riwayat uji'), findsNothing);
    expect(find.text('buka'), findsOneWidget);
  });
}
