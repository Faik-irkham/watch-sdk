import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hr_sdk_004/heart_rate_summary.dart';
import 'package:hr_sdk_004/measurement_shared.dart';
import 'package:hr_sdk_004/measurement_store.dart';
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

  /// Pembacaan absah sesi ini, untuk ringkasan saat pengukuran dihentikan.
  final List<HeartRateBeat> _beats = [];
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
      _beats.clear();
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
            _record(event);
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

  /// Titik yang sama bisa terkirim ulang saat layar mati; salinannya dilewati.
  void _record(HeartRateSample sample) {
    if (!sample.isValid) return;
    if (_beats.isNotEmpty && !sample.timestamp.isAfter(_beats.last.at)) return;
    _beats.add(
      HeartRateBeat(
        at: sample.timestamp,
        bpm: sample.heartRate,
        ibi: sample.ibi,
        ibiStatus: sample.ibiStatus,
      ),
    );
  }

  void _openHistory() {
    HistoryPage.open(
      context,
      accent: SensorColors.heartRate,
      title: 'Riwayat detak jantung',
      itemNoun: 'sesi',
      load: () async {
        final beats = await store.heartRateBeats();
        final sessions = summarizeSessions(
          beats.items,
          truncated: beats.items.length < beats.total,
        );
        return History([
          for (final s in sessions)
            HistoryEntry(
              at: s.start,
              value: formatBpmRange(s),
              detail: '${formatHrv(s)} · ${formatSessionDuration(s.duration)}',
              onTap: () => _openSession(s),
            ),
        ], beats.total);
      },
    );
  }

  /// Rincian satu sesi: setiap pembacaan per detik beserta IBI-nya, urut waktu.
  void _openSession(HeartRateSummary session) {
    HistoryPage.open(
      context,
      accent: SensorColors.heartRate,
      title: 'Rincian sesi',
      load: () async => History([
        for (final beat in session.beats)
          HistoryEntry(
            at: beat.at,
            value: '${beat.bpm} bpm',
            detail: formatIbi(beat),
          ),
      ], session.beats.length),
    );
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;
    final summary = HeartRateSummary.of(_beats);
    setState(() {
      _measuring = false;
      _message = summary == null
          ? 'Pengukuran dihentikan'
          : describeSession(summary);
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

/// Rata-rata dan rentang bpm satu sesi, misalnya "76 bpm · 73–87".
String formatBpmRange(HeartRateSummary s) =>
    '${s.meanBpm.round()} bpm · ${s.minBpm}–${s.maxBpm}';

/// HRV satu sesi, atau keterangan bila IBI berurutannya belum cukup.
String formatHrv(HeartRateSummary s) {
  final rmssd = s.rmssd;
  return rmssd == null ? 'HRV: IBI belum cukup' : 'HRV ${rmssd.round()} ms';
}

/// Lama sesi, misalnya "45 dtk" atau "3 mnt 5 dtk".
String formatSessionDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '$seconds dtk';
  return '${seconds ~/ 60} mnt ${seconds % 60} dtk';
}

/// Pesan setelah pengukuran dihentikan: rata-rata dan rentang, lalu HRV.
String describeSession(HeartRateSummary s) =>
    'Rata-rata ${formatBpmRange(s)}\n${formatHrv(s)}';

/// IBI satu pembacaan: nilai yang valid (status 0), lalu jumlah yang galat.
String formatIbi(HeartRateBeat beat) {
  final valid = <int>[];
  var invalid = 0;
  for (var i = 0; i < beat.ibi.length; i++) {
    if (i < beat.ibiStatus.length && beat.ibiStatus[i] == 0) {
      valid.add(beat.ibi[i]);
    } else {
      invalid++;
    }
  }
  final parts = [
    if (valid.isNotEmpty) 'IBI ${valid.join(', ')} ms',
    if (invalid > 0) '$invalid IBI galat',
  ];
  return parts.isEmpty ? 'tanpa IBI' : parts.join(' · ');
}
