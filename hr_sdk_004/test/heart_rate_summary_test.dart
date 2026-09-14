import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_004/heart_rate_summary.dart';
import 'package:hr_sdk_004/widgets/heart_rate_view.dart';

/// Satu pembacaan per detik, masing-masing dengan satu IBI.
List<HeartRateBeat> beats(List<int> ibis, {int bpm = 80, List<int>? status}) => [
      for (var i = 0; i < ibis.length; i++)
        HeartRateBeat(
          at: DateTime.fromMillisecondsSinceEpoch(i * 1000),
          bpm: bpm,
          ibi: [ibis[i]],
          ibiStatus: [status?[i] ?? 0],
        ),
    ];

void main() {
  test('RMSSD: akar rata-rata kuadrat selisih IBI berurutan', () {
    // Selisih: 10, -20, 10, 20, -20, -10, 20, -10, -10, 10
    // Kuadrat berjumlah 2200 dari 10 selisih, jadi RMSSD = √220.
    final summary = HeartRateSummary.of(
      beats([800, 810, 790, 800, 820, 800, 790, 810, 800, 790, 800]),
    )!;

    expect(summary.intervalPairs, 10);
    expect(summary.rmssd, closeTo(14.832, 0.001));
  });

  test('RMSSD kosong bila selisih berurutan kurang dari batas minimum', () {
    final summary = HeartRateSummary.of(beats(List.filled(10, 800)))!;

    expect(summary.intervalPairs, 9);
    expect(summary.rmssd, isNull);
  });

  test('IBI berstatus galat memutus rantai, tidak sekadar dilewati', () {
    final summary = HeartRateSummary.of(
      beats([800, 900, 810], status: [0, -1, 0]),
    )!;

    // 800 dan 810 bukan detak berurutan: ada detak galat di antaranya.
    expect(summary.intervalPairs, 0);
  });

  test('jeda antarpembacaan memutus rantai IBI', () {
    HeartRateBeat at(int ms, int ibi) => HeartRateBeat(
          at: DateTime.fromMillisecondsSinceEpoch(ms),
          bpm: 80,
          ibi: [ibi],
          ibiStatus: const [0],
        );

    expect(HeartRateSummary.of([at(0, 800), at(1000, 810)])!.intervalPairs, 1);
    // Pembacaan detik ke-2 tidak tersimpan, beserta IBI-nya.
    expect(HeartRateSummary.of([at(0, 800), at(3000, 810)])!.intervalPairs, 0);
  });

  test('pembacaan tanpa IBI (layar mati) tidak memutus rantai', () {
    final summary = HeartRateSummary.of([
      HeartRateBeat(
        at: DateTime.fromMillisecondsSinceEpoch(0),
        bpm: 80,
        ibi: const [800, 810, 820],
        ibiStatus: const [0, 0, 0],
      ),
      HeartRateBeat(at: DateTime.fromMillisecondsSinceEpoch(1000), bpm: 80),
      HeartRateBeat(
        at: DateTime.fromMillisecondsSinceEpoch(2000),
        bpm: 80,
        ibi: const [830],
        ibiStatus: const [0],
      ),
    ])!;

    expect(summary.intervalPairs, 3);
  });

  test('rentang dan rata-rata bpm', () {
    final summary = HeartRateSummary.of([
      for (final (i, bpm) in [72, 80, 88].indexed)
        HeartRateBeat(at: DateTime.fromMillisecondsSinceEpoch(i * 1000), bpm: bpm),
    ])!;

    expect(summary.minBpm, 72);
    expect(summary.maxBpm, 88);
    expect(summary.meanBpm, 80);
    expect(summary.readings, 3);
    expect(summary.duration, const Duration(seconds: 2));
    expect(HeartRateSummary.of(const []), isNull);
  });

  test('ringkasan menyimpan pembacaannya untuk rincian per detik', () {
    final input = beats([800, 810, 820]);
    expect(HeartRateSummary.of(input)!.beats, input);
  });

  group('sesi', () {
    HeartRateBeat at(int seconds, int bpm) =>
        HeartRateBeat(at: DateTime.fromMillisecondsSinceEpoch(seconds * 1000), bpm: bpm);

    // Urutan riwayat: paling baru di depan. Jeda 100 detik memisahkan sesi.
    final newestFirst = [at(102, 90), at(101, 90), at(1, 60), at(0, 60)];

    test('dipisahkan jeda panjang, sesi terbaru di depan', () {
      final sessions = summarizeSessions(newestFirst);

      expect(sessions.map((s) => s.meanBpm), [90, 60]);
      expect(sessions.first.start, DateTime.fromMillisecondsSinceEpoch(101000));
    });

    test('sesi terlama dibuang bila pemuatan terpotong', () {
      expect(summarizeSessions(newestFirst, truncated: true).map((s) => s.meanBpm), [90]);
      // Satu-satunya sesi tetap ditampilkan walau mungkin tidak utuh.
      expect(summarizeSessions(newestFirst.take(2).toList(), truncated: true), hasLength(1));
    });
  });

  group('teks', () {
    final summary = HeartRateSummary.of(
      beats([800, 820, 800, 820, 800, 820, 800, 820, 800, 820, 800], bpm: 76),
    )!;

    test('ringkasan setelah pengukuran dihentikan', () {
      expect(describeSession(summary), 'Rata-rata 76 bpm · 76–76\nHRV 20 ms');
    });

    test('HRV tanpa cukup IBI tidak ditebak', () {
      expect(formatHrv(HeartRateSummary.of(beats([800]))!), 'HRV: IBI belum cukup');
    });

    test('lama sesi', () {
      expect(formatSessionDuration(const Duration(seconds: 45)), '45 dtk');
      expect(formatSessionDuration(const Duration(seconds: 185)), '3 mnt 5 dtk');
    });

    test('IBI per detik: nilai yang valid, lalu jumlah yang galat', () {
      HeartRateBeat beat(List<int> ibi, List<int> status) =>
          HeartRateBeat(at: DateTime(2026), bpm: 80, ibi: ibi, ibiStatus: status);

      expect(formatIbi(beat([812, 790], [0, 0])), 'IBI 812, 790 ms');
      expect(formatIbi(beat([606, 337], [-1, -1])), '2 IBI galat');
      expect(formatIbi(beat([812, 606], [0, -1])), 'IBI 812 ms · 1 IBI galat');
      expect(formatIbi(beat([], [])), 'tanpa IBI');
    });
  });
}
