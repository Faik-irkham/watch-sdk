import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> heartRate(int id, {int bpm = 76}) => {
  'id': id,
  'measured_at': 1000 * id,
  'bpm': bpm,
  'ibi_ms': '[800]',
  'ibi_status': '[0]',
};

void main() {
  sqfliteFfiInit();

  late EdgeStore store;

  setUp(() {
    store = EdgeStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => store.close());

  test('batch tersimpan, batch ulang tidak menggandakan data', () async {
    expect(
      await store.insertBatch('heart_rate', [
        heartRate(1),
        heartRate(2),
      ], deviceId: 'jam-1'),
      2,
    );
    expect(
      await store.insertBatch('heart_rate', [
        heartRate(2),
        heartRate(3),
      ], deviceId: 'jam-1'),
      1,
    );

    final snapshot = await store.snapshot();
    expect(snapshot.counts['heart_rate'], 3);
    expect(snapshot.latest['heart_rate'], containsPair('watch_id', 3));
    expect(snapshot.latest['heart_rate'], containsPair('device_id', 'jam-1'));
  });

  test('id baris yang sama dari jam lain tetap disimpan', () async {
    await store.insertBatch('heart_rate', [heartRate(1)], deviceId: 'jam-1');

    expect(
      await store.insertBatch('heart_rate', [heartRate(1)], deviceId: 'jam-2'),
      1,
    );
    expect((await store.snapshot()).counts['heart_rate'], 2);
  });

  test('baris tidak lengkap membatalkan seluruh batch', () async {
    await expectLater(
      store.insertBatch('heart_rate', [
        heartRate(1),
        {'id': 2, 'measured_at': 2000},
      ], deviceId: 'jam-1'),
      throwsA(anything),
    );
    expect((await store.snapshot()).counts['heart_rate'], 0);
  });

  test(
    'batch tanpa identitas jam atau tabel yang tidak dikenal ditolak',
    () async {
      await expectLater(
        store.insertBatch('heart_rate', [heartRate(1)], deviceId: ''),
        throwsFormatException,
      );
      await expectLater(
        store.insertBatch('ppg', [heartRate(1)], deviceId: 'jam-1'),
        throwsArgumentError,
      );
    },
  );

  test('ringkasan: jumlah, baris terbaru, dan waktu terima terakhir', () async {
    await store.insertBatch(
      'spo2',
      [
        {
          'id': 1,
          'measured_at': 5000,
          'spo2_percent': 98,
          'bpm': 72,
          'accuracy_flag': 0,
        },
      ],
      deviceId: 'jam-1',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(9000),
    );
    await store.insertBatch(
      'accelerometer',
      [
        for (var i = 1; i <= 3; i++)
          {'id': i, 'measured_at': i * 40, 'x': i, 'y': 0, 'z': 4096},
      ],
      deviceId: 'jam-1',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(8000),
    );

    final snapshot = await store.snapshot();
    expect(snapshot.counts, {'heart_rate': 0, 'spo2': 1, 'accelerometer': 3});
    expect(snapshot.latest['heart_rate'], isNull);
    expect(snapshot.latest['accelerometer'], containsPair('x', 3));
    expect(snapshot.lastReceivedAt, DateTime.fromMillisecondsSinceEpoch(9000));
  });
}
