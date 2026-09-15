import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_watch/measurement_store.dart';
import 'package:hr_sdk_005_watch/phone_link.dart';
import 'package:hr_sdk_005_watch/phone_sync.dart';
import 'package:hr_sdk_005_watch/samsung_health_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// HP palsu: mencatat kiriman yang diterimanya, dan bisa menolak satu kiriman.
class FakeLink implements PhoneLink {
  PhoneNode? phone = const PhoneNode(id: 'n1', name: 'Galaxy S23');
  final List<Map<String, Object?>> received = [];

  /// Kiriman ke-berapa (mulai 1) yang ditolak, sekali saja.
  int? rejectAt;
  int _attempts = 0;

  /// Pendengar yang dipasang PhoneSync, untuk menirukan kabar dari BleServer.kt.
  void Function()? phoneReady;
  void Function(String message)? linkError;

  /// Galat yang dilempar saat BLE dinyalakan, misalnya jam tanpa advertising.
  Object? startError;
  int? lastPending;

  @override
  Future<void> start() async {
    if (startError case final error?) throw error;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setPending(int pending) async => lastPending = pending;

  @override
  void listen({void Function()? onPhoneReady, void Function(String message)? onError}) {
    phoneReady = onPhoneReady;
    linkError = onError;
  }

  @override
  Future<PhoneNode?> connectedPhone() async => phone;

  @override
  Future<bool> sendBatch(String json) async {
    _attempts++;
    if (_attempts == rejectAt) return false;
    received.add(jsonDecode(json) as Map<String, Object?>);
    return true;
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

  List<String> tables() => [for (final b in link.received) b['table']! as String];
  int rowCount() => link.received.fold(0, (n, b) => n + (b['rows']! as List).length);

  test('semua baris terkirim per kelompok, lalu antrean kosong', () async {
    await sync.sync();

    // Akselerometer 600 baris terbagi 250 + 250 + 100.
    expect(tables(), ['heart_rate', 'spo2', 'accelerometer', 'accelerometer', 'accelerometer']);
    expect(rowCount(), 604);
    expect(link.received.every((b) => b['v'] == batchVersion), isTrue);
    expect((link.received.first['rows']! as List).first, containsPair('bpm', 71));

    expect(sync.status.value.totalPending, 0);
    expect(sync.status.value.lastSentRows, 604);
    expect(sync.status.value.phoneName, 'Galaxy S23');
    expect(sync.status.value.error, isNull);
  });

  test('kiriman yang ditolak dikirim ulang di putaran berikutnya', () async {
    link.rejectAt = 2; // kiriman SpO₂
    await sync.sync();

    expect(tables(), ['heart_rate']);
    expect(sync.status.value.error, isNotNull);
    expect(sync.status.value.pending, {'heart_rate': 0, 'spo2': 1, 'accelerometer': 600});

    await sync.sync();
    expect(tables(), ['heart_rate', 'spo2', 'accelerometer', 'accelerometer', 'accelerometer']);
    expect(rowCount(), 604, reason: 'tidak ada baris yang terkirim dua kali');
    expect(sync.status.value.totalPending, 0);
    expect(sync.status.value.error, isNull);
  });

  test('tanpa HP tersambung tidak ada yang dikirim', () async {
    link.phone = null;
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
    final last = link.received.last;
    expect(last['table'], 'spo2');
    expect((last['rows']! as List).single, containsPair('spo2_percent', 97));
  });

  test('jumlah antrean dilaporkan ke characteristic STATUS', () async {
    await sync.sync();
    expect(link.lastPending, 0);
  });

  test('START dari HP langsung memicu pengiriman', () async {
    sync.start();
    addTearDown(sync.stop);

    link.phoneReady!();
    for (var i = 0; link.received.length < 5 && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(link.received, hasLength(5));
  });

  test('galat menyalakan BLE tetap tampil, bukan sekadar "belum tersambung"', () async {
    link
      ..phone = null
      ..startError = PlatformException(
        code: 'NO_ADVERTISER',
        message: 'Jam ini tidak mendukung BLE advertising (peripheral)',
      );
    sync.start();
    addTearDown(sync.stop);
    await Future<void>.delayed(Duration.zero);

    await sync.sync();
    expect(sync.status.value.error, 'Jam ini tidak mendukung BLE advertising (peripheral)');
  });
}
