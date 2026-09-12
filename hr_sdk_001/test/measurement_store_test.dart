import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_001/measurement_store.dart';
import 'package:hr_sdk_001/heart_rate_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

HeartRateSample heartRate({required int status, int bpm = 79, int at = 1000}) =>
    HeartRateSample(
      heartRate: bpm,
      status: status,
      ibi: const [677, 682],
      ibiStatus: const [0, 0],
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
