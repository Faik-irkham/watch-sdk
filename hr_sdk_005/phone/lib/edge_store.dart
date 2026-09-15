import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Penyimpanan di HP (edge): salinan data yang diterima dari jam.
///
/// Setiap baris membawa `device_id` (identitas jam) dan `watch_id` (id barisnya
/// di jam). Pasangan itu unik, sama seperti `(device_id, record_id)` di proyek
/// heart_rate_phone_receiver, jadi batch yang dikirim ulang (misalnya karena
/// ACK sebelumnya tidak sampai ke jam) tidak menggandakan data.
class EdgeStore {
  EdgeStore({this.factory, this.path});

  static final EdgeStore instance = EdgeStore();

  static const String fileName = 'edge.db';

  /// Kolom data tiap tabel yang diterima dari jam, selain `device_id` dan
  /// `watch_id`.
  static const Map<String, List<String>> columns = {
    'heart_rate': ['measured_at', 'bpm', 'ibi_ms', 'ibi_status'],
    'spo2': ['measured_at', 'spo2_percent', 'bpm', 'accuracy_flag'],
    'accelerometer': ['measured_at', 'x', 'y', 'z'],
  };

  /// Null berarti pabrik bawaan sqflite; diisi di test.
  final DatabaseFactory? factory;

  /// Lokasi berkas basis data; null berarti direktori bawaan aplikasi.
  final String? path;

  Future<Database>? _db;

  /// Kegagalan membuka tidak disimpan, jadi panggilan berikutnya mencoba lagi.
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
    await db.execute('''
      CREATE TABLE heart_rate (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id   TEXT    NOT NULL,
        watch_id    INTEGER NOT NULL,
        measured_at INTEGER NOT NULL,
        bpm         INTEGER NOT NULL,
        ibi_ms      TEXT    NOT NULL,
        ibi_status  TEXT    NOT NULL,
        received_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE spo2 (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id     TEXT    NOT NULL,
        watch_id      INTEGER NOT NULL,
        measured_at   INTEGER NOT NULL,
        spo2_percent  INTEGER NOT NULL,
        bpm           INTEGER NOT NULL,
        accuracy_flag INTEGER NOT NULL,
        received_at   INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE accelerometer (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id   TEXT    NOT NULL,
        watch_id    INTEGER NOT NULL,
        measured_at INTEGER NOT NULL,
        x           INTEGER NOT NULL,
        y           INTEGER NOT NULL,
        z           INTEGER NOT NULL,
        received_at INTEGER NOT NULL
      )''');
    await db.execute(
      'CREATE INDEX accelerometer_measured_at ON accelerometer (measured_at)',
    );
    // Identitas record dari jam mencegah duplikat saat batch dikirim ulang.
    for (final table in columns.keys) {
      await db.execute(
        'CREATE UNIQUE INDEX ${table}_record ON $table (device_id, watch_id)',
      );
    }
  }

  /// Menyimpan satu kiriman dalam satu transaksi dan mengembalikan jumlah
  /// baris yang baru. Baris yang sudah pernah diterima dilewati. Bila satu
  /// baris tidak lengkap, seluruh kiriman ditolak sebelum ada yang disimpan,
  /// sehingga jam tidak menerima balasan berhasil dan akan mengirim ulang.
  Future<int> insertBatch(
    String table,
    List<Map<String, Object?>> rows, {
    required String deviceId,
    DateTime? receivedAt,
  }) async {
    final names = columns[table];
    if (names == null) {
      throw ArgumentError.value(table, 'table', 'tabel tidak dikenal');
    }
    if (deviceId.isEmpty) {
      throw const FormatException('Batch tanpa identitas jam');
    }
    // Diperiksa sendiri: INSERT OR IGNORE juga melewati pelanggaran NOT NULL
    // tanpa galat, sehingga baris tidak lengkap akan hilang diam-diam.
    for (final row in rows) {
      final missing = [
        for (final name in ['id', ...names])
          if (row[name] == null) name,
      ];
      if (missing.isNotEmpty) {
        throw FormatException(
          'Baris dari jam tanpa kolom: ${missing.join(', ')}',
        );
      }
    }
    final at = (receivedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final db = await database;
    var inserted = 0;
    await db.transaction((txn) async {
      for (final row in rows) {
        final values = <String, Object?>{
          'device_id': deviceId,
          'watch_id': row['id'],
          'received_at': at,
        };
        for (final name in names) {
          values[name] = row[name];
        }
        final id = await txn.insert(
          table,
          values,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) inserted++;
      }
    });
    return inserted;
  }

  /// Ringkasan untuk layar utama: jumlah baris, baris terbaru tiap tabel, dan
  /// waktu kiriman terakhir diterima.
  Future<EdgeSnapshot> snapshot() async {
    final db = await database;
    final counts = <String, int>{};
    final latest = <String, Map<String, Object?>?>{};
    int? receivedAt;
    for (final table in columns.keys) {
      counts[table] =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;
      final rows = await db.query(table, orderBy: 'measured_at DESC', limit: 1);
      latest[table] = rows.isEmpty ? null : rows.first;
      final received = Sqflite.firstIntValue(
        await db.rawQuery('SELECT MAX(received_at) FROM $table'),
      );
      if (received != null && (receivedAt == null || received > receivedAt)) {
        receivedAt = received;
      }
    }
    return EdgeSnapshot(
      counts: counts,
      latest: latest,
      lastReceivedAt: receivedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(receivedAt),
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await (await db).close();
  }
}

/// Keadaan data di HP pada satu saat.
class EdgeSnapshot {
  const EdgeSnapshot({
    this.counts = const {},
    this.latest = const {},
    this.lastReceivedAt,
  });

  final Map<String, int> counts;

  /// Baris terbaru tiap tabel menurut `measured_at`; null bila tabel kosong.
  final Map<String, Map<String, Object?>?> latest;

  final DateTime? lastReceivedAt;
}
