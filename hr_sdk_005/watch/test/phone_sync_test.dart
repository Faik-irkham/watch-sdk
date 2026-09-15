import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_watch/ble_peripheral.dart';
import 'package:hr_sdk_005_watch/measurement_store.dart';
import 'package:hr_sdk_005_watch/phone_link.dart';
import 'package:hr_sdk_005_watch/phone_sync.dart';
import 'package:hr_sdk_005_watch/samsung_health_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// HP palsu di ujung BLE: mencatat batch yang diterimanya, dan bisa menolak
/// satu batch seperti NACK dari heart_rate_phone_receiver.
class FakeLink implements PhoneLink {
  @override
  final ValueNotifier<BleStatus> status = ValueNotifier(BleStatus.connected);

  @override
  final ValueNotifier<String?> message = ValueNotifier('AA:BB:CC:DD:EE:FF');

  final List<({String table, List<Map<String, Object?>> rows, String device})>
  received = [];

  /// Batch ke-berapa (mulai 1) yang ditolak, sekali saja.
  int? rejectAt;
  int _attempts = 0;

  /// Galat saat BLE dinyalakan, misalnya izin ditolak.
  Object? startError;

  @override
  Future<void> start() async {
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<BatchAckResult> send(
    String table,
    List<Map<String, Object?>> rows, {
    required String deviceId,
  }) async {
    _attempts++;
    if (_attempts == rejectAt) {
      return BatchAckResult(
        batchId: _attempts,
        expected: rows.length,
        status: 'crc_mismatch',
      );
    }
    received.add((table: table, rows: rows, device: deviceId));
    return BatchAckResult(
      batchId: _attempts,
      expected: rows.length,
      ok: true,
      stored: rows.length,
      status: 'ok',
    );
  }
}

void main() {
  sqfliteFfiInit();

  late MeasurementStore store;
  late FakeLink link;
  late PhoneSync sync;

  setUp(() async {
    store = MeasurementStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    link = FakeLink();
    sync = PhoneSync(store: store, link: link);

    for (var i = 1; i <= 3; i++) {
      await store.saveHeartRate(HeartRateSample(
        heartRate: 70 + i,
        status: 1,
        ibi: const [800],
        ibiStatus: const [0],
        timestamp: DateTime.fromMillisecondsSinceEpoch(i * 1000),
      ));
    }
    await store.saveSpo2(Spo2Sample(
      spo2: 98,
      status: 2,
      heartRate: 72,
      accuracyFlag: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(5000),
    ));
    await store.saveAccelerometer(AccelerometerBatch([
      for (var i = 0; i < 600; i++)
        AccelerometerSample(
          x: i,
          y: 0,
          z: 4096,
          timestamp: DateTime.fromMillisecondsSinceEpoch(6000 + i * 40),
        ),
    ]));
  });

  tearDown(() => store.close());

  List<String> tables() => [for (final b in link.received) b.table];
  int rowCount() => link.received.fold(0, (n, b) => n + b.rows.length);

  test('semua baris terkirim per batch, lalu antrean kosong', () async {
    await sync.sync();

    // Akselerometer 600 baris terbagi 250 + 250 + 100.
    expect(tables(), ['heart_rate', 'spo2', 'accelerometer', 'accelerometer', 'accelerometer']);
    expect(rowCount(), 604);
    expect(link.received.first.rows.first, containsPair('bpm', 71));

    expect(sync.status.value.totalPending, 0);
    expect(sync.status.value.lastSentRows, 604);
    expect(sync.status.value.phoneName, 'AA:BB:CC:DD:EE:FF');
    expect(sync.status.value.error, isNull);
  });

  test('setiap batch membawa identitas jam yang sama', () async {
    await sync.sync();

    final id = await store.deviceId();
    expect(link.received.map((b) => b.device).toSet(), {id});
  });

  test('batch yang ditolak HP dikirim ulang di putaran berikutnya', () async {
    link.rejectAt = 2; // batch SpO₂
    await sync.sync();

    expect(tables(), ['heart_rate']);
    expect(sync.status.value.error, contains('crc_mismatch'));
    expect(sync.status.value.pending, {'heart_rate': 0, 'spo2': 1, 'accelerometer': 600});

    await sync.sync();
    expect(tables(), ['heart_rate', 'spo2', 'accelerometer', 'accelerometer', 'accelerometer']);
    expect(rowCount(), 604, reason: 'tidak ada baris yang terkirim dua kali');
    expect(sync.status.value.totalPending, 0);
    expect(sync.status.value.error, isNull);
  });

  test('tanpa HP tersambung tidak ada yang dikirim', () async {
    link.status.value = BleStatus.advertising;
    await sync.sync();

    expect(link.received, isEmpty);
    expect(sync.status.value.error, 'HP belum tersambung lewat BLE');
    expect(sync.status.value.totalPending, 604);
  });

  test('baris yang tersimpan setelah pengiriman ikut di putaran berikutnya', () async {
    await sync.sync();
    await store.saveSpo2(Spo2Sample(
      spo2: 97,
      status: 2,
      heartRate: 70,
      accuracyFlag: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(90000),
    ));

    await sync.sync();
    expect(link.received.last.table, 'spo2');
    expect(link.received.last.rows.single, containsPair('spo2_percent', 97));
  });

  test('HP yang tersambung kembali langsung memicu pengiriman', () async {
    link.status.value = BleStatus.advertising;
    sync.start();
    addTearDown(sync.stop);

    link.status.value = BleStatus.connected;
    for (var i = 0; link.received.length < 5 && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(link.received, hasLength(5));
  });

  test('galat menyalakan BLE tetap tampil, bukan sekadar "belum tersambung"', () async {
    link
      ..status.value = BleStatus.idle
      ..startError = PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Izin Bluetooth ditolak',
      );
    sync.start();
    addTearDown(sync.stop);
    await Future<void>.delayed(Duration.zero);

    await sync.sync();
    expect(sync.status.value.error, 'Izin Bluetooth ditolak');
  });
}
