import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_004/heart_rate_summary.dart';
import 'package:hr_sdk_004/measurement_shared.dart';
import 'package:hr_sdk_004/samsung_health_service.dart';
import 'package:hr_sdk_004/widgets/heart_rate_view.dart';

/// Langkah dalam satu siklus mode berkala, beserta labelnya di layar.
enum IntervalStep {
  idle('mode berkala'),
  heartRate('detak jantung'),
  spo2('SpO₂'),
  pause('jeda');

  const IntervalStep(this.label);

  final String label;
}

/// Mode berkala: detak jantung bersama akselerometer, lalu SpO₂, diulang tiap
/// [cycle] selama halaman ini terbuka.
///
/// Sensor dijalankan bergantian karena pedoman Samsung: satu tracker
/// sekali-ukur pada satu waktu, dan tracker menerus yang berjalan bersamaan
/// dengan pengukuran sekali-ukur bisa memberi nilai tidak valid. Tracker juga
/// hanya dipakai di latar depan, jadi mode ini berhenti bila halamannya
/// ditinggalkan, dan layar dijaga tetap menyala selama mode berjalan.
class IntervalView extends StatefulWidget {
  const IntervalView({super.key});

  /// Jarak antara awal dua siklus.
  static const Duration cycle = Duration(minutes: 5);

  /// Lama detak jantung dan akselerometer diukur. Di Galaxy Watch4 sekitar 20
  /// detik pertama detak jantung belum valid, dan HRV butuh minimal 10 selisih
  /// IBI berurutan.
  static const Duration heartRateWindow = Duration(seconds: 60);

  /// Batas pengukuran SpO₂ menurut pedoman resmi Samsung.
  static const Duration spo2Limit = Duration(seconds: 30);

  @override
  State<IntervalView> createState() => _IntervalViewState();
}

