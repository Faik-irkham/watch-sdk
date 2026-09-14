import 'dart:math' as math;

/// Satu pembacaan detak jantung yang absah (status 1), dalam bentuk yang sama
/// untuk data yang sedang mengalir dan data yang dibaca dari SQLite.
class HeartRateBeat {
  const HeartRateBeat({
    required this.at,
    required this.bpm,
    this.ibi = const [],
    this.ibiStatus = const [],
  });

  final DateTime at;
  final int bpm;

  /// Inter-beat interval (ms) yang dikirim bersama pembacaan ini.
  final List<int> ibi;

  /// Status tiap elemen [ibi]. Menurut tabel resmi Samsung, 0 berarti normal
  /// dan −1 berarti galat.
  final List<int> ibiStatus;
}

/// Ringkasan satu sesi pengukuran detak jantung: rentang dan rata-rata bpm,
/// serta HRV sebagai RMSSD.
class HeartRateSummary {
  const HeartRateSummary({
    required this.start,
    required this.end,
    required this.readings,
    required this.minBpm,
    required this.maxBpm,
    required this.meanBpm,
    required this.intervalPairs,
    this.rmssd,
  });

  /// Jeda antarpembacaan yang lebih panjang dari ini memisahkan dua sesi.
  static const Duration sessionGap = Duration(seconds: 30);

  /// Pembacaan dikirim sekali per detik. Jeda yang lebih panjang berarti ada
  /// pembacaan tidak absah yang tidak disimpan beserta IBI-nya, sehingga IBI
  /// di kedua sisi jeda bukan detak yang berurutan.
  static const Duration maxBeatGap = Duration(milliseconds: 1500);

  /// Selisih IBI berurutan minimum sebelum RMSSD ditampilkan. Dengan lebih
  /// sedikit dari ini, satu selisih yang menyimpang terlalu menentukan hasil.
  static const int minIntervalPairs = 10;

  final DateTime start;
  final DateTime end;
  final int readings;
  final int minBpm;
  final int maxBpm;
  final double meanBpm;

  /// Jumlah selisih IBI berurutan yang dipakai untuk [rmssd].
  final int intervalPairs;

  /// HRV dalam milidetik: akar rata-rata kuadrat selisih IBI berurutan
  /// (RMSSD). Null bila [intervalPairs] kurang dari [minIntervalPairs].
  final double? rmssd;

  Duration get duration => end.difference(start);

  /// Ringkasan dari pembacaan yang urut waktu, terlama di depan. Null bila
  /// tidak ada pembacaan.
  ///
  /// Hanya IBI berstatus 0 yang dipakai, tanpa penyaringan tambahan. IBI
  /// berstatus galat dan jeda antarpembacaan memutus rantai, jadi selisih
  /// hanya dihitung antara dua detak yang benar-benar berurutan.
  static HeartRateSummary? of(List<HeartRateBeat> beats) {
    if (beats.isEmpty) return null;
    var minBpm = beats.first.bpm;
    var maxBpm = minBpm;
    var bpmSum = 0;
    var squares = 0.0;
    var pairs = 0;
    int? previousIbi;
    DateTime? previousAt;
    for (final beat in beats) {
      minBpm = math.min(minBpm, beat.bpm);
      maxBpm = math.max(maxBpm, beat.bpm);
      bpmSum += beat.bpm;
      if (previousAt != null && beat.at.difference(previousAt) > maxBeatGap) {
        previousIbi = null;
      }
      previousAt = beat.at;
      for (var i = 0; i < beat.ibi.length; i++) {
        final valid = i < beat.ibiStatus.length && beat.ibiStatus[i] == 0;
        if (!valid) {
          previousIbi = null;
          continue;
        }
        final ibi = beat.ibi[i];
        if (previousIbi != null) {
          final difference = ibi - previousIbi;
          squares += difference * difference;
          pairs++;
        }
        previousIbi = ibi;
      }
    }
    return HeartRateSummary(
      start: beats.first.at,
      end: beats.last.at,
      readings: beats.length,
      minBpm: minBpm,
      maxBpm: maxBpm,
      meanBpm: bpmSum / beats.length,
      intervalPairs: pairs,
      rmssd: pairs >= minIntervalPairs ? math.sqrt(squares / pairs) : null,
    );
  }
}

/// Ringkasan per sesi dari pembacaan terbaru, paling baru di depan seperti
/// urutan riwayat. Sesi dipisahkan oleh jeda lebih dari
/// [HeartRateSummary.sessionGap].
///
/// Bila [truncated], pemuatan terpotong batas baris dan sesi terlama mungkin
/// tidak utuh, jadi sesi itu dibuang selama masih ada sesi lain.
List<HeartRateSummary> summarizeSessions(
  List<HeartRateBeat> newestFirst, {
  bool truncated = false,
}) {
  final sessions = <List<HeartRateBeat>>[];
  for (final beat in newestFirst.reversed) {
    final current = sessions.isEmpty ? null : sessions.last;
    if (current == null ||
        beat.at.difference(current.last.at) > HeartRateSummary.sessionGap) {
      sessions.add([beat]);
    } else {
      current.add(beat);
    }
  }
  if (truncated && sessions.length > 1) sessions.removeAt(0);
  return [
    for (final session in sessions.reversed) HeartRateSummary.of(session)!,
  ];
}
