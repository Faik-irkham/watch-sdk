import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_003/measurement_store.dart';
import 'package:hr_sdk_003/samsung_health_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

HeartRateSample heartRate({required int status, int bpm = 79, int at = 1000}) =>
    HeartRateSample(
      heartRate: bpm,
      status: status,
      ibi: const [677, 682],
      ibiStatus: const [0, 0],
      timestamp: DateTime.fromMillisecondsSinceEpoch(at),
    );

Spo2Sample spo2({required int status, int value = 98, int at = 2000}) => Spo2Sample(
      spo2: value,
      status: status,
      heartRate: 83,
      accuracyFlag: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(at),
    );

void main() {
  sqfliteFfiInit();

  late MeasurementStore store;

  setUp(() {
    store = MeasurementStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  Future<List<Map<String, Object?>>> rows(String table) async =>
      (await store.database).query(table, orderBy: 'id');

  test('only heart rate readings with status 1 are saved', () async {
    expect(await store.saveHeartRate(heartRate(status: 0, at: 1)), 0);
    expect(await store.saveHeartRate(heartRate(status: -3, at: 2)), 0);
    expect(await store.saveHeartRate(heartRate(status: 1, at: 3)), 1);

    final saved = await rows('heart_rate');
    expect(saved, hasLength(1));
    expect(saved.single['measured_at'], 3);
    expect(saved.single['bpm'], 79);
    expect(saved.single['ibi_ms'], '[677,682]');
    expect(saved.single['ibi_status'], '[0,0]');
  });

  test('a heart rate point delivered twice is stored once', () async {
    expect(await store.saveHeartRate(heartRate(status: 1, at: 5)), 1);
    expect(await store.saveHeartRate(heartRate(status: 1, at: 5)), 0);
    expect(await rows('heart_rate'), hasLength(1));
  });

  test('only a completed SpO2 measurement is saved', () async {
    expect(await store.saveSpo2(spo2(status: 0, value: 0, at: 1)), 0);
    expect(await store.saveSpo2(spo2(status: -6, at: 2)), 0);
    expect(await store.saveSpo2(spo2(status: 2, at: 3)), 1);

    final saved = await rows('spo2');
    expect(saved, hasLength(1));
    expect(saved.single['spo2_percent'], 98);
    expect(saved.single['bpm'], 83);
  });

  test('an accelerometer batch is saved sample by sample', () async {
    final batch = AccelerometerBatch([
      for (var i = 0; i < 25; i++)
        AccelerometerSample(
          x: i,
          y: -i,
          z: 10,
          timestamp: DateTime.fromMillisecondsSinceEpoch(40 * i),
        ),
    ]);

    expect(await store.saveAccelerometer(batch), 25);

    final saved = await rows('accelerometer');
    expect(saved, hasLength(25));
    expect(saved.last['x'], 24);
    expect(saved.last['y'], -24);
    expect(saved.last['measured_at'], 960);
  });

  group('riwayat', () {
    test('detak jantung: terbaru di atas, dibatasi, total tetap utuh', () async {
      for (var i = 1; i <= 5; i++) {
        await store.saveHeartRate(heartRate(status: 1, bpm: 70 + i, at: i * 1000));
      }

      final history = await store.heartRateHistory(limit: 3);

      expect(history.total, 5);
      expect(history.items.map((r) => r.bpm), [75, 74, 73]);
      expect(history.items.first.measuredAt, DateTime.fromMillisecondsSinceEpoch(5000));
    });

    test('SpO2: hanya hasil selesai yang muncul', () async {
      await store.saveSpo2(spo2(status: 0, value: 0, at: 1000));
      await store.saveSpo2(spo2(status: 2, value: 97, at: 2000));
      await store.saveSpo2(spo2(status: 2, value: 98, at: 3000));

      final history = await store.spo2History();

      expect(history.total, 2);
      expect(history.items.map((r) => r.spo2Percent), [98, 97]);
      expect(history.items.first.bpm, 83);
    });

    test('akselerometer diringkas per detik', () async {
      AccelerometerSample at(int ms, int x) => AccelerometerSample(
            x: x,
            y: 0,
            z: -x,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
          );
      // Detik ke-1 berisi dua sampel, detik ke-2 berisi tiga sampel.
      await store.saveAccelerometer(AccelerometerBatch([
        at(1000, 10),
        at(1500, 20),
        at(2000, 30),
        at(2400, 60),
        at(2800, 90),
      ]));

      final history = await store.accelerometerHistory();

      expect(history.total, 5);
      expect(history.items, hasLength(2));
      final latest = history.items.first;
      expect(latest.second, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(latest.samples, 3);
      expect(latest.meanX, 60);
      expect(latest.meanZ, -60);
      expect(history.items.last.samples, 2);
      expect(history.items.last.meanX, 15);
    });

    test('tabel kosong menghasilkan riwayat kosong', () async {
      final history = await store.heartRateHistory();
      expect(history.items, isEmpty);
      expect(history.total, 0);
    });
  });

  test('gagal membuka sekali tidak membuat penyimpanan gagal selamanya', () async {
    final flaky = _FlakyFactory(databaseFactoryFfi);
    final retrying = MeasurementStore(factory: flaky, path: inMemoryDatabasePath);
    addTearDown(retrying.close);

    await expectLater(
      retrying.saveHeartRate(heartRate(status: 1, at: 1)),
      throwsStateError,
    );
    expect(await retrying.saveHeartRate(heartRate(status: 1, at: 2)), 1);
    expect(flaky.opens, 2);
  });
}

/// Gagal pada pembukaan pertama, lalu meneruskan ke pabrik yang sebenarnya.
class _FlakyFactory implements DatabaseFactory {
  _FlakyFactory(this.inner);

  final DatabaseFactory inner;
  int opens = 0;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    opens++;
    if (opens == 1) return Future.error(StateError('disk sibuk'));
    return inner.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
