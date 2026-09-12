import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Sensor yang bisa diminta izinnya.
///
/// Sejak Wear OS 6 (Android 16) izin sensor tubuh pindah ke Health Connect dan
/// tiap sensor punya izin sendiri, jadi permintaan izin dibedakan per sensor.
enum HealthSensor {
  heartRate,
  spo2,
  accelerometer,
  ppg;

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

  /// Pengukuran berakhir karena waktu habis, tanpa hasil.
  static const int statusTimeout = -6;

  /// Saturasi oksigen dalam persen. Bermakna kalau [isComplete] true.
  final int spo2;

  final int status;

  /// Detak jantung yang terbaca berbarengan dengan pengukuran SpO2.
  final int heartRate;

  final int accuracyFlag;

  final DateTime timestamp;

  bool get isComplete => status == statusCompleted;

  bool get isCalculating => status == statusCalculating;

  /// Arti kode status menurut tabel resmi Samsung (ValueKey.SpO2Set).
  String get statusMessage {
    switch (status) {
      case statusCompleted:
        return 'Pengukuran selesai';
      case statusCalculating:
        return 'Menghitung… tahan tangan tetap diam';
      case statusTimeout:
        return 'Waktu habis — silakan ukur ulang';
      case -5:
        return 'Kualitas sinyal rendah — pastikan jam menempel';
      case -4:
        return 'Jam bergerak saat mengukur — tahan tangan tetap diam';
      default:
        return 'Status sensor: $status';
    }
  }
}

/// Satu sampel akselerometer tiga sumbu.
///
/// Nilainya bilangan bulat mentah dari sensor. Menurut dokumentasi resmi
/// Samsung datanya tidak termasuk gravitasi, sehingga saat jam diam nilainya
/// mendekati nol. Konversi resmi ke m/s²: nilai × 9,81 / (16383,75 / 4).
class AccelerometerSample {
  const AccelerometerSample({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  factory AccelerometerSample.fromMap(Map<Object?, Object?> map) {
    return AccelerometerSample(
      x: _int(map['x']),
      y: _int(map['y']),
      z: _int(map['z']),
      timestamp: _time(map['timestamp']),
    );
  }

  final int x;
  final int y;
  final int z;
  final DateTime timestamp;

  /// Besaran vektor percepatan, dalam satuan mentah yang sama dengan sumbunya.
  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

/// Satu kiriman akselerometer. Sensor berlaju tinggi mengirim sampelnya
/// berkelompok, dan satu kelompok diteruskan utuh sebagai satu peristiwa.
class AccelerometerBatch {
  const AccelerometerBatch(this.samples);

  factory AccelerometerBatch.fromMap(Map<Object?, Object?> map) {
    final raw = (map['samples'] as List?) ?? const [];
    return AccelerometerBatch(
      raw
          .map((e) => AccelerometerSample.fromMap(e as Map<Object?, Object?>))
          .toList(growable: false),
    );
  }

  final List<AccelerometerSample> samples;

  AccelerometerSample? get latest => samples.isEmpty ? null : samples.last;

  /// Laju sampel terukur dari cap waktu dalam kelompok ini; null bila sampel
  /// terlalu sedikit untuk dihitung.
  double? get rateHz => samples.isEmpty
      ? null
      : _rateHz(samples.length, samples.first.timestamp, samples.last.timestamp);
}

/// Satu sampel PPG: nilai ADC mentah LED hijau, serta inframerah dan merah bila
/// jam mengirimnya. Warna yang tidak dilacak bernilai null.
///
/// Status tiap warna menurut tabel resmi Samsung (ValueKey.PpgSet) untuk
/// PPG_CONTINUOUS: 0 normal, -1 sensor yang lebih prioritas sedang berjalan.
class PpgSample {
  const PpgSample({
    this.green,
    this.greenStatus,
    this.ir,
    this.irStatus,
    this.red,
    this.redStatus,
    required this.timestamp,
  });

  factory PpgSample.fromMap(Map<Object?, Object?> map) {
    return PpgSample(
      green: _intOrNull(map['green']),
      greenStatus: _intOrNull(map['greenStatus']),
      ir: _intOrNull(map['ir']),
      irStatus: _intOrNull(map['irStatus']),
      red: _intOrNull(map['red']),
      redStatus: _intOrNull(map['redStatus']),
      timestamp: _time(map['timestamp']),
    );
  }

  static const int statusNormal = 0;

  /// Sensor yang lebih prioritas, misalnya BIA, sedang berjalan.
  static const int statusPreempted = -1;

  final int? green;
  final int? greenStatus;
  final int? ir;
  final int? irStatus;
  final int? red;
  final int? redStatus;
  final DateTime timestamp;

  /// Absah bila setidaknya satu warna terbaca dan semua warna yang terbaca
  /// berstatus normal.
  bool get isValid {
    final statuses = [
      if (green != null) greenStatus,
      if (ir != null) irStatus,
      if (red != null) redStatus,
    ];
    return statuses.isNotEmpty && statuses.every((s) => s == statusNormal);
  }

  bool get isPreempted =>
      [greenStatus, irStatus, redStatus].contains(statusPreempted);
}

/// Satu kiriman PPG, diteruskan utuh seperti akselerometer.
class PpgBatch {
  const PpgBatch(this.samples);

  factory PpgBatch.fromMap(Map<Object?, Object?> map) {
    final raw = (map['samples'] as List?) ?? const [];
    return PpgBatch(
      raw
          .map((e) => PpgSample.fromMap(e as Map<Object?, Object?>))
          .toList(growable: false),
    );
  }

  final List<PpgSample> samples;

  PpgSample? get latest => samples.isEmpty ? null : samples.last;

  List<PpgSample> get validSamples =>
      samples.where((s) => s.isValid).toList(growable: false);

  double? get rateHz => samples.isEmpty
      ? null
      : _rateHz(samples.length, samples.first.timestamp, samples.last.timestamp);
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
  static const EventChannel _accelerometer =
      EventChannel('samsung_health/accelerometer');
  static const EventChannel _ppg = EventChannel('samsung_health/ppg');

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

  /// Mengalirkan [AccelerometerBatch] dan [TrackerStatus].
  Stream<Object> accelerometerStream() => _accelerometer
      .receiveBroadcastStream()
      .map((e) => _decode(e, AccelerometerBatch.fromMap));

  /// Mengalirkan [PpgBatch] dan [TrackerStatus].
  Stream<Object> ppgStream() =>
      _ppg.receiveBroadcastStream().map((e) => _decode(e, PpgBatch.fromMap));

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

int? _intOrNull(Object? value) => (value as num?)?.toInt();

/// Laju sampel dari cap waktu sampel pertama dan terakhir dalam satu kiriman;
/// null bila sampel terlalu sedikit atau cap waktunya tidak bergerak.
double? _rateHz(int count, DateTime first, DateTime last) {
  if (count < 2) return null;
  final spanMs = last.difference(first).inMilliseconds;
  if (spanMs <= 0) return null;
  return (count - 1) * 1000 / spanMs;
}
