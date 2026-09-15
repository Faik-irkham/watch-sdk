import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_005_watch/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

/// Penghubung PhoneSync ke [BlePeripheral], dipisah agar PhoneSync bisa diuji
/// dengan HP palsu tanpa Bluetooth sungguhan.
class PhoneLink {
  const PhoneLink();

  BlePeripheral get _ble => BlePeripheral.instance;

  ValueListenable<BleStatus> get status => _ble.status;

  /// Alamat HP saat tersambung, atau pesan galat dari sisi native.
  ValueListenable<String?> get message => _ble.message;

  /// Minta izin Bluetooth, seperti MonitoringCubit di proyek rujukan, lalu
  /// mulai beriklan.
  Future<void> start() async {
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();
    if (!statuses.values.every((s) => s.isGranted)) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Izin Bluetooth ditolak',
      );
    }
    await _ble.start();
  }

  Future<void> stop() => _ble.stop();

  /// Kirim satu batch dan tunggu ACK yang cocok dari HP.
  Future<BatchAckResult> send(
    String table,
    List<Map<String, Object?>> rows, {
    required String deviceId,
  }) => _ble.sendBatchAndAwaitAck(table, rows, deviceId: deviceId);
}
