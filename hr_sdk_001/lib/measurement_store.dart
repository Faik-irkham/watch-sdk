import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'heart_rate_service.dart';

/// Penyimpanan hasil pengukuran di SQLite lokal jam.
///
/// Hanya pembacaan detak jantung yang oleh SDK dinyatakan sukses (status 1)
/// yang disimpan. Kolom `measured_at` memakai cap waktu sensor dalam milidetik
/// epoch, bukan waktu penyisipan.
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

  Future<Database> get database => _db ??= _open();

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

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}
