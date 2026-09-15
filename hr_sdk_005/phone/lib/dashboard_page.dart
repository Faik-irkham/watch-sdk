import 'package:flutter/material.dart';
import 'package:hr_sdk_005_phone/ble_receiver.dart';
import 'package:hr_sdk_005_phone/edge_store.dart';
import 'package:hr_sdk_005_phone/watch_batch.dart';

/// Layar utama HP (edge): sambungan BLE ke jam, nilai terbaru tiap sensor, dan
/// batch yang baru diterima. Diperbarui setiap ada batch masuk.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store, required this.receiver});

  final EdgeStore store;
  final BleReceiver receiver;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  EdgeSnapshot _snapshot = const EdgeSnapshot();
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.receiver.recent.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.receiver.recent.removeListener(_reload);
    super.dispose();
  }

  /// Memuat ulang data, dan mencari jam lagi selama belum tersambung. Pencarian
  /// BLE berhenti sendiri setelah 20 detik (seperti proyek rujukan) tanpa
  /// mengubah status "Mencari watch…", jadi status itu juga dimulai ulang.
  Future<void> _refresh() async {
    final status = widget.receiver.status.value;
    if (status != ReceiverStatus.connected &&
        status != ReceiverStatus.connecting) {
      await widget.receiver.start();
    }
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final snapshot = await widget.store.snapshot();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal membaca data: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('HR 005 · Edge'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([
                widget.receiver.status,
                widget.receiver.message,
              ]),
              builder: (context, _) => _WatchCard(
                status: widget.receiver.status.value,
                message: widget.receiver.message.value,
                lastReceivedAt: _snapshot.lastReceivedAt,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            for (final table in EdgeStore.columns.keys)
              _SensorCard(
                table: table,
                count: _snapshot.counts[table] ?? 0,
                latest: _snapshot.latest[table],
              ),
            const SizedBox(height: 16),
            Text('Batch terbaru', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ValueListenableBuilder<List<ReceivedBatch>>(
              valueListenable: widget.receiver.recent,
              builder: (context, batches, _) => batches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Belum ada batch sejak aplikasi dibuka'),
                    )
                  : Column(
                      children: [
                        for (final batch in batches) _BatchTile(batch),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu status BLE, dengan label yang sama seperti StatusCard di proyek
/// heart_rate_phone_receiver.
class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.status,
    required this.message,
    required this.lastReceivedAt,
  });

  final ReceiverStatus status;
  final String? message;
  final DateTime? lastReceivedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final received = lastReceivedAt;
    final text = message;
    final (label, icon, color) = switch (status) {
      ReceiverStatus.connected => (
        'Terhubung',
        Icons.bluetooth_connected,
        scheme.primaryContainer,
      ),
      ReceiverStatus.connecting => (
        'Menghubungkan…',
        Icons.bluetooth_searching,
        scheme.surfaceContainerHighest,
      ),
      ReceiverStatus.scanning => (
        'Mencari watch…',
        Icons.bluetooth_searching,
        scheme.surfaceContainerHighest,
      ),
      ReceiverStatus.error => (
        'Error',
        Icons.error_outline,
        scheme.errorContainer,
      ),
      ReceiverStatus.idle => (
        'Belum terhubung',
        Icons.bluetooth,
        scheme.surfaceContainerHighest,
      ),
    };
    final lines = [
      ?text,
      received == null
          ? 'Belum ada data diterima'
          : 'Terakhir menerima ${formatDateTime(received)}',
    ];
    return Card(
      color: color,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.table,
    required this.count,
    required this.latest,
  });

  final String table;
  final int count;
  final Map<String, Object?>? latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = sensorStyle(table);
    final row = latest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tableLabel(table), style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    row == null ? '--' : describeLatest(table, row),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    row == null
                        ? 'Belum ada data'
                        : '$count ${countNoun(table)} · terakhir '
                              '${formatDateTime(DateTime.fromMillisecondsSinceEpoch(row['measured_at']! as int))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile(this.batch);

  final ReceivedBatch batch;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.download_done),
      title: Text('${tableLabel(batch.table)} · ${batch.rows} baris'),
      subtitle: Text('${batch.inserted} baru · ${formatClock(batch.at)}'),
    );
  }
}

String tableLabel(String table) => switch (table) {
  'heart_rate' => 'Detak jantung',
  'spo2' => 'SpO₂',
  'accelerometer' => 'Akselerometer',
  _ => table,
};

/// Kata benda untuk jumlah baris tiap tabel.
String countNoun(String table) => switch (table) {
  'heart_rate' => 'data',
  'spo2' => 'hasil',
  _ => 'sampel',
};

(IconData, Color) sensorStyle(String table) => switch (table) {
  'heart_rate' => (Icons.favorite, const Color(0xFFE53935)),
  'spo2' => (Icons.water_drop, const Color(0xFF039BE5)),
  _ => (Icons.open_with, const Color(0xFFF9A825)),
};

/// Nilai terbaru satu tabel dalam bentuk siap tampil.
String describeLatest(String table, Map<String, Object?> row) =>
    switch (table) {
      'heart_rate' => '${row['bpm']} bpm',
      'spo2' => '${row['spo2_percent']}%',
      _ => 'x ${row['x']} · y ${row['y']} · z ${row['z']}',
    };

String formatClock(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

String formatDateTime(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatClock(at)} · ${two(at.day)}/${two(at.month)}';
}
