import 'package:flutter_test/flutter_test.dart';
import 'package:hr_sdk_001/heart_rate_service.dart';

HeartRateSample heartRate(int status) => HeartRateSample(
      heartRate: 0,
      status: status,
      ibi: const [],
      ibiStatus: const [],
      timestamp: DateTime(2026),
    );

void main() {
  test('label detak jantung mengikuti tabel resmi ValueKey.HeartRateSet', () {
    expect(heartRate(1).statusMessage, 'Pengukuran valid');
    expect(heartRate(0).statusMessage, 'Memulai pengukuran…');
    expect(heartRate(-2).statusMessage, startsWith('Gerakan terdeteksi'));
    expect(heartRate(-3).statusMessage, 'Jam terlepas dari pergelangan');
    expect(heartRate(-8).statusMessage, 'Sinyal lemah atau tangan bergerak');
    expect(heartRate(-10).statusMessage, 'Sinyal terlalu lemah atau gerakan berlebihan');
    expect(heartRate(-999).statusMessage, startsWith('Sensor lain'));
  });

  test('kode detak jantung di luar tabel resmi tidak diberi label karangan', () {
    expect(heartRate(-1).statusMessage, 'Status sensor: -1');
    expect(heartRate(-99).statusMessage, 'Status sensor: -99');
  });
}
