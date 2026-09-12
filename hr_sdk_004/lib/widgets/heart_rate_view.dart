import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_004/measurement_shared.dart';
import 'package:hr_sdk_004/samsung_health_service.dart';
import 'package:hr_sdk_004/widgets/history_page.dart';

class HeartRateView extends StatefulWidget {
  const HeartRateView({super.key});

  @override
  State<HeartRateView> createState() => _HeartRateViewState();
}

class _HeartRateViewState extends State<HeartRateView>
    with PersistsMeasurements<HeartRateView> {
  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  HeartRateSample? _sample;
  String _message = 'Tekan mulai untuk mengukur';
  bool _measuring = false;
  bool _failed = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.heartRate)) {
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
      resetSaved();
    });

    _subscription = _service.heartRateStream().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event is HeartRateSample) {
            _sample = event;
            _message = event.statusMessage;
          } else if (event is TrackerStatus) {
            _message = event.message;
          }
        });
        if (event is HeartRateSample) persist(store.saveHeartRate(event));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _measuring = false;
          _message = describeStreamError(error);
          _failed = true;
        });
      },
    );
  }

  void _openHistory() {
    HistoryPage.open(
      context,
      accent: SensorColors.heartRate,
      title: 'Riwayat detak jantung',
      load: () async => (await store.heartRateHistory()).map(
        (r) => HistoryEntry(at: r.measuredAt, value: '${r.bpm} bpm'),
      ),
    );
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _message = 'Pengukuran dihentikan';
    });
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return MeasurementLayout(
      title: 'Detak jantung',
      icon: Icons.favorite,
      accent: SensorColors.heartRate,
      reading: ValueReading(
        value: (sample != null && sample.isValid)
            ? '${sample.heartRate}'
            : '--',
        unit: 'bpm',
      ),
      message: _message,
      messageIsError: _failed,
      footnote: savedLabel,
      measuring: _measuring,
      onStart: _start,
      onStop: _stop,
      onHistory: _openHistory,
    );
  }
}
