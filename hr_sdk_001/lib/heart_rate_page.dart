import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hr_sdk_001/heart_rate_service.dart';
import 'package:hr_sdk_001/measurement_store.dart';

class HeartRatePage extends StatefulWidget {
  const HeartRatePage({super.key});

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  final HeartRateService _service = HeartRateService();
  final MeasurementStore _store = MeasurementStore.instance;

  StreamSubscription<Object>? _subscription;
  HeartRateSample? _sample;
  String _message = 'Tekan mulai untuk mengukur';
  bool _measuring = false;
  int _saved = 0;
  bool _saveFailed = false;

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
      _saved = 0;
      _saveFailed = false;
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
        if (event is HeartRateSample) _persist(event);
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

  /// Menulis ke SQLite tanpa menahan aliran data. Hanya status 1 yang
  /// tersimpan; penyaringannya ada di MeasurementStore.
  void _persist(HeartRateSample sample) {
    _store.saveHeartRate(sample).then(
      (count) {
        if (count > 0 && mounted) setState(() => _saved += count);
      },
      onError: (Object error) {
        debugPrint('Gagal menyimpan ke SQLite: $error');
        if (mounted) setState(() => _saveFailed = true);
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
    final savedLabel = _saveFailed
        ? 'Gagal menyimpan ke SQLite'
        : (_saved == 0 ? null : '$_saved tersimpan');
    final bpm = (sample != null && sample.isValid)
        ? '${sample.heartRate}'
        : '--';

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
                if (savedLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      savedLabel,
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
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
