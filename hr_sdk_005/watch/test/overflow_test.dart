import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_watch/main.dart';

import 'watch_harness.dart';

/// Setiap layar diuji pada ukuran logis Galaxy Watch4 dalam keadaan terpadatnya.
/// Overflow RenderFlex otomatis menggagalkan test; pemeriksaan lingkaran
/// menangkap isi yang tidak overflow secara teknis tetapi terpotong lengkung
/// layar bulat.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadWatchFonts();
  });

  for (final scale in watchTextScales) {
    group('skala huruf $scale', () {
      for (final scenario in pageScenarios) {
        testWidgets(scenario.name, (tester) async {
          useWatchScreen(tester, textScale: scale);
          await showScenario(tester, const SamsungHealthApp(), scenario);

          expect(tester.takeException(), isNull);
          expectInsideRoundScreen(tester);
          expectNoBrokenWords(tester);
        });
      }

      for (final MapEntry(key: name, value: (title, noun, history))
          in historyScenarios.entries) {
        testWidgets(name, (tester) async {
          useWatchScreen(tester, textScale: scale);
          await tester.pumpWidget(historyApp(title, noun, history));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          // Baris daftar memang boleh terpotong saat digulir melewati tepi;
          // yang wajib utuh saat halaman dibuka adalah judul dan ringkasannya.
          expectInsideRoundScreen(tester, only: find.text(title));
        });
      }

      testWidgets('riwayat · galat baca dari SQLite', (tester) async {
        useWatchScreen(tester, textScale: scale);
        // Pemuat palsu, bukan MeasurementStore.instance: objek global itu
        // menyimpan Future dari zona test sebelumnya yang tak pernah selesai.
        await tester.pumpWidget(historyErrorApp());
        await tester.pumpAndSettle();

        expect(find.textContaining('Gagal membaca riwayat'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectInsideRoundScreen(tester);
      });
    });
  }
}
