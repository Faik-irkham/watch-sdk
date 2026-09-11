import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_003/measurement_shared.dart';
import 'package:hr_sdk_003/samsung_health_service.dart';

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
        if (event is AccelerometerBatch)
          persist(store.saveAccelerometer(event));
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
    final footnote = savedLabel;
    String axis(int? v) => v == null ? '--' : '$v';

    return Center(
      // Tambahkan SingleChildScrollView agar bisa digulir jika layar terlalu kecil
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 8, 40, 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize
                .min, // Tambahkan ini agar Column mengambil ruang seperlunya
            children: [
              Icon(
                Icons.open_with,
                color: _measuring ? Colors.amberAccent : Colors.white24,
                size: 20,
              ),
              const SizedBox(height: 4),
              _AxisRow(label: 'X', value: axis(latest?.x)),
              _AxisRow(label: 'Y', value: axis(latest?.y)),
              _AxisRow(label: 'Z', value: axis(latest?.z)),
              _AxisRow(
                label: '|a|',
                value: latest == null
                    ? '--'
                    : latest.magnitude.toStringAsFixed(0),
                dim: true,
              ),
              const SizedBox(height: 6),
              Text(
                _message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
              if (footnote != null) Footnote(footnote),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _measuring ? _stop : _start,
                child: Text(_measuring ? 'Berhenti' : 'Mulai'),
              ),
            ],
          ),
        ),
      ),
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
              fontSize: 20,
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
