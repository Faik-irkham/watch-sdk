import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_003/measurement_store.dart';
import 'package:hr_sdk_003/samsung_health_service.dart';

class SensorPages extends StatefulWidget {
  const SensorPages({super.key});

  @override
  State<SensorPages> createState() => _SensorPagesState();
}

class _SensorPagesState extends State<SensorPages> {
  static const List<Widget> _pages = [HeartRateView(), Spo2View(), AccelerometerView()];

  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView(
              controller: _controller,
              onPageChanged: (page) => setState(() => _page = page),
              children: _pages,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_pages.length, (index) {
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == _page ? Colors.white70 : Colors.white24,
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HeartRateView extends StatefulWidget {
  const HeartRateView({super.key});

  @override
  State<HeartRateView> createState() => _HeartRateViewState();
}

class _HeartRateViewState extends State<HeartRateView>
    with _PersistsMeasurements<HeartRateView> {
  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  HeartRateSample? _sample;
  String _message = 'Tekan mulai untuk mengukur';
  bool _measuring = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.heartRate)) {
      if (mounted) setState(() => _message = 'Izin sensor ditolak');
      return;
    }
    if (!mounted) return;

    setState(() {
      _measuring = true;
      _sample = null;
      _message = 'Menyambung ke sensor…';
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
        // Hanya status 1 yang tersimpan; penyaringannya ada di MeasurementStore.
        if (event is HeartRateSample) persist(store.saveHeartRate(event));
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
    final sample = _sample;
    return MeasurementLayout(
      icon: Icons.favorite,
      iconColor: _measuring ? Colors.redAccent : Colors.white24,
      value: (sample != null && sample.isValid) ? '${sample.heartRate}' : '--',
      unit: 'bpm',
      message: _message,
      footnote: savedLabel,
      buttonLabel: _measuring ? 'Berhenti' : 'Mulai',
      onPressed: _measuring ? _stop : _start,
    );
  }
}

class Spo2View extends StatefulWidget {
  const Spo2View({super.key});

  @override
  State<Spo2View> createState() => _Spo2ViewState();
}

class _Spo2ViewState extends State<Spo2View>
    with _PersistsMeasurements<Spo2View> {
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
          // Pustaka dapat mengirim hasil akhir dua kali dengan cap waktu
          // berbeda beberapa milidetik; satu pengukuran cukup satu baris.
          if (event.isComplete && !_resultSaved) {
            _resultSaved = true;
            persist(store.saveSpo2(event));
          }
        } else if (event is TrackerStatus) {
          setState(() => _message = event.message);
          // Pengukuran SpO2 sekali jalan: sensor sudah dimatikan di sisi
          // Android, jadi langganan ikut ditutup.
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
    );
  }
}

class AccelerometerView extends StatefulWidget {
  const AccelerometerView({super.key});

  @override
  State<AccelerometerView> createState() => _AccelerometerViewState();
}

class _AccelerometerViewState extends State<AccelerometerView>
    with _PersistsMeasurements<AccelerometerView> {
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
        if (event is AccelerometerBatch) persist(store.saveAccelerometer(event));
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              value: latest == null ? '--' : latest.magnitude.toStringAsFixed(0),
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
            if (footnote != null) _Footnote(footnote),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _measuring ? _stop : _start,
              child: Text(_measuring ? 'Berhenti' : 'Mulai'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris sumbu: label di kiri, nilai rata kanan dengan angka selebar tetap.
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
          child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.white54)),
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

/// Tata letak yang dipakai halaman detak jantung dan SpO2.
class MeasurementLayout extends StatelessWidget {
  const MeasurementLayout({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.footnote,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  /// Keterangan kecil di bawah pesan, misalnya jumlah data yang tersimpan.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
            Text(unit, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
            if (footnote != null) _Footnote(footnote!),
            const SizedBox(height: 10),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white38)),
    );
  }
}

/// Menulis ke SQLite tanpa menahan aliran data, lalu menghitung baris yang
/// benar-benar tersimpan agar pengguna tahu penyimpanan berjalan.
mixin _PersistsMeasurements<T extends StatefulWidget> on State<T> {
  final MeasurementStore store = MeasurementStore.instance;

  int _saved = 0;
  bool _saveFailed = false;

  String? get savedLabel {
    if (_saveFailed) return 'Gagal menyimpan ke SQLite';
    return _saved == 0 ? null : '$_saved tersimpan';
  }

  void resetSaved() {
    _saved = 0;
    _saveFailed = false;
  }

  void persist(Future<int> write) {
    write.then(
      (count) {
        if (count > 0 && mounted) setState(() => _saved += count);
      },
      onError: (Object error) {
        debugPrint('Gagal menyimpan ke SQLite: $error');
        if (mounted) setState(() => _saveFailed = true);
      },
    );
  }
}

String describeStreamError(Object error) => error is PlatformException
    ? (error.message ?? error.code)
    : error.toString();
