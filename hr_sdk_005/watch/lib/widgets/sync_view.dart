import 'package:flutter/material.dart';
import 'package:hr_sdk_005_watch/measurement_shared.dart';
import 'package:hr_sdk_005_watch/phone_sync.dart';

/// Halaman "Kirim ke HP": jumlah data yang belum diterima HP, HP yang
/// tersambung, dan tombol untuk mengirim sekarang. Pengiriman otomatis juga
/// berjalan tiap [PhoneSync.period] selama aplikasi terbuka.
class SyncView extends StatefulWidget {
  const SyncView({super.key, this.sync});

  /// Null berarti [PhoneSync.instance]; diisi di test.
  final PhoneSync? sync;

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  late final PhoneSync _sync = widget.sync ?? PhoneSync.instance;

  @override
  void initState() {
    super.initState();
    _sync.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: _sync.status,
      builder: (context, status, _) {
        final sentAt = status.lastSentAt;
        final error = status.error;
        return MeasurementLayout(
          title: 'Kirim ke HP',
          icon: Icons.phone_android,
          accent: SensorColors.phone,
          reading: ValueReading(
            value: '${status.totalPending}',
            unit: 'data belum terkirim',
          ),
          message: status.sending
              ? 'Mengirim…'
              : error ?? describePhone(status.phoneName),
          messageIsError: !status.sending && error != null,
          footnote: sentAt == null
              ? null
              : 'Terakhir ${formatClock(sentAt)} · ${status.lastSentRows} data',
          // Pengiriman berlangsung singkat, jadi tidak ada keadaan "mengukur";
          // ketukan saat pengiriman masih berjalan diabaikan PhoneSync.
          measuring: false,
          startLabel: 'Kirim',
          onStart: () => _sync.sync(manual: true),
          onStop: () => _sync.sync(manual: true),
        );
      },
    );
  }
}

String describePhone(String? name) =>
    name == null ? 'Menunggu HP tersambung…' : 'Terhubung: $name';

/// Jam saja, misalnya "14:05:09".
String formatClock(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}
