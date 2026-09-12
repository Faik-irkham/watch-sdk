import 'package:flutter/services.dart';

/// Satu pembacaan detak jantung dari Samsung Health Sensor SDK.
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
      heartRate: (map['heartRate'] as num?)?.toInt() ?? 0,
      status: (map['heartRateStatus'] as num?)?.toInt() ?? 0,
      ibi: ((map['ibi'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      ibiStatus: ((map['ibiStatus'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ?? 0,
      ),
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

  /// Arti kode status menurut tabel resmi Samsung (ValueKey.HeartRateSet).
  /// Kode di luar tabel ditampilkan mentah, bukan diberi label karangan.
  String get statusMessage {
    switch (status) {
      case 1:
        return 'Pengukuran valid';
      case 0:
        return 'Memulai pengukuran…';
      case -2:
        return 'Gerakan terdeteksi — tahan tangan tetap diam';
      case -3:
        return 'Jam terlepas dari pergelangan';
      case -8:
        return 'Sinyal lemah atau tangan bergerak';
      case -10:
        return 'Sinyal terlalu lemah atau gerakan berlebihan';
      case -999:
        return 'Sensor lain yang lebih prioritas sedang berjalan';
      default:
        return 'Status sensor: $status';
    }
  }
}

/// Kabar dari sisi Android yang bukan data pengukuran (koneksi, flush, dsb).
class HeartRateStatus {
  const HeartRateStatus(this.state, this.message);

  final String state;
  final String message;
}

/// Akses ke sensor detak jantung lewat Samsung Health Sensor SDK.
///
/// Stream baru terbuka setelah izin `BODY_SENSORS` diberikan; panggil
/// [requestPermission] lebih dulu.
class HeartRateService {
  static const MethodChannel _methods = MethodChannel('samsung_hr/method');
  static const EventChannel _events = EventChannel('samsung_hr/heart_rate');

  Future<bool> hasPermission() async =>
      await _methods.invokeMethod<bool>('hasPermission') ?? false;

  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  /// Daftar tracker yang didukung jam ini. Kosong sebelum stream tersambung.
  Future<List<String>> supportedTrackers() async =>
      (await _methods.invokeListMethod<String>('supportedTrackers')) ?? const [];

  /// Mengalirkan pembacaan detak jantung selama ada yang listen.
  ///
  /// Sensor menyala saat listen pertama dan mati saat langganan dibatalkan.
  Stream<Object> stream() {
    return _events.receiveBroadcastStream().map((event) {
      final map = event as Map<Object?, Object?>;
      if (map['event'] == 'status') {
        return HeartRateStatus(
          map['state'] as String? ?? '',
          map['message'] as String? ?? '',
        );
      }
      return HeartRateSample.fromMap(map);
    });
  }
}
