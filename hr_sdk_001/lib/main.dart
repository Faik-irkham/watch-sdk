import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'heart_rate_service.dart';

void main() {
  runApp(const HeartRateApp());
}

class HeartRateApp extends StatelessWidget {
  const HeartRateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Rate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        // Layar jam berbentuk bulat dan hitam pekat menghemat daya OLED.
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HeartRatePage(),
    );
  }
}

class HeartRatePage extends StatefulWidget {
  const HeartRatePage({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  final HeartRateService _service = HeartRateService();

  StreamSubscription<Object>? _subscription;
  HeartRateSample? _sample;
  String _message = 'Tekan mulai untuk mengukur';
  bool _measuring = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleMeasuring() async {
    if (_measuring) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    final granted = await _service.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _message = 'Izin sensor ditolak');
      return;
    }

    setState(() {
      _measuring = true;
      _sample = null;
      _message = 'Menyambung ke sensor…';
    });

    _subscription = _service.stream().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event is HeartRateSample) {
            _sample = event;
            _message = event.statusMessage;
          } else if (event is HeartRateStatus) {
            _message = event.message;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        final message = error is PlatformException
            ? (error.message ?? error.code)
            : error.toString();
        setState(() {
          _measuring = false;
          _message = message;
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
    final bpm = (sample != null && sample.isValid) ? '${sample.heartRate}' : '--';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite,
                      color: _measuring ? Colors.redAccent : Colors.white24,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      bpm,
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const Text('bpm', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 8),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _toggleMeasuring,
                  child: Text(_measuring ? 'Berhenti' : 'Mulai'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
