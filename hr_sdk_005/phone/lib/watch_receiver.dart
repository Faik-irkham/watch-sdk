import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';

/// Versi format kiriman yang dipahami HP; harus sama dengan aplikasi jam.
const int batchVersion = 1;

/// Satu kiriman dari jam: nama tabel dan baris-barisnya.
class WatchBatch {
  const WatchBatch(this.table, this.rows);

  final String table;
  final List<Map<String, Object?>> rows;
}

/// Membaca kiriman JSON dari jam. Melempar [FormatException] bila bentuknya
/// tidak dikenal.
WatchBatch decodeBatch(String json) {
  final map = jsonDecode(json);
  if (map is! Map<String, Object?> || map['v'] != batchVersion) {
    throw const FormatException('Versi kiriman tidak dikenal');
  }
  final table = map['table'];
  if (table is! String || !EdgeStore.columns.containsKey(table)) {
    throw FormatException('Tabel tidak dikenal: $table');
  }
  final rows = map['rows'];
  if (rows is! List) throw const FormatException('Kiriman tanpa baris');
  return WatchBatch(table, [
    for (final row in rows) (row as Map).cast<String, Object?>(),
  ]);
}

/// Catatan satu kiriman yang diterima, untuk daftar di layar.
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

/// Tahap sambungan BLE ke jam, sebagaimana dilaporkan BleClient.kt.
enum LinkPhase { idle, scanning, connecting, connected, disconnected, error }

/// Keadaan sambungan BLE ke jam.
@immutable
class WatchLinkState {
  const WatchLinkState({
    this.phase = LinkPhase.idle,
    this.name,
    this.message,
    this.pending,
  });

  final LinkPhase phase;

  /// Nama atau alamat Bluetooth jam.
  final String? name;

  /// Keterangan galat untuk [LinkPhase.error].
  final String? message;

  /// Jumlah data yang masih menunggu di jam, dari characteristic STATUS.
  final int? pending;
}

/// Menerima kiriman dari jam lewat BleClient.kt, menyimpannya, lalu menjawab.
///
/// Jawaban true membuat HP menulis ACK dan jam menandai data terkirim.
/// Jawaban false membuat HP menulis RETRY dan jam mengirim ulang nanti, jadi
/// data tidak hilang bila penyimpanan gagal.
class WatchReceiver {
  WatchReceiver({EdgeStore? store}) : store = store ?? EdgeStore.instance;

  static const MethodChannel channel = MethodChannel('edge/watch');

  /// Jumlah kiriman terakhir yang ditampilkan.
  static const int recentLimit = 20;

  final EdgeStore store;

  /// Kiriman terbaru, paling baru di depan.
  final ValueNotifier<List<ReceivedBatch>> recent = ValueNotifier(const []);

  final ValueNotifier<WatchLinkState> link = ValueNotifier(
    const WatchLinkState(),
  );

  void attach() => channel.setMethodCallHandler(_handle);

  void detach() => channel.setMethodCallHandler(null);

  /// Mulai mencari dan tersambung ke jam lewat BLE. Galat, misalnya izin
  /// ditolak atau Bluetooth mati, ditampilkan lewat [link].
  Future<void> connect() async {
    try {
      await channel.invokeMethod<void>('start');
    } on PlatformException catch (error) {
      link.value = WatchLinkState(
        phase: LinkPhase.error,
        message: error.message ?? error.code,
      );
    } on MissingPluginException {
      link.value = const WatchLinkState(
        phase: LinkPhase.error,
        message: 'BLE tidak tersedia',
      );
    }
  }

  Future<void> disconnect() => channel.invokeMethod<void>('stop');

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onBatch':
        return receive((call.arguments as Map)['json'] as String);
      case 'onState':
        _onState((call.arguments as Map).cast<String, Object?>());
        return null;
      case 'onStatus':
        _onStatus(call.arguments as String);
        return null;
      default:
        throw MissingPluginException('Metode tidak dikenal: ${call.method}');
    }
  }

  void _onState(Map<String, Object?> state) {
    final phase =
        LinkPhase.values.asNameMap()[state['phase']] ?? LinkPhase.error;
    link.value = WatchLinkState(
      phase: phase,
      name: state['name'] as String?,
      message: state['message'] as String?,
      // Antrean dari jam hanya bermakna selama tersambung.
      pending: phase == LinkPhase.connected ? link.value.pending : null,
    );
  }

  /// Isi characteristic STATUS: `{"v":1,"pending":N}`.
  void _onStatus(String json) {
    try {
      final status = jsonDecode(json) as Map<String, Object?>;
      final now = link.value;
      link.value = WatchLinkState(
        phase: now.phase,
        name: now.name,
        message: now.message,
        pending: (status['pending'] as num?)?.toInt(),
      );
    } catch (error) {
      debugPrint('STATUS dari jam tidak terbaca: $error');
    }
  }

  /// Menyimpan satu kiriman. True bila tersimpan, termasuk bila semua
  /// barisnya ternyata sudah pernah diterima.
  Future<bool> receive(String json) async {
    try {
      final batch = decodeBatch(json);
      final inserted = await store.insertBatch(batch.table, batch.rows);
      recent.value = [
        ReceivedBatch(
          at: DateTime.now(),
          table: batch.table,
          rows: batch.rows.length,
          inserted: inserted,
        ),
        ...recent.value,
      ].take(recentLimit).toList(growable: false);
      return true;
    } catch (error) {
      debugPrint('Kiriman dari jam ditolak: $error');
      return false;
    }
  }
}
