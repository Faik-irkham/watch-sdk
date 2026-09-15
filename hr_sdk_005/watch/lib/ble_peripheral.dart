import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Status BLE dari sisi native (watch berperan sebagai peripheral).
enum BleStatus { idle, advertising, connected, error }

/// Hasil satu percobaan pengiriman batch beserta konfirmasinya.
class BatchAckResult {
  const BatchAckResult({
    required this.batchId,
    required this.expected,
    this.ok = false,
    this.stored = 0,
    this.status = 'timeout',
    this.ackLatency,
  });

  /// Pengenal batch yang dikirim di frame START.
  final int batchId;

  /// Jumlah record yang dikirim watch.
  final int expected;

  /// `true` hanya bila ponsel mengonfirmasi batch **ini** tersimpan.
  final bool ok;

  /// Jumlah record yang baru tersimpan di ponsel.
  final int stored;

  /// `ok`, `parse_error`, `no_start`, `timeout`, atau `not_sent`.
  final String status;

  /// Waktu dari permintaan kirim sampai ACK yang cocok diterima.
  final Duration? ackLatency;

  /// Record yang ternyata sudah ada di ponsel sebelumnya.
  int get duplicates => ok ? expected - stored : 0;
}

/// Jembatan ke BLE GATT server native (HeartRateBleServer.kt, lihat
/// MainActivity.kt).
///
/// Disalin dari proyek basic_sensor_heart_rate_interval_sqflite_ble: UUID,
/// format frame, dan ACK sama persis. Perbedaannya hanya isi batch: selain
/// `device` dan `records`, batch membawa `table`, karena proyek ini mengirim
/// beberapa tabel (detak jantung, SpO₂, akselerometer). Setiap record adalah
/// baris SQLite apa adanya, dengan kolom `id` sebagai identitasnya.
class BlePeripheral {
  BlePeripheral._();

  static final BlePeripheral instance = BlePeripheral._();

  // Harus sama dengan nama channel di MainActivity.kt.
  static const _method = MethodChannel('heart_rate/ble');
  static const _statusChannel = EventChannel('heart_rate/ble/status');
  static const _ackChannel = EventChannel('heart_rate/ble/ack');

  /// Bila `false`, record ditandai terkirim begitu panggilan kirim lokal
  /// berhasil, **tanpa menunggu konfirmasi penerima** — perilaku versi awal
  /// proyek rujukan. Jalankan dengan `--dart-define=AWAIT_ACK=false`.
  static const awaitAck = bool.fromEnvironment('AWAIT_ACK', defaultValue: true);

  // Aliran ACK dari ponsel, berisi JSON {batch_id, expected, stored, status}.
  // ACK yang tidak bisa di-parse jadi map kosong agar tidak pernah cocok
  // dengan batch mana pun.
  Stream<Map<String, dynamic>>? _ackStream;
  Stream<Map<String, dynamic>> get _acks =>
      _ackStream ??= _ackChannel.receiveBroadcastStream().map((event) {
        try {
          final decoded = jsonDecode(event as String);
          if (decoded is Map) return decoded.cast<String, dynamic>();
        } catch (_) {
          // Ditangani sama seperti ACK yang bentuknya tak dikenal.
        }
        debugPrint('[HR-BLE] ACK tidak dikenali: $event');
        return <String, dynamic>{};
      }).asBroadcastStream();

  // Di-seed dari epoch detik agar tetap menaik walau aplikasi dimulai ulang,
  // sehingga ACK sesi sebelumnya tidak pernah cocok. Dibatasi 32 bit karena
  // frame START membawanya sebagai uint32.
  int _nextBatchId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  int _takeBatchId() {
    final id = _nextBatchId & 0xFFFFFFFF;
    _nextBatchId = id + 1;
    return id;
  }

  /// Status koneksi terkini, dipakai UI untuk menampilkan indikator.
  final ValueNotifier<BleStatus> status = ValueNotifier(BleStatus.idle);

  /// Pesan tambahan (mis. alamat perangkat yang terhubung atau pesan error).
  final ValueNotifier<String?> message = ValueNotifier(null);

  StreamSubscription<dynamic>? _statusSub;

  void _ensureListening() {
    _statusSub ??= _statusChannel.receiveBroadcastStream().listen(
      (event) {
        final data = (event as Map).cast<String, dynamic>();
        final state = data['state'] as String?;
        message.value = data['message'] as String?;
        status.value = switch (state) {
          'advertising' => BleStatus.advertising,
          'connected' => BleStatus.connected,
          'error' => BleStatus.error,
          _ => BleStatus.idle,
        };
        debugPrint('[HR-BLE] state=$state message=${message.value}');
      },
      onError: (Object err) {
        status.value = BleStatus.error;
        message.value = err is PlatformException ? err.message : err.toString();
      },
    );
  }

