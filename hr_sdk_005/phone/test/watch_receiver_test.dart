import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/watch_receiver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String batch(
  String table,
  List<Map<String, Object?>> rows, {
  int v = batchVersion,
}) => jsonEncode({'v': v, 'table': table, 'rows': rows});

const spo2Row = {
  'id': 7,
  'measured_at': 5000,
  'spo2_percent': 98,
  'bpm': 72,
  'accuracy_flag': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late EdgeStore store;
  late WatchReceiver receiver;

  setUp(() {
    store = EdgeStore(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    receiver = WatchReceiver(store: store);
  });

  tearDown(() {
    receiver.detach();
    return store.close();
  });

  /// Menirukan BleClient.kt yang memanggil Dart lewat kanal edge/watch.
  Future<Object?> fromKotlin(String method, Object? arguments) async {
    receiver.attach();
    const codec = StandardMethodCodec();
    Object? answer;
    var answered = false;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          WatchReceiver.channel.name,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (reply) {
            answer = codec.decodeEnvelope(reply!);
            answered = true;
          },
        );
    // Penyimpanan berjalan di isolat SQLite; tunggu jawabannya sebentar.
    for (var i = 0; !answered && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return answer;
  }

  test('kiriman yang sah disimpan dan dicatat', () async {
    expect(await receiver.receive(batch('spo2', [spo2Row])), isTrue);

    expect((await store.snapshot()).counts['spo2'], 1);
    expect(receiver.recent.value.single.table, 'spo2');
    expect(receiver.recent.value.single.inserted, 1);
  });

  test('kiriman ulang tetap dijawab berhasil, tanpa baris baru', () async {
    await receiver.receive(batch('spo2', [spo2Row]));

    expect(await receiver.receive(batch('spo2', [spo2Row])), isTrue);
    expect(receiver.recent.value.first.inserted, 0);
    expect((await store.snapshot()).counts['spo2'], 1);
  });

  test('kiriman yang tidak dikenal dijawab gagal', () async {
    expect(await receiver.receive('bukan json'), isFalse);
    expect(await receiver.receive(batch('spo2', [spo2Row], v: 2)), isFalse);
    expect(await receiver.receive(batch('ppg', [spo2Row])), isFalse);
    expect(receiver.recent.value, isEmpty);
  });

  test('onBatch dari BleClient.kt dijawab dengan hasil penyimpanan', () async {
    final answer = await fromKotlin('onBatch', {
      'json': batch('spo2', [spo2Row]),
    });

    expect(answer, isTrue);
    expect((await store.snapshot()).counts['spo2'], 1);
  });

  test('onState dan onStatus memperbarui keadaan sambungan BLE', () async {
    await fromKotlin('onState', {
      'phase': 'connected',
      'name': 'Galaxy Watch4',
      'message': null,
    });
    expect(receiver.link.value.phase, LinkPhase.connected);
    expect(receiver.link.value.name, 'Galaxy Watch4');

    await fromKotlin('onStatus', '{"v":1,"pending":12}');
    expect(receiver.link.value.pending, 12);

    await fromKotlin('onState', {
      'phase': 'disconnected',
      'name': 'Galaxy Watch4',
      'message': null,
    });
    expect(receiver.link.value.phase, LinkPhase.disconnected);
    expect(receiver.link.value.pending, isNull);
  });

  test('tanpa sisi Kotlin, connect melaporkan galat', () async {
    await receiver.connect();

    expect(receiver.link.value.phase, LinkPhase.error);
    expect(receiver.link.value.message, 'BLE tidak tersedia');
  });
}
