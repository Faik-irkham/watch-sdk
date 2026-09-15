import 'dart:convert';

import 'package:hr_sdk_005_phone/edge_store.dart';

/// Satu batch dari jam: `{"device": …, "table": …, "records": [baris, …]}`.
class WatchBatch {
  const WatchBatch({
    required this.device,
    required this.table,
    required this.records,
  });

  /// Identitas jam (device_id).
  final String device;
  final String table;
  final List<Map<String, Object?>> records;
}

/// Membaca batch yang sudah dirangkai. Melempar [FormatException] bila
/// bentuknya tidak dikenal.
WatchBatch decodeBatch(String json) {
  final map = jsonDecode(json);
  if (map is! Map<String, Object?>) {
    throw const FormatException('Batch bukan objek JSON');
  }
  final device = map['device'];
  if (device is! String || device.isEmpty) {
    throw const FormatException('Batch tanpa identitas jam');
  }
  final table = map['table'];
  if (table is! String || !EdgeStore.columns.containsKey(table)) {
    throw FormatException('Tabel tidak dikenal: $table');
  }
  final records = map['records'];
  if (records is! List) throw const FormatException('Batch tanpa records');
  return WatchBatch(
    device: device,
    table: table,
    records: [for (final r in records) (r as Map).cast<String, Object?>()],
  );
}

/// Catatan satu batch yang diterima, untuk daftar di layar.
class ReceivedBatch {
  const ReceivedBatch({
    required this.at,
    required this.table,
    required this.rows,
    required this.inserted,
  });

  final DateTime at;
  final String table;
  final int rows;

  /// Baris yang benar-benar baru; sisanya kiriman ulang yang sudah ada.
  final int inserted;
}
