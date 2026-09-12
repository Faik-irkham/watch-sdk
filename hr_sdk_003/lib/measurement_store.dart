import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'samsung_health_service.dart';

/// Penyimpanan hasil pengukuran di SQLite lokal jam.
///
/// Hanya nilai yang oleh SDK dinyatakan sukses yang disimpan: detak jantung
/// berstatus 1, SpO2 berstatus 2, dan setiap sampel akselerometer (sensor ini
/// tidak memiliki kode status). Kolom `measured_at` memakai cap waktu sensor
/// dalam milidetik epoch, bukan waktu penyisipan.
class MeasurementStore {
  MeasurementStore({this.factory, this.path});

  /// Satu instans untuk seluruh aplikasi, supaya basis data hanya dibuka sekali.
  static final MeasurementStore instance = MeasurementStore();

  static const String fileName = 'measurements.db';

  /// Null berarti pabrik bawaan sqflite, yang baru disentuh saat basis data
  /// dibuka pertama kali. Membangun halaman tidak menyentuh platform.
  final DatabaseFactory? factory;

  /// Lokasi berkas basis data; null berarti direktori bawaan aplikasi.
  final String? path;

  Future<Database>? _db;

  /// Kegagalan membuka tidak disimpan: panggilan berikutnya mencoba lagi,
  /// alih-alih mengulang galat yang sama sampai aplikasi dimulai ulang.
  Future<Database> get database =>
      _db ??= _open().catchError((Object error, StackTrace stack) {
        _db = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<Database> _open() async {
    final opener = factory ?? databaseFactory;
    final location = path ?? p.join(await opener.getDatabasesPath(), fileName);
    return opener.openDatabase(
      location,
      options: OpenDatabaseOptions(version: 1, onCreate: _create),
    );
  }

  static Future<void> _create(Database db, int version) async {
    // measured_at unik untuk dua kanal pertama: pustaka dapat mengirim ulang
    // titik data yang sama saat layar mati, dan salinannya cukup diabaikan.
    await db.execute('''
      CREATE TABLE heart_rate (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        measured_at INTEGER NOT NULL UNIQUE,
        bpm         INTEGER NOT NULL,
        ibi_ms      TEXT    NOT NULL,
        ibi_status  TEXT    NOT NULL
      )''');
    // accuracy_flag disimpan apa adanya; maknanya tidak didokumentasikan Samsung.
    await db.execute('''
      CREATE TABLE spo2 (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        measured_at   INTEGER NOT NULL UNIQUE,
        spo2_percent  INTEGER NOT NULL,
        bpm           INTEGER NOT NULL,
        accuracy_flag INTEGER NOT NULL
      )''');
    // Nilai mentah tanpa gravitasi. Konversi resmi Samsung ke m/s²:
    // nilai * 9.81 / (16383.75 / 4.0).
    await db.execute('''
      CREATE TABLE accelerometer (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        measured_at INTEGER NOT NULL,
        x           INTEGER NOT NULL,
        y           INTEGER NOT NULL,
        z           INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX accelerometer_measured_at ON accelerometer (measured_at)',
    );
  }

  /// Menyimpan satu pembacaan detak jantung. Mengembalikan jumlah baris yang
  /// benar-benar tersimpan: 0 bila pembacaan tidak absah atau sudah ada.
  Future<int> saveHeartRate(HeartRateSample sample) async {
    if (!sample.isValid) return 0;
    final db = await database;
    final id = await db.insert(
      'heart_rate',
      {
        'measured_at': sample.timestamp.millisecondsSinceEpoch,
        'bpm': sample.heartRate,
        'ibi_ms': jsonEncode(sample.ibi),
        'ibi_status': jsonEncode(sample.ibiStatus),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0 ? 1 : 0;
  }

  /// Menyimpan hasil akhir satu pengukuran SpO2. Mengembalikan 0 bila
  /// pengukuran belum rampung atau sudah pernah tersimpan.
  Future<int> saveSpo2(Spo2Sample sample) async {
    if (!sample.isComplete) return 0;
    final db = await database;
    final id = await db.insert(
      'spo2',
      {
        'measured_at': sample.timestamp.millisecondsSinceEpoch,
        'spo2_percent': sample.spo2,
        'bpm': sample.heartRate,
        'accuracy_flag': sample.accuracyFlag,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0 ? 1 : 0;
  }

  /// Menyimpan satu kiriman akselerometer dalam satu transaksi, agar laju
  /// 25 Hz tidak memicu satu penulisan disk per sampel.
  Future<int> saveAccelerometer(AccelerometerBatch batch) async {
    if (batch.samples.isEmpty) return 0;
    final db = await database;
    await db.transaction((txn) async {
      final writes = txn.batch();
      for (final s in batch.samples) {
        writes.insert('accelerometer', {
          'measured_at': s.timestamp.millisecondsSinceEpoch,
          'x': s.x,
          'y': s.y,
          'z': s.z,
        });
      }
      await writes.commit(noResult: true);
    });
    return batch.samples.length;
  }

  /// Batas baris yang ditampilkan di halaman riwayat. Layar jam tidak butuh
  /// lebih, dan membatasi query menjaga halaman tetap cepat dibuka.
  static const int historyLimit = 100;

  Future<History<HeartRateRecord>> heartRateHistory({int limit = historyLimit}) async {
    final db = await database;
    final rows = await db.query(
      'heart_rate',
      columns: ['measured_at', 'bpm'],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return History(
      [
        for (final r in rows)
          HeartRateRecord(measuredAt: _time(r['measured_at']), bpm: _int(r['bpm'])),
      ],
      await _count(db, 'heart_rate'),
    );
  }

  Future<History<Spo2Record>> spo2History({int limit = historyLimit}) async {
    final db = await database;
    final rows = await db.query(
      'spo2',
      columns: ['measured_at', 'spo2_percent', 'bpm'],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return History(
      [
        for (final r in rows)
          Spo2Record(
            measuredAt: _time(r['measured_at']),
            spo2Percent: _int(r['spo2_percent']),
            bpm: _int(r['bpm']),
          ),
      ],
      await _count(db, 'spo2'),
    );
  }

  /// Riwayat akselerometer diringkas per detik: tabel mentahnya berisi sekitar
  /// 25 sampel per detik, terlalu rapat untuk dibaca satu per satu di jam.
  /// [History.total] tetap menghitung sampel mentah.
  Future<History<AccelerometerSecond>> accelerometerHistory({
    int limit = historyLimit,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT measured_at / 1000 AS second,
             COUNT(*) AS samples,
             AVG(x)   AS mean_x,
             AVG(y)   AS mean_y,
             AVG(z)   AS mean_z
      FROM accelerometer
      GROUP BY second
      ORDER BY second DESC
      LIMIT ?''', [limit]);
    return History(
      [
        for (final r in rows)
          AccelerometerSecond(
            second: _time(_int(r['second']) * 1000),
            samples: _int(r['samples']),
            meanX: (r['mean_x'] as num).toDouble(),
            meanY: (r['mean_y'] as num).toDouble(),
            meanZ: (r['mean_z'] as num).toDouble(),
          ),
      ],
      await _count(db, 'accelerometer'),
    );
  }

  static Future<int> _count(Database db, String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}

/// Potongan riwayat terbaru dari satu tabel.
class History<T> {
  const History(this.items, this.total);

  /// Baris terbaru, paling baru di depan, sebanyak-banyaknya
  /// [MeasurementStore.historyLimit].
  final List<T> items;

  /// Jumlah seluruh baris di tabel, bukan hanya yang dimuat di [items].
  final int total;

  History<R> map<R>(R Function(T item) convert) =>
      History(items.map(convert).toList(growable: false), total);
}

class HeartRateRecord {
  const HeartRateRecord({required this.measuredAt, required this.bpm});

  final DateTime measuredAt;
  final int bpm;
}

class Spo2Record {
  const Spo2Record({
    required this.measuredAt,
    required this.spo2Percent,
    required this.bpm,
  });

  final DateTime measuredAt;
  final int spo2Percent;
  final int bpm;
}

/// Ringkasan sampel akselerometer dalam satu detik, dalam satuan mentah sensor.
class AccelerometerSecond {
  const AccelerometerSecond({
    required this.second,
    required this.samples,
    required this.meanX,
    required this.meanY,
    required this.meanZ,
  });

  final DateTime second;
  final int samples;
  final double meanX;
  final double meanY;
  final double meanZ;
}

int _int(Object? value) => (value as num).toInt();

DateTime _time(Object? millis) =>
    DateTime.fromMillisecondsSinceEpoch((millis as num).toInt());