  /// Mulai mengiklankan service record agar smartphone bisa menemukan dan
  /// terhubung ke watch.
  Future<void> start() async {
    _ensureListening();
    try {
      await _method.invokeMethod('startAdvertising');
    } on PlatformException catch (e) {
      status.value = BleStatus.error;
      message.value = e.message;
    }
  }

  /// Hentikan advertising dan tutup GATT server.
  Future<void> stop() async {
    try {
      await _method.invokeMethod('stopAdvertising');
    } on PlatformException catch (_) {
      // Abaikan; menghentikan sesuatu yang sudah berhenti tidak apa-apa.
    }
    status.value = BleStatus.idle;
    message.value = null;
  }

  /// Kirim satu **batch** baris dari [table] ke smartphone yang sedang
  /// subscribe.
  ///
  /// Payload JSON: `{"device": …, "table": …, "records": [baris, …]}`.
  /// Pasangan `device` + `id` baris menjadi identitas record di ponsel. Native
  /// memecah payload menjadi beberapa notifikasi (chunk) dengan flow-control,
  /// lalu phone merangkainya kembali.
  ///
  /// Mengembalikan `true` jika native menerima permintaan kirim (ada perangkat
  /// terhubung dan tidak ada batch lain yang sedang dikirim).
  ///
  /// [batchId] dibawa frame START dan dikembalikan ponsel di dalam ACK.
  Future<bool> sendBatch(
    String table,
    List<Map<String, Object?>> records, {
    required int batchId,
    required String deviceId,
  }) async {
    if (records.isEmpty) return false;
    final json = jsonEncode({
      'device': deviceId,
      'table': table,
      'records': records,
    });
    try {
      final ok = await _method.invokeMethod<bool>('sendBatch', {
        'json': json,
        // Jumlah record dikirim agar native bisa mencatat metrik per batch.
        'count': records.length,
        'batchId': batchId,
      });
      return ok ?? false;
    } on PlatformException catch (_) {
      // Jika belum ada yang terhubung, native akan mengabaikan dengan aman.
      return false;
    }
  }

  /// Kirim batch lalu **tunggu ACK yang cocok** dari ponsel.
  ///
  /// Batch diberi `batch_id` unik yang dibawa frame START; ACK hanya diterima
  /// bila membawa `batch_id` yang sama **dan** `status == "ok"`.
  ///
  /// Hasilnya `ok == false` bila konfirmasi tidak datang dalam [timeout], agar
  /// pemanggil membiarkan record belum terkirim untuk dikirim ulang nanti.
  Future<BatchAckResult> sendBatchAndAwaitAck(
    String table,
    List<Map<String, Object?>> records, {
    required String deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final batchId = _takeBatchId();
    final expected = records.length;
    if (records.isEmpty) {
      return BatchAckResult(batchId: batchId, expected: 0, status: 'not_sent');
    }

    final completer = Completer<BatchAckResult>();
    final elapsed = Stopwatch()..start();

    void finish(BatchAckResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    // Berlangganan ACK sebelum mengirim agar tidak ada yang terlewat.
    final sub = _acks.listen((ack) {
      final id = (ack['batch_id'] as num?)?.toInt();
      if (id != batchId) {
        // ACK basi: milik batch lain, mis. yang sudah kedaluwarsa.
        debugPrint('[HR-BLE] ACK diabaikan (batch $id ≠ $batchId)');
        return;
      }
      final status = (ack['status'] as String?) ?? 'ok';
      finish(
        BatchAckResult(
          batchId: batchId,
          expected: expected,
          ok: status == 'ok',
          stored: (ack['stored'] as num?)?.toInt() ?? 0,
          status: status,
          ackLatency: elapsed.elapsed,
        ),
      );
    });
    final timer = Timer(timeout, () {
      finish(
        BatchAckResult(batchId: batchId, expected: expected, status: 'timeout'),
      );
    });

    final sent = await sendBatch(
      table,
      records,
      batchId: batchId,
      deviceId: deviceId,
    );
    if (!sent) {
      finish(
        BatchAckResult(
          batchId: batchId,
          expected: expected,
          status: 'not_sent',
        ),
      );
    } else if (!awaitAck) {
      // Versi awal: status kirim dimajukan oleh keberhasilan panggilan lokal,
      // bukan oleh konfirmasi penerima. Direproduksi apa adanya sebagai
      // kelompok pembanding.
      finish(
        BatchAckResult(
          batchId: batchId,
          expected: expected,
          ok: true,
          stored: expected,
          status: 'sent_unconfirmed',
          ackLatency: elapsed.elapsed,
        ),
      );
    }

    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    elapsed.stop();
    return result;
  }
}