class _IntervalViewState extends State<IntervalView>
    with PersistsMeasurements<IntervalView> {
  static const Duration _tick = Duration(seconds: 1);

  final SamsungHealthService _service = SamsungHealthService();
  final List<StreamSubscription<Object>> _subscriptions = [];

  /// Satu detak per detik menggerakkan seluruh jadwal sekaligus hitung mundur
  /// di layar, jadi urutan langkah tidak bergantung pada beberapa timer.
  Timer? _ticker;
  bool _running = false;
  bool _failed = false;
  IntervalStep _step = IntervalStep.idle;
  Duration _remaining = Duration.zero;
  Duration _elapsedInCycle = Duration.zero;
  int _cycles = 0;
  String _message = 'Detak jantung lalu SpO₂, diulang tiap 5 menit';

  /// Hasil siklus yang sedang berjalan.
  final List<HeartRateBeat> _beats = [];
  Spo2Sample? _spo2;

  @override
  void dispose() {
    _ticker?.cancel();
    _cancelSensors();
    super.dispose();
  }

  Future<void> _start() async {
    // Satu per satu: sisi Android menolak permintaan izin yang tumpang tindih.
    for (final (sensor, name) in [
      (HealthSensor.heartRate, 'detak jantung'),
      (HealthSensor.accelerometer, 'akselerometer'),
      (HealthSensor.spo2, 'SpO₂'),
    ]) {
      if (!await _service.requestPermission(sensor)) {
        if (mounted) {
          setState(() {
            _message = 'Izin sensor $name ditolak';
            _failed = true;
          });
        }
        return;
      }
    }
    if (!mounted) return;

    setState(() {
      _running = true;
      _failed = false;
      _cycles = 0;
      resetSaved();
      _startCycle();
    });
    _ticker = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    if (!mounted || !_running) return;
    setState(() {
      _elapsedInCycle += _tick;
      _remaining -= _tick;
      if (_remaining > Duration.zero) return;
      switch (_step) {
        case IntervalStep.heartRate:
          _startSpo2();
        case IntervalStep.spo2:
          // Batas 30 detik tercapai tanpa hasil akhir.
          _startPause();
        case IntervalStep.pause:
          _startCycle();
        case IntervalStep.idle:
          break;
      }
    });
  }

  // Langkah-langkah di bawah hanya mengubah keadaan; pemanggilnya yang
  // membungkusnya dengan setState.

  void _startCycle() {
    _elapsedInCycle = Duration.zero;
    _beats.clear();
    _spo2 = null;
    _enter(
      IntervalStep.heartRate,
      IntervalView.heartRateWindow,
      'Menyambung ke sensor…',
    );
    _listen(_service.heartRateStream(), (event) {
      if (event is! HeartRateSample) return;
      _message = event.statusMessage;
      // Titik yang sama bisa terkirim ulang saat layar mati; salinannya dilewati.
      if (event.isValid &&
          (_beats.isEmpty || event.timestamp.isAfter(_beats.last.at))) {
        _beats.add(
          HeartRateBeat(
            at: event.timestamp,
            bpm: event.heartRate,
            ibi: event.ibi,
            ibiStatus: event.ibiStatus,
          ),
        );
      }
      persist(store.saveHeartRate(event));
    });
    _listen(_service.accelerometerStream(), (event) {
      if (event is AccelerometerBatch) persist(store.saveAccelerometer(event));
    });
  }

  void _startSpo2() {
    // Sensor menerus dimatikan dulu: pedoman Samsung menyebut tracker menerus
    // yang berjalan selama pengukuran sekali-ukur bisa memberi nilai tidak valid.
    _cancelSensors();
    _enter(
      IntervalStep.spo2,
      IntervalView.spo2Limit,
      'Tahan tangan tetap diam',
    );
    _listen(_service.spo2Stream(), (event) {
      if (event is Spo2Sample) {
        _message = event.statusMessage;
        if (event.isComplete && _spo2 == null) {
          _spo2 = event;
          persist(store.saveSpo2(event));
        }
      } else if (event is TrackerStatus && event.isCompleted) {
        _startPause();
      }
    });
  }

  void _startPause() {
    _cancelSensors();
    _cycles++;
    final left = IntervalView.cycle - _elapsedInCycle;
    _enter(
      IntervalStep.pause,
      left.isNegative ? Duration.zero : left,
      describeCycle(HeartRateSummary.of(_beats), _spo2),
    );
  }

  void _enter(IntervalStep step, Duration length, String message) {
    _step = step;
    _remaining = length;
    _message = message;
  }

  /// Galat menghentikan seluruh mode: galat seperti izin atau sensor yang
  /// tidak didukung akan berulang di setiap siklus.
  void _listen(Stream<Object> stream, void Function(Object event) onEvent) {
    _subscriptions.add(
      stream.listen(
        (event) {
          if (!mounted || !_running) return;
          setState(() => onEvent(event));
        },
        onError: (Object error) {
          if (mounted) _stop(message: describeStreamError(error), failed: true);
        },
      ),
    );
  }

  /// Dibatalkan tanpa ditunggu: pesan batal sudah terkirim ke sisi Android
  /// sebelum langkah berikutnya mulai mendengarkan sensor lain.
  void _cancelSensors() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _stop({String? message, bool failed = false}) {
    _ticker?.cancel();
    _ticker = null;
    _cancelSensors();
    setState(() {
      _running = false;
      _failed = failed;
      _step = IntervalStep.idle;
      _message =
          message ??
          (_cycles == 0
              ? 'Mode berkala dihentikan'
              : 'Dihentikan setelah $_cycles siklus');
    });
  }

  String get _unit => switch (_step) {
    IntervalStep.idle => _step.label,
    IntervalStep.pause => '${_step.label} · $_cycles siklus selesai',
    _ => '${_step.label} · siklus ${_cycles + 1}',
  };

  @override
  Widget build(BuildContext context) {
    return MeasurementLayout(
      title: 'Berkala',
      icon: Icons.repeat,
      accent: SensorColors.interval,
      reading: ValueReading(
        value: _running ? formatCountdown(_remaining) : '--',
        unit: _unit,
      ),
      message: _message,
      messageIsError: _failed,
      // Jumlah baris tersimpan tidak bermakna di sini, karena akselerometer
      // menyumbang 25 baris per detik; hanya kegagalan yang ditampilkan.
      footnote: saveFailed ? savedLabel : null,
      measuring: _running,
      onStart: _start,
      onStop: _stop,
    );
  }
}

/// Sisa waktu langkah yang berjalan, misalnya "0:42" atau "3:59".
String formatCountdown(Duration remaining) {
  final seconds = remaining.inSeconds.clamp(0, 5999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Hasil satu siklus: rata-rata detak jantung dan HRV, lalu SpO₂.
String describeCycle(HeartRateSummary? heartRate, Spo2Sample? spo2) {
  final first = heartRate == null
      ? 'Detak jantung tidak terbaca'
      : '${heartRate.meanBpm.round()} bpm · ${formatHrv(heartRate)}';
  final second = spo2 == null ? 'SpO₂ tidak selesai' : 'SpO₂ ${spo2.spo2}%';
  return '$first\n$second';
}
