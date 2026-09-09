import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'samsung_health_service.dart';

void main() {
  runApp(const SamsungHealthApp());
}

class SamsungHealthApp extends StatelessWidget {
  const SamsungHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Jam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Layar jam bulat dan hitam pekat menghemat daya OLED.
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const SensorPages(),
    );
  }
}

/// Dua halaman yang bisa digeser: detak jantung dan SpO2.
class SensorPages extends StatefulWidget {
  const SensorPages({super.key});

  @override
  State<SensorPages> createState() => _SensorPagesState();
}

class _SensorPagesState extends State<SensorPages> {
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
              children: const [HeartRateView(), Spo2View()],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(2, (index) {
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

class _HeartRateViewState extends State<HeartRateView> {
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

class _Spo2ViewState extends State<Spo2View> {
  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  Spo2Sample? _sample;
  String _message = 'Tekan mulai, lalu diam ±30 detik';
  bool _measuring = false;

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
    });

    _subscription = _service.spo2Stream().listen(
      (event) {
        if (!mounted) return;
        if (event is Spo2Sample) {
          setState(() {
            _sample = event;
            _message = event.statusMessage;
          });
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
      buttonLabel: _measuring ? 'Berhenti' : 'Mulai',
      onPressed: _measuring ? _stop : _start,
    );
  }
}

/// Tata letak yang dipakai kedua halaman pengukuran.
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
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

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
            const SizedBox(height: 10),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}

String describeStreamError(Object error) => error is PlatformException
    ? (error.message ?? error.code)
    : error.toString();
