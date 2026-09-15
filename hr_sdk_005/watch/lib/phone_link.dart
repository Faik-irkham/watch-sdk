import 'package:flutter/services.dart';

/// HP yang tersambung ke jam lewat BLE.
class PhoneNode {
  const PhoneNode({required this.id, required this.name});

  /// Alamat Bluetooth HP.
  final String id;
  final String name;
}

/// Kanal ke BleServer.kt: jam sebagai peripheral BLE (GATT server).
class PhoneLink {
  const PhoneLink();

  static const MethodChannel _channel = MethodChannel('edge/phone');

  /// Menyalakan GATT server dan iklan BLE. Melempar [PlatformException] bila
  /// Bluetooth mati, izin ditolak, atau jam tidak mendukung BLE advertising.
  Future<void> start() => _channel.invokeMethod<void>('start');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// HP yang sudah menyalakan notifikasi DATA, atau null bila belum ada.
  Future<PhoneNode?> connectedPhone() async {
    final node = await _channel.invokeMapMethod<String, Object?>(
      'connectedPhone',
    );
    if (node == null) return null;
    return PhoneNode(id: node['id']! as String, name: node['name']! as String);
  }

  /// Mengirim satu kiriman JSON lewat notifikasi DATA. True bila HP membalas
  /// ACK (sudah disimpan), false bila HP meminta kirim ulang (RETRY).
  Future<bool> sendBatch(String json) async =>
      await _channel.invokeMethod<bool>('sendBatch', json) ?? false;

  /// Jumlah antrean yang dibaca HP lewat characteristic STATUS.
  Future<void> setPending(int pending) =>
      _channel.invokeMethod<void>('setPending', pending);

  /// Kabar dari BleServer.kt: HP menulis START (siap menerima), atau iklan BLE
  /// gagal. Tanpa argumen berarti berhenti mendengarkan.
  void listen({
    void Function()? onPhoneReady,
    void Function(String message)? onError,
  }) {
    if (onPhoneReady == null && onError == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'phoneReady':
          onPhoneReady?.call();
        case 'linkError':
          onError?.call(call.arguments as String);
      }
      return null;
    });
  }
}
