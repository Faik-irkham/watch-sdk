import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_003/measurement_shared.dart';
import 'package:hr_sdk_003/samsung_health_service.dart';
import 'package:hr_sdk_003/widgets/history_page.dart';

class Spo2View extends StatefulWidget {
  const Spo2View({super.key});

  @override
  State<Spo2View> createState() => _Spo2ViewState();
}

class _Spo2ViewState extends State<Spo2View>
    with PersistsMeasurements<Spo2View> {
  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  Spo2Sample? _sample;
  String _message = 'Tekan mulai, lalu diam ±15 detik';
  bool _measuring = false;
  bool _resultSaved = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.spo2)) {
      if (mounted) setState(() => _message = 'Izin sensor ditolak');
      return;
    }
    if (!mounted) return;

    setState(() {
      _measuring = true;
      _sample = null;
      _message = 'Menyambung ke sensor…';
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
          setState(() => _message = event.message);
          if (event.isCompleted) _stop(keepMessage: true);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _measuring = false;
          _message = describeStreamError(error);
        });
      },
    );
  }

  void _openHistory() {
    HistoryPage.open(
      context,
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

  Future<void> _stop({bool keepMessage = false}) async {
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    setState(() {
      _measuring = false;
      if (!keepMessage) _message = 'Pengukuran dihentikan';
    });
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    return MeasurementLayout(
      icon: Icons.water_drop,
      iconColor: _measuring ? Colors.lightBlueAccent : Colors.white24,
      value: (sample != null && sample.isComplete) ? '${sample.spo2}' : '--',
      unit: '% SpO₂',
      message: _message,
      footnote: savedLabel,
      buttonLabel: _measuring ? 'Berhenti' : 'Mulai',
      onPressed: _measuring ? _stop : _start,
      onHistory: _openHistory,
    );
  }
}
