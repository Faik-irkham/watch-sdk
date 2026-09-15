import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_phone/ble_receiver.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/utils/crc32.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<int> _u32(int v) => [
  v >> 24 & 0xFF,
  v >> 16 & 0xFF,
  v >> 8 & 0xFF,
  v & 0xFF,
];

/// Frame persis seperti HeartRateBleServer.kt di jam:
/// START | batch_id(4) | jumlah DATA(2) | panjang payload(4), lalu
/// DATA | seq(2) | potongan, lalu END | crc32(4).
List<List<int>> framesOf(
  String json, {
  required int batchId,
  int chunk = 20,
  bool corruptCrc = false,
  bool dropSecond = false,
}) {
  final bytes = utf8.encode(json);
  final data = <List<int>>[];
  for (var i = 0, seq = 0; i < bytes.length; i += chunk, seq++) {
    data.add([
      0x02,
      seq >> 8 & 0xFF,
      seq & 0xFF,
      ...bytes.sublist(i, min(i + chunk, bytes.length)),
    ]);
  }
  final crc = crc32(bytes) ^ (corruptCrc ? 1 : 0);
  return [
    [
      0x01,
      ..._u32(batchId),
      data.length >> 8 & 0xFF,
      data.length & 0xFF,
      ..._u32(bytes.length),
    ],
    for (var i = 0; i < data.length; i++)
      if (!(dropSecond && i == 1)) data[i],
    [0x03, ..._u32(crc)],
  ];
}

String spo2Batch({String table = 'spo2', String device = 'jam-1'}) =>
    jsonEncode({
      'device': device,
      'table': table,
      'records': [
        {
          'id': 7,
          'measured_at': 5000,
          'spo2_percent': 98,
          'bpm': 72,
          'accuracy_flag': 0,
        },
      ],
    });

void main() {
  sqfliteFfiInit();

  late EdgeStore store;
  late List<Map<String, dynamic>> acks;
  late BleReceiver receiver;

  setUp(() {
    store = EdgeStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    acks = [];
    receiver = BleReceiver.forTest(
      store,
      ackWriter: (payload) async =>
          acks.add(jsonDecode(payload) as Map<String, dynamic>),
    );
  });

  tearDown(() => store.close());

  Future<void> feed(List<List<int>> frames) async {
    for (final frame in frames) {
      await receiver.handleValue(frame);
    }
  }

  test(
    'batch utuh disimpan lalu dibalas ACK ok dengan batch_id yang sama',
    () async {
      await feed(framesOf(spo2Batch(), batchId: 4242));

      expect(acks.single, {
        'batch_id': 4242,
        'expected': 1,
        'stored': 1,
        'status': 'ok',
      });
      expect((await store.snapshot()).counts['spo2'], 1);
      expect(receiver.recent.value.single.table, 'spo2');
    },
  );

  test('batch yang dikirim ulang dibalas ok tanpa baris baru', () async {
    await feed(framesOf(spo2Batch(), batchId: 1));
    await feed(framesOf(spo2Batch(), batchId: 2));

    expect(acks.last, {
      'batch_id': 2,
      'expected': 1,
      'stored': 0,
      'status': 'ok',
    });
    expect((await store.snapshot()).counts['spo2'], 1);
  });

  test(
    'CRC tidak cocok dibalas NACK crc_mismatch dan tidak disimpan',
    () async {
      await feed(framesOf(spo2Batch(), batchId: 3, corruptCrc: true));

      expect(acks.single['status'], 'crc_mismatch');
      expect((await store.snapshot()).counts['spo2'], 0);
    },
  );

  test('frame DATA yang hilang dibalas NACK missing_frames', () async {
    await feed(framesOf(spo2Batch(), batchId: 4, dropSecond: true));

    expect(acks.single['status'], 'missing_frames');
    expect((await store.snapshot()).counts['spo2'], 0);
  });

  test('tabel yang tidak dikenal dibalas parse_error', () async {
    await feed(framesOf(spo2Batch(table: 'ppg'), batchId: 5));

    expect(acks.single['status'], 'parse_error');
  });
}
