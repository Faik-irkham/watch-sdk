import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_004/measurement_shared.dart';
import 'package:hr_sdk_004/measurement_store.dart';
import 'package:hr_sdk_004/samsung_health_service.dart';
import 'package:hr_sdk_004/widgets/history_page.dart';

class AccelerometerView extends StatefulWidget {
  const AccelerometerView({super.key});

  @override
  State<AccelerometerView> createState() => _AccelerometerViewState();
}

class _AccelerometerViewState extends State<AccelerometerView>
    with PersistsMeasurements<AccelerometerView> {
  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  AccelerometerBatch? _batch;
  String _message = 'Nilai mentah sensor, belum m/s²';
  bool _measuring = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.accelerometer)) {
      if (mounted) setState(() => _message = 'Izin sensor ditolak');
      return;
    }
    if (!mounted) return;

    setState(() {
      _measuring = true;
      _batch = null;
      _message = 'Menyambung ke sensor…';
      resetSaved();
    });

    _subscription = _service.accelerometerStream().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event is AccelerometerBatch) {
            _batch = event;
            final rate = event.rateHz;
            _message = rate == null
                ? '${event.samples.length} sampel'
                : '${event.samples.length} sampel · ${rate.toStringAsFixed(1)} Hz';
          } else if (event is TrackerStatus) {
            _message = event.message;
          }
        });
        if (event is AccelerometerBatch) {
          persist(store.saveAccelerometer(event));
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
      title: 'Riwayat akselerometer',
      totalNoun: 'sampel',
      load: () async => (await store.accelerometerHistory()).map(
        (s) => HistoryEntry(
          at: s.second,
          value: formatAccelerometerMeans(s),
          detail: 'rata-rata ${s.samples} sampel, nilai mentah',
        ),
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
    final latest = _batch?.latest;
    String axis(int? v) => v == null ? '--' : '$v';

    return MeasurementLayout(
      reading: SizedBox(
        width: 124,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.open_with,
              color: _measuring ? Colors.amberAccent : Colors.white24,
              size: 18,
            ),
            const SizedBox(height: 2),
            _AxisRow(label: 'X', value: axis(latest?.x)),
            _AxisRow(label: 'Y', value: axis(latest?.y)),
            _AxisRow(label: 'Z', value: axis(latest?.z)),
            _AxisRow(
              label: '|a|',
              value: latest == null ? '--' : latest.magnitude.toStringAsFixed(0),
              dim: true,
            ),
          ],
        ),
      ),
      message: _message,
      footnote: savedLabel,
      buttonLabel: _measuring ? 'Berhenti' : 'Mulai',
      onPressed: _measuring ? _stop : _start,
      onHistory: _openHistory,
    );
  }
}

/// Satu baris sumbu hanya digunakan di dalam AccelerometerView
class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.label, required this.value, this.dim = false});

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: dim ? Colors.white60 : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rata-rata tiga sumbu dalam satu detik. Spasi di dalam tiap pasangan sumbu
/// tak-terputus, supaya baris hanya patah di antara sumbu, bukan di antara
/// huruf sumbu dan nilainya.
String formatAccelerometerMeans(AccelerometerSecond s) {
  String axis(double v) => v.round().toString();
  return 'x\u00A0${axis(s.meanX)} · y\u00A0${axis(s.meanY)} · z\u00A0${axis(s.meanZ)}';
}
