import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_002/measurement_store.dart';
import 'package:hr_sdk_002/samsung_health_service.dart';
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
}
