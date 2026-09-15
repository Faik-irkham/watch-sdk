import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_005_watch/measurement_shared.dart';
import 'package:hr_sdk_005_watch/samsung_health_service.dart';
import 'package:hr_sdk_005_watch/widgets/history_page.dart';

class Spo2View extends StatefulWidget {
  const Spo2View({super.key});

  @override
  State<Spo2View> createState() => _Spo2ViewState();
}

class _Spo2ViewState extends State<Spo2View>
    with PersistsMeasurements<Spo2View> {
  /// Pedoman resmi Samsung (Health Sensor Data Specifications): pelacak
  /// on-demand dipakai paling lama 30 detik.
  static const Duration _measurementLimit = Duration(seconds: 30);

  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  Timer? _limitTimer;
  Spo2Sample? _sample;
  String _message = 'Tekan mulai, lalu diam ±15 detik';
  bool _measuring = false;
  bool _failed = false;
  bool _resultSaved = false;

  @override
  void dispose() {
    _limitTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.spo2)) {
      if (mounted) {
        setState(() {
          _message = 'Izin sensor ditolak';
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() {
      _measuring = true;
      _sample = null;
      _message = 'Menyambung ke sensor…';
      _failed = false;
      _resultSaved = false;
      resetSaved();
    });

    _subscription = _service.spo2Stream().listen(
      (event) {
        if (!mounted) return;
        if (event is Spo2Sample) {
          setState(() {
            _sample = event;
            _message = event.statusMessage;
          });
          if (event.isComplete && !_resultSaved) {
            _resultSaved = true;
            persist(store.saveSpo2(event));
          }
        } else if (event is TrackerStatus) {
          // "completed" juga dikirim saat waktu habis. Pesan dari sampel
          // terakhir ("selesai" atau "waktu habis") dipertahankan, karena
          // pesan umum dari sisi Android tidak membedakan keduanya.
          if (event.isCompleted) {
            _stop(keepMessage: true);
          } else {
            setState(() => _message = event.message);
          }
        }
      },
      onError: (Object error) {
        _limitTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _measuring = false;
          _message = describeStreamError(error);
          _failed = true;
        });
      },
    );
    _limitTimer?.cancel();
    _limitTimer = Timer(_measurementLimit, _onLimitReached);
  }

  /// Kode -4/-5 hanya peringatan dan tidak mengakhiri pengukuran, jadi tanpa
  /// batas ini sensor bisa menyala melewati 30 detik.
  void _onLimitReached() {
    if (!_measuring) return;
    _stop(message: 'Batas 30 detik tercapai — silakan ukur ulang');
  }

  void _openHistory() {
    HistoryPage.open(
      context,
      accent: SensorColors.spo2,
      title: 'Riwayat SpO₂',
      load: () async => (await store.spo2History()).map(
        (r) => HistoryEntry(
          at: r.measuredAt,
          value: '${r.spo2Percent}%',
          detail: '${r.bpm} bpm',
        ),
      ),
    );
  }

  Future<void> _stop({bool keepMessage = false, String? message}) async {
    _limitTimer?.cancel();
    _limitTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() {
      _measuring = false;
      if (message != null) {
        _message = message;
      } else if (!keepMessage) {
        _message = 'Pengukuran dihentikan';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return MeasurementLayout(
      title: 'SpO₂',
      icon: Icons.water_drop,
      accent: SensorColors.spo2,
      reading: ValueReading(
        value: (sample != null && sample.isComplete) ? '${sample.spo2}' : '--',
        unit: '%',
      ),
      message: _message,
      messageIsError: _failed,
      footnote: savedLabel,
      measuring: _measuring,
      countdown: _measurementLimit,
      onStart: _start,
      onStop: _stop,
      onHistory: _openHistory,
    );
  }
}
