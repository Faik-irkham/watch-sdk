import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'samsung_health_service.dart';

/// Penyimpanan hasil pengukuran di SQLite lokal jam.
///
/// Hanya nilai yang oleh SDK dinyatakan sukses yang disimpan: detak jantung
/// berstatus 1 dan SpO2 berstatus 2. Kolom `measured_at` memakai cap waktu
/// sensor dalam milidetik epoch, bukan waktu penyisipan.
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
    // measured_at unik: pustaka dapat mengirim ulang titik data yang sama saat
    // layar mati, dan salinannya cukup diabaikan.
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

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}
