import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_005_watch/ble_peripheral.dart';
import 'package:hr_sdk_005_watch/measurement_store.dart';
import 'package:hr_sdk_005_watch/phone_link.dart';

/// Keadaan pengiriman ke HP, untuk halaman "Kirim ke HP".
@immutable
class SyncStatus {
  const SyncStatus({
    this.pending = const {},
    this.phoneName,
    this.sending = false,
    this.lastSentAt,
    this.lastSentRows = 0,
    this.error,
  });

  /// Jumlah baris yang belum diterima HP, per tabel.
  final Map<String, int> pending;

  /// Alamat atau nama HP yang tersambung; null bila belum ada.
  final String? phoneName;
  final bool sending;
  final DateTime? lastSentAt;
  final int lastSentRows;
  final String? error;

  int get totalPending => pending.values.fold(0, (sum, n) => sum + n);
}

/// Mengirim data yang tersimpan di jam ke HP (edge), dengan antrean di SQLite.
///
/// Jalur BLE-nya sama dengan proyek basic_sensor_heart_rate_interval_sqflite_ble
/// (lihat [BlePeripheral]): setiap kelompok baris dikirim sebagai satu batch,
/// lalu jam menunggu ACK dengan `batch_id` yang sama dari HP. Hanya batch yang
/// dikonfirmasi `ok` yang memajukan penanda antrean; sisanya dikirim ulang
/// pada putaran berikutnya, dan HP mengabaikan baris yang sudah pernah
/// diterimanya.
class PhoneSync {
  PhoneSync({MeasurementStore? store, PhoneLink? link})
    : store = store ?? MeasurementStore.instance,
      link = link ?? const PhoneLink();

  static final PhoneSync instance = PhoneSync();

  /// Baris per batch: sekitar 10 detik akselerometer, jadi batch tetap kecil.
  static const int batchSize = 250;

  /// Jeda antarputaran otomatis selama aplikasi terbuka.
  static const Duration period = Duration(seconds: 30);

  final MeasurementStore store;
  final PhoneLink link;
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  Timer? _timer;
  bool _busy = false;
  bool _listening = false;
  BleStatus _lastStatus = BleStatus.idle;

  /// Galat BLE di jam; ditampilkan selama belum teratasi.
  String? _linkError;

  /// Menyalakan iklan BLE dan pengiriman berkala.
  void start() {
    _timer ??= Timer.periodic(period, (_) => sync());
    if (!_listening) {
      link.status.addListener(_onLinkChanged);
      _listening = true;
    }
    unawaited(_startLink());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_listening) {
      link.status.removeListener(_onLinkChanged);
      _listening = false;
    }
    unawaited(
      link.stop().catchError((Object error) {
        debugPrint('Gagal menghentikan BLE: $error');
      }),
    );
  }

  Future<void> _startLink() async {
    try {
      await link.start();
      _linkError = null;
    } catch (error) {
      _emit(error: _linkError = describeSyncError(error));
    }
  }

  /// Seperti proyek rujukan: begitu HP tersambung kembali, antrean dikirim
  /// tanpa menunggu putaran berikutnya.
  void _onLinkChanged() {
    final now = link.status.value;
    final reconnected =
        now == BleStatus.connected && _lastStatus != BleStatus.connected;
    _lastStatus = now;
    _showLink();
    if (reconnected) unawaited(sync());
  }

  /// Menampilkan keadaan BLE terkini tanpa mengirim.
  void _showLink() {
    switch (link.status.value) {
      case BleStatus.connected:
        _emit(phoneName: link.message.value ?? 'HP', clearError: true);
      case BleStatus.error:
        _emit(
          clearPhone: true,
          error: _linkError = link.message.value ?? 'BLE error',
        );
      case BleStatus.advertising:
        _linkError = null;
        _emit(clearPhone: true, clearError: true);
      case BleStatus.idle:
        _emit(clearPhone: true);
    }
  }

  /// Memperbarui keadaan BLE dan jumlah antrean, tanpa mengirim.
  Future<void> refresh() async {
    _showLink();
    await _refreshPending();
  }

  /// Mengirim semua baris yang belum diterima HP, tabel demi tabel, per
  /// kelompok [batchSize] baris. Berhenti di batch pertama yang tidak
  /// dikonfirmasi.
  ///
  /// [manual] (tombol Kirim) juga mencoba lagi menyalakan BLE bila sebelumnya
  /// gagal, misalnya setelah Bluetooth dinyalakan atau izinnya diberikan.
  Future<void> sync({bool manual = false}) async {
    if (_busy) return;
    if (manual && _linkError != null) await _startLink();
    _busy = true;
    _emit(sending: true);
    try {
      _showLink();
      if (link.status.value != BleStatus.connected) {
        _emit(
          clearPhone: true,
          error: _linkError ?? 'HP belum tersambung lewat BLE',
        );
        return;
      }
      final deviceId = await store.deviceId();
      var sent = 0;
      for (final table in MeasurementStore.syncTables) {
        while (true) {
          final rows = await store.pendingRows(table, limit: batchSize);
          if (rows.isEmpty) break;
          final ack = await link.send(table, rows, deviceId: deviceId);
          if (!ack.ok) {
            _emit(error: describeAck(ack));
            return;
          }
          await store.markSynced(table, rows.last['id']! as int);
          sent += rows.length;
          await _refreshPending();
        }
      }
      _emit(clearError: true);
      if (sent > 0) _emit(lastSentAt: DateTime.now(), lastSentRows: sent);
    } catch (error) {
      _emit(error: describeSyncError(error));
    } finally {
      await _refreshPending();
      _busy = false;
      _emit(sending: false);
    }
  }

  Future<void> _refreshPending() async {
    try {
      _emit(
        pending: {
          for (final table in MeasurementStore.syncTables)
            table: await store.pendingCount(table),
        },
      );
    } catch (error) {
      debugPrint('Gagal membaca antrean kirim: $error');
    }
  }

  void _emit({
    Map<String, int>? pending,
    String? phoneName,
    bool clearPhone = false,
    bool? sending,
    DateTime? lastSentAt,
    int? lastSentRows,
    String? error,
    bool clearError = false,
  }) {
    final now = status.value;
    status.value = SyncStatus(
      pending: pending ?? now.pending,
      phoneName: clearPhone ? null : (phoneName ?? now.phoneName),
      sending: sending ?? now.sending,
      lastSentAt: lastSentAt ?? now.lastSentAt,
      lastSentRows: lastSentRows ?? now.lastSentRows,
      error: clearError ? null : (error ?? now.error),
    );
  }
}

/// Keterangan batch yang tidak dikonfirmasi, menurut status ACK dari HP.
String describeAck(BatchAckResult ack) => switch (ack.status) {
  'timeout' => 'HP tidak membalas kiriman; dicoba lagi nanti',
  'not_sent' => 'Kiriman tidak dapat dikirim; dicoba lagi nanti',
  _ => 'HP menolak kiriman (${ack.status}); dicoba lagi nanti',
};

String describeSyncError(Object error) => error is PlatformException
    ? (error.message ?? error.code)
    : error.toString();
