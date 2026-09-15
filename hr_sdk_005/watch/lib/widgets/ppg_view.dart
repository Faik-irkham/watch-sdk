import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hr_sdk_005_watch/measurement_shared.dart';
import 'package:hr_sdk_005_watch/measurement_store.dart';
import 'package:hr_sdk_005_watch/samsung_health_service.dart';
import 'package:hr_sdk_005_watch/widgets/history_page.dart';

/// PPG mentah: gelombang LED hijau beberapa detik terakhir dan nilai terbaru
/// tiap warna.
class PpgView extends StatefulWidget {
  const PpgView({super.key});

  @override
  State<PpgView> createState() => _PpgViewState();
}

class _PpgViewState extends State<PpgView> with PersistsMeasurements<PpgView> {
  /// Tiga detik pada 25 Hz: cukup untuk melihat beberapa denyut.
  static const int _waveLength = 75;

  final SamsungHealthService _service = SamsungHealthService();

  StreamSubscription<Object>? _subscription;
  final List<int> _wave = [];
  PpgSample? _latest;
  String _message = 'Nilai ADC mentah LED';
  bool _measuring = false;
  bool _failed = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _service.requestPermission(HealthSensor.ppg)) {
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
      _latest = null;
      _wave.clear();
      _message = 'Menyambung ke sensor…';
      _failed = false;
      resetSaved();
    });

    _subscription = _service.ppgStream().listen(
      (event) {
        if (!mounted) return;
        setState(() {
          if (event is PpgBatch) {
            _latest = event.latest;
            _wave.addAll(
              event.validSamples.map((s) => s.green).whereType<int>(),
            );
            if (_wave.length > _waveLength) {
              _wave.removeRange(0, _wave.length - _waveLength);
            }
            _message = _describe(event);
          } else if (event is TrackerStatus) {
            _message = event.message;
          }
        });
        // Hanya sampel berstatus normal yang tersimpan; penyaringannya ada di
        // MeasurementStore.
        if (event is PpgBatch) persist(store.savePpg(event));
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

  String _describe(PpgBatch batch) {
    if (batch.samples.isNotEmpty && batch.validSamples.isEmpty) {
      return batch.samples.any((s) => s.isPreempted)
          ? 'Sensor lain yang lebih prioritas sedang berjalan'
          : 'Sampel tidak berstatus normal';
    }
    final rate = batch.rateHz;
    return rate == null
        ? '${batch.samples.length} sampel'
        : '${batch.samples.length} sampel · ${rate.toStringAsFixed(1)} Hz';
  }

  void _openHistory() {
    HistoryPage.open(
      context,
      accent: SensorColors.ppg,
      title: 'Riwayat PPG',
      totalNoun: 'sampel',
      load: () async => (await store.ppgHistory()).map(
        (s) => HistoryEntry(
          at: s.second,
          value: formatPpgMeans(s),
          detail: 'rata-rata ${s.samples} sampel, ADC mentah',
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
    final latest = _latest;
    String value(int? v) => v == null ? '--' : '$v';

    return MeasurementLayout(
      title: 'PPG',
      icon: Icons.monitor_heart,
      accent: SensorColors.ppg,
      reading: SizedBox(
        width: 124,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Gelombang PPG hijau tiga detik terakhir',
              child: SizedBox(
                height: 34,
                width: double.infinity,
                child: CustomPaint(
                  painter: _WavePainter(
                    List.of(_wave),
                    color: _measuring ? SensorColors.ppg : Colors.white24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _ChannelRow(label: 'Hijau', value: value(latest?.green)),
            _ChannelRow(label: 'IR', value: value(latest?.ir)),
            _ChannelRow(label: 'Merah', value: value(latest?.red)),
          ],
        ),
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

/// Satu baris warna: nama di kiri, nilai ADC rata kanan dengan angka selebar tetap.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Label dan angka mengecil bila perlu, bukan terbelah ke baris berikutnya:
    // angka ADC bisa delapan digit, dan ukuran huruf jam bisa diperbesar.
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: SensorColors.ppg.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        // Jarak tetap: tanpa ini label dan angka yang sama-sama penuh saling
        // menempel ("Merah16777215") pada ukuran huruf besar.
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Garis gelombang yang dinormalisasi ke rentang nilai di jendela yang tampil,
/// karena nilai ADC mentah jauh lebih besar dari ayunan denyutnya.
class _WavePainter extends CustomPainter {
  _WavePainter(this.values, {required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()
        ..color = Colors.white12
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;

    final low = values.reduce(math.min);
    final span = math.max(1, values.reduce(math.max) - low);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] - low) / span * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Rata-rata tiap warna dalam satu detik; warna yang tidak dilacak dilewati.
/// Spasi di dalam tiap pasangan tak-terputus, supaya baris hanya patah di
/// antara warna.
String formatPpgMeans(PpgSecond s) {
  String part(String label, double? v) =>
      v == null ? '' : '$label ${v.round()}';
  return [
    part('hijau', s.meanGreen),
    part('IR', s.meanIr),
    part('merah', s.meanRed),
  ].where((p) => p.isNotEmpty).join(' · ');
}
