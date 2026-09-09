import 'package:flutter/services.dart';

/// Sensor yang bisa diminta izinnya.
///
/// Sejak Wear OS 6 (Android 16) izin sensor tubuh pindah ke Health Connect dan
/// tiap sensor punya izin sendiri, jadi permintaan izin dibedakan per sensor.
enum HealthSensor {
  heartRate,
  spo2;

  Map<String, String> get _args => {'sensor': name};
}

/// Kabar dari sisi Android yang bukan hasil pengukuran (koneksi, selesai, dsb).
class TrackerStatus {
  const TrackerStatus(this.state, this.message);

  final String state;
  final String message;

  /// Pengukuran sekali jalan sudah rampung dan sensor dimatikan.
  bool get isCompleted => state == 'completed';
}

/// Satu pembacaan detak jantung.
class HeartRateSample {
  const HeartRateSample({
    required this.heartRate,
    required this.status,
    required this.ibi,
    required this.ibiStatus,
    required this.timestamp,
  });

  factory HeartRateSample.fromMap(Map<Object?, Object?> map) {
    return HeartRateSample(
      heartRate: _int(map['heartRate']),
      status: _int(map['heartRateStatus']),
      ibi: _intList(map['ibi']),
      ibiStatus: _intList(map['ibiStatus']),
      timestamp: _time(map['timestamp']),
    );
  }

  /// Detak per menit. Hanya bermakna kalau [isValid] true.
  final int heartRate;

  /// Kode status mentah dari SDK, lihat [statusMessage].
  final int status;

  /// Inter-beat interval (ms) sejak pembacaan sebelumnya.
  final List<int> ibi;

  /// Status tiap elemen [ibi]; 0 berarti valid.
  final List<int> ibiStatus;

  final DateTime timestamp;

  bool get isValid => status == 1;

  /// Terjemahan kode status yang umum muncul. Tabel lengkapnya ada di
  /// dokumentasi Samsung Health Sensor SDK (ValueKey.HeartRateSet).
  String get statusMessage {
    switch (status) {
      case 1:
        return 'Pengukuran valid';
      case 0:
        return 'Belum ada data';
      case -1:
        return 'Sinyal belum stabil';
      case -2:
        return 'Jam tidak menempel di pergelangan';
      case -10:
        return 'Jam tidak dipakai';
      case -99:
        return 'Gagal membaca sensor';
      default:
        return 'Status sensor: $status';
    }
  }
}

/// Satu pembacaan saturasi oksigen.
///
/// SpO2 diukur sekali jalan: sensor mengirim kabar berkala dengan status
/// [statusCalculating] selama menghitung, lalu satu hasil akhir dengan status
/// [statusCompleted].
class Spo2Sample {
  const Spo2Sample({
    required this.spo2,
    required this.status,
    required this.heartRate,
    required this.accuracyFlag,
    required this.timestamp,
  });

  factory Spo2Sample.fromMap(Map<Object?, Object?> map) {
    return Spo2Sample(
      spo2: _int(map['spo2']),
      status: _int(map['spo2Status']),
      heartRate: _int(map['heartRate']),
      accuracyFlag: _int(map['accuracyFlag']),
      timestamp: _time(map['timestamp']),
    );
  }

  /// Sensor masih menghitung; nilai [spo2] belum final.
  static const int statusCalculating = 0;

  /// Pengukuran rampung; [spo2] sudah final.
  static const int statusCompleted = 2;

  /// Saturasi oksigen dalam persen. Bermakna kalau [isComplete] true.
  final int spo2;

  final int status;

  /// Detak jantung yang terbaca berbarengan dengan pengukuran SpO2.
  final int heartRate;

  final int accuracyFlag;

  final DateTime timestamp;

  bool get isComplete => status == statusCompleted;

  bool get isCalculating => status == statusCalculating;

  String get statusMessage {
    if (isComplete) return 'Pengukuran selesai';
    if (isCalculating) return 'Menghitung… tahan tangan tetap diam';
    // Kode negatif menandakan pengukuran terganggu (gerakan, sinyal lemah,
    // jam longgar). Kodenya ditampilkan apa adanya supaya mudah dicocokkan
    // dengan tabel di dokumentasi Samsung.
    return 'Pengukuran terganggu — tahan tangan tetap diam (kode $status)';
  }
}

/// Akses ke sensor Samsung Health Sensor SDK.
///
/// Stream baru mengalir setelah izin `BODY_SENSORS` diberikan; panggil
/// [requestPermission] lebih dulu. Sensor menyala saat ada yang listen dan
/// mati saat langganan dibatalkan.
class SamsungHealthService {
  static const MethodChannel _methods = MethodChannel('samsung_health/method');
  static const EventChannel _heartRate = EventChannel('samsung_health/heart_rate');
  static const EventChannel _spo2 = EventChannel('samsung_health/spo2');

  Future<bool> hasPermission(HealthSensor sensor) async =>
      await _methods.invokeMethod<bool>('hasPermission', sensor._args) ?? false;

  Future<bool> requestPermission(HealthSensor sensor) async =>
      await _methods.invokeMethod<bool>('requestPermission', sensor._args) ?? false;

  /// Daftar tracker yang didukung jam ini. Kosong sebelum ada koneksi aktif.
  Future<List<String>> supportedTrackers() async =>
      (await _methods.invokeListMethod<String>('supportedTrackers')) ?? const [];

  /// Mengalirkan [HeartRateSample] dan [TrackerStatus].
  Stream<Object> heartRateStream() =>
      _heartRate.receiveBroadcastStream().map((e) => _decode(e, HeartRateSample.fromMap));

  /// Mengalirkan [Spo2Sample] dan [TrackerStatus].
  Stream<Object> spo2Stream() =>
      _spo2.receiveBroadcastStream().map((e) => _decode(e, Spo2Sample.fromMap));

  static Object _decode(
    Object? event,
    Object Function(Map<Object?, Object?>) toSample,
  ) {
    final map = event as Map<Object?, Object?>;
    if (map['event'] == 'status') {
      return TrackerStatus(
        map['state'] as String? ?? '',
        map['message'] as String? ?? '',
      );
    }
    return toSample(map);
  }
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

List<int> _intList(Object? value) => ((value as List?) ?? const [])
    .map((e) => (e as num).toInt())
    .toList(growable: false);

DateTime _time(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch((value as num?)?.toInt() ?? 0);
