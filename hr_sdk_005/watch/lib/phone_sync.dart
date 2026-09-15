import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_005_watch/measurement_store.dart';
import 'package:hr_sdk_005_watch/phone_link.dart';

/// Versi format kiriman; aplikasi HP menolak versi yang tidak dikenalnya.
const int batchVersion = 1;

/// Satu kiriman ke HP: nama tabel dan baris-barisnya apa adanya dari SQLite,
/// termasuk kolom `id` yang dipakai HP untuk mengabaikan kiriman ulang.
String encodeBatch(String table, List<Map<String, Object?>> rows) =>
    jsonEncode({'v': batchVersion, 'table': table, 'rows': rows});

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

  /// Nama HP yang tersambung; null bila belum ada.
  final String? phoneName;
  final bool sending;
  final DateTime? lastSentAt;
  final int lastSentRows;
  final String? error;

  int get totalPending => pending.values.fold(0, (sum, n) => sum + n);
}

/// Mengirim data yang tersimpan di jam ke HP (edge), dengan antrean di SQLite.
///
/// Jalurnya BLE: jam menjadi GATT server, HP tersambung sebagai central.
/// Notifikasi BLE tidak dikonfirmasi penerimanya, jadi setiap kelompok baris
/// baru ditandai terkirim setelah HP menulis ACK, yaitu setelah kelompok itu
/// tersimpan di HP. Kelompok yang gagal dikirim ulang pada putaran berikutnya,
/// dan HP mengabaikan baris yang sudah pernah diterimanya.
class PhoneSync {
  PhoneSync({MeasurementStore? store, PhoneLink? link})
    : store = store ?? MeasurementStore.instance,
      link = link ?? const PhoneLink();

  static final PhoneSync instance = PhoneSync();

  /// Baris per kiriman: sekitar 10 detik akselerometer, jadi pesan tetap kecil.
  static const int batchSize = 250;

  /// Jeda antarputaran otomatis selama aplikasi terbuka.
  static const Duration period = Duration(seconds: 30);

  final MeasurementStore store;
  final PhoneLink link;
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  Timer? _timer;
  bool _busy = false;

  /// Galat saat menyalakan BLE di jam; ditampilkan selama belum teratasi.
  String? _linkError;

  /// Menyalakan iklan BLE dan pengiriman berkala. HP yang baru tersambung
  /// menulis START, dan jam langsung mengirim tanpa menunggu putaran berikutnya.
  void start() {
    _timer ??= Timer.periodic(period, (_) => sync());
    link.listen(
      onPhoneReady: sync,
      onError: (message) => _emit(error: _linkError = message),
    );
    unawaited(_startLink());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    link.listen();
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

  /// Memperbarui jumlah antrean dan HP yang tersambung, tanpa mengirim.
  Future<void> refresh() async {
    await _checkPhone();
    await _refreshPending();
  }

  /// Mengirim semua baris yang belum diterima HP, tabel demi tabel, per
  /// kelompok [batchSize] baris. Berhenti di kelompok pertama yang gagal.
  ///
  /// [manual] (tombol Kirim) juga mencoba lagi menyalakan BLE bila sebelumnya
  /// gagal, misalnya setelah Bluetooth dinyalakan atau izinnya diberikan.
  Future<void> sync({bool manual = false}) async {
    if (_busy) return;
    if (manual && _linkError != null) await _startLink();
    _busy = true;
    _emit(sending: true);
    try {
      final phone = await _checkPhone();
      if (phone == null) return;
      var sent = 0;
      for (final table in MeasurementStore.syncTables) {
        while (true) {
          final rows = await store.pendingRows(table, limit: batchSize);
          if (rows.isEmpty) break;
          if (!await link.sendBatch(encodeBatch(table, rows))) {
            _emit(error: 'HP menolak kiriman; dicoba lagi nanti');
            return;
          }
          await store.markSynced(table, rows.last['id']! as int);
          sent += rows.length;
          await _refreshPending();
        }
      }
      if (sent > 0) _emit(lastSentAt: DateTime.now(), lastSentRows: sent);
    } catch (error) {
      _emit(error: describeSyncError(error));
    } finally {
      await _refreshPending();
      _busy = false;
      _emit(sending: false);
    }
  }

  Future<PhoneNode?> _checkPhone() async {
    try {
      final phone = await link.connectedPhone();
      if (phone == null) {
        _emit(
          clearPhone: true,
          error: _linkError ?? 'HP belum tersambung lewat BLE',
        );
      } else {
        _emit(phoneName: phone.name, clearError: true);
      }
      return phone;
    } catch (error) {
      _emit(clearPhone: true, error: describeSyncError(error));
      return null;
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
      // Dibaca HP lewat characteristic STATUS.
      await link.setPending(status.value.totalPending);
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

String describeSyncError(Object error) => error is PlatformException
    ? (error.message ?? error.code)
    : error.toString();
